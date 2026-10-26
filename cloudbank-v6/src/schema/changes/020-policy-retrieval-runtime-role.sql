-- CloudBank AI 2026.0
-- Least-privilege read role for policy-retrieval-service.

BEGIN
  BEGIN
    EXECUTE IMMEDIATE 'CREATE ROLE cb_policy_retrieval_runtime';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLCODE != -1921 THEN
        RAISE;
      END IF;
  END;

  EXECUTE IMMEDIATE 'GRANT CREATE SESSION TO cb_policy_retrieval_runtime';
  EXECUTE IMMEDIATE 'GRANT SELECT ON cb_policy_document TO cb_policy_retrieval_runtime';
  EXECUTE IMMEDIATE 'GRANT SELECT ON cb_policy_chunk TO cb_policy_retrieval_runtime';
END;
/
