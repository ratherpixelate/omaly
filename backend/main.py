from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from api import search, best_shot, wrapped, thumbnails

app = FastAPI(title="Omaly API")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

@app.get("/health")
def health():
    return {"status": "ok"}

for r in (search.router, best_shot.router, wrapped.router, thumbnails.router):
    app.include_router(r)