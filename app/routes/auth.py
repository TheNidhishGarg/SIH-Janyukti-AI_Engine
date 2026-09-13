"""Auth: real replacement for the Flutter demoLogin() stub.

Includes a dev OTP path because the app already ships an OTP screen. It is
gated behind DEV_OTP and must be swapped for a real SMS gateway (MSG91 /
Firebase Phone Auth) before anything resembling production.
"""
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.core.ids import new_uuid
from app.core.security import (
    create_access_token,
    get_current_user,
    hash_password,
    verify_password,
)
from app.db import get_db
from app.models import IndustryProfile, University, User, UserRole
from app.schemas.auth import (
    LoginRequest,
    OtpRequestBody,
    OtpVerifyBody,
    RegisterRequest,
    TokenResponse,
    UserOut,
)
from app.schemas.common import Message

router = APIRouter(prefix="/auth", tags=["Auth"])


def _token_response(user: User) -> TokenResponse:
    return TokenResponse(
        access_token=create_access_token(user.id, user.role.value),
        expires_in=settings.ACCESS_TOKEN_EXPIRE_MINUTES * 60,
        user=UserOut.model_validate(user),
    )


@router.post("/register", response_model=TokenResponse, status_code=status.HTTP_201_CREATED)
async def register(payload: RegisterRequest, db: AsyncSession = Depends(get_db)):
    existing = await db.scalar(select(User).where(User.email == payload.email.lower()))
    if existing is not None:
        raise HTTPException(status.HTTP_409_CONFLICT, "An account with this email already exists")

    if payload.role == UserRole.university:
        if not payload.university_id:
            raise HTTPException(status.HTTP_400_BAD_REQUEST, "university_id is required for university accounts")
        if not await db.scalar(select(University.id).where(University.id == payload.university_id)):
            raise HTTPException(status.HTTP_404_NOT_FOUND, "University not found")
    if payload.role == UserRole.industry:
        if not payload.industry_id:
            raise HTTPException(status.HTTP_400_BAD_REQUEST, "industry_id is required for industry accounts")
        if not await db.scalar(select(IndustryProfile.id).where(IndustryProfile.id == payload.industry_id)):
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Industry profile not found")

    user = User(
        id=new_uuid(),
        name=payload.name.strip(),
        email=payload.email.lower(),
        phone=payload.phone,
        password_hash=hash_password(payload.password),
        role=payload.role,
        university_id=payload.university_id,
        industry_id=payload.industry_id,
        is_verified=True,
    )
    db.add(user)
    await db.commit()
    await db.refresh(user)
    return _token_response(user)


@router.post("/login", response_model=TokenResponse)
async def login(payload: LoginRequest, db: AsyncSession = Depends(get_db)):
    user = await db.scalar(select(User).where(User.email == payload.email.lower()))
    # Same message either way, so the endpoint cannot be used to enumerate accounts.
    if user is None or not verify_password(payload.password, user.password_hash):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Incorrect email or password")
    if not user.is_active:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "This account has been deactivated")
    return _token_response(user)


@router.post("/otp/request", response_model=Message)
async def request_otp(payload: OtpRequestBody):
    if not settings.DEBUG:
        raise HTTPException(status.HTTP_501_NOT_IMPLEMENTED, "SMS OTP is not configured")
    return Message(message=f"Development OTP for {payload.phone} is {settings.DEV_OTP}")


@router.post("/otp/verify", response_model=TokenResponse)
async def verify_otp(payload: OtpVerifyBody, db: AsyncSession = Depends(get_db)):
    if not settings.DEBUG:
        raise HTTPException(status.HTTP_501_NOT_IMPLEMENTED, "SMS OTP is not configured")
    if payload.otp != settings.DEV_OTP:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Invalid OTP")

    user = await db.scalar(select(User).where(User.phone == payload.phone))
    if user is None:
        # Phone-first signup: create the citizen account on first verify.
        user = User(
            id=new_uuid(),
            name=payload.name or f"Citizen {payload.phone[-4:]}",
            email=f"{payload.phone}@phone.janyukti.local",
            phone=payload.phone,
            password_hash=hash_password(new_uuid()),
            role=payload.role,
            is_verified=True,
        )
        db.add(user)
        await db.commit()
        await db.refresh(user)
    else:
        user.is_verified = True
        await db.commit()
    return _token_response(user)


@router.get("/me", response_model=UserOut)
async def me(user: User = Depends(get_current_user)):
    return UserOut.model_validate(user)
