-- CloudBank AI 2026.0
-- load-seed-data.sql
-- Package that loads src/schema/seeds/seed-data.json from CB_SEED_PAYLOAD.
--
-- SQLcl usage pattern:
--   1. Load seed-data.json into CB_SEED_PAYLOAD.PAYLOAD as seed_name 'cloudbank-2026.0-fixtures'.
--   2. EXEC cb_seed_loader.load('cloudbank-2026.0-fixtures');
--
-- Keep fixture data in JSON. This package uses set-based MERGE operations so retries are idempotent.

CREATE OR REPLACE PACKAGE cb_seed_loader AUTHID DEFINER AS
  PROCEDURE load(p_seed_name IN VARCHAR2 DEFAULT 'cloudbank-2026.0-fixtures');
END cb_seed_loader;
/

CREATE OR REPLACE PACKAGE BODY cb_seed_loader AS
  PROCEDURE load(p_seed_name IN VARCHAR2 DEFAULT 'cloudbank-2026.0-fixtures') IS
    l_payload CLOB;
  BEGIN
    SELECT JSON_SERIALIZE(payload RETURNING CLOB)
    INTO l_payload
    FROM cb_seed_payload
    WHERE seed_name = p_seed_name;

    MERGE INTO cb_app_principal t
    USING (
      SELECT *
      FROM JSON_TABLE(l_payload, '$.principals[*]' COLUMNS (
        principal_id VARCHAR2(80) PATH '$.principalId',
        principal_type VARCHAR2(40) PATH '$.principalType',
        display_name VARCHAR2(200) PATH '$.displayName',
        external_subject VARCHAR2(300) PATH '$.externalSubject'
      ))
    ) s
    ON (t.principal_id = s.principal_id)
    WHEN MATCHED THEN UPDATE SET
      t.principal_type = s.principal_type,
      t.display_name = s.display_name,
      t.external_subject = s.external_subject,
      t.status = 'ACTIVE'
    WHEN NOT MATCHED THEN INSERT (
      principal_id, principal_type, display_name, external_subject
    ) VALUES (
      s.principal_id, s.principal_type, s.display_name, s.external_subject
    );

    MERGE INTO cb_app_role_grant t
    USING (
      SELECT p.principal_sk, r.role_code
      FROM JSON_TABLE(l_payload, '$.roleGrants[*]' COLUMNS (
        principal_id VARCHAR2(80) PATH '$.principalId',
        role_code VARCHAR2(40) PATH '$.roleCode'
      )) r
      JOIN cb_app_principal p ON p.principal_id = r.principal_id
    ) s
    ON (t.principal_sk = s.principal_sk AND t.role_code = s.role_code)
    WHEN MATCHED THEN UPDATE SET
      t.grant_status = 'ACTIVE',
      t.expires_at = NULL
    WHEN NOT MATCHED THEN INSERT (
      principal_sk, role_code, grant_status
    ) VALUES (
      s.principal_sk, s.role_code, 'ACTIVE'
    );

    MERGE INTO cb_employer t
    USING (
      SELECT *
      FROM JSON_TABLE(l_payload, '$.employers[*]' COLUMNS (
        employer_id VARCHAR2(40) PATH '$.employerId',
        employer_name VARCHAR2(220) PATH '$.employerName',
        employer_token VARCHAR2(80) PATH '$.employerToken',
        employer_address VARCHAR2(300) PATH '$.employerAddress'
      ))
    ) s
    ON (t.employer_id = s.employer_id)
    WHEN MATCHED THEN UPDATE SET
      t.employer_name = s.employer_name,
      t.employer_token = s.employer_token,
      t.employer_address = s.employer_address,
      t.status = 'ACTIVE'
    WHEN NOT MATCHED THEN INSERT (
      employer_id, employer_name, employer_token, employer_address
    ) VALUES (
      s.employer_id, s.employer_name, s.employer_token, s.employer_address
    );

    MERGE INTO cb_applicant t
    USING (
      SELECT *
      FROM JSON_TABLE(l_payload, '$.applicants[*]' COLUMNS (
        applicant_id VARCHAR2(40) PATH '$.applicantId',
        display_name VARCHAR2(200) PATH '$.displayName',
        phone_token VARCHAR2(80) PATH '$.phoneToken',
        email_token VARCHAR2(160) PATH '$.emailToken',
        age_band VARCHAR2(20) PATH '$.ageBand'
      ))
    ) s
    ON (t.applicant_id = s.applicant_id)
    WHEN MATCHED THEN UPDATE SET
      t.display_name = s.display_name,
      t.phone_token = s.phone_token,
      t.email_token = s.email_token,
      t.age_band = s.age_band
    WHEN NOT MATCHED THEN INSERT (
      applicant_id, display_name, phone_token, email_token, age_band
    ) VALUES (
      s.applicant_id, s.display_name, s.phone_token, s.email_token, s.age_band
    );

    MERGE INTO cb_address t
    USING (
      SELECT
        a.applicant_sk,
        jt.address_id,
        jt.address_line,
        jt.locality,
        jt.jurisdiction_code,
        jt.jurisdiction_status,
        jt.address_token,
        jt.country_code,
        jt.postal_code,
        jt.longitude,
        jt.latitude
      FROM JSON_TABLE(l_payload, '$.applicants[*]' COLUMNS (
        applicant_id VARCHAR2(40) PATH '$.applicantId',
        address_id VARCHAR2(40) PATH '$.address.addressId',
        address_line VARCHAR2(300) PATH '$.address.addressLine',
        locality VARCHAR2(120) PATH '$.address.locality',
        jurisdiction_code VARCHAR2(20) PATH '$.address.jurisdictionCode',
        jurisdiction_status VARCHAR2(40) PATH '$.address.jurisdictionStatus',
        address_token VARCHAR2(80) PATH '$.address.addressToken',
        country_code VARCHAR2(2) PATH '$.address.countryCode',
        postal_code VARCHAR2(20) PATH '$.address.postalCode',
        longitude NUMBER PATH '$.address.longitude',
        latitude NUMBER PATH '$.address.latitude'
      )) jt
      JOIN cb_applicant a ON a.applicant_id = jt.applicant_id
    ) s
    ON (t.address_id = s.address_id)
    WHEN MATCHED THEN UPDATE SET
      t.applicant_sk = s.applicant_sk,
      t.address_line = s.address_line,
      t.locality = s.locality,
      t.jurisdiction_code = s.jurisdiction_code,
      t.jurisdiction_status = s.jurisdiction_status,
      t.address_token = s.address_token,
      t.country_code = s.country_code,
      t.postal_code = s.postal_code,
      t.location_geom = MDSYS.SDO_GEOMETRY(2001, 4326, MDSYS.SDO_POINT_TYPE(s.longitude, s.latitude, NULL), NULL, NULL)
    WHEN NOT MATCHED THEN INSERT (
      applicant_sk, address_id, address_line, locality, jurisdiction_code,
      jurisdiction_status, address_token, country_code, postal_code, location_geom
    ) VALUES (
      s.applicant_sk, s.address_id, s.address_line, s.locality, s.jurisdiction_code,
      s.jurisdiction_status, s.address_token, s.country_code, s.postal_code,
      MDSYS.SDO_GEOMETRY(2001, 4326, MDSYS.SDO_POINT_TYPE(s.longitude, s.latitude, NULL), NULL, NULL)
    );

    MERGE INTO cb_jurisdiction_zone t
    USING (
      SELECT *
      FROM JSON_TABLE(l_payload, '$.jurisdictionZones[*]' COLUMNS (
        zone_id VARCHAR2(80) PATH '$.zoneId',
        jurisdiction_code VARCHAR2(20) PATH '$.jurisdictionCode',
        zone_name VARCHAR2(160) PATH '$.zoneName',
        zone_type VARCHAR2(40) PATH '$.zoneType',
        zone_status VARCHAR2(40) PATH '$.zoneStatus',
        wkt VARCHAR2(2000) PATH '$.wkt'
      ))
    ) s
    ON (t.zone_id = s.zone_id)
    WHEN MATCHED THEN UPDATE SET
      t.jurisdiction_code = s.jurisdiction_code,
      t.zone_name = s.zone_name,
      t.zone_type = s.zone_type,
      t.zone_status = s.zone_status,
      t.zone_geom = MDSYS.SDO_GEOMETRY(s.wkt, 4326)
    WHEN NOT MATCHED THEN INSERT (
      zone_id, jurisdiction_code, zone_name, zone_type, zone_status, zone_geom
    ) VALUES (
      s.zone_id, s.jurisdiction_code, s.zone_name, s.zone_type, s.zone_status,
      MDSYS.SDO_GEOMETRY(s.wkt, 4326)
    );

    MERGE INTO cb_policy_document t
    USING (
      SELECT *
      FROM JSON_TABLE(l_payload, '$.policyDocuments[*]' COLUMNS (
        policy_document_id VARCHAR2(80) PATH '$.policyDocumentId',
        policy_code VARCHAR2(40) PATH '$.policyCode',
        policy_title VARCHAR2(300) PATH '$.policyTitle',
        source_path VARCHAR2(500) PATH '$.sourcePath',
        effective_date DATE PATH '$.effectiveDate',
        owner_role VARCHAR2(40) PATH '$.ownerRole'
      ))
    ) s
    ON (t.policy_document_id = s.policy_document_id)
    WHEN MATCHED THEN UPDATE SET
      t.policy_code = s.policy_code,
      t.policy_title = s.policy_title,
      t.source_path = s.source_path,
      t.effective_date = s.effective_date,
      t.owner_role = s.owner_role,
      t.review_status = 'APPROVED'
    WHEN NOT MATCHED THEN INSERT (
      policy_document_id, policy_code, policy_title, source_path, effective_date, owner_role
    ) VALUES (
      s.policy_document_id, s.policy_code, s.policy_title, s.source_path, s.effective_date, s.owner_role
    );

    MERGE INTO cb_policy_chunk t
    USING (
      SELECT
        pd.policy_document_sk,
        jt.chunk_id,
        jt.section_ref,
        jt.heading,
        jt.chunk_ordinal,
        jt.text AS chunk_text,
        jt.min_role,
        jt.embedding_text
      FROM JSON_TABLE(l_payload, '$.policyDocuments[*]' COLUMNS (
        policy_document_id VARCHAR2(80) PATH '$.policyDocumentId',
        NESTED PATH '$.chunks[*]' COLUMNS (
          chunk_id VARCHAR2(100) PATH '$.chunkId',
          section_ref VARCHAR2(80) PATH '$.sectionRef',
          heading VARCHAR2(300) PATH '$.heading',
          chunk_ordinal NUMBER PATH '$.chunkOrdinal',
          min_role VARCHAR2(40) PATH '$.minRole',
          text VARCHAR2(4000) PATH '$.text',
          embedding_text VARCHAR2(4000) PATH '$.embeddingText'
        )
      )) jt
      JOIN cb_policy_document pd ON pd.policy_document_id = jt.policy_document_id
    ) s
    ON (t.chunk_id = s.chunk_id)
    WHEN MATCHED THEN UPDATE SET
      t.policy_document_sk = s.policy_document_sk,
      t.section_ref = s.section_ref,
      t.heading = s.heading,
      t.chunk_ordinal = s.chunk_ordinal,
      t.chunk_text = s.chunk_text,
      t.min_role = s.min_role,
      t.embedding = TO_VECTOR(s.embedding_text)
    WHEN NOT MATCHED THEN INSERT (
      policy_document_sk, chunk_id, section_ref, heading, chunk_ordinal, chunk_text, min_role, embedding
    ) VALUES (
      s.policy_document_sk, s.chunk_id, s.section_ref, s.heading, s.chunk_ordinal, s.chunk_text,
      s.min_role, TO_VECTOR(s.embedding_text)
    );

    MERGE INTO cb_loan_application t
    USING (
      SELECT
        a.applicant_sk,
        jt.*
      FROM JSON_TABLE(l_payload, '$.applications[*]' COLUMNS (
        application_id VARCHAR2(40) PATH '$.applicationId',
        applicant_id VARCHAR2(40) PATH '$.applicantId',
        scenario_id VARCHAR2(80) PATH '$.scenarioId',
        requested_amount NUMBER PATH '$.requestedAmount',
        requested_term_months NUMBER PATH '$.requestedTermMonths',
        purpose_code VARCHAR2(40) PATH '$.purposeCode',
        application_status VARCHAR2(40) PATH '$.applicationStatus',
        expected_outcome VARCHAR2(40) PATH '$.expectedOutcome',
        workflow_id VARCHAR2(80) PATH '$.workflowId'
      )) jt
      JOIN cb_applicant a ON a.applicant_id = jt.applicant_id
    ) s
    ON (t.application_id = s.application_id)
    WHEN MATCHED THEN UPDATE SET
      t.applicant_sk = s.applicant_sk,
      t.scenario_id = s.scenario_id,
      t.requested_amount = s.requested_amount,
      t.requested_term_months = s.requested_term_months,
      t.purpose_code = s.purpose_code,
      t.application_status = s.application_status,
      t.expected_outcome = s.expected_outcome,
      t.application_packet_json = JSON_OBJECT(
        'applicationId' VALUE s.application_id,
        'applicantId' VALUE s.applicant_id,
        'scenarioId' VALUE s.scenario_id,
        'workflowId' VALUE s.workflow_id
        RETURNING JSON
      ),
      t.updated_at = SYSTIMESTAMP
    WHEN NOT MATCHED THEN INSERT (
      application_id, applicant_sk, scenario_id, requested_amount,
      requested_term_months, purpose_code, application_status, expected_outcome,
      application_packet_json
    ) VALUES (
      s.application_id, s.applicant_sk, s.scenario_id, s.requested_amount,
      s.requested_term_months, s.purpose_code, s.application_status, s.expected_outcome,
      JSON_OBJECT(
        'applicationId' VALUE s.application_id,
        'applicantId' VALUE s.applicant_id,
        'scenarioId' VALUE s.scenario_id,
        'workflowId' VALUE s.workflow_id
        RETURNING JSON
      )
    );

    MERGE INTO cb_data_grant t
    USING (
      SELECT p.principal_sk, la.application_sk, 'APPLICATION' AS grant_scope
      FROM cb_app_principal p
      CROSS JOIN cb_loan_application la
      WHERE p.principal_id = 'loan-officer-001'
    ) s
    ON (t.principal_sk = s.principal_sk AND t.application_sk = s.application_sk AND t.grant_scope = s.grant_scope)
    WHEN MATCHED THEN UPDATE SET t.grant_status = 'ACTIVE'
    WHEN NOT MATCHED THEN INSERT (
      principal_sk, application_sk, grant_scope, grant_reason
    ) VALUES (
      s.principal_sk, s.application_sk, s.grant_scope, 'Fixture assignment for demo loan officer'
    );

    MERGE INTO cb_employment t
    USING (
      SELECT
        la.application_sk,
        e.employer_sk,
        jt.employment_status,
        jt.job_title,
        jt.tenure_text,
        jt.tenure_band,
        jt.income_source_type,
        jt.pay_frequency
      FROM JSON_TABLE(l_payload, '$.applications[*]' COLUMNS (
        application_id VARCHAR2(40) PATH '$.applicationId',
        employer_id VARCHAR2(40) PATH '$.employment.employerId',
        employment_status VARCHAR2(40) PATH '$.employment.employmentStatus',
        job_title VARCHAR2(160) PATH '$.employment.jobTitle',
        tenure_text VARCHAR2(80) PATH '$.employment.tenureText',
        tenure_band VARCHAR2(40) PATH '$.employment.tenureBand',
        income_source_type VARCHAR2(80) PATH '$.employment.incomeSourceType',
        pay_frequency VARCHAR2(40) PATH '$.employment.payFrequency'
      )) jt
      JOIN cb_loan_application la ON la.application_id = jt.application_id
      LEFT JOIN cb_employer e ON e.employer_id = jt.employer_id
    ) s
    ON (t.application_sk = s.application_sk)
    WHEN MATCHED THEN UPDATE SET
      t.employer_sk = s.employer_sk,
      t.employment_status = s.employment_status,
      t.job_title = s.job_title,
      t.tenure_text = s.tenure_text,
      t.tenure_band = s.tenure_band,
      t.income_source_type = s.income_source_type,
      t.pay_frequency = s.pay_frequency
    WHEN NOT MATCHED THEN INSERT (
      application_sk, employer_sk, employment_status, job_title, tenure_text,
      tenure_band, income_source_type, pay_frequency
    ) VALUES (
      s.application_sk, s.employer_sk, s.employment_status, s.job_title, s.tenure_text,
      s.tenure_band, s.income_source_type, s.pay_frequency
    );

    MERGE INTO cb_document t
    USING (
      SELECT
        la.application_sk,
        jt.application_id,
        jt.packet_dir,
        jt.document_id,
        jt.document_type,
        jt.file_name,
        jt.content_sha256,
        jt.status AS document_status,
        jt.min_role,
        'synthetic_data/customer_packets/' || jt.packet_dir || '/' || jt.file_name AS source_packet_path
      FROM JSON_TABLE(l_payload, '$.applications[*]' COLUMNS (
        application_id VARCHAR2(40) PATH '$.applicationId',
        packet_dir VARCHAR2(120) PATH '$.packetDir',
        NESTED PATH '$.documents[*]' COLUMNS (
          document_id VARCHAR2(60) PATH '$.documentId',
          document_type VARCHAR2(60) PATH '$.documentType',
          file_name VARCHAR2(260) PATH '$.fileName',
          content_sha256 VARCHAR2(64) PATH '$.contentSha256',
          status VARCHAR2(40) PATH '$.status',
          min_role VARCHAR2(40) PATH '$.minRole'
        )
      )) jt
      JOIN cb_loan_application la ON la.application_id = jt.application_id
    ) s
    ON (t.document_id = s.document_id)
    WHEN MATCHED THEN UPDATE SET
      t.application_sk = s.application_sk,
      t.document_type = s.document_type,
      t.file_name = s.file_name,
      t.content_sha256 = s.content_sha256,
      t.source_packet_path = s.source_packet_path,
      t.document_status = s.document_status,
      t.min_role = s.min_role
    WHEN NOT MATCHED THEN INSERT (
      application_sk, document_id, document_type, file_name, content_sha256,
      source_packet_path, document_status, min_role
    ) VALUES (
      s.application_sk, s.document_id, s.document_type, s.file_name, s.content_sha256,
      s.source_packet_path, s.document_status, s.min_role
    );

    MERGE INTO cb_document_extraction t
    USING (
      SELECT
        d.document_sk,
        d.application_sk,
        'EXT-' || d.document_id AS extraction_id,
        d.document_id,
        d.document_type,
        la.application_id
      FROM cb_document d
      JOIN cb_loan_application la ON la.application_sk = d.application_sk
    ) s
    ON (t.extraction_id = s.extraction_id)
    WHEN MATCHED THEN UPDATE SET
      t.extraction_status = 'SUCCEEDED',
      t.extraction_payload = JSON_OBJECT(
        'applicationId' VALUE s.application_id,
        'documentId' VALUE s.document_id,
        'documentType' VALUE s.document_type,
        'source' VALUE 'seed-data.json'
        RETURNING JSON
      ),
      t.confidence_score = 0.95
    WHEN NOT MATCHED THEN INSERT (
      document_sk, application_sk, extraction_id, provider, extraction_model,
      extraction_status, extraction_payload, raw_text_line_count, confidence_score
    ) VALUES (
      s.document_sk, s.application_sk, s.extraction_id, 'DOCUMENT_INGEST', 'fixture-loader',
      'SUCCEEDED',
      JSON_OBJECT(
        'applicationId' VALUE s.application_id,
        'documentId' VALUE s.document_id,
        'documentType' VALUE s.document_type,
        'source' VALUE 'seed-data.json'
        RETURNING JSON
      ),
      20,
      0.95
    );

    MERGE INTO cb_income_evidence t
    USING (
      SELECT
        la.application_sk,
        d.document_sk,
        jt.stated_gross_monthly_income,
        jt.pay_document_monthly_income,
        jt.verified_gross_monthly_income,
        jt.income_consistency_result,
        jt.extraction_confidence,
        jt.document_validation_status
      FROM JSON_TABLE(l_payload, '$.applications[*]' COLUMNS (
        application_id VARCHAR2(40) PATH '$.applicationId',
        document_id VARCHAR2(60) PATH '$.incomeEvidence.documentId',
        stated_gross_monthly_income NUMBER PATH '$.incomeEvidence.statedGrossMonthlyIncome',
        pay_document_monthly_income NUMBER PATH '$.incomeEvidence.payDocumentMonthlyIncome',
        verified_gross_monthly_income NUMBER PATH '$.incomeEvidence.verifiedGrossMonthlyIncome',
        income_consistency_result VARCHAR2(80) PATH '$.incomeEvidence.incomeConsistencyResult',
        extraction_confidence VARCHAR2(40) PATH '$.incomeEvidence.extractionConfidence',
        document_validation_status VARCHAR2(40) PATH '$.incomeEvidence.documentValidationStatus'
      )) jt
      JOIN cb_loan_application la ON la.application_id = jt.application_id
      LEFT JOIN cb_document d ON d.document_id = jt.document_id
    ) s
    ON (t.application_sk = s.application_sk)
    WHEN MATCHED THEN UPDATE SET
      t.document_sk = s.document_sk,
      t.stated_gross_monthly_income = s.stated_gross_monthly_income,
      t.pay_document_monthly_income = s.pay_document_monthly_income,
      t.verified_gross_monthly_income = s.verified_gross_monthly_income,
      t.income_consistency_result = s.income_consistency_result,
      t.extraction_confidence = s.extraction_confidence,
      t.document_validation_status = s.document_validation_status
    WHEN NOT MATCHED THEN INSERT (
      application_sk, document_sk, stated_gross_monthly_income,
      pay_document_monthly_income, verified_gross_monthly_income,
      income_consistency_result, extraction_confidence, document_validation_status
    ) VALUES (
      s.application_sk, s.document_sk, s.stated_gross_monthly_income,
      s.pay_document_monthly_income, s.verified_gross_monthly_income,
      s.income_consistency_result, s.extraction_confidence, s.document_validation_status
    );

    MERGE INTO cb_liability_snapshot t
    USING (
      SELECT la.application_sk, jt.*
      FROM JSON_TABLE(l_payload, '$.applications[*]' COLUMNS (
        application_id VARCHAR2(40) PATH '$.applicationId',
        existing_monthly_debt NUMBER PATH '$.liability.existingMonthlyDebt',
        proposed_monthly_payment NUMBER PATH '$.liability.proposedMonthlyPayment',
        debt_to_income_pct NUMBER PATH '$.liability.debtToIncomePct',
        recent_delinquency_indicator VARCHAR2(40) PATH '$.liability.recentDelinquencyIndicator',
        bankruptcy_indicator VARCHAR2(40) PATH '$.liability.bankruptcyIndicator'
      )) jt
      JOIN cb_loan_application la ON la.application_id = jt.application_id
    ) s
    ON (t.application_sk = s.application_sk)
    WHEN MATCHED THEN UPDATE SET
      t.existing_monthly_debt = s.existing_monthly_debt,
      t.proposed_monthly_payment = s.proposed_monthly_payment,
      t.debt_to_income_pct = s.debt_to_income_pct,
      t.recent_delinquency_indicator = s.recent_delinquency_indicator,
      t.bankruptcy_indicator = s.bankruptcy_indicator
    WHEN NOT MATCHED THEN INSERT (
      application_sk, existing_monthly_debt, proposed_monthly_payment,
      debt_to_income_pct, recent_delinquency_indicator, bankruptcy_indicator
    ) VALUES (
      s.application_sk, s.existing_monthly_debt, s.proposed_monthly_payment,
      s.debt_to_income_pct, s.recent_delinquency_indicator, s.bankruptcy_indicator
    );

    MERGE INTO cb_payment_calculation t
    USING (
      SELECT la.application_sk, jt.*
      FROM JSON_TABLE(l_payload, '$.applications[*]' COLUMNS (
        application_id VARCHAR2(40) PATH '$.applicationId',
        requested_amount NUMBER PATH '$.payment.requestedAmount',
        evaluated_amount NUMBER PATH '$.payment.evaluatedAmount',
        term_months NUMBER PATH '$.payment.termMonths',
        apr_text VARCHAR2(30) PATH '$.payment.aprText',
        monthly_payment NUMBER PATH '$.payment.monthlyPayment',
        calculation_status VARCHAR2(40) PATH '$.payment.calculationStatus'
      )) jt
      JOIN cb_loan_application la ON la.application_id = jt.application_id
    ) s
    ON (t.application_sk = s.application_sk)
    WHEN MATCHED THEN UPDATE SET
      t.requested_amount = s.requested_amount,
      t.evaluated_amount = s.evaluated_amount,
      t.term_months = s.term_months,
      t.apr_text = s.apr_text,
      t.monthly_payment = s.monthly_payment,
      t.calculation_status = s.calculation_status
    WHEN NOT MATCHED THEN INSERT (
      application_sk, requested_amount, evaluated_amount, term_months,
      apr_text, monthly_payment, calculation_status
    ) VALUES (
      s.application_sk, s.requested_amount, s.evaluated_amount, s.term_months,
      s.apr_text, s.monthly_payment, s.calculation_status
    );

    MERGE INTO cb_document_fact t
    USING (
      SELECT la.application_sk, jt.fact_name, jt.fact_value_text, jt.fact_value_number, jt.confidence
      FROM JSON_TABLE(l_payload, '$.applications[*]' COLUMNS (
        application_id VARCHAR2(40) PATH '$.applicationId',
        NESTED PATH '$.documentFacts[*]' COLUMNS (
          fact_name VARCHAR2(100) PATH '$.factName',
          fact_value_text VARCHAR2(1000) PATH '$.factValueText',
          fact_value_number NUMBER PATH '$.factValueNumber',
          confidence NUMBER PATH '$.confidence'
        )
      )) jt
      JOIN cb_loan_application la ON la.application_id = jt.application_id
    ) s
    ON (t.application_sk = s.application_sk AND t.fact_name = s.fact_name)
    WHEN MATCHED THEN UPDATE SET
      t.fact_value_text = s.fact_value_text,
      t.fact_value_number = s.fact_value_number,
      t.confidence_score = s.confidence
    WHEN NOT MATCHED THEN INSERT (
      application_sk, fact_name, fact_value_text, fact_value_number, confidence_score
    ) VALUES (
      s.application_sk, s.fact_name, s.fact_value_text, s.fact_value_number, s.confidence
    );

    MERGE INTO cb_document_issue t
    USING (
      SELECT la.application_sk, jt.*
      FROM JSON_TABLE(l_payload, '$.applications[*]' COLUMNS (
        application_id VARCHAR2(40) PATH '$.applicationId',
        NESTED PATH '$.documentIssues[*]' COLUMNS (
          issue_code VARCHAR2(120) PATH '$.issueCode',
          issue_severity VARCHAR2(40) PATH '$.severity',
          routing_effect VARCHAR2(60) PATH '$.routingEffect',
          policy_hint VARCHAR2(80) PATH '$.policyHint'
        )
      )) jt
      JOIN cb_loan_application la ON la.application_id = jt.application_id
    ) s
    ON (t.application_sk = s.application_sk AND t.issue_code = s.issue_code)
    WHEN MATCHED THEN UPDATE SET
      t.issue_severity = s.issue_severity,
      t.routing_effect = s.routing_effect,
      t.policy_hint = s.policy_hint
    WHEN NOT MATCHED THEN INSERT (
      application_sk, issue_code, issue_severity, routing_effect, policy_hint
    ) VALUES (
      s.application_sk, s.issue_code, s.issue_severity, s.routing_effect, s.policy_hint
    );

    MERGE INTO cb_document_chunk t
    USING (
      SELECT d.document_sk, la.application_sk, jt.*
      FROM JSON_TABLE(l_payload, '$.applications[*]' COLUMNS (
        application_id VARCHAR2(40) PATH '$.applicationId',
        NESTED PATH '$.documentChunks[*]' COLUMNS (
          document_id VARCHAR2(60) PATH '$.documentId',
          chunk_id VARCHAR2(80) PATH '$.chunkId',
          ordinal NUMBER PATH '$.ordinal',
          min_role VARCHAR2(40) PATH '$.minRole',
          text VARCHAR2(4000) PATH '$.text',
          embedding_text VARCHAR2(4000) PATH '$.embeddingText'
        )
      )) jt
      JOIN cb_loan_application la ON la.application_id = jt.application_id
      JOIN cb_document d ON d.document_id = jt.document_id
    ) s
    ON (t.chunk_id = s.chunk_id)
    WHEN MATCHED THEN UPDATE SET
      t.document_sk = s.document_sk,
      t.application_sk = s.application_sk,
      t.chunk_ordinal = s.ordinal,
      t.chunk_text = s.text,
      t.min_role = s.min_role,
      t.embedding = TO_VECTOR(s.embedding_text)
    WHEN NOT MATCHED THEN INSERT (
      document_sk, application_sk, chunk_id, chunk_ordinal, chunk_text, min_role, embedding
    ) VALUES (
      s.document_sk, s.application_sk, s.chunk_id, s.ordinal, s.text, s.min_role, TO_VECTOR(s.embedding_text)
    );

    MERGE INTO cb_relationship_edge t
    USING (
      SELECT la.application_sk, jt.*
      FROM JSON_TABLE(l_payload, '$.applications[*]' COLUMNS (
        application_id VARCHAR2(40) PATH '$.applicationId',
        NESTED PATH '$.relationships[*]' COLUMNS (
          edge_id VARCHAR2(80) PATH '$.edgeId',
          source_entity_type VARCHAR2(40) PATH '$.sourceEntityType',
          source_entity_id VARCHAR2(80) PATH '$.sourceEntityId',
          target_entity_type VARCHAR2(40) PATH '$.targetEntityType',
          target_entity_id VARCHAR2(80) PATH '$.targetEntityId',
          relationship_type VARCHAR2(60) PATH '$.relationshipType',
          evidence_strength NUMBER PATH '$.evidenceStrength',
          signal_status VARCHAR2(40) PATH '$.signalStatus'
        )
      )) jt
      JOIN cb_loan_application la ON la.application_id = jt.application_id
    ) s
    ON (t.edge_id = s.edge_id)
    WHEN MATCHED THEN UPDATE SET
      t.application_sk = s.application_sk,
      t.source_entity_type = s.source_entity_type,
      t.source_entity_id = s.source_entity_id,
      t.target_entity_type = s.target_entity_type,
      t.target_entity_id = s.target_entity_id,
      t.relationship_type = s.relationship_type,
      t.evidence_strength = s.evidence_strength,
      t.signal_status = s.signal_status
    WHEN NOT MATCHED THEN INSERT (
      edge_id, application_sk, source_entity_type, source_entity_id,
      target_entity_type, target_entity_id, relationship_type, evidence_strength, signal_status
    ) VALUES (
      s.edge_id, s.application_sk, s.source_entity_type, s.source_entity_id,
      s.target_entity_type, s.target_entity_id, s.relationship_type, s.evidence_strength, s.signal_status
    );

    MERGE INTO cb_spatial_signal t
    USING (
      SELECT la.application_sk, ad.address_sk, z.jurisdiction_zone_sk, jt.*,
             CASE
               WHEN jt.signal_result = 'NOT_EVALUATED' THEN 'ADDRESS_COORDINATES_MISSING'
               WHEN jt.signal_type = 'BOUNDARY_PROXIMITY' THEN 'BOUNDARY_REVIEW_REQUIRED'
               WHEN jt.signal_type = 'RISK_ZONE_INTERSECTION' THEN 'LOCATION_RISK_REVIEW'
               WHEN jt.signal_result = 'FAIL' THEN 'LOCATION_EXCLUDED'
               ELSE 'LOCATION_IN_SERVICE_AREA'
             END signal_code
      FROM JSON_TABLE(l_payload, '$.applications[*]' COLUMNS (
        application_id VARCHAR2(40) PATH '$.applicationId',
        applicant_id VARCHAR2(40) PATH '$.applicantId',
        signal_id VARCHAR2(80) PATH '$.spatialSignal.signalId',
        zone_id VARCHAR2(80) PATH '$.spatialSignal.zoneId',
        signal_type VARCHAR2(60) PATH '$.spatialSignal.signalType',
        signal_result VARCHAR2(60) PATH '$.spatialSignal.signalResult',
        distance_to_boundary_m NUMBER PATH '$.spatialSignal.distanceToBoundaryM',
        routing_effect VARCHAR2(60) PATH '$.spatialSignal.routingEffect'
      )) jt
      JOIN cb_loan_application la ON la.application_id = jt.application_id
      JOIN cb_applicant a ON a.applicant_id = jt.applicant_id
      JOIN cb_address ad ON ad.applicant_sk = a.applicant_sk
      LEFT JOIN cb_jurisdiction_zone z ON z.zone_id = jt.zone_id
      WHERE jt.signal_id IS NOT NULL
    ) s
    ON (t.signal_id = s.signal_id)
    WHEN MATCHED THEN UPDATE SET
      t.application_sk = s.application_sk,
      t.address_sk = s.address_sk,
      t.jurisdiction_zone_sk = s.jurisdiction_zone_sk,
      t.signal_code = s.signal_code,
      t.signal_type = s.signal_type,
      t.signal_result = s.signal_result,
      t.distance_to_boundary_m = s.distance_to_boundary_m,
      t.routing_effect = s.routing_effect
    WHEN NOT MATCHED THEN INSERT (
      application_sk, address_sk, jurisdiction_zone_sk, signal_id,
      signal_code, signal_type, signal_result, distance_to_boundary_m, routing_effect
    ) VALUES (
      s.application_sk, s.address_sk, s.jurisdiction_zone_sk, s.signal_id,
      s.signal_code, s.signal_type, s.signal_result, s.distance_to_boundary_m, s.routing_effect
    );

    MERGE INTO cb_decision t
    USING (
      SELECT la.application_sk, jt.*
      FROM JSON_TABLE(l_payload, '$.applications[*]' COLUMNS (
        application_id VARCHAR2(40) PATH '$.applicationId',
        decision_id VARCHAR2(80) PATH '$.decision.decisionId',
        decision_type VARCHAR2(40) PATH '$.decision.decisionType',
        decision_outcome VARCHAR2(40) PATH '$.decision.decisionOutcome',
        risk_band VARCHAR2(20) PATH '$.decision.riskBand'
      )) jt
      JOIN cb_loan_application la ON la.application_id = jt.application_id
    ) s
    ON (t.decision_id = s.decision_id)
    WHEN MATCHED THEN UPDATE SET
      t.application_sk = s.application_sk,
      t.decision_type = s.decision_type,
      t.decision_outcome = s.decision_outcome,
      t.risk_band = s.risk_band,
      t.decision_payload = JSON_OBJECT('source' VALUE 'seed-data.json' RETURNING JSON)
    WHEN NOT MATCHED THEN INSERT (
      application_sk, decision_id, decision_type, decision_outcome, risk_band, decision_payload
    ) VALUES (
      s.application_sk, s.decision_id, s.decision_type, s.decision_outcome, s.risk_band,
      JSON_OBJECT('source' VALUE 'seed-data.json' RETURNING JSON)
    );

    MERGE INTO cb_decision_policy_evidence t
    USING (
      SELECT
        d.decision_sk,
        pc.policy_chunk_sk,
        jt.decision_id || '-' || jt.chunk_id AS evidence_id,
        pd.policy_code,
        pc.section_ref,
        'ROUTING' AS evidence_role,
        pc.heading AS evidence_summary
      FROM JSON_TABLE(l_payload, '$.applications[*]' COLUMNS (
        decision_id VARCHAR2(80) PATH '$.decision.decisionId',
        NESTED PATH '$.decision.evidenceChunkIds[*]' COLUMNS (
          chunk_id VARCHAR2(100) PATH '$'
        )
      )) jt
      JOIN cb_decision d ON d.decision_id = jt.decision_id
      JOIN cb_policy_chunk pc ON pc.chunk_id = jt.chunk_id
      JOIN cb_policy_document pd ON pd.policy_document_sk = pc.policy_document_sk
    ) s
    ON (t.evidence_id = s.evidence_id)
    WHEN MATCHED THEN UPDATE SET
      t.decision_sk = s.decision_sk,
      t.policy_chunk_sk = s.policy_chunk_sk,
      t.policy_code = s.policy_code,
      t.section_ref = s.section_ref,
      t.evidence_summary = s.evidence_summary
    WHEN NOT MATCHED THEN INSERT (
      decision_sk, policy_chunk_sk, evidence_id, policy_code, section_ref,
      evidence_role, evidence_summary
    ) VALUES (
      s.decision_sk, s.policy_chunk_sk, s.evidence_id, s.policy_code, s.section_ref,
      s.evidence_role, s.evidence_summary
    );

    MERGE INTO cb_explanation t
    USING (
      SELECT d.decision_sk, jt.decision_id || '-UW' AS explanation_id, jt.explanation
      FROM JSON_TABLE(l_payload, '$.applications[*]' COLUMNS (
        decision_id VARCHAR2(80) PATH '$.decision.decisionId',
        explanation VARCHAR2(4000) PATH '$.decision.explanation'
      )) jt
      JOIN cb_decision d ON d.decision_id = jt.decision_id
    ) s
    ON (t.explanation_id = s.explanation_id)
    WHEN MATCHED THEN UPDATE SET
      t.explanation_text = s.explanation,
      t.explanation_status = 'READY'
    WHEN NOT MATCHED THEN INSERT (
      decision_sk, explanation_id, audience, explanation_text
    ) VALUES (
      s.decision_sk, s.explanation_id, 'UNDERWRITER', s.explanation
    );

    MERGE INTO cb_manual_review_task t
    USING (
      SELECT la.application_sk, jt.*
      FROM JSON_TABLE(l_payload, '$.applications[*]' COLUMNS (
        application_id VARCHAR2(40) PATH '$.applicationId',
        task_id VARCHAR2(80) PATH '$.reviewTask.taskId',
        task_type VARCHAR2(60) PATH '$.reviewTask.taskType',
        priority VARCHAR2(20) PATH '$.reviewTask.priority',
        reason_code VARCHAR2(120) PATH '$.reviewTask.reasonCode'
      )) jt
      JOIN cb_loan_application la ON la.application_id = jt.application_id
      WHERE jt.task_id IS NOT NULL
    ) s
    ON (t.task_id = s.task_id)
    WHEN MATCHED THEN UPDATE SET
      t.application_sk = s.application_sk,
      t.task_type = s.task_type,
      t.priority = s.priority,
      t.reason_code = s.reason_code,
      t.task_status = 'OPEN',
      t.updated_at = SYSTIMESTAMP
    WHEN NOT MATCHED THEN INSERT (
      application_sk, task_id, task_type, priority, reason_code
    ) VALUES (
      s.application_sk, s.task_id, s.task_type, s.priority, s.reason_code
    );

    MERGE INTO cb_workflow_instance t
    USING (
      SELECT la.application_sk, jt.*
      FROM JSON_TABLE(l_payload, '$.applications[*]' COLUMNS (
        application_id VARCHAR2(40) PATH '$.applicationId',
        workflow_id VARCHAR2(80) PATH '$.workflowId',
        trace_id VARCHAR2(80) PATH '$.traceId',
        application_status VARCHAR2(40) PATH '$.applicationStatus'
      )) jt
      JOIN cb_loan_application la ON la.application_id = jt.application_id
    ) s
    ON (t.workflow_id = s.workflow_id)
    WHEN MATCHED THEN UPDATE SET
      t.application_sk = s.application_sk,
      t.workflow_status = CASE s.application_status WHEN 'MANUAL_REVIEW' THEN 'WAITING' WHEN 'RECOVERED' THEN 'RECOVERED' ELSE 'COMPLETED' END,
      t.trace_id = s.trace_id
    WHEN NOT MATCHED THEN INSERT (
      application_sk, workflow_id, workflow_status, trace_id
    ) VALUES (
      s.application_sk, s.workflow_id,
      CASE s.application_status WHEN 'MANUAL_REVIEW' THEN 'WAITING' WHEN 'RECOVERED' THEN 'RECOVERED' ELSE 'COMPLETED' END,
      s.trace_id
    );

    MERGE INTO cb_workflow_event t
    USING (
      SELECT wi.workflow_instance_sk, wi.workflow_id || '-SUBMITTED' AS event_id,
             'APPLICATION_SUBMITTED' AS event_type, 'SUCCEEDED' AS event_status,
             'loan-service' AS service_name, wi.trace_id
      FROM cb_workflow_instance wi
      UNION ALL
      SELECT wi.workflow_instance_sk, wi.workflow_id || '-DECISIONED' AS event_id,
             'DECISION_COMPLETED' AS event_type, 'SUCCEEDED' AS event_status,
             'decision-service' AS service_name, wi.trace_id
      FROM cb_workflow_instance wi
    ) s
    ON (t.event_id = s.event_id)
    WHEN MATCHED THEN UPDATE SET
      t.workflow_instance_sk = s.workflow_instance_sk,
      t.event_type = s.event_type,
      t.event_status = s.event_status,
      t.service_name = s.service_name,
      t.trace_id = s.trace_id
    WHEN NOT MATCHED THEN INSERT (
      workflow_instance_sk, event_id, event_type, event_status, service_name, trace_id
    ) VALUES (
      s.workflow_instance_sk, s.event_id, s.event_type, s.event_status, s.service_name, s.trace_id
    );

    MERGE INTO cb_telemetry_correlation t
    USING (
      SELECT la.application_sk, 'TEL-' || la.application_id AS correlation_id,
             wi.trace_id, 'loan-origination' AS service_name, 'TRACE' AS telemetry_kind
      FROM cb_loan_application la
      JOIN cb_workflow_instance wi ON wi.application_sk = la.application_sk
    ) s
    ON (t.correlation_id = s.correlation_id)
    WHEN MATCHED THEN UPDATE SET
      t.application_sk = s.application_sk,
      t.trace_id = s.trace_id,
      t.service_name = s.service_name,
      t.telemetry_kind = s.telemetry_kind
    WHEN NOT MATCHED THEN INSERT (
      application_sk, correlation_id, trace_id, service_name, telemetry_kind
    ) VALUES (
      s.application_sk, s.correlation_id, s.trace_id, s.service_name, s.telemetry_kind
    );

    MERGE INTO cb_audit_event t
    USING (
      SELECT la.application_sk, 'AUD-' || la.application_id || '-DECISION' AS audit_event_id,
             'svc-decision' AS principal_id, 'DECISION_RECORDED' AS event_action,
             'SUCCESS' AS event_outcome, 'CB_DECISION' AS object_type,
             d.decision_id AS object_id, wi.trace_id
      FROM cb_loan_application la
      JOIN cb_decision d ON d.application_sk = la.application_sk
      JOIN cb_workflow_instance wi ON wi.application_sk = la.application_sk
    ) s
    ON (t.audit_event_id = s.audit_event_id)
    WHEN MATCHED THEN UPDATE SET
      t.application_sk = s.application_sk,
      t.principal_id = s.principal_id,
      t.event_action = s.event_action,
      t.event_outcome = s.event_outcome,
      t.object_type = s.object_type,
      t.object_id = s.object_id,
      t.trace_id = s.trace_id
    WHEN NOT MATCHED THEN INSERT (
      application_sk, audit_event_id, principal_id, event_action,
      event_outcome, object_type, object_id, trace_id
    ) VALUES (
      s.application_sk, s.audit_event_id, s.principal_id, s.event_action,
      s.event_outcome, s.object_type, s.object_id, s.trace_id
    );

    COMMIT;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(-20001, 'Seed payload not found: ' || p_seed_name);
  END load;
END cb_seed_loader;
/
