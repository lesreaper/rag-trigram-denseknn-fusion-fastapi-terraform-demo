import os

# Environment
OPENAI_API_KEY = os.environ["OPENAI_API_KEY"]
POSTGRES_HOST = os.environ["POSTGRES_HOST"]
POSTGRES_PORT = os.environ["POSTGRES_PORT"]
POSTGRES_DB = os.environ["POSTGRES_DB"]
POSTGRES_USER = os.environ["POSTGRES_USER"]
POSTGRES_PASSWORD = os.environ["POSTGRES_PASSWORD"]
AWS_REGION = os.environ.get("AWS_REGION", "us-east-1")
SENTRY_API_DSN = os.environ.get("SENTRY_API_DSN")

# Embeddings
EMBED_MODEL = os.environ.get("EMBED_MODEL", "text-embedding-3-small")
MAX_TOKENS_PER_ITEM = int(os.environ.get("MAX_TOKENS_PER_ITEM", "8000"))      # cap each row
MAX_TOKENS_PER_BATCH = int(os.environ.get("MAX_TOKENS_PER_BATCH", "240000"))  # < 300k safety
MAX_ITEMS_PER_BATCH = int(os.environ.get("MAX_ITEMS_PER_BATCH", "128"))
MAX_CONTEXT_CHARS = int(os.environ.get("MAX_CONTEXT_CHARS", "25000"))  # for retrieval
EMBED_DIM = int(os.environ.get("EMBED_DIM", "1536"))
BATCH_SIZE_HARD_LIMIT  = int(os.environ.get("BATCH_SIZE_HARD_LIMIT ", "200"))

# Answering
ANSWER_MODEL = os.environ.get("ANSWER_MODEL", "gpt-4o-mini")
ANSWER_TEMPERATURE = float(os.environ.get("ANSWER_TEMPERATURE", "0.5"))

# Concurrency
EMBED_CONCURRENCY = int(os.environ.get("EMBED_CONCURRENCY", "3"))
