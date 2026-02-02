from pydantic_settings import BaseSettings
from functools import lru_cache
from typing import Optional


class Settings(BaseSettings):
    SUPABASE_URL: str
    SUPABASE_KEY: str
    OPENAI_API_KEY: Optional[str] = None
    GEMINI_API_KEY: Optional[str] = None
    DEMO_USER_ID: str
    ENVIRONMENT: str = "development"
    FRONTEND_URL: str = "http://localhost:8000"
    
    # Adzuna Job API credentials
    ADZUNA_APP_ID: Optional[str] = None
    ADZUNA_APP_KEY: Optional[str] = None
    
    class Config:
        env_file = ".env"


@lru_cache()
def get_settings():
    return Settings()
