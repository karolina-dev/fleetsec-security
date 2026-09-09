from fastapi import FastAPI

from .database import Base, engine
from . import models
from .routes import auth

Base.metadata.create_all(bind=engine)

app = FastAPI(
    title="FleetSec API",
    description="API for fleet telemetry management",
    version="1.0.0"
)

app.include_router(auth.router)


@app.get("/health")
def health():
    return {
        "status": "ok",
        "service": "fleetsec-api"
    }


@app.get("/")
def root():
    return {
        "message": "FleetSec API"
    }