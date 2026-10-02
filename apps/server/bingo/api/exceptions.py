from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException

from bingo.services.exceptions import ServiceError


async def service_error(_: Request, error: ServiceError) -> JSONResponse:
    return JSONResponse(
        status_code=error.status_code,
        content={"code": error.status_code, "message": error.message, "data": None},
        headers=error.headers,
    )


async def http_error(_: Request, error: HTTPException) -> JSONResponse:
    return JSONResponse(
        status_code=error.status_code,
        content={"code": error.status_code, "message": str(error.detail), "data": None},
        headers=error.headers,
    )


async def validation_error(_: Request, error: RequestValidationError) -> JSONResponse:
    fields = [
        {"field": ".".join(map(str, item["loc"])), "message": item["msg"]}
        for item in error.errors()
    ]
    return JSONResponse(
        status_code=422, content={"code": 422, "message": "请求参数错误", "data": fields}
    )


def register_exception_handlers(app: FastAPI) -> None:
    app.add_exception_handler(ServiceError, service_error)
    app.add_exception_handler(HTTPException, http_error)
    app.add_exception_handler(RequestValidationError, validation_error)
    app.add_exception_handler(Exception, unexpected_error)


async def unexpected_error(_: Request, error: Exception) -> JSONResponse:
    return JSONResponse(
        status_code=500,
        content={"code": 500, "message": "服务暂时不可用，请稍后重试", "data": None},
    )
