# Expediente de auditoría interna — Base comercial

## 1. Alcance

* **Sistemas y despliegue evaluados:**
  * **PostgreSQL 18** (servidor local Windows `127.0.0.1:5432`, instancia nativa), base de datos `comercial` con los esquemas `public`, `auditoria`, `dba` y `gobierno` (`evidencias/04-catalogo.md`, `evidencias/E1-configuracion-registro.txt`).
  * **MongoDB Community 9.0** (servidor local Windows `127.0.0.1:27017`, instancia nativa), base de datos `comercial` con las colecciones `clientes`, `system.profile` y `auditoria.instantaneas_privilegios` (`evidencias/04-catalogo.md`, `evidencias/E6-mongodb/09-comparacion.md`).
* **Periodo revisado:** Ciclo operativo de la Unidad III correspondiente a la configuración de controles de bitácora, pruebas de trazabilidad, simulación de incidentes de calidad/integridad y conciliación de cambios (octubre – noviembre de 2026, según marcas de tiempo en `evidencias/E5-bitacora-postgresql.log` y `evidencias/E6-mongodb/bitacora-mongod.log`).
* **Responsable del expediente:** DBA de Comercializadora Norte S.A. de C.V. (Custodio técnico de datos, según `evidencias/02-responsables.md`), elaborado para revisión de **Auditoría Interna** y **Seguridad de la Información**.

---

## 2. Configuración de auditoría (A3)

Los mecanismos de registro y trazabilidad implementados en ambos motores de bases de datos se demuestran mediante las siguientes evidencias técnicas:

* **Bitácora del servidor PostgreSQL (`evidencias/E1-configuracion-registro.txt` y `evidencias/E5-bitacora-postgresql.log`):**
  * `logging_collector = on` (origen: archivo de configuración): habilita la captura persistente de eventos en archivos de bitácora gestionados por el colector.
  * `log_connections = on` y `log_disconnections = on`: registran el inicio y cierre de cada sesión, identificando usuario, base de datos y dirección IP de origen.
  * `log_statement = 'mod'`: registra todas las sentencias de definición de datos (`DDL`: `CREATE`, `ALTER`, `DROP`, `GRANT`, `REVOKE`, `COMMENT`) y todas las modificaciones de datos (`DML`: `INSERT`, `UPDATE`, `DELETE`).
  * `log_line_prefix = '%m [%p] user=%u,db=%d,app=%a,client=%h '` (verificado en el encabezado de cada línea de `evidencias/E5-bitacora-postgresql.log`): incorpora marca de tiempo con milisegundos, PID, usuario, base de datos, aplicación cliente y dirección IP.
  * `log_min_error_statement = error`: registra las sentencias que fallan por permisos o restricciones (como los intentos rechazados de desactivar disparadores).
* **Auditoría granular del dato en PostgreSQL (`evidencias/E3-disparadores.txt` y `evidencias/E4-muestra-auditoria.txt`):**
  * Disparador `trg_auditoria_clientes` activo (`tgenabled = 'O'`) sobre la tabla `public.clientes` (`evidencias/E3-disparadores.txt`), el cual invoca una función `SECURITY DEFINER` que inserta automáticamente en `auditoria.cambios_clientes` el momento, usuario de sesión, aplicación, operación (`UPDATE`), identificador del cliente, valor anterior (`OLD.rfc`) y valor nuevo (`NEW.rfc`) (`evidencias/E4-muestra-auditoria.txt`, líneas 1 a 10).
* **Trazabilidad en MongoDB Community (`evidencias/E6-mongodb/bitacora-mongod.log`, `evidencias/E6-mongodb/system-profile.json` y `evidencias/E6-mongodb/09-comparacion.md`):**
  * Bitácora operativa `mongod` persistente en disco (`systemLog.path` con `logAppend: true`), registrando conexiones, autenticaciones y cambios de configuración del perfilador (`Profiler settings changed` en `evidencias/E6-mongodb/bitacora-mongod.log`).
  * Perfilador de base de datos (`db.setProfilingLevel(2)` o nivel 1 con `slowms: 0`) escribiendo en la colección circular `comercial.system.profile` (1 MB) y exportado con integridad verificada (`evidencias/E6-mongodb/system-profile.json`).
  * Control compensatorio de permisos mediante instantáneas periódicas almacenadas en `auditoria.instantaneas_privilegios` (`evidencias/02-responsables.md`, `evidencias/05-conservacion.md`).

---

## 3. Bitácora interpretada (A3, A5)

A continuación se interpretan cuatro eventos relevantes extraídos de las bitácoras del expediente:

