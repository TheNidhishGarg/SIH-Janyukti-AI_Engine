from typing import Generic, TypeVar

from pydantic import BaseModel

T = TypeVar("T")


class Page(BaseModel, Generic[T]):
    items: list[T]
    total: int
    page: int = 1
    page_size: int = 20
    has_more: bool = False


class Message(BaseModel):
    message: str
    ok: bool = True


class ErrorResponse(BaseModel):
    detail: str
    code: str | None = None
