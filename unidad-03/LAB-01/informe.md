# Informe de Laboratorio: Bitácoras y auditoría del dato en PostgreSQL

**Alumno:** Oliver Coronel Caro
**Materia:** Gestión de Seguridad y Desempeño de Bases de Datos
**Unidad:** III — Auditoría, trazabilidad y gobierno práctico de datos

---

## 1. Despliegue y situación inicial
**Despliegue:** El servidor PostgreSQL 16 fue desplegado mediante instalación nativa (o contenedor/máquina virtual, según aplique), utilizando el cliente `psql` para conectarse a la base de datos `comercial`.
**Situación inicial:** Por defecto, el servidor tenía `logging_collector = off`, `log_connections = off`, `log_disconnections = off` y `log_statement = none`.
**Problema detectado:** Esta configuración inicial no producía evidencia. Al modificarse el RFC de la clienta María García, la base de datos no registró quién realizó el cambio, desde qué IP, ni a qué hora, lo que imposibilitó a Dirección identificar al responsable o el valor anterior del dato.

## 2. Configuración aplicada
Se aplicaron los siguientes parámetros mediante `ALTER SYSTEM` para que funcionen independientemente del despliegue:
*   `logging_collector = on`: Para que PostgreSQL capture y administre sus propios archivos de bitácora en la carpeta `log/`. (Requirió **reinicio**).
*   `log_connections = on` y `log_disconnections = on`: Para registrar cada inicio y fin de sesión con su duración. (Requirió **recarga**).
*   `log_line_prefix = '%m [%p] user=%u db=%d app=%a client=%h '`: Para añadir fecha, hora, PID, usuario, base de datos, aplicación e IP a cada línea de la bitácora. (Requirió **recarga**).
*   `log_statement = 'mod'`: Para registrar todo cambio de estructura (DDL) y modificación de datos (INSERT, UPDATE, DELETE), sin saturar el disco con consultas SELECT. (Requirió **recarga**).

## 3. Eventos observados
A través de la vista `dba.bitacora`, se observó cómo la nueva configuración capturó los eventos:
*   **Accesos:** Se registraron errores `FATAL: password authentication failed` cuando `app_ventas` y `usuario_inexistente` intentaron entrar con contraseñas incorrectas, revelando intentos fallidos de conexión, seguidos por un `connection authorized` exitoso.
*   **Cambios de privilegios y estructura (DDL):** Las sentencias `GRANT`, `REVOKE` y `ALTER TABLE` ejecutadas por el administrador quedaron escritas literalmente en la bitácora con la etiqueta `LOG: statement:`.
*   **Modificaciones (MOD):** Un `UPDATE` ejecutado por la aplicación de ventas para cambiar el teléfono quedó registrado con la IP del cliente y la sentencia exacta, demostrando quién actuó.
*   **Errores:** El intento del usuario `soporte_ana` de borrar un registro generó un registro `ERROR: permission denied for table clientes`, capturado gracias a `log_min_error_statement = error`.

## 4. Auditoría del dato
La bitácora registra la sentencia SQL enviada, pero no el valor que el dato tenía antes. Para solucionarlo, se creó el esquema `auditoria` y la tabla `cambios_clientes` utilizando campos `JSONB` (`valores_antes` y `valores_despues`).
*   **Papel de SECURITY DEFINER y session_user:** El disparador se ejecuta con privilegios del administrador (el creador de la función) para poder escribir en la tabla de auditoría, a la cual el usuario público no tiene acceso. Al usar `session_user`, la tabla guarda la identidad del usuario que realmente inició la sesión (ej. `app_ventas`), y no el `current_user` (que siempre sería `postgres`).
*   **Resultado del incidente auditado:** Cuando `app_ventas` volvió a cambiar el RFC, la tabla guardó una fila mostrando la operación `UPDATE`, la IP del cliente, `GAMA780912XYZ` como el valor anterior y `GAMA780912ZZZ` como el nuevo.

