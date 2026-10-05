CREATE EXTENSION IF NOT EXISTS btree_gist;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

CREATE TYPE booking_status AS ENUM ('pending', 'confirmed', 'cancelled')
CREATE TYPE user_role AS ENUM ('user', 'admin')
CREATE TYPE location_kind AS ENUM ('building', 'floor')

CREATE DOMAIN email_address AS text
    CHECK (VALUE ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$')
