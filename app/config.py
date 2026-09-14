from functools import lru_cache
from typing import List

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    # --- App ---
    APP_NAME: str = "JanYukti API"
    VERSION: str = "1.0.0"
    DEBUG: bool = True
    CORS_ORIGINS: str = "*"

    # --- Database ---
    DATABASE_URL: str = "sqlite+aiosqlite:///./janyukti.db"

    # --- Auth ---
    # 32+ bytes, as HS256 requires. Override in .env for any real deployment.
    JWT_SECRET: str = "janyukti-dev-secret-change-me-in-production-0123456789"
    JWT_ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 60 * 24 * 7  # 7 days
    # Dev-only fixed OTP so the existing Flutter OTP screen works without an SMS gateway.
    DEV_OTP: str = "123456"

    # --- ML ---
    GEMINI_API_KEY: str = ""
    GEMINI_MODEL: str = "gemini-1.5-flash"
    EMBEDDING_MODEL: str = "sentence-transformers/all-MiniLM-L6-v2"
    # Set false to skip loading sentence-transformers (uses the hashing fallback instead).
    USE_LOCAL_EMBEDDINGS: bool = True
    # Calibrated for MiniLM: measured paraphrases of the same report score
    # 0.565-0.700 and unrelated reports 0.158-0.279, so 0.50 separates them with
    # margin on both sides. The hashing fallback has its own lower default; see
    # app/ml/duplicates.default_threshold().
    DUPLICATE_SIMILARITY_THRESHOLD: float = 0.50
    MATCH_TOP_K: int = 5

    # --- Flutter app integration ---
    # The app signs users in with Firebase and calls /ai with its ID token.
    FIREBASE_PROJECT_ID: str = ""
    # off: accept unauthenticated /ai calls (local development).
    # required: verify the Firebase ID token on every /ai call.
    FIREBASE_AUTH_MODE: str = "off"

    # --- Media ---
    CLOUDINARY_URL: str = ""
    UPLOAD_DIR: str = "./uploads"
    MAX_UPLOAD_MB: int = 25

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    @property
    def cors_origin_list(self) -> List[str]:
        if self.CORS_ORIGINS.strip() == "*":
            return ["*"]
        return [o.strip() for o in self.CORS_ORIGINS.split(",") if o.strip()]


@lru_cache()
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
