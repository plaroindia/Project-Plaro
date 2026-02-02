"""
PEARL Agent Backend - Vercel Entry Point
"""

import sys
import os
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

# Ensure imports work
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.append(os.path.dirname(BASE_DIR))

app = FastAPI(
    title="PEARL Agent API",
    description="Agentic Career Mentor",
    version="1.0.0"
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

try:
    from routes.pearl_routes import router as pearl_router
    app.include_router(pearl_router, prefix="/agent", tags=["PEARL Agent"])
except Exception as e:
    print("Router import error:", e)

@app.get("/")
async def root():
    return {
        "status": "online",
        "service": "PEARL Agent API",
        "docs": "/docs",
        "health": "/health"
    }

@app.get("/health")
async def health():
    return {"status": "healthy"}

@app.get("/test")
async def test():
    return {"message": "API working"}

@app.exception_handler(Exception)
async def error_handler(request, exc):
    return JSONResponse(
        status_code=500,
        content={
            "error": str(exc),
            "type": type(exc).__name__
        }
    )
    