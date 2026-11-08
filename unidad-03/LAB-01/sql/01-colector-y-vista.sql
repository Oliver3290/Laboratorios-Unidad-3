-- Actividad 2: Activar el colector de bitácora (Requiere reinicio)
ALTER SYSTEM SET logging_collector = on;

-- Crear esquema y vista para lectura de la bitácora desde el motor
CREATE SCHEMA dba;
REVOKE ALL ON SCHEMA dba FROM PUBLIC;

CREATE VIEW dba.bitacora AS
SELECT t.n AS num, t.linea
FROM regexp_split_to_table(pg_read_file(pg_current_logfile()), E'\n')
     WITH ORDINALITY AS t(linea, n)
WHERE t.linea <> '';