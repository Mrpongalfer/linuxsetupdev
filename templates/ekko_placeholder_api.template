#!/usr/bin/env python3
# File: src/ekko/api/main.py
"""Project Ekko - FastAPI Backend (Placeholder)"""
import logging
from fastapi import FastAPI

logger = logging.getLogger(__name__)
app = FastAPI(title="Project Ekko API", version="0.1.0")

@app.on_event("startup")
async def startup_event():
    logger.info("Ekko API starting up...")
    # Add any async setup needed here (e.g., DB connection pool)

@app.on_event("shutdown")
async def shutdown_event():
    logger.info("Ekko API shutting down...")
    # Add cleanup here

@app.get("/")
async def read_root():
    """Root endpoint."""
    logger.debug("Root endpoint accessed.")
    return {"message": "Welcome to Ekko API v0.1"}

@app.get("/health")
async def health_check():
    """Basic health check."""
    logger.debug("Health check accessed.")
    # TODO: Add checks for DB, LLM connectivity etc.
    return {"status": "ok"}

# TODO: Add more sophisticated endpoints for:
# - Project initialization (POST /projects)
# - Code generation (POST /projects/{id}/generate)
# - Validation runs (POST /projects/{id}/validate, GET /projects/{id}/validation/{run_id})
# - Deployments (POST /projects/{id}/deployments)
# - Status updates

# Add uvicorn runner for direct execution (primarily for development)
if __name__ == "__main__":
    try:
        import uvicorn
        logger.info("Running Uvicorn server for development...")
        # Use host 0.0.0.0 to be accessible on network if needed
        uvicorn.run(app, host="0.0.0.0", port=8888, log_level="info")
    except ImportError:
        logger.error("Uvicorn not installed. Run 'pip install uvicorn[standard]'")
        print("ERROR: Uvicorn not installed. Cannot run API server directly.", file=sys.stderr)