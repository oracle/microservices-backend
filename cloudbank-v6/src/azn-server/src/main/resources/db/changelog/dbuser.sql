-- liquibase formatted sql

-- changeset az_admin:initial_user endDelimiter:/ runAlways:true runOnChange:true
DECLARE
    l_user      VARCHAR2(255);
    l_runtime_user VARCHAR2(255);
    l_tblspace  VARCHAR2(255);
BEGIN
    BEGIN
        SELECT username INTO l_user FROM DBA_USERS WHERE USERNAME='USER_REPO';
    EXCEPTION WHEN no_data_found THEN
        EXECUTE IMMEDIATE 'CREATE USER "USER_REPO" IDENTIFIED BY "${userRepoOwnerPassword}"';
    END;

    BEGIN
        EXECUTE IMMEDIATE 'ALTER USER "USER_REPO" IDENTIFIED BY "${userRepoOwnerPassword}" ACCOUNT LOCK';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE = -28007 THEN
                EXECUTE IMMEDIATE 'ALTER USER "USER_REPO" ACCOUNT LOCK';
            ELSE
                RAISE;
            END IF;
    END;

    SELECT default_tablespace INTO l_tblspace FROM dba_users WHERE username = 'USER_REPO';

    EXECUTE IMMEDIATE 'ALTER USER "USER_REPO" QUOTA 100M ON ' || l_tblspace;

    BEGIN
        SELECT username INTO l_runtime_user FROM DBA_USERS WHERE USERNAME='USER_REPO_APP';
    EXCEPTION WHEN no_data_found THEN
        EXECUTE IMMEDIATE 'CREATE USER "USER_REPO_APP" IDENTIFIED BY "${userRepoRuntimePassword}"';
    END;

    EXECUTE IMMEDIATE 'ALTER USER "USER_REPO_APP" ACCOUNT UNLOCK';
    EXECUTE IMMEDIATE 'GRANT CREATE SESSION TO "USER_REPO_APP"';
END;
/

--rollback drop user "USER_REPO_APP" cascade;
--rollback drop user "USER_REPO" cascade;
