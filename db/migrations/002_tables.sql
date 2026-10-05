-- Здание
CREATE TABLE locations (
    id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    parent_id REFERENCES locations(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    kind location_kind NOT NULL,
    CHECK((kind = 'building') = (parent_id IS NULL)),
    UNIQUE NULLS NOT DISTINCT (parent_id, name)
);


CREATE TABLE users (
    id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    email email_address NOT NULL,
    full_name TEXT NOT NULL CHECK(length(trim(full_name)) > 0),
    password_hash TEXT NOT NULL,
    role user_role NOT NULL DEFAULT 'user',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX users_email_uq ON users (lower(email::text))

CREATE TABLE auth_tokens (
    token UUID PRIMARY KEY DEFAULT get_random_uuid(),
    user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL DEFAULT now() + interval '7 days'
);

CREATE TABLE rooms (
    id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    location_id INT NOT NULL REFERENCES locations(id),
    name TEXT NOT NULL,
    capacity INT NOT NULL CHECK(capacity > 0),
    price_per_hour NUMERIC(8,2) NOT NULL DEFAULT 0 CHECK(price_per_hour >= 0),
    tags TEXT[] NOT NULL DEFAULT '{}' 
    equipment JSONB NOT NULL DEFAULT '{}' 
)