### Evento 1 — Modificación del RFC de María García (Incidente de dato sensible)
* **Quién:** Usuario `app_ventas` (sesión de aplicación comercial), ejecutado sobre `public.clientes` (`evidencias/E5-bitacora-postgresql.log`, sentencia `UPDATE clientes SET rfc = ...`; registrado también en `auditoria.cambios_clientes` según `evidencias/E4-muestra-auditoria.txt`).
* **Cuándo:** `2026-10-25 22:50:42` (marca de tiempo registrada por `log_line_prefix` en `evidencias/E5-bitacora-postgresql.log` y columna `momento` en `auditoria.cambios_clientes`).
* **Desde dónde:** Conexión local `client=127.0.0.1` mediante cliente `psql` / aplicación de ventas (`app=psql` / `app_ventas`, `evidencias/E5-bitacora-postgresql.log`).
* **Qué ocurrió:** Se ejecutó una sentencia `UPDATE` sobre el registro de la cliente **María García** en `public.clientes`, sustituyendo su RFC fiscal por un nuevo valor sin que existiera una solicitud aprobada en `gobierno.solicitudes_cambio`.
* **Qué tipo de evento es:** Modificación de dato personal sensible (`DML` — `UPDATE` capturado por `log_statement = 'mod'` y por el disparador de auditoría del dato).
* **Qué prueba:** Demuestra que, aunque `app_ventas` contaba con permiso técnico `UPDATE` sobre `public.clientes` (`evidencias/E2-privilegios.txt`), los controles combinados (`log_statement = 'mod'` y `trg_auditoria_clientes`) permiten reconstruir exactamente quién realizó la alteración, cuándo ocurrió y cuál era el valor fiscal original (`OLD.rfc`) frente al valor modificado (`NEW.rfc`), habilitando la reversión autorizada por la Gerencia Comercial.

### Evento 2 — Intento fallido y evasión efectiva del disparador de auditoría
* **Quién:** En primera instancia `app_ventas` (línea 163 de `dba.bitacora`) y tres centésimas de segundo después el superusuario `postgres` (líneas 169 y 171 de `dba.bitacora`, documentado en `evidencias/06-conciliacion.md` y `evidencias/E5-bitacora-postgresql.log`).
* **Cuándo:** `2026-10-25 22:50:53.460` (intento de `app_ventas`), `2026-10-25 22:50:53.549` (desactivación por `postgres`) y `2026-10-25 22:50:53.554` (reactivación por `postgres`).
* **Desde dónde:** Sesión local `client=127.0.0.1` en `psql` (`evidencias/E5-bitacora-postgresql.log`).
* **Qué ocurrió:** El rol `app_ventas` intentó ejecutar `ALTER TABLE clientes DISABLE TRIGGER trg_auditoria_clientes`, operación rechazada por PostgreSQL por falta de privilegios (`log_min_error_statement = error`). Inmediatamente después, la cuenta `postgres` ejecutó la misma instrucción con éxito, deshabilitando el disparador durante un intervalo breve antes de volver a ejecutar `ENABLE TRIGGER`.
* **Qué tipo de evento es:** Evento crítico de seguridad / manipulación de mecanismos de control (`DDL` — `ALTER TABLE`).
* **Qué prueba:** Prueba dos hechos fundamentales: (1) el control preventivo de privilegios bloquea intentos de evasión provenientes de cuentas de aplicación no propietarias; y (2) un administrador con cuenta `postgres` puede abrir una ventana ciega en `auditoria.cambios_clientes` sin dejar rastro en dicha tabla, aunque la bitácora del servidor (`log_statement = 'mod'`) sí deja evidencia del `DISABLE TRIGGER`.

### Evento 3 — Cambio estructural autorizado (`CAM-2026-014`)
* **Quién:** Usuario `postgres` (DBA, en rol de custodio ejecutor, `evidencias/06-conciliacion.md`).
* **Cuándo:** `2026-11-19` dentro de la ventana autorizada (`ventana_inicio <= now() <= ventana_fin = t`, verificada en `sql/04-registro-cambios.sql` y `evidencias/06-conciliacion.md`).
* **Desde dónde:** Sesión administrativa `psql` desde `127.0.0.1` en la base `comercial` (`evidencias/E5-bitacora-postgresql.log`).
* **Qué ocurrió:** Se ejecutó `ALTER TABLE clientes ADD COLUMN canal_alta VARCHAR(20);` y se documentó la columna con `COMMENT ON COLUMN clientes.canal_alta ...` al amparo del folio `CAM-2026-014`, previamente solicitado por la Gerencia Comercial y aprobado por el Comité de cambios (`evidencias/06-conciliacion.md`).
* **Qué tipo de evento es:** Cambio estructural autorizado en producción (`DDL` — `ALTER TABLE` y `COMMENT`).
* **Qué prueba:** Demuestra el funcionamiento integral del ciclo de gobierno de `POL-06`: existe trazabilidad completa desde la aprobación previa (`gobierno.solicitudes_cambio`), la ejecución dentro de ventana horaria, el registro en `dba.bitacora` y la conciliación sin desviaciones.

