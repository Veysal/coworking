

CREATE INDEX room_search_gin ON rooms using gin (search_vec);
CREATE INDEX room_name_trgm ON rooms using gin (name gin_trgm_ops);
CREATE INDEX room_equipment_gin ON rooms using gin (equipment jsonb_path_ops);
CREATE INDEX room_tags_gin ON rooms using gin (tags);
CREATE INDEX room_location_idx ON rooms (location_id);

CREATE INDEX bookings_user_start ON bookings (user_id, (lower(period)) desc) include (status, room_id);
CREATE INDEX bookings_pending ON bookings (created_at) where status = 'pending';
CREATE INDEX bookings_room_start ON bookings (room_id, (lower(period)));

CREATE INDEX audit_created_brin on audit_log using brin (created_at);
