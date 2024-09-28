-- jira_extension--1.0.sql

-- Criar o schema migration_control
CREATE SCHEMA IF NOT EXISTS migration_control;

-- Criar a tabela de configuração do Jira
CREATE TABLE IF NOT EXISTS migration_control.jira_config (
    id SERIAL NOT NULL PRIMARY KEY,
    jira_user TEXT NOT NULL,
    jira_token TEXT NOT NULL,
    jira_domain TEXT NOT NULL,
    send_messages_automatically BOOLEAN DEFAULT TRUE,
    message_template_show TEXT DEFAULT '@{reporter} Working to apply this upgrade SQL file',
    message_template_apply_success TEXT DEFAULT '@{reporter} Script applied with success',
    message_template_apply_error TEXT DEFAULT '@{reporter} Script application failed: {error}',
    message_template_deny TEXT DEFAULT '@{reporter} This script was not applied due to errors or security issues'
);

-- Criar a tabela de histórico dos scripts aplicados
CREATE TABLE IF NOT EXISTS migration_control.executed_scripts (
    id SERIAL NOT NULL PRIMARY KEY,
    ticket_jira VARCHAR NOT NULL,
    script_name VARCHAR NOT NULL,
    status VARCHAR NOT NULL,
    result TEXT,
    executed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Funções

CREATE OR REPLACE FUNCTION fetch_script_from_jira(ticket_jira VARCHAR, script_type VARCHAR, action VARCHAR)
RETURNS RECORD AS $$
import requests

# Obter configurações do Jira
result = plpy.execute("SELECT jira_user, jira_token, jira_domain FROM migration_control.jira_config LIMIT 1")
jira_user = result[0]['jira_user']
jira_token = result[0]['jira_token']
jira_domain = result[0]['jira_domain']

# Montar a URL da API do Jira para o ticket
jira_url = f"{jira_domain}/rest/api/2/issue/{ticket_jira}"

# Cabeçalho da requisição
headers = {
    'Content-Type': 'application/json'
}

# Fazer a requisição HTTP para obter detalhes do ticket
response = requests.get(jira_url, auth=(jira_user, jira_token), headers=headers)

# Verificar se a requisição foi bem-sucedida
if response.status_code != 200:
    raise Exception(f"Error fetching issue from Jira: {response.status_code}")

# Processar os dados do ticket
issue_data = response.json()

# Verificar anexos
attachments = issue_data['fields'].get('attachment', [])
if not attachments:
    raise Exception("No attachments found for this issue")

# Verificar o status e responsável apenas se a ação for 'apply' ou 'deny'
if action in ('apply', 'deny'):
    status = issue_data['fields']['status']['name'].lower()
    assignee = issue_data['fields'].get('assignee')

    if status not in ['in progress', 'em andamento'] or assignee is None:
        raise Exception("Ticket is not 'In Progress' or 'Em Andamento', or does not have an assignee.")

# Obter o reporter do ticket, verificando diferentes campos
reporter_info = issue_data['fields'].get('reporter', {})
reporter = reporter_info.get('name') or reporter_info.get('displayName') or reporter_info.get('emailAddress')

if reporter is None:
    raise Exception("No reporter information found for this ticket.")

# Procurar o arquivo correto no anexo
for attachment in attachments:
    if script_type in attachment['filename']:
        # Fazer o download do arquivo do anexo
        file_url = attachment['content']
        file_response = requests.get(file_url, auth=(jira_user, jira_token))
        
        if file_response.status_code == 200:
            return (file_response.text, reporter)  # Retornar o conteúdo do arquivo e o reporter
        else:
            raise Exception(f"Error downloading attachment: {file_response.status_code}")

# Se não encontrar o arquivo
raise Exception(f"{script_type}.sql not found in attachments for ticket {ticket_jira}")
$$ LANGUAGE plpython3u;


CREATE OR REPLACE FUNCTION add_comment_to_jira(ticket_jira VARCHAR, reporter VARCHAR, action VARCHAR, error_msg TEXT DEFAULT NULL)
RETURNS VOID AS $$
import requests
import json

# Obter configurações do Jira
result = plpy.execute("SELECT jira_user, jira_token, jira_domain, send_messages_automatically, message_template_show, message_template_apply_success, message_template_apply_error, message_template_deny FROM migration_control.jira_config LIMIT 1")
jira_user = result[0]['jira_user']
jira_token = result[0]['jira_token']
jira_domain = result[0]['jira_domain']

# Verificar se envio automático está habilitado corretamente
if not result[0]['send_messages_automatically']:
    return  # Não envia a mensagem se o envio automático estiver desabilitado

# Definir o modelo da mensagem baseado na ação
if action == 'show':
    message_template = result[0]['message_template_show']
elif action == 'apply' and error_msg is None:
    message_template = result[0]['message_template_apply_success']
elif action == 'apply' and error_msg is not None:
    message_template = result[0]['message_template_apply_error'].replace('{error}', error_msg)
elif action == 'deny':
    message_template = result[0]['message_template_deny']

# Substituir o marcador {reporter} pelo nome do relator
message = message_template.replace('{reporter}', reporter)

# Montar a URL da API do Jira para adicionar comentários
jira_url = f"{jira_domain}/rest/api/2/issue/{ticket_jira}/comment"

# Cabeçalho da requisição
headers = {
    'Content-Type': 'application/json'
}

# Corpo da requisição (conteúdo do comentário)
payload = {
    "body": message
}

# Fazer a requisição HTTP para adicionar o comentário
response = requests.post(jira_url, auth=(jira_user, jira_token), headers=headers, data=json.dumps(payload))

# Verificar se o comentário foi adicionado com sucesso
if response.status_code != 201:
    raise Exception(f"Error adding comment to Jira: {response.status_code}")
$$ LANGUAGE plpython3u;


CREATE OR REPLACE FUNCTION apply_script(ticket_jira VARCHAR, script_type VARCHAR, action VARCHAR)
RETURNS TEXT AS $$
DECLARE
    script TEXT;
    ticket_reporter VARCHAR;
    result TEXT;
BEGIN
    -- Buscar o script via API do Jira e obter o reporter
    SELECT script_content, reporter INTO script, ticket_reporter 
    FROM fetch_script_from_jira(ticket_jira, script_type, action) 
    AS fetch_result(script_content TEXT, reporter VARCHAR);

    -- Verificar o tipo de ação: show, apply ou deny
    IF action = 'show' THEN
        -- Adicionar comentário no Jira (se aplicável)
        PERFORM add_comment_to_jira(ticket_jira, ticket_reporter, action);
        
        -- Apenas mostrar o conteúdo do script
        RETURN script;

    ELSIF action = 'apply' THEN
        BEGIN
            -- Tentar executar o script SQL
            EXECUTE script;

            -- Registrar o sucesso na tabela de controle
            INSERT INTO migration_control.executed_scripts (ticket_jira, script_name, status, result)
            VALUES (ticket_jira, script_type || '.sql', 'OK', 'Script executed successfully');
            
            -- Adicionar comentário de sucesso no Jira (se aplicável)
            PERFORM add_comment_to_jira(ticket_jira, ticket_reporter, action);
            
            RETURN 'Script applied successfully.';
        EXCEPTION
            WHEN OTHERS THEN
                -- Registrar erro na tabela de controle
                result := SQLERRM;
                INSERT INTO migration_control.executed_scripts (ticket_jira, script_name, status, result)
                VALUES (ticket_jira, script_type || '.sql', 'ERROR', result);

                -- Adicionar comentário de erro no Jira (se aplicável)
                PERFORM add_comment_to_jira(ticket_jira, ticket_reporter, action, result);
                
                RAISE;
        END;

    ELSIF action = 'deny' THEN
        -- Adicionar comentário no Jira explicando que o script não foi aplicado (se aplicável)
        PERFORM add_comment_to_jira(ticket_jira, ticket_reporter, action);
        
        RETURN 'Script denied.';

    ELSE
        -- Se a ação não for válida, retornar um erro
        RAISE EXCEPTION 'Invalid action. Use "show", "apply" or "deny".';
    END IF;

EXCEPTION
    WHEN OTHERS THEN
        RAISE;
END;
$$ LANGUAGE plpgsql;

