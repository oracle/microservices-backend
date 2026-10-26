-- CloudBank AI 2026.0
-- 003-vector-indexes.sql
-- 26ai vector indexes for authorized RAG retrieval.

CREATE VECTOR INDEX cb_policy_chunk_embedding_vix
  ON cb_policy_chunk (embedding)
  ORGANIZATION INMEMORY NEIGHBOR GRAPH
  DISTANCE COSINE
  WITH TARGET ACCURACY 95;

CREATE VECTOR INDEX cb_document_chunk_embedding_vix
  ON cb_document_chunk (embedding)
  ORGANIZATION INMEMORY NEIGHBOR GRAPH
  DISTANCE COSINE
  WITH TARGET ACCURACY 95;
