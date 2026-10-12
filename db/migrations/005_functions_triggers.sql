CREATE FUNCTION app_user_id() RETURNS int LANGUAGE sql STABLE AS
$$ SELECT nullif(current_setting('app.user_id', true), '')::int $$;

CREATE FUNCTION app_role() RETURNS text LANGUAGE sql STABLE AS
$$ SELECT coalesce(nullif(current_setting('app.role', true), ''), 'anonymous') $$;

CREATE FUNCTION app_is_admin() RETURNS boolean LANGUAGE sql STABLE AS
$$ SELECT app_role() = 'admin' $$;

-- ---------- автообновление updated_at ----------
CREATE FUNCTION set_updated_at() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END $$;

CREATE TRIGGER trg_users_upd    BEFORE UPDATE ON users    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_rooms_upd    BEFORE UPDATE ON rooms    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_bookings_upd BEFORE UPDATE ON bookings FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ---------- аудит изменений ----------
CREATE FUNCTION audit_row() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_old jsonb;
    v_new jsonb;
BEGIN
    IF TG_OP IN ('UPDATE', 'DELETE') THEN v_old := to_jsonb(OLD) - 'search_vec' - 'password_hash'; END IF;
    IF TG_OP IN ('INSERT', 'UPDATE') THEN v_new := to_jsonb(NEW) - 'search_vec' - 'password_hash'; END IF;
    INSERT INTO audit_log (table_name, op, row_id, actor_id, old_data, new_data)
    VALUES (TG_TABLE_NAME, TG_OP, COALESCE(v_new, v_old) ->> 'id', app_user_id(), v_old, v_new);
    RETURN NULL;
END $$;

CREATE TRIGGER trg_bookings_audit AFTER INSERT OR UPDATE OR DELETE ON bookings FOR EACH ROW EXECUTE FUNCTION audit_row();
CREATE TRIGGER trg_rooms_audit    AFTER INSERT OR UPDATE OR DELETE ON rooms    FOR EACH ROW EXECUTE FUNCTION audit_row();
CREATE TRIGGER trg_users_audit    AFTER INSERT OR UPDATE OR DELETE ON users    FOR EACH ROW EXECUTE FUNCTION audit_row();

-- ---------- LISTEN / NOTIFY ----------
-- Уведомление уходит подписчикам только после COMMIT. Личных данных в нём нет.
CREATE FUNCTION notify_booking() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE r bookings;
BEGIN
    r := CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
    PERFORM pg_notify('booking_events', json_build_object(
        'op', TG_OP, 'booking_id', r.id, 'room_id', r.room_id,
        'status', r.status, 'start', lower(r.period), 'end', upper(r.period))::text);
    RETURN NULL;
END $$;

CREATE TRIGGER trg_bookings_notify AFTER INSERT OR UPDATE OR DELETE ON bookings
    FOR EACH ROW EXECUTE FUNCTION notify_booking();

CREATE FUNCTION book_room(p_room_id int, p_start timestamptz, p_end timestamptz, p_title text DEFAULT 'Встреча')
RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE
    v_user int := app_user_id();
    v_id   bigint;
BEGIN
    IF v_user IS NULL THEN
        RAISE EXCEPTION 'Требуется авторизация' USING ERRCODE = '28000';
    END IF;
    IF p_end <= p_start THEN
        RAISE EXCEPTION 'Время окончания должно быть позже времени начала';
    END IF;
    IF p_start < now() - interval '5 minutes' THEN
        RAISE EXCEPTION 'Нельзя бронировать время в прошлом';
    END IF;
    PERFORM 1 FROM rooms WHERE id = p_room_id AND is_active;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Комната не найдена или недоступна';
    END IF;


    INSERT INTO bookings (room_id, user_id, period, title)
    VALUES (p_room_id, v_user, tstzrange(p_start, p_end, '[)'),
            coalesce(nullif(trim(p_title), ''), 'Встреча'))
    RETURNING id INTO v_id;
    RETURN v_id;
END $$;

CREATE FUNCTION cancel_booking(p_id bigint) RETURNS boolean LANGUAGE plpgsql AS $$
BEGIN
    UPDATE bookings SET status = 'cancelled' WHERE id = p_id AND status <> 'cancelled';
    RETURN FOUND;      
END $$;