## 5. Limitaciones
*   **Lecturas:** Ni la tabla de auditoría ni `log_statement = 'mod'` registran las consultas `SELECT`. Para auditar accesos de lectura a datos sensibles (como el RFC) es necesario usar extensiones como `pgaudit`.
*   **Volumen:** Un `UPDATE` masivo sin cláusula `WHERE` genera una sola línea en la bitácora, pero dispara múltiples inserciones en la tabla de auditoría (una por cada fila afectada), lo que puede saturar el almacenamiento.
*   **Administrador con control total:** Un superusuario puede ejecutar `DISABLE TRIGGER`, modificar datos sin dejar rastro en la tabla de auditoría, y volver a habilitarlo (como se demostró en la Actividad 14).

## 6. Riesgos de la bitácora
*   **Secretos expuestos:** Sentencias como `CREATE ROLE ... PASSWORD` guardan contraseñas en texto claro en la bitácora, lo que vulnera la seguridad si terceros acceden a los logs.
*   **Pérdida y alteración:** Conservar la bitácora solo en el servidor que la produce permite que un atacante que comprometa la máquina elimine sus propias huellas. Se requiere exportarla a un sistema externo y asegurar su integridad con resúmenes criptográficos (ej. SHA-256).

## 7. Cronología y conclusión

| # | Fecha y hora (Ejemplo) | Usuario | Cliente | Tipo de evento | Qué ocurrió | ¿Exitoso? | Fuente |
|---|---|---|---|---|---|---|---|
| 1 | 2026-10-25 22:49:50 | postgres | [local] | Configuración | Cambio de log_statement a 'mod' | Sí | dba.bitacora |
| 2 | 2026-10-25 22:50:00 | app_ventas | 127.0.0.1 | Acceso | Fallo de autenticación por contraseña | No | dba.bitacora |
| 3 | 2026-10-25 22:50:00 | app_ventas | 127.0.0.1 | Acceso | Conexión autorizada | Sí | dba.bitacora |
| 4 | 2026-10-25 22:50:09 | postgres | [local] | Privilegio | REVOKE UPDATE a soporte_ana | Sí | dba.bitacora |
| 5 | 2026-10-25 22:50:09 | postgres | [local] | Estructura | ALTER TABLE clientes ADD segmento | Sí | dba.bitacora |
| 6 | 2026-10-25 22:50:15 | soporte_ana| 127.0.0.1 | Error | Intento de DELETE en clientes | No | dba.bitacora |
| 7 | 2026-10-25 22:50:52 | app_ventas | 127.0.0.1 | Datos | UPDATE a RFC de id 3 | Sí | Tabla auditoria (id_evento 1) |
| 8 | 2026-10-25 22:55:00 | postgres | [local] | Datos | DISABLE TRIGGER y UPDATE oculto | Sí | dba.bitacora (statement) |

**Conclusión:**
Con esta configuración dual (bitácora + disparador de auditoría), sí puede demostrarse quién cambió un dato sensible, desde qué IP, y qué valor tenía antes. La tabla de auditoría retiene el valor exacto anterior y nuevo del RFC, mientras que la bitácora provee un marco irrefutable de la sesión, los intentos de acceso y cualquier intento del administrador por alterar la configuración.

---

## Preguntas de reflexión (Finales)

1. **¿Por qué la auditoría no puede configurarse después de un incidente para investigarlo?**
   Porque la auditoría depende de registrar los eventos en el instante exacto en que ocurren. No existe manera de reconstruir criptográficamente acciones pasadas si el motor no fue instruido previamente para guardarlas.
2. **¿Por qué conviene que la bitácora la administre el propio servidor y no el mecanismo de despliegue?**
   Porque utilizar `logging_collector` permite al DBA configurar y consultar los logs de manera unificada mediante SQL (ej. `pg_read_file`), independientemente de si el sistema subyacente es Linux, Windows o Docker.
3. **¿Por qué el prefijo de línea es tan importante como el nivel de log_statement?**
   `log_statement` define "qué" sentencia se registra, pero sin un `log_line_prefix` adecuado, la línea carecerá de "quién" (usuario), "cuándo" (fecha) y "desde dónde" (IP), haciendo inútil el registro para una investigación.
4. **¿Qué diferencia práctica hay entre registrar la sentencia y registrar el cambio en el dato?**
   Registrar la sentencia (bitácora) solo documenta la orden enviada (ej. `UPDATE clientes SET rfc = 'X'`). Registrar el cambio (trigger de auditoría) preserva el estado real del registro antes (`OLD`) y después (`NEW`), indispensable para poder revertir daños.
