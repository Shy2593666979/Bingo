from __future__ import annotations

from functools import wraps
from typing import Any, get_type_hints

from fastapi.routing import APIRoute
from pydantic import BaseModel


class APIResponse[T](BaseModel):
    code: int | str = 0
    message: str = "操作成功"
    data: T | None = None

    @classmethod
    def success(cls, data: T | None = None) -> APIResponse[T]:
        return cls(data=data)


class EnvelopeRoute(APIRoute):
    def __init__(self, path: str, endpoint, **kwargs):
        binary_paths = {"/chat/stream", "/chat/images/{image_id}", "/role-voice-samples/{token}"}
        plain = kwargs.get("status_code") == 204 or any(
            path.endswith(item) for item in binary_paths
        )
        if not plain and not getattr(endpoint, "_bingo_enveloped", False):
            declared = kwargs.get("response_model")
            if not isinstance(declared, type) and not hasattr(declared, "__origin__"):
                declared = get_type_hints(endpoint).get("return", Any)
            kwargs["response_model"] = APIResponse[declared or Any]

            original_endpoint = endpoint

            @wraps(original_endpoint)
            async def enveloped(*args, **parameters):
                return APIResponse.success(await original_endpoint(*args, **parameters))

            enveloped._bingo_enveloped = True
            endpoint = enveloped
        super().__init__(path, endpoint, **kwargs)
