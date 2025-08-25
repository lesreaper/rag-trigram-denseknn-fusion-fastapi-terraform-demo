-- Extensions
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS vector;

-- Table (adjust vector dimension to your embed model)
-- For OpenAI text-embedding-3-small use 1536; for -3-large use 3072.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name='documents') THEN
    CREATE TABLE documents (
      id BIGSERIAL PRIMARY KEY,
      tenant_id TEXT NOT NULL,
      content TEXT NOT NULL,
      embedding vector(1536)  -- <— set to 1536 or 3072 to match EMBED_MODEL
    );
  END IF;
END $$;

-- Indexes (idempotent)
CREATE INDEX IF NOT EXISTS idx_documents_content_trgm
  ON documents USING gin (content gin_trgm_ops);

CREATE INDEX IF NOT EXISTS idx_documents_tenant
  ON documents (tenant_id);

-- ANN index only if vector is present and column exists
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname='vector') THEN
    IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname='idx_documents_embedding') THEN
      EXECUTE 'CREATE INDEX idx_documents_embedding
               ON documents USING ivfflat (embedding vector_l2_ops)
               WITH (lists = 50)';
    END IF;
  END IF;
END $$;