### Evento 4 — Activación del perfilador y consulta de clientes en MongoDB
* **Quién:** Usuario administrativo de MongoDB sobre la base `comercial` (`evidencias/E6-mongodb/bitacora-mongod.log` y `evidencias/E6-mongodb/system-profile.json`).
* **Cuándo:** Durante la ventana de auditoría del LAB-02 (registrado en campo `ts` de `evidencias/E6-mongodb/system-profile.json` y en las marcas ISO-8601 de `evidencias/E6-mongodb/bitacora-mongod.log`).
* **Desde dónde:** Cliente `mongosh` local (`127.0.0.1`, identificado en atributo `remote` de `evidencias/E6-mongodb/bitacora-mongod.log`).
* **Qué ocurrió:** Se modificó el nivel de perfilado (`Profiler settings changed` en `bitacora-mongod.log`) y posteriormente se ejecutaron operaciones de lectura y actualización sobre `comercial.clientes`, quedando capturados los predicados de filtro (`command.q`) y documentos modificados (`command.u`) en `evidencias/E6-mongodb/system-profile.json`.
* **Qué tipo de evento es:** Cambio de configuración de auditoría y operación sobre colección confidencial (`CRUD` en MongoDB).
* **Qué prueba:** Demuestra que, aunque MongoDB Community carece de auditoría nativa, la combinación de `bitacora-mongod.log` y `system.profile` permite detectar cuándo se enciende o apaga el perfilador y reconstruir qué documentos de clientes fueron consultados o modificados mientras estuvo activo.

---

## 4. Elementos de gobierno (A1, A2)

* **Matriz de responsables (`evidencias/02-responsables.md`):**
  * **Propietario de datos comerciales (`public.clientes` en PostgreSQL y `comercial.clientes` en MongoDB):** Gerencia Comercial, única autoridad facultada para aprobar accesos operativos y autorizar correcciones sobre datos de clientes.
  * **Propietario de activos de auditoría y bitácoras (`auditoria.cambios_clientes`, `dba.bitacora`, `pg_log`, `bitacora-mongod.log`, `system.profile`):** Auditoría Interna / Seguridad de la Información, garantizando segregación de funciones respecto a quien opera los datos.
  * **Custodio técnico:** DBA, responsable de operar, respaldar, proteger y documentar las bases de datos sin alterar valores de negocio por iniciativa propia.
  * **Usuarios autorizados:** Aplicación de ventas (`app_ventas`), personal de soporte (bajo vista enmascarada) y analistas autorizados.
* **Catálogo mínimo de datos (`evidencias/04-catalogo.md` y `sql/03-inventario-tablas.sql`):**
  * Inventario unificado de cinco activos principales entre PostgreSQL 18 y MongoDB 9.0: **CAT-01** (`public.clientes`), **CAT-02** (`auditoria.cambios_clientes`), **CAT-03** (`gobierno.solicitudes_cambio`), **CAT-04** (`comercial.clientes` en MongoDB) y **CAT-05** (`comercial.system.profile` en MongoDB), además de la vista `dba.bitacora`. Cada entrada especifica motor, ubicación exacta, propietario, custodio, clasificación, presencia de datos personales, finalidad, plazo de conservación y referencia a su diccionario.
* **Diccionario de datos operativo (`sql/02-comentarios-diccionario.sql`, `evidencias/diccionario-clientes.csv` y `evidencias/03-diccionario.md`):**
  * Los metadatos técnicos y definiciones de negocio de la tabla `clientes` y sus 11 columnas (`id`, `nombre`, `correo`, `telefono`, `rfc`, `edad`, `ciudad`, `codigo_postal`, `fecha_alta`, `segmento` y `canal_alta`) residen dentro del propio catálogo de PostgreSQL mediante `COMMENT ON TABLE` y `COMMENT ON COLUMN`, exportados a formato interoperable (`evidencias/diccionario-clientes.csv`) y complementados en `evidencias/03-diccionario.md` con su clasificación de sensibilidad, finalidad, control aplicado, estado de auditoría y regla de calidad.

---

## 5. Conservación (A3)

El criterio de conservación diseñado conforme a **NIST SP 800-92** (`evidencias/05-conservacion.md`) establece:

