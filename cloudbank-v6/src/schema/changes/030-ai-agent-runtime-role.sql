-- CloudBank AI 2026.0
-- AI runtime owns results only. Evidence is retrieved through authorized APIs.
BEGIN
  BEGIN
    EXECUTE IMMEDIATE 'CREATE ROLE cb_ai_agent_runtime';
  EXCEPTION WHEN OTHERS THEN
    IF SQLCODE != -1921 THEN RAISE; END IF;
  END;
  EXECUTE IMMEDIATE 'GRANT CREATE SESSION TO cb_ai_agent_runtime';
  EXECUTE IMMEDIATE 'GRANT SELECT, INSERT ON cb_ai_document_summary TO cb_ai_agent_runtime';
END;
/
