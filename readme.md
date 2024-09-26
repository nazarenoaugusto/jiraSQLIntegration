
# PostgreSQL Jira Extension

## Description

This extension integrates Jira with PostgreSQL, allowing you to fetch upgrade and downgrade SQL scripts based on Jira ticket numbers and apply, view, or deny those scripts directly in the database. You can also automatically add comments to Jira with customizable messages.

## Requirements

- PostgreSQL version 13 or higher
- PL/Python3 (`plpython3u`) enabled in PostgreSQL
- Connection to the Jira API
- A configuration repository with Jira credentials

## Installation

### Step 1: Ensure `plpython3u` is enabled

You must have `plpython3u` enabled on your PostgreSQL instance.

```sql
CREATE EXTENSION plpython3u;
```

### Step 2: Place the extension files in the PostgreSQL extension directory

1. Place the `jira_extension.control` file in the directory:

   ```
   /usr/share/postgresql/13/extension/jira_extension.control
   ```

2. Place the SQL file for the extension `jira_extension--1.0.sql` in the same directory:

   ```
   /usr/share/postgresql/13/extension/jira_extension--1.0.sql
   ```

### Step 3: Install the extension in the database

Now, install the extension on your PostgreSQL database:

```sql
CREATE EXTENSION jira_extension;
```

### Configuration

Before using the extension, configure the Jira credentials.

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

### Usage

You can use the following functions with the extension:

- **View the Script**:
  
  ```sql
  SELECT apply_script('JIRA-1234', 'upgrade', 'show');
  ```

- **Apply the Script**:
  
  ```sql
  SELECT apply_script('JIRA-1234', 'upgrade', 'apply');
  ```

- **Deny the Script**:
  
  ```sql
  SELECT apply_script('JIRA-1234', 'upgrade', 'deny');
  ```

## License

This project is distributed under the MIT license.