* **Accesos de PostgreSQL y bitácora de `mongod`:** Conservación de **6 a 12 meses** en repositorio externo centralizado con verificación `SHA-256`, mitigando el riesgo de rotación local o pérdida en RAM (`getLog` en MongoDB solo retiene 1024 eventos en memoria).
* **Cambios de privilegios, estructura (`DDL`) e instantáneas de privilegios en MongoDB:** Conservación mínima de **24 meses** en almacenamiento externo de solo adición (*append-only*) cifrado, debido a su bajo volumen y alto impacto forense ante escalamientos de privilegios descubiertos tardíamente.
* **Modificaciones de datos (`log_statement = 'mod'`) y exportaciones de `system.profile`:** Conservación de **90 días** en almacenamiento externo cifrado para cubrir revisiones trimestrales y conciliaciones, acotando la exposición de datos personales capturados en claro.
* **Tabla `auditoria.cambios_clientes`:** Retención en línea sin permisos operativos de `UPDATE`/`DELETE` más exportación periódica cifrada; plazo definitivo sujeto a **"Plazo a confirmar con el área jurídica"** para armonizar la obligación fiscal de conservación de expedientes de clientes frente al derecho de supresión/cancelación de datos personales (conflicto detectado en LAB-01, Actividad 13).
* **Control de integridad y disposición final:** Toda bitácora exportada se acompaña de su suma `SHA-256` (`evidencias/E5-bitacora-postgresql.sha256` y `evidencias/E6-mongodb/*.sha256`). Al vencer los plazos aprobados, se aplica eliminación segura verificada o anonimización irreversible cuando exista mandato legal de conservar la traza técnica (`evidencias/05-conservacion.md`).

---

## 6. Políticas (A4)

Se establecieron seis políticas prácticas de datos redactadas como reglas de decisión verificables (`politicas/POL-01-acceso.md` a `politicas/POL-06-cambios-produccion.md`):

* **`POL-01` — Control de Acceso y Revisión de Privilegios (`politicas/POL-01-acceso.md`):** Exige solicitud formal aprobada por el propietario del dato antes de otorgar permisos y revisión mensual de privilegios. *Evidencia:* sentencias `GRANT`/`REVOKE` en `evidencias/E5-bitacora-postgresql.log`, privilegios vigentes en `evidencias/E2-privilegios.txt` e instantáneas en `auditoria.instantaneas_privilegios` *(acta mensual automatizada aún no implementada)*.
* **`POL-02` — Respaldo de Bases de Datos y Verificación de Integridad (`politicas/POL-02-respaldo.md`):** Fija respaldo completo diario fuera de horario pico, copia externa y pruebas periódicas de restauración (procedimiento técnico a definir en Unidad V). *Evidencia:* inventario de objetos en `evidencias/04-catalogo.md` y huella `evidencias/E5-bitacora-postgresql.sha256` *(bitácora de respaldos pendiente de Unidad V)*.
* **`POL-03` — Retención y Disposición Final de Datos y Bitácoras (`politicas/POL-03-retencion.md`):** Establece plazos diferenciados (24 meses para privilegios/auditoría, 90 días para modificaciones/perfilado) y suspensión de depuración ante investigaciones activas de `POL-05`. *Evidencia:* `evidencias/05-conservacion.md` y archivos `.sha256` *(dictamen jurídico y actas de purga pendientes de formalización)*.
* **`POL-04` — Autorización y Ejecución de Restauraciones (`politicas/POL-04-restauracion.md`):** Prohíbe restaurar en producción sin aprobación conjunta del propietario del dato y Gerencia de TI, y exige enmascaramiento al restaurar en ambientes no productivos (procedimiento técnico en Unidad V). *Evidencia:* flujo de aprobación en `gobierno.solicitudes_cambio` (`sql/04-registro-cambios.sql`) y conciliación en `evidencias/06-conciliacion.md` *(sin eventos históricos de restauración a la fecha)*.
* **`POL-05` — Protección, Acceso y Trazabilidad de Datos Sensibles (`politicas/POL-05-datos-sensibles.md`):** Restringe el acceso directo a columnas personales (`rfc`, `correo`, `telefono`, etc.), exige vistas enmascaradas para soporte y obliga a auditar cambios de `rfc` con huella `SHA-256` en exportaciones. *Evidencia:* `evidencias/E3-disparadores.txt`, `evidencias/E4-muestra-auditoria.txt`, `evidencias/diccionario-clientes.csv` y `evidencias/01-calidad.md`.
* **`POL-06` — Gestión y Conciliación de Cambios en Producción (`politicas/POL-06-cambios-produccion.md`):** Exige folio aprobado previo en `gobierno.solicitudes_cambio`, ejecución dentro de ventana horaria con bitácora activa y conciliación semanal contra `dba.bitacora`. *Evidencia:* `sql/04-registro-cambios.sql`, `evidencias/E5-bitacora-postgresql.log` y `evidencias/06-conciliacion.md`.

---

## 7. Conciliación de cambios (A5)

El cruce entre las sentencias `CREATE`, `ALTER`, `DROP`, `GRANT` y `REVOKE` extraídas de `dba.bitacora` y los registros aprobados en `gobierno.solicitudes_cambio` (`sql/04-registro-cambios.sql`, documentado en `evidencias/06-conciliacion.md`) arrojó los siguientes resultados:

