-- jira_extension--1.1.sql

-- Criar a função para alterar o status do ticket no Jira para "UNDER REVIEW"
CREATE OR REPLACE FUNCTION change_ticket_status_to_under_review(ticket_jira VARCHAR)
RETURNS VOID AS $$
import requests
import json

# Obter configurações do Jira, incluindo jira_user, jira_token, e jira_domain
result = plpy.execute("SELECT jira_user, jira_token, jira_domain FROM migration_control.jira_config LIMIT 1")
jira_user = result[0]['jira_user']
jira_token = result[0]['jira_token']
jira_domain = result[0]['jira_domain']

# Montar a URL da API para buscar as transições disponíveis para o ticket
transitions_url = f"{jira_domain}/rest/api/2/issue/{ticket_jira}/transitions"

# Cabeçalho da requisição
headers = {
    'Content-Type': 'application/json'
}

# Fazer a requisição HTTP para obter as transições possíveis
response = requests.get(transitions_url, auth=(jira_user, jira_token), headers=headers)
if response.status_code != 200:
    raise Exception(f"Error fetching transitions for Jira issue: {response.status_code}")

# Encontrar a transição "UNDER REVIEW"
transitions_data = response.json()
transition_id = None
for transition in transitions_data['transitions']:
    if transition['name'].lower() == 'under review':
        transition_id = transition['id']
        break

if transition_id is None:
    raise Exception("Transition to 'UNDER REVIEW' not found for this ticket")

# Montar o corpo da requisição para alterar o status
transition_payload = {
    "transition": {
        "id": transition_id
    }
}

# Fazer a requisição para alterar o status do ticket
response = requests.post(transitions_url, auth=(jira_user, jira_token), headers=headers, data=json.dumps(transition_payload))
if response.status_code != 204:
    raise Exception(f"Error changing status to 'UNDER REVIEW': {response.status_code}")

$$ LANGUAGE plpython3u;

-- Modificar a função apply_script para incluir a chamada à função de mudança de status
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

            -- Alterar o status do ticket para "UNDER REVIEW"
            PERFORM change_ticket_status_to_under_review(ticket_jira);
            
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

