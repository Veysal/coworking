GRANT USAGE ON SCHEMA public TO app_user;
GRANT SELECT ON locations, rooms, users, audit_log, v_room_places, v_bookings_full,
                mv_room_daily, mv_user_stats TO app_user;
GRANT INSERT, UPDATE, DELETE ON rooms TO app_user;
GRANT SELECT, INSERT, UPDATE ON bookings TO app_user;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO app_user;


ALTER TABLE bookings ENABLE ROW LEVEL SECURITY;
CREATE POLICY bookings_select ON bookings FOR SELECT
    USING (user_id = app_user_id() OR app_is_admin());
CREATE POLICY bookings_insert ON bookings FOR INSERT
    WITH CHECK (user_id = app_user_id());
CREATE POLICY bookings_update ON bookings FOR UPDATE
    USING (user_id = app_user_id() OR app_is_admin())
    WITH CHECK (user_id = app_user_id() OR app_is_admin());

-- ----- users: каждый видит себя, админ — всех -----
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
CREATE POLICY users_select ON users FOR SELECT
    USING (id = app_user_id() OR app_is_admin());

-- ----- rooms: читают все, менять может только админ -----
ALTER TABLE rooms ENABLE ROW LEVEL SECURITY;
CREATE POLICY rooms_read  ON rooms FOR SELECT USING (true);
CREATE POLICY rooms_admin ON rooms FOR ALL
    USING (app_is_admin()) WITH CHECK (app_is_admin());

-- ----- audit_log: только админ -----
ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY audit_admin ON audit_log FOR SELECT USING (app_is_admin());