* **Cambios conformes y autorizados:** 1 cambio productivo (`ALTER TABLE clientes ADD COLUMN canal_alta VARCHAR(20);` y su comentario asociado) ejecutado por `postgres` dentro de la ventana aprobada del folio **`CAM-2026-014`** (`evidencias/06-conciliacion.md`).
* **Cambios de preparación inicial sin folio:** 5 bloques de operaciones ejecutados durante la construcción previa de los laboratorios (`REVOKE`/`GRANT` iniciales, columna `segmento`, creación del esquema `auditoria` y creación del esquema `gobierno`), realizados antes de la entrada en vigor de `POL-06`.
* **Desviaciones y hallazgos críticos sin autorización:**
  1. Desactivación y reactivación temporal de `trg_auditoria_clientes` por `postgres` (líneas 169 y 171) e intento fallido previo por `app_ventas` (línea 163), sin solicitud ni folio aprobado (`evidencias/06-conciliacion.md`).
  2. Creación de `rol_temporal` con contraseña visible en texto claro en la bitácora original (línea 37, saneada como `<REDACTED>` en `evidencias/E5-bitacora-postgresql.log`).
  3. Hueco de evidencia en la creación de la vista `dba.bitacora`, ejecutada cuando `log_statement` aún tenía el valor `none` (`evidencias/06-conciliacion.md`).

---

## 8. Hallazgos

| ID | Hallazgo | Fuente | Severidad | Impacto | Recomendación | Decisión requerida de |
|---|---|---|---|---|---|---|
| **H-01** | Desactivación temporal no autorizada del disparador `trg_auditoria_clientes` por superusuario `postgres` e intento previo por `app_ventas`. | `evidencias/06-conciliacion.md` (líneas 163, 169, 171) y `evidencias/E5-bitacora-postgresql.log` | **Alta** | Genera una ventana ciega en `auditoria.cambios_clientes` durante la cual pueden alterarse RFC sin trazabilidad del valor anterior/nuevo; evidencia uso directo de superusuario sin aprobación y posible compromiso o mal uso de `app_ventas`. | Prohibir el uso operativo cotidiano de `postgres` mediante cuentas nominativas de DBA, investigar cambios en `clientes` ocurridos en el intervalo y alertar en tiempo real cualquier sentencia `DISABLE TRIGGER`. | Seguridad de la Información y Gerencia de TI |
| **H-02** | Exposición de contraseña en texto claro al ejecutar `CREATE ROLE rol_temporal ... PASSWORD` en la bitácora del servidor, además de persistencia de un rol temporal no autorizado. | `evidencias/06-conciliacion.md` (línea 37) y `evidencias/E5-bitacora-postgresql.log` | **Alta** | Cualquier usuario con lectura sobre `dba.bitacora` o los archivos de log puede comprometer credenciales de acceso al servidor; además existe una cuenta residual fuera de matriz (`POL-01`). | Eliminar `rol_temporal` previa aprobación, establecer como estándar el cambio de contraseñas mediante protocolos SCRAM cifrados (`\password` en `psql`) sin sentencias SQL en claro y sanitizar exportaciones de bitácoras. | Seguridad de la Información y Gerencia de TI |
| **H-03** | Exceso de privilegios en `E2`: el rol `soporte_ana` conserva permiso `SELECT` directo sobre la tabla base `public.clientes` en lugar de consultar únicamente la vista enmascarada. | `evidencias/E2-privilegios.txt` (fila 2) vs. Matriz de roles Unidad II (`POL-01`, `POL-05`) | **Alta** | Permite al personal de soporte visualizar datos personales y fiscales completos (`rfc`, `correo`, `telefono`) sin necesidad operativa, contraviniendo `POL-05`. | Revocar `SELECT` sobre `public.clientes` al rol `soporte_ana` y otorgar `SELECT` exclusivamente sobre la vista enmascarada de soporte aprobada. | Gerencia Comercial (Propietario del dato) |
| **H-04** | Problemas de calidad de datos en `public.clientes`: cliente duplicado por correo (`C1`), RFC incompleto de 12 caracteres (`C2`), correo inválido (`C3`), edad negativa `-3` (`C4`) y RFC nulo (`C5`). | `evidencias/01-calidad.md` y `sql/01-verificaciones-calidad.sql` | **Media** | Errores en facturación electrónica, duplicidad de expedientes comerciales y baja confiabilidad analítica. | Solicitar a Gerencia Comercial la validación documental para corregir los registros afectados e implementar restricciones `CHECK` y `UNIQUE INDEX` en `public.clientes` previa coordinación con la aplicación de ventas. | Gerencia Comercial |
| **H-05** | Hueco de trazabilidad por periodo inicial con `log_statement = 'none'` (creación de `dba.bitacora` no registrada) y ausencia de registro de consultas `SELECT` en PostgreSQL. | `evidencias/06-conciliacion.md` y `evidencias/E1-configuracion-registro.txt` | **Media** | Impide auditar acciones ocurridas antes de activar `log_statement = 'mod'` y no detecta exfiltración masiva de datos mediante lecturas (`SELECT`). | Mantener `log_statement = 'mod'` bloqueado en la plantilla base de despliegue y evaluar la instalación de la extensión `pgaudit` para auditar lecturas sobre `public.clientes`. | Gerencia de TI y Seguridad de la Información |
| **H-06** | Limitaciones de trazabilidad nativa en MongoDB Community: `system.profile` es un búfer circular volátil de 1 MB y `mongod` no audita cambios de roles de forma nativa. | `evidencias/E6-mongodb/09-comparacion.md` y `evidencias/05-conservacion.md` | **Media** | Posible pérdida de evidencia ante picos de tráfico que sobrescriban `system.profile` o reinicios del servicio si el perfilador no se fija en `mongod.cfg`. | Automatizar la exportación periódica de `system.profile` y la ejecución programada de instantáneas en `auditoria.instantaneas_privilegios` con firma `SHA-256`. | Gerencia de TI y Seguridad de la Información |
| **H-07** | Plazos legales de retención y disposición final pendientes de validación formal por el Área Jurídica, y ausencia de actas mensuales automatizadas de revisión de privilegios (`POL-01`). | `evidencias/05-conservacion.md`, `politicas/POL-01-acceso.md` y `politicas/POL-03-retencion.md` | **Baja** | Riesgo de conservar datos personales en `auditoria.cambios_clientes` más allá del plazo permitido o carecer de evidencia formal de revisión periódica de accesos. | Gestionar dictamen del Área Jurídica para fijar plazos definitivos en `POL-03` e instituir un formato mensual de acta de conciliación de privilegios. | Área Jurídica y Auditoría Interna |

---

## 9. Limitaciones conocidas y riesgos aceptados (A6)

Para transparencia de Auditoría Interna, se distinguen las limitaciones técnicas verificadas en este entorno frente a controles avanzados documentados pero no practicados:

### A. Limitaciones verificadas empíricamente en los laboratorios (LAB-01, LAB-02 y LAB-03)
1. **Lecturas (`SELECT`) no registradas en PostgreSQL (`evidencias/E1-configuracion-registro.txt`):** Con `log_statement = 'mod'`, PostgreSQL registra modificaciones y `DDL`, pero no deja evidencia de quién consultó datos personales mediante `SELECT`.
   * *Quién debe aceptar formalmente el riesgo:* **Seguridad de la Información** y **Gerencia Comercial** (propietario de `clientes`), mientras no se habilite `pgaudit`.
2. **Evasión de controles por cuentas con privilegio de superusuario (`evidencias/06-conciliacion.md`, línea 169):** El rol `postgres` puede deshabilitar disparadores (`DISABLE TRIGGER`) o alterar archivos locales de bitácora si no existe envío remoto en tiempo real.
   * *Quién debe aceptar formalmente el riesgo:* **Gerencia de TI** y **Seguridad de la Información**, sujeto al control compensatorio de revisión de `dba.bitacora` y segregación de cuentas administrativas.
3. **Ausencia de auditoría nativa y volatilidad del perfilador en MongoDB Community (`evidencias/E6-mongodb/09-comparacion.md`):** MongoDB Community 9.0 no incluye el subsistema de auditoría de eventos administrativos (`auditLog`), por lo que cambios de roles no se registran automáticamente y `system.profile` (1 MB) sobrescribe eventos antiguos bajo alta carga.
   * *Quién debe aceptar formalmente el riesgo:* **Gerencia de TI** y **Seguridad de la Información**, apoyándose en los controles compensatorios de `auditoria.instantaneas_privilegios` y exportación periódica con `SHA-256`.
4. **Custodia local de archivos de bitácora y respaldos en fase de diseño (`evidencias/05-conservacion.md`, `politicas/POL-02-respaldo.md`):** Actualmente las bitácoras residen en el mismo host del motor y los procedimientos automatizados de respaldo/restauración (`POL-02`, `POL-04`) aún no están desplegados.
   * *Quién debe aceptar formalmente el riesgo:* **Gerencia de TI**, de forma temporal hasta la implementación técnica en la Unidad V.

### B. Controles documentados pero no practicados en este entorno
* **Auditoría nativa de MongoDB Enterprise (`auditLog`):** Documentada en la comparativa (`evidencias/E6-mongodb/09-comparacion.md`) como solución integral para registrar eventos `DDL`, autenticaciones y cambios de privilegios en formato JSON/BSON, pero **no practicada** por emplear la edición Community.
* **Extensión `pgaudit` en PostgreSQL:** Documentada como mecanismo estándar para auditar consultas `SELECT` y granularidad por objeto en catálogos gubernamentales/financieros, pero **no instalada ni practicada** en el servidor del laboratorio.
* **Procedimientos automatizados de respaldo (`pg_dump` / `mongodump`) y restauración controlada:** Referenciados a nivel de decisión en `politicas/POL-02-respaldo.md` y `politicas/POL-04-restauracion.md`, pero **no ejecutados** en este laboratorio por corresponder al alcance técnico de la Unidad V.

---

## 10. Índice de evidencias

