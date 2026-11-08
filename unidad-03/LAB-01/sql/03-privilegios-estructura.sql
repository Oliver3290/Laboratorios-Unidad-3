-- Actividad 6: Cambios de privilegios y de estructura (DDL)
REVOKE UPDATE ON clientes FROM soporte_ana;
GRANT UPDATE ON clientes TO app_ventas;
ALTER TABLE clientes ADD COLUMN segmento VARCHAR(20);

-- Demostración de secretos expuestos en la bitácora
CREATE ROLE rol_temporal LOGIN PASSWORD 'Temporal_Practica_2026';
DROP ROLE rol_temporal;