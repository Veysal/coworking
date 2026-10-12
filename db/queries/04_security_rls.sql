\du
\dp bookings
SELECT polname, polcmd, pg_get_expr(polqual, polrelid) AS using_expr FROM pg_policy;

SELECT count(*) FROM bookings;

SET ROLE app_user;
SELECT set_config('app.user_id', '5', false), set_config('app.role', 'user', false);
SELECT count(*) AS only_mine FROM bookings;                
SELECT count(*) AS only_me   FROM users;                  
SELECT count(*) AS audit_rows FROM audit_log;            
UPDATE rooms SET capacity = 1 WHERE id = 1;               
SELECT * FROM auth_tokens;                               

SELECT set_config('app.role', 'admin', false);
SELECT count(*) AS everything FROM bookings;
RESET ROLE;

SELECT proname, prosecdef FROM pg_proc WHERE proname IN ('find_free_slots','book_room','free_rooms');

SELECT email, left(password_hash, 7) AS algo_and_cost FROM users LIMIT 3;         -- $2a$04$ — bcrypt
SELECT (password_hash = crypt('password', password_hash)) AS ok FROM users WHERE email = 'user1@example.com';