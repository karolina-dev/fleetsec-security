from fastapi import FastAPI

app = FastAPI(
    title="FleetSec API",
    description="API for fleet telemetry management",
    version="1.0.0"
)


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