from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from ingest import router as ingest_router
from chat import router as chat_router
from debug import router as debug_router
from presign import router as presign_router

app = FastAPI(title="Kizen Demo API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Mount routers
app.include_router(ingest_router, prefix="/api")
app.include_router(chat_router, prefix="/api")
app.include_router(debug_router, prefix="/api")
app.include_router(presign_router, prefix="/api")

@app.get("/health")
def health():
    return {"status": "ok"}

@app.get("/api/health")
def health_api():
    return {"status": "ok"}