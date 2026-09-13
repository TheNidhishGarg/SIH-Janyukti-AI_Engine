"""Media upload.

Cloudinary when CLOUDINARY_URL is set, local disk otherwise, so the submit flow
with photos works out of the box on a laptop with no cloud account.
"""
import os
import shutil

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile, status
from fastapi.responses import FileResponse

from app.config import settings
from app.core.ids import new_uuid
from app.core.security import get_current_user
from app.models import User
from app.schemas.challenge import AttachmentIn

router = APIRouter(prefix="/uploads", tags=["Uploads"])

ALLOWED = {
    "image/jpeg": ("image", ".jpg"),
    "image/png": ("image", ".png"),
    "image/webp": ("image", ".webp"),
    "video/mp4": ("video", ".mp4"),
    "application/pdf": ("document", ".pdf"),
}


def _cloudinary_configured() -> bool:
    return bool(settings.CLOUDINARY_URL)


@router.post("", response_model=AttachmentIn, status_code=status.HTTP_201_CREATED)
async def upload(file: UploadFile = File(...), _: User = Depends(get_current_user)):
    if file.content_type not in ALLOWED:
        raise HTTPException(
            status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            f"Unsupported type {file.content_type}. Allowed: {', '.join(ALLOWED)}",
        )
    kind, ext = ALLOWED[file.content_type]

    if _cloudinary_configured():
        try:
            import cloudinary
            import cloudinary.uploader

            cloudinary.config(cloudinary_url=settings.CLOUDINARY_URL)
            result = cloudinary.uploader.upload(
                file.file,
                resource_type="video" if kind == "video" else "auto",
                folder="janyukti",
            )
            return AttachmentIn(
                url=result["secure_url"],
                kind=kind,
                filename=file.filename or "",
                size_bytes=int(result.get("bytes", 0)),
            )
        except Exception as exc:  # noqa: BLE001
            raise HTTPException(status.HTTP_502_BAD_GATEWAY, f"Cloudinary upload failed: {exc}")

    os.makedirs(settings.UPLOAD_DIR, exist_ok=True)
    name = f"{new_uuid()}{ext}"
    path = os.path.join(settings.UPLOAD_DIR, name)
    with open(path, "wb") as out:
        shutil.copyfileobj(file.file, out)

    size = os.path.getsize(path)
    if size > settings.MAX_UPLOAD_MB * 1024 * 1024:
        os.remove(path)
        raise HTTPException(
            status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            f"File exceeds {settings.MAX_UPLOAD_MB} MB",
        )

    return AttachmentIn(url=f"/uploads/{name}", kind=kind, filename=file.filename or "", size_bytes=size)


@router.get("/{filename}", include_in_schema=False)
async def serve(filename: str):
    """Serves locally stored uploads. Cloudinary URLs bypass this entirely."""
    safe = os.path.basename(filename)
    path = os.path.join(settings.UPLOAD_DIR, safe)
    if not os.path.isfile(path):
        raise HTTPException(status.HTTP_404_NOT_FOUND, "File not found")
    return FileResponse(path)
