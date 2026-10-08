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
        constraint equipment_is_object check(jsonb_typeof(equipment) = 'object'),
    description text,
    is_active boolean not null default true,
    search_vec tsvector generated always as (
        to_tsvector('russian', coalesce(name, '') || ' ' || coalesce(description, ''))
    ) stored,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    unique (location_id, name)
);


CREATE TABLE bookings(
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    room_id int not null references rooms(id),
    user_id int not null references users(id),
    period tstzrange not null,
    status booking_status not null default 'pending',
    title text not null default 'Встреча',
    duration interval generated always as (upper(period) - lower(period)) stored,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    constraint period_is_bounded check(
        not isempty(period) and not lower_inf(period) and not upper_inf(period)
        and lower_inc(period) and not upper_inc(period)
    ),
    constraint period_max_8h check(upper(period) - lower(period) <= interval '8 hours'),
    constraint booking_no_overlap exclude using gist (room_id with =, period with &&)
        where (status <> 'cancelled')
);


create table audit_log(
    id bigint generated always as identity,
    created_at timestamptz not null default now(),
    table_name text not null,
    op text not null,
    row_id text,
    actor_id int,
    old_data jsonb,
    new_data jsonb,
    primary key(id,created_at)
) partition by range (created_at);

create table audit_log_default partition of audit_log default;

create function create_audit_partition(p_month date) returns text
language plpgsql AS $$
declare
    v_from date := date_trunc('month', p_month)::date;
    v_name text := format('audit_log_y%sm%s', to_char(p_month, 'YYYY'), to_char(p_month, 'MM'));
begin
    execute format('create table if not exists %I partition of audit_log for values from (%L) to (%L)',
        v_name, v_from, (v_from + interval '1 month')::date);
    return v_name;
end $$

select create_audit_partition((date_trunc('month', now()) + make_interval(month => m))::date)
from generate_series(-3, 6) as m