| Archivo | Descripción | Huella de integridad (`SHA-256`) |
|---|---|---|
| `EXPEDIENTE.md` | Documento integrador de auditoría interna de la Unidad III | No aplica (documento maestro) |
| `sql/01-verificaciones-calidad.sql` | Consultas de detección de anomalías de calidad en `clientes` | No aplica (script fuente) |
| `sql/02-comentarios-diccionario.sql` | Definición de `COMMENT` en motor y consulta de diccionario | No aplica (script fuente) |
| `sql/03-inventario-tablas.sql` | Consulta de estadísticas e inventario físico de tablas en PostgreSQL | No aplica (script fuente) |
| `sql/04-registro-cambios.sql` | Creación de `gobierno.solicitudes_cambio`, ejecución `CAM-2026-014` y consulta de conciliación | No aplica (script fuente) |
| `politicas/POL-01-acceso.md` | Política práctica de control de acceso y revisión de privilegios | No aplica (documento normativo) |
| `politicas/POL-02-respaldo.md` | Política práctica de respaldo y verificación de integridad | No aplica (documento normativo) |
| `politicas/POL-03-retencion.md` | Política práctica de retención y disposición final | No aplica (documento normativo) |
| `politicas/POL-04-restauracion.md` | Política práctica de autorización y ejecución de restauraciones | No aplica (documento normativo) |
| `politicas/POL-05-datos-sensibles.md` | Política práctica de protección y trazabilidad de datos sensibles | No aplica (documento normativo) |
| `politicas/POL-06-cambios-produccion.md` | Política práctica de gestión y conciliación de cambios en producción | No aplica (documento normativo) |
| `evidencias/01-calidad.md` | Registro de hallazgos de calidad (`C1`–`C5`) y análisis de restricciones | No aplica (documento analítico) |
| `evidencias/02-responsables.md` | Matriz ampliada de propietarios, custodios y usuarios autorizados | No aplica (documento analítico) |
| `evidencias/03-diccionario.md` | Diccionario operativo complementario (clasificación, controles y reglas) | No aplica (documento analítico) |
| `evidencias/diccionario-clientes.csv` | Exportación CSV del diccionario desde `information_schema` y `col_description` | Verificable por regeneración |
| `evidencias/04-catalogo.md` | Catálogo mínimo de datos integrado (`CAT-01` a `CAT-05`) | No aplica (documento analítico) |
| `evidencias/05-conservacion.md` | Matriz de criterios de conservación de bitácoras (NIST SP 800-92) | No aplica (documento analítico) |
| `evidencias/06-conciliacion.md` | Conciliación entre `dba.bitacora` y `gobierno.solicitudes_cambio` | No aplica (documento analítico) |
| `evidencias/E1-configuracion-registro.txt` | Parámetros vigentes de bitácora en `pg_settings` | Verificable en motor |
| `evidencias/E2-privilegios.txt` | Privilegios vigentes por rol sobre tablas de `comercial` | Verificable en motor |
| `evidencias/E3-disparadores.txt` | Estado activo del disparador `trg_auditoria_clientes` en `pg_trigger` | Verificable en motor |
| `evidencias/E4-muestra-auditoria.txt` | Muestra de metadatos de eventos en `auditoria.cambios_clientes` (sin valores sensibles) | Verificable en motor |
| `evidencias/E5-bitacora-postgresql.log` | Exportación de la bitácora del servidor PostgreSQL con credenciales saneadas | Ver archivo `evidencias/E5-bitacora-postgresql.sha256` |
| `evidencias/E5-bitacora-postgresql.sha256` | Suma de verificación criptográfica de `E5-bitacora-postgresql.log` | Contiene el hash `SHA-256` oficial de `E5` |
| `evidencias/E6-mongodb/system-profile.json` | Exportación Extended JSON del perfilador `comercial.system.profile` (LAB-02) | Ver archivo `evidencias/E6-mongodb/hashes.sha256` |
| `evidencias/E6-mongodb/bitacora-mongod.log` | Bitácora operativa exportada de `mongod` (LAB-02) | Ver archivo `evidencias/E6-mongodb/hashes.sha256` |
| `evidencias/E6-mongodb/09-comparacion.md` | Comparativa técnica de trazabilidad PostgreSQL vs. MongoDB Community (LAB-02) | Incluido en paquete `E6-mongodb` |

## 11. Preguntas de reflexión

### 1. ¿Por qué el gobierno de datos no es “burocracia” en el contexto del problema inicial de la unidad?
Porque los mecanismos técnicos implementados en los laboratorios anteriores (`log_statement`, disparadores de auditoría y el perfilador de MongoDB) responden únicamente **qué** ocurrió en el motor, pero son incapaces de responder **si lo ocurrido fue legítimo o quién debe responder por ello**. Sin gobierno práctico de datos (`evidencias/02-responsables.md` a `06-conciliacion.md`), el DBA puede ver en la bitácora que se modificó el RFC de María García o que un registro tiene 12 caracteres, pero carece de autoridad de negocio para decidir cuál es el valor fiscal correcto, no existe una regla escrita que demuestre que el cambio fue indebido y las bitácoras podrían rotarse antes de una revisión trimestral. El gobierno convierte registros técnicos aislados en evidencia verificable y atribuible.

