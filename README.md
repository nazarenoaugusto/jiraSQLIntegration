
# JiraSQL Integration

## Description

JiraSQL Integration is a PostgreSQL extension that integrates directly with Jira to automate the retrieval, execution, and management of SQL scripts associated with Jira tickets. This extension allows you to:
- Fetch and view SQL scripts attached to Jira tickets.
- Apply or deny SQL scripts, automatically adding comments to Jira tickets.
- Change the status of Jira tickets to "UNDER REVIEW" after successful script execution.

This extension is designed for development and operations teams that want to streamline database management using Jira as a central platform.

## Features

- Fetch SQL scripts from Jira based on ticket number.
- Automatically apply, view, or deny SQL scripts.
- Automatically add comments to Jira tickets with custom messages.
- Change the status of Jira tickets to "UNDER REVIEW" upon successful execution.

## Requirements

- PostgreSQL version 13 or higher.
- PL/Python3 (`plpython3u`) enabled in PostgreSQL.
- Jira API access with a user account and API token.

## Installation

### Step 1: Ensure `plpython3u` is enabled

Ensure that PL/Python3 is enabled in your PostgreSQL instance.

```sql
CREATE EXTENSION plpython3u;
```

### Step 2: Download and install the extension

1. Clone the repository or download the extension files from GitHub.
   
   ```bash
   git clone https://github.com/yourusername/jirasql-integration.git
   ```

2. Place the extension files in the PostgreSQL extension directory:

   - `jira_extension.control`
   - `jira_extension--1.0.sql`
   - `jira_extension--1.1.sql`

   The directory is typically located at:

   ```
   /usr/share/postgresql/13/extension/
   ```

### Step 3: Install the extension

Run the following command to install the extension in your PostgreSQL database:

```sql
CREATE EXTENSION jira_extension;
```

To update to version 1.1, run:

```sql
ALTER EXTENSION jira_extension UPDATE TO '1.1';
```

## Configuration

### Step 1: Create the configuration table

You need to create the `jira_config` table to store your Jira credentials and settings:

```sql
CREATE TABLE migration_control.jira_config (
    jira_user TEXT NOT NULL,
    jira_token TEXT NOT NULL,
    jira_domain TEXT NOT NULL,
    send_messages_automatically BOOLEAN DEFAULT TRUE,
    message_template_show TEXT DEFAULT '@{reporter} Working to apply this upgrade SQL file',
    message_template_apply_success TEXT DEFAULT '@{reporter} Script applied with success',
    message_template_apply_error TEXT DEFAULT '@{reporter} Script application failed: {error}',
    message_template_deny TEXT DEFAULT '@{reporter} This script was not applied due to errors or security issues'
);
```

### Step 2: Add your Jira credentials

Insert your Jira credentials and domain into the configuration table:

```sql
INSERT INTO migration_control.jira_config (jira_user, jira_token, jira_domain) 
VALUES ('your_jira_user', 'your_jira_api_token', 'https://yourcompany.atlassian.net');
```

### Step 3: Customize message templates (Optional)

You can customize the messages that are automatically added as comments in Jira when scripts are applied, denied, or viewed.

Example:

```sql
UPDATE migration_control.jira_config 
SET message_template_apply_success = '@{reporter} The script was successfully applied on {date}.';
```

## Usage

You can use the following functions to interact with Jira tickets and SQL scripts:

### Fetch and View a Script

To fetch and view the SQL script attached to a Jira ticket, run:

```sql
SELECT apply_script('JIRA-1234', 'upgrade', 'show');
```

### Apply a Script

To apply the SQL script and automatically change the Jira ticket status to "UNDER REVIEW", run:

```sql
SELECT apply_script('JIRA-1234', 'upgrade', 'apply');
```

### Deny a Script

If you decide not to apply the script, you can deny it, and a comment will be added to the Jira ticket:

```sql
SELECT apply_script('JIRA-1234', 'upgrade', 'deny');
```

## Contributing

Feel free to fork this repository, make changes, and submit a pull request.

## License

This project is licensed under the MIT License.
