-- CloudBank AI 2026.0
-- Least-privilege one-shot role for loading an initially empty policy corpus.

BEGIN
  BEGIN
    EXECUTE IMMEDIATE 'CREATE ROLE cb_policy_loader_runtime';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLCODE != -1921 THEN
        RAISE;
      END IF;
  END;

  EXECUTE IMMEDIATE 'GRANT CREATE SESSION TO cb_policy_loader_runtime';
  EXECUTE IMMEDIATE 'GRANT SELECT, INSERT ON cb_policy_document TO cb_policy_loader_runtime';
  EXECUTE IMMEDIATE 'GRANT SELECT, INSERT ON cb_policy_chunk TO cb_policy_loader_runtime';
  EXECUTE IMMEDIATE 'GRANT SELECT, INSERT ON cb_policy_corpus_load TO cb_policy_loader_runtime';
END;
/