5. **¿Qué evidencia ofrece pg_stat_activity que no ofrece la bitácora, y viceversa?**
   `pg_stat_activity` ofrece una fotografía del "presente" (consultas ejecutándose en este milisegundo y sesiones activas). La bitácora ofrece la "historia" (consultas ya finalizadas, intentos fallidos y eventos pasados).
6. **Si el administrador puede cambiar log_statement a none y desactivar el disparador, ¿quién audita al administrador?**
   Técnicamente, ningún control interno puede bloquear totalmente a un superusuario. Al administrador lo auditan mecanismos externos: el envío de logs a un sistema SIEM administrado por otra área (Seguridad) aplicando el principio de separación de funciones.

---

## Anexo: Análisis y Respuestas por Actividad

**Actividad 1:**
1. ¿Se registra quién se conecta? No, `log_connections` está apagado.
2. ¿Se registran las sentencias UPDATE? No, `log_statement` es `none`.
3. ¿Línea incluye usuario o IP? No, `%m [%p]` solo tiene fecha y PID.
4. ¿Zona horaria? UTC. Importa para ordenar eventos globalmente sin desfases de horarios locales.
5. ¿Quién decide destino de logs? El mecanismo de despliegue (SO o contenedor), porque el motor solo arroja a `stderr`.

**Actividad 2:**
1. ¿Por qué logging_collector requiere reinicio? Porque inicia un subproceso nuevo en el sistema operativo. `log_statement` solo cambia una directiva en memoria (recarga).
2. Ventaja/Riesgo vista SQL: Ventaja, unifica la consulta sin requerir acceso de terminal al servidor. Riesgo, si no se limitan privilegios, cualquier usuario podría leer datos sensibles de los logs.
3. ¿Quién debe consultar dba.bitacora? Solo DBAs y auditores autorizados.

**Actividad 3:**
1 y 2. ¿Demostrar quién modificó o que no fue soporte_ana? No, la ausencia de bitácoras deja un punto ciego total.
3. ¿Impidieron el cambio los privilegios? No, porque `app_ventas` requiere el permiso legítimo de `UPDATE`.
4. ¿Qué debió estar configurado? Auditoría de datos y bitácora con `log_statement`.

**Actividad 4:**
1. ¿Por qué registra el PID 1? Porque el proceso principal (postmaster) es el encargado de releer la configuración general y aplicarla a los subprocesos.
2. ¿Queda rastro de apagar log_statement? Sí, la acción de cambiar el parámetro a `none` queda grabada indicando alteración de configuración.
3. ¿Por qué no editar auto.conf a mano? Porque es administrado automáticamente por `ALTER SYSTEM` y editarlo manualmente puede causar errores de sintaxis y corrupción en el arranque.

**Actividad 5:**
1. ¿Prueba que la app entró? Prueba que una conexión intentó usar esas credenciales, pero no prueba que fuera el software original.
2. ¿Usuario inexistente? La bitácora revela "Role does not exist", valioso para auditar escaneos de fuerza bruta sin revelar el detalle al atacante.
3. ¿Por qué app=[unknown]? En un fallo, la cadena de conexión se corta antes de evaluar el application_name. Al desconectar, la sesión ya lo tenía validado.
4. Patrón de fuerza bruta: Repetidos eventos FATAL en poco tiempo desde una misma IP.

**Actividad 6:**
1. Privilegio (`GRANT/REVOKE`) y Estructura (`ALTER TABLE`).
2. ¿Por qué son ddl? Porque alteran los metadatos de seguridad y definición del catálogo.
3. ¿Lectura de contraseñas en bitácora? Se mitiga enviando el hash (SCRAM) o restringiendo la bitácora solo a oficiales de seguridad.

**Actividad 7:**
1. ¿Nivel para lectura y costo? Nivel `all`. El costo es alto volumen de disco e I/O constante.
2. ¿Qué falta para revertir? El estado de la fila antes del UPDATE (el `OLD`), que no se guarda en el log.