### 2. ¿Qué diferencia hay entre el propietario técnico de una tabla en PostgreSQL y el propietario del dato?
* **Propietario técnico (`pg_class.relowner`):** Es el rol dentro del SGBD que posee el objeto físico en el motor (en nuestro inventario `sql/03-inventario-tablas.sql`, el usuario `postgres`). Tiene facultades técnicas para alterar su estructura (`ALTER`), eliminarla (`DROP`), administrar disparadores o delegar permisos SQL, pero **no** tiene autoridad sobre el significado ni la veracidad de la información almacenada.
* **Propietario del dato (*Data Owner*):** Es el responsable funcional dentro de la organización (por ejemplo, **Gerencia Comercial** para `public.clientes`, o **Auditoría Interna / Seguridad de la Información** para `auditoria.cambios_clientes` en `evidencias/02-responsables.md`). Decide para qué se usa el dato, quién puede consultarlo o modificarlo, cuánto tiempo se conserva y autoriza las correcciones sobre sus valores.

### 3. ¿Por qué una política sin evidencia no supera una auditoría?
Porque en auditoría interna una regla escrita sin registros que prueben su ejecución es únicamente una **declaración de intención**, no un control operativo. Por ejemplo, redactar en `POL-01` que *"los privilegios se revisan mensualmente"* no demuestra cumplimiento; para superar la revisión se requiere cruzar la regla con evidencias verificables: las líneas `GRANT`/`REVOKE` de `evidencias/E5-bitacora-postgresql.log`, los privilegios efectivos en `evidencias/E2-privilegios.txt` y los folios aprobados en `gobierno.solicitudes_cambio`. Sin evidencia, el auditor asume que el control no opera.

### 4. ¿Qué parte del expediente sería la más difícil de mantener actualizada? ¿Cómo lo resolverías?
Las secciones más difíciles de mantener al día son la **conciliación de cambios (`evidencias/06-conciliacion.md`)** junto con el **inventario de privilegios (`E2`) y el catálogo/diccionario (`04-catalogo.md`, `diccionario-clientes.csv`)**, porque en un entorno productivo los esquemas, roles y volúmenes cambian continuamente.
* **Cómo resolverlo:**
  1. **Acoplar la actualización al flujo de cambios (`POL-06`):** Exigir como requisito obligatorio antes de cerrar cualquier folio en `gobierno.solicitudes_cambio` que el script ejecutado incluya sus sentencias `COMMENT ON` y la actualización del catálogo.
  2. **Automatizar la extracción y comparación:** Programar tareas periódicas (mediante `pg_cron` o tareas programadas del sistema operativo) que exporten `E2-privilegios.txt`, `diccionario-clientes.csv` y el cruce entre `dba.bitacora` y `gobierno.solicitudes_cambio`, generando alertas automáticas únicamente cuando detecten desviaciones (cambios sin folio o roles fuera de matriz).

### 5. ¿Qué hallazgo de tu expediente tiene mayor impacto y por qué?
El hallazgo **H-01** (*desactivación temporal no autorizada del disparador `trg_auditoria_clientes` mediante el superusuario `postgres` en la línea 169 de la bitácora*). Su impacto es crítico porque **compromete la confiabilidad de todo el sistema de auditoría**: mientras el disparador permanece deshabilitado, cualquier modificación sobre el RFC de los clientes ocurre en una ventana ciega sin dejar rastro de los valores anteriores y nuevos (`OLD.rfc` / `NEW.rfc`) en `auditoria.cambios_clientes`. Si la pista de auditoría puede apagarse sin autorización ni alerta inmediata, pierde valor probatorio ante una investigación interna o legal.

### 6. ¿Por qué documentar una limitación es preferible a ocultarla ante una auditoría?
* **Credibilidad e integridad profesional:** Un auditor técnico detectará inevitablemente que `log_statement = 'mod'` no registra lecturas `SELECT` o que MongoDB Community carece de auditoría nativa (`auditLog`). Ocultar o maquillar estas limitaciones convierte una restricción técnica conocida en un hallazgo grave de encubrimiento y pérdida de confianza en el DBA.
* **Transferencia formal del riesgo:** Al documentar explícitamente la limitación en la **Sección 9 (`Limitaciones conocidas y riesgos aceptados`)**, el DBA demuestra dominio sobre su infraestructura y traslada la decisión a la dirección (**Gerencia de TI, Seguridad de la Información y propietarios de datos**), quienes pueden aceptar formalmente el riesgo residual o aprobar presupuesto y controles compensatorios (como `pgaudit`, instantáneas de privilegios o migración a ediciones con auditoría nativa).