CREATE FUNCTION confirm_booking(p_id bigint) RETURNS boolean LANGUAGE plpgsql AS $$
BEGIN
    IF NOT app_is_admin() THEN
        RAISE EXCEPTION 'Подтверждать брони может только администратор' USING ERRCODE = '42501';
    END IF;
    UPDATE bookings SET status = 'confirmed' WHERE id = p_id AND status = 'pending';
    RETURN FOUND;
END $$;


CREATE FUNCTION find_free_slots(p_room_id int, p_day date, p_tz text DEFAULT 'UTC',
                                p_from_hour int DEFAULT 8, p_to_hour int DEFAULT 20)
RETURNS TABLE (slot_start timestamptz, slot_end timestamptz, is_free boolean)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    WITH slots AS (
        SELECT g AT TIME ZONE p_tz                       AS s_start,
               (g + interval '1 hour') AT TIME ZONE p_tz AS s_end
        FROM generate_series(p_day::timestamp + make_interval(hours => p_from_hour),
                             p_day::timestamp + make_interval(hours => p_to_hour - 1),
                             interval '1 hour') AS g
    )
    SELECT s.s_start, s.s_end,
           NOT EXISTS (SELECT 1 FROM bookings b
                       WHERE b.room_id = p_room_id AND b.status <> 'cancelled'
                         AND b.period && tstzrange(s.s_start, s.s_end, '[)'))
    FROM slots s
    ORDER BY s.s_start
$$;

CREATE FUNCTION free_rooms(p_start timestamptz, p_end timestamptz, p_capacity int DEFAULT 1)
RETURNS TABLE (o_room_id int, o_name text, o_place text, o_capacity int, o_price numeric, o_next_at timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT r.id, r.name, p.place, r.capacity, r.price_per_hour, nb.next_start
    FROM rooms r
    JOIN v_room_places p ON p.room_id = r.id
    LEFT JOIN LATERAL (
        SELECT lower(b.period) AS next_start
        FROM bookings b
        WHERE b.room_id = r.id AND b.status <> 'cancelled' AND lower(b.period) >= p_end
        ORDER BY lower(b.period) LIMIT 1
    ) nb ON true
    WHERE r.is_active AND r.capacity >= p_capacity
      AND NOT EXISTS (SELECT 1 FROM bookings b
                      WHERE b.room_id = r.id AND b.status <> 'cancelled'
                        AND b.period && tstzrange(p_start, p_end, '[)'))
    ORDER BY r.capacity, r.name
    LIMIT 30
$$;


CREATE FUNCTION register_user(p_email text, p_name text, p_password text) RETURNS int
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id int;
BEGIN
    IF length(p_password) < 6 THEN
        RAISE EXCEPTION 'Пароль должен быть не короче 6 символов';
    END IF;
    INSERT INTO users (email, full_name, password_hash)
    VALUES (p_email, p_name, crypt(p_password, gen_salt('bf')))
    RETURNING id INTO v_id;
    RETURN v_id;
END $$;

CREATE FUNCTION login(p_email text, p_password text)
RETURNS TABLE (out_token uuid, out_id int, out_name text, out_role user_role)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    u       users;
    v_token uuid;
BEGIN
    SELECT * INTO u FROM users WHERE lower(email::text) = lower(p_email);
    IF NOT FOUND OR u.password_hash <> crypt(p_password, u.password_hash) THEN
        RAISE EXCEPTION 'Неверный email или пароль' USING ERRCODE = '28P01';
    END IF;
    INSERT INTO auth_tokens (user_id) VALUES (u.id) RETURNING token INTO v_token;
    RETURN QUERY SELECT v_token, u.id, u.full_name, u.role;
END $$;

CREATE FUNCTION auth_user(p_token uuid)
RETURNS TABLE (out_id int, out_name text, out_role user_role)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT u.id, u.full_name, u.role
    FROM auth_tokens t JOIN users u ON u.id = t.user_id
    WHERE t.token = p_token AND t.expires_at > now()
$$;

CREATE FUNCTION logout(p_token uuid) RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
    DELETE FROM auth_tokens WHERE token = p_token
$$;

CREATE FUNCTION refresh_reports() RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    IF NOT app_is_admin() THEN
        RAISE EXCEPTION 'Только для администратора' USING ERRCODE = '42501';
    END IF;
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_room_daily;
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_user_stats;
END $$;
