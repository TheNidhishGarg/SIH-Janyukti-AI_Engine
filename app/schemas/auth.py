from datetime import datetime

from pydantic import BaseModel, ConfigDict, EmailStr, Field

from app.models import UserRole


class RegisterRequest(BaseModel):
    name: str = Field(min_length=2, max_length=120)
    email: EmailStr
    password: str = Field(min_length=6, max_length=128)
    role: UserRole = UserRole.citizen
    phone: str | None = Field(default=None, max_length=20)
    # Required when role is university/industry: which org this login belongs to.
    university_id: str | None = None
    industry_id: str | None = None


class LoginRequest(BaseModel):
    email: EmailStr
    password: str


class OtpRequestBody(BaseModel):
    phone: str = Field(min_length=6, max_length=20)


class OtpVerifyBody(BaseModel):
    phone: str
    otp: str
    name: str | None = None
    role: UserRole = UserRole.citizen


class UserOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    name: str
    email: str
    phone: str | None = None
    role: UserRole
    university_id: str | None = None
    industry_id: str | None = None
    is_verified: bool = False
    created_at: datetime | None = None


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    expires_in: int
    user: UserOut
