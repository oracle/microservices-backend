-- CloudBank AI 2026.0
-- Align the database service principal with the stable principal derived from
-- azn-server's cloudbank-service-client JWT subject.

UPDATE cb_app_principal
SET principal_id = 'svc-cloudbank-service-client',
    display_name = 'CloudBank Service Client'
WHERE principal_id = 'svc-loan-application'
  AND NOT EXISTS (
    SELECT 1 FROM cb_app_principal
    WHERE principal_id = 'svc-cloudbank-service-client'
  );

MERGE INTO cb_app_principal target
USING (
  SELECT 'svc-cloudbank-service-client' principal_id, 'SERVICE' principal_type,
         'CloudBank Service Client' display_name,
         'cloudbank-internal' external_issuer,
         'cloudbank-service-client' external_subject
  FROM dual
) source
ON (target.principal_id = source.principal_id)
WHEN MATCHED THEN UPDATE SET
  target.display_name = source.display_name,
  target.status = 'ACTIVE'
WHEN NOT MATCHED THEN INSERT (
  principal_id, principal_type, display_name, external_issuer, external_subject
) VALUES (
  source.principal_id, source.principal_type, source.display_name,
  source.external_issuer, source.external_subject
);

MERGE INTO cb_app_role_grant target
USING (
  SELECT principal_sk
  FROM cb_app_principal
  WHERE principal_id = 'svc-cloudbank-service-client'
) source
ON (target.principal_sk = source.principal_sk AND target.role_code = 'SERVICE')
WHEN MATCHED THEN UPDATE SET target.grant_status = 'ACTIVE'
WHEN NOT MATCHED THEN INSERT (principal_sk, role_code, granted_by)
VALUES (source.principal_sk, 'SERVICE', 'schema-migration');