**Actividad 8:**
1. ¿Causó daño soporte_ana? No. Se audita para detectar intentos de abuso interno o malas configuraciones de clientes.
2. Diferencia de errores: Actividad 5 (Autenticación - falló la identidad). Actividad 8 (Autorización - identidad correcta, pero permisos insuficientes).
3. ¿Orden de DROP ROLE? Primero deben removerse sus permisos (`REVOKE`) o transferirse la propiedad de sus objetos, luego borrar el rol.

**Actividad 9:**
1. ¿Columna para relacionar? El PID de sesión.
2. ¿Qué fuente conserva evidencia tras el reporte? La bitácora (`dba.bitacora`).
3. ¿Por qué IP vacía? El DBA usa una conexión de socket local Unix, no una red TCP.

**Actividad 10:**
1. ¿TIMESTAMPTZ? Para no perder la noción exacta de huso horario al registrar el momento.
2. ¿Por qué JSONB? Para crear una copia íntegra de la fila completa, haciéndola tolerante a cambios en las columnas de `clientes` a futuro.
3. ¿Clasificación? Adquiere el mismo nivel de sensibilidad y requiere las mismas restricciones que la tabla origen.

**Actividad 11:**
1. ¿REVOKE ALL de la función? Para evitar que usuarios llamen a la función directamente falsificando datos de auditoría.
2. ¿Sin SECURITY DEFINER? El trigger fallaría porque `app_ventas` carece de permisos de `INSERT` sobre la tabla de auditoría.
3. ¿Registro en bitácora? Sí, al ser sentencias DDL, quedaron grabadas.

**Actividad 12:**
1. Hipótesis: El uso de SECURITY DEFINER permitió a la función escalar temporalmente privilegios e insertar exitosamente la fila.
2. Sentencia para revertir: `UPDATE clientes SET rfc = 'GAMA780912XYZ' WHERE id = 3;`
3. ¿Evidencia fuerte? `ip_cliente`. El `aplicacion_name` lo envía el cliente en la cadena de conexión y es fácilmente falsificable.

**Actividad 13:**
1. ¿Dónde queda evidencia del registro borrado? En el campo `valores_antes` del evento `DELETE` en la tabla de auditoría.
2. ¿Por qué IP vacía? Por usar conexión local.
3. Conflicto de retención: El derecho legal de borrado (ej. GDPR) choca con la inmutabilidad de los registros de auditoría. Lo resuelve la gobernanza de datos.

**Actividad 14:**
1. ¿Evidencia de salto de auditoría? La bitácora del servidor muestra la sentencia explícita `ALTER TABLE ... DISABLE TRIGGER`.
2. ¿Control administrativo? Segregación estricta de funciones.
3. Separación Unidad II: Nadie debería tener la capacidad técnica de alterar simultáneamente los datos y los registros que vigilan esos datos.

**Actividad 15:**
1. ¿UPDATE masivo? Una fila en bitácora genera millones de filas de auditoría.
2. ¿Quién autoriza depurar? Auditoría Interna / CISO, no el DBA.
3. ¿Riesgo de log_statement='all'? Transforma los archivos de log en un archivo de texto plano masivo lleno de datos sensibles legibles (tarjetas, RFCs).

**Actividad 16:**
1. ¿El hash impide modificación? No, pero permite detectar inequívocamente si un solo byte fue alterado tras su generación.
2. ¿Dónde guardarlo? En un repositorio independiente de solo escritura.
3. Riesgos: Destrucción por falla física del disco del servidor o borrado intencional por atacante.
4. Tiempo de conservación: Típicamente de 1 a 5 años dependiendo de legislaciones fiscales y de protección de datos aplicables a los RFCs.

**Actividad 19:**
1. ¿Por qué no apareció la primera consulta? Porque el rol `auditor_datos` solo monitorea las columnas `rfc` y `telefono`.
2. ¿Por qué no apareció UPDATE ciudad? Porque la columna `ciudad` no está dentro del alcance asignado al auditor.
3. ¿Volumen pgaudit vs all? Mucho menor, `pgaudit` es un enfoque quirúrgico y selectivo, mientras `all` graba indiscriminadamente toda la instancia.
4. ¿Auditar superusuarios? Es imposible garantizalo desde dentro de la base. Un superusuario siempre puede deshabilitar bibliotecas en memoria o evadir triggers.
