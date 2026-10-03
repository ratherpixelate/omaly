import threading

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from api import search, best_shot, wrapped, thumbnails
from ingestion import quality

app = FastAPI(title="Omaly API")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

@app.on_event("startup")
def warm_best_shot():
    # Load models + cache burst metrics in the background so the first
    # /best-shot call stays inside the frontend's 10s timeout.
    threading.Thread(target=quality.warm, daemon=True).start()

@app.get("/health")
def health():
    return {"status": "ok"}

for r in (search.router, best_shot.router, wrapped.router, thumbnails.router):
    app.include_router(r)