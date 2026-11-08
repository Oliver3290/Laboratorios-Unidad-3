-- Actividad 4: Configurar los parámetros de registro
ALTER SYSTEM SET log_connections = on;
ALTER SYSTEM SET log_disconnections = on;
ALTER SYSTEM SET log_line_prefix = '%m [%p] user=%u db=%d app=%a client=%h ';
ALTER SYSTEM SET log_statement = 'ddl';

-- Aplicar los cambios en caliente
SELECT pg_reload_conf();