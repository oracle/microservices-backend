-- CloudBank AI 2026.0
-- 007-ords-inspection-endpoints.sql
-- Read-only ORDS inspection endpoints for demos.

BEGIN
  ORDS.ENABLE_SCHEMA(
    p_enabled             => TRUE,
    p_schema              => USER,
    p_url_mapping_type    => 'BASE_PATH',
    p_url_mapping_pattern => 'cloudbank',
    p_auto_rest_auth      => FALSE
  );

  ORDS.DEFINE_MODULE(
    p_module_name    => 'cloudbank.schema',
    p_base_path      => '/schema/',
    p_items_per_page => 25,
    p_status         => 'PUBLISHED',
    p_comments       => 'CloudBank schema inspection endpoints backed by read-only views.'
  );

  ORDS.DEFINE_TEMPLATE(
    p_module_name => 'cloudbank.schema',
    p_pattern     => 'applications/:application_id'
  );

  ORDS.DEFINE_HANDLER(
    p_module_name => 'cloudbank.schema',
    p_pattern     => 'applications/:application_id',
    p_method      => 'GET',
    p_source_type => ORDS.source_type_collection_item,
    p_source      => q'[
      SELECT *
      FROM cb_v_application_summary
      WHERE application_id = :application_id
    ]',
    p_items_per_page => 1
  );

  ORDS.DEFINE_TEMPLATE(
    p_module_name => 'cloudbank.schema',
    p_pattern     => 'manual-review'
  );

  ORDS.DEFINE_HANDLER(
    p_module_name => 'cloudbank.schema',
    p_pattern     => 'manual-review',
    p_method      => 'GET',
    p_source_type => ORDS.source_type_collection_feed,
    p_source      => q'[
      SELECT *
      FROM cb_v_manual_review_queue
      ORDER BY
        CASE priority
          WHEN 'URGENT' THEN 1
          WHEN 'HIGH' THEN 2
          WHEN 'NORMAL' THEN 3
          ELSE 4
        END,
        created_at
    ]'
  );

  COMMIT;
END;
/
