-- CloudBank AI 2026.0
-- Auditable identity for an immutable policy corpus and its OCI GenAI embeddings.

CREATE TABLE cb_policy_corpus_load (
  corpus_id VARCHAR2(80) NOT NULL,
  corpus_version VARCHAR2(20) NOT NULL,
  corpus_sha256 CHAR(64) NOT NULL,
  embedding_provider VARCHAR2(40) NOT NULL,
  embedding_model VARCHAR2(200) NOT NULL,
  embedding_region VARCHAR2(80),
  embedding_dimensions NUMBER(8,0) NOT NULL,
  document_count NUMBER(8,0) NOT NULL,
  chunk_count NUMBER(8,0) NOT NULL,
  loaded_at TIMESTAMP WITH LOCAL TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT cb_policy_corpus_load_pk PRIMARY KEY (corpus_id),
  CONSTRAINT cb_policy_corpus_sha_ck CHECK (REGEXP_LIKE(corpus_sha256, '^[0-9a-f]{64}$')),
  CONSTRAINT cb_policy_corpus_provider_ck CHECK (embedding_provider = 'OCI_GENAI'),
  CONSTRAINT cb_policy_corpus_dim_ck CHECK (embedding_dimensions > 0),
  CONSTRAINT cb_policy_corpus_doc_count_ck CHECK (document_count > 0),
  CONSTRAINT cb_policy_corpus_chunk_count_ck CHECK (chunk_count > 0)
);

COMMENT ON TABLE cb_policy_corpus_load IS
  'Immutable identity and OCI GenAI embedding metadata for a loaded CloudBank policy corpus.';
COMMENT ON COLUMN cb_policy_corpus_load.corpus_sha256 IS
  'SHA-256 digest over the manifest and every policy file in manifest order.';
COMMENT ON COLUMN cb_policy_corpus_load.embedding_model IS
  'OCI Generative AI embedding model used for both policy load and query embeddings.';

ALTER TABLE cb_policy_corpus_load ANNOTATIONS (
  ADD Domain 'Policy RAG',
  ADD Entity 'Policy Corpus Load',
  ADD OwnerService 'policy-loader',
  ADD OracleFeature 'Vector Search',
  ADD DataClassification 'internal'
);
