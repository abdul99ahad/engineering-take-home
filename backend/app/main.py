import logging
import time
from collections.abc import Awaitable, Callable

from fastapi import FastAPI, Request, Response
from fastapi.responses import JSONResponse
from prometheus_client import CONTENT_TYPE_LATEST, generate_latest

from app.api import router
from app.metrics import LATENCY, REQUESTS

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")
logger = logging.getLogger("diary.requests")
# The server's own access log prints raw paths (with patient IDs) and client IPs (O.Log_4);
# log_requests below replaces it. Set here so it holds however the app is started.
logging.getLogger("uvicorn.access").disabled = True

app = FastAPI(title="Symptom Diary API")
app.include_router(router)


@app.middleware("http")
async def log_requests(
    request: Request, call_next: Callable[[Request], Awaitable[Response]]
) -> Response:
    # Logs carry the route template only: bodies hold health data and raw paths hold patient IDs
    # (O.Log_4). Doctor reads are recorded in the access log, not here.
    started = time.perf_counter()
    try:
        response = await call_next(request)
    except Exception as exc:
        # Handled here rather than with an exception handler: Starlette re-raises after those, and
        # the server would then log the message, which for database errors includes the SQL
        # parameters. Only the exception type is logged (O.Log_4), and the client gets no
        # internals (O.Err_1).
        logger.error("Unhandled %s on %s", type(exc).__name__, _route(request))
        response = JSONResponse({"detail": "Internal server error"}, status_code=500)
    route = _route(request)
    REQUESTS.labels(request.method, route, response.status_code).inc()
    LATENCY.labels(request.method, route).observe(time.perf_counter() - started)
    logger.info(
        "%s %s -> %s in %.0f ms",
        request.method,
        route,
        response.status_code,
        (time.perf_counter() - started) * 1000,
    )
    return response


def _route(request: Request) -> str:
    return request.scope["route"].path if "route" in request.scope else "unmatched"


@app.get("/metrics", include_in_schema=False)
def metrics() -> Response:
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)
