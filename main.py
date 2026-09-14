import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from app.config import settings
from app.db import init_db
from app.routes import (
    admin,
    ai,
    auth,
    challenges,
    health,
    industry,
    ml,
    notifications,
    projects,
    universities,
    uploads,
)

logging.basicConfig(
    level=logging.INFO if not settings.DEBUG else logging.DEBUG,
    format="%(asctime)s %(levelname)-8s %(name)s: %(message)s",
)
log = logging.getLogger("janyukti")


@asynccontextmanager
async def lifespan(app: FastAPI):
    await init_db()
    log.info("Database ready (%s)", settings.DATABASE_URL.split("://")[0])

    # Report which AI backend is live at boot, so a missing key is obvious
    # immediately rather than halfway through a demo.
    from app.ml.embeddings import active_model_name
    from app.ml.llm import is_available

    log.info("AI engine: llm=%s embeddings=%s",
             settings.GEMINI_MODEL if is_available() else "heuristic-fallback",
             active_model_name())
    if settings.FIREBASE_AUTH_MODE.strip().lower() == "off":
        log.warning("FIREBASE_AUTH_MODE=off: /ai routes accept unauthenticated requests")
    else:
        log.info("Firebase auth required for /ai (project %s)", settings.FIREBASE_PROJECT_ID)
    yield


app = FastAPI(
    title=settings.APP_NAME,
    description=(
        "Backend for JanYukti (SIH26043): crowdsourced societal challenges routed "
        "to university and industry partners by an AI matching engine."
    ),
    version=settings.VERSION,
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origin_list,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.exception_handler(Exception)
async def unhandled_exception_handler(request: Request, exc: Exception):
    log.exception("Unhandled error on %s %s", request.method, request.url.path)
    return JSONResponse(status_code=500, content={"detail": "Internal server error"})


for router in (
    health.router,
    ai.router,
    auth.router,
    challenges.router,
    projects.router,
    universities.router,
    industry.router,
    admin.router,
    ml.router,
    notifications.router,
    uploads.router,
):
    app.include_router(router)


@app.get("/", include_in_schema=False)
async def root():
    return {
        "service": settings.APP_NAME,
        "version": settings.VERSION,
        "docs": "/docs",
        "health": "/health",
    }


if __name__ == "__main__":
    import uvicorn

    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
