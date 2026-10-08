import os 

DATABASE_URL = os.environ.get(
    "DATABASE_URL", "postgresql://app_user:app_password@localhost:5432/coworking"
)

DEFAULT_TZ = os.environ.get("APP_TZ")