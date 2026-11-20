# 06 - Conciliación de Cambios en Producción

## Tabla de Conciliación (`dba.bitacora` vs. `gobierno.solicitudes_cambio`)

| Momento (bitácora) | Usuario | Sentencia | Folio que lo autoriza | ¿Autorizado? | Hallazgo |
|---|---|---|---|---|---|
| `2026-10-25 22:50:09.341` | `postgres` | `REVOKE UPDATE ON clientes FROM soporte_ana` | Sin folio (LAB-01 Act. 6) | No formalizado | Cambio de privilegios ejecutado durante preparación previa a la implementación de `POL-01` y `POL-06`. |
| `2026-10-25 22:50:09.367` | `postgres` | `GRANT UPDATE ON clientes TO app_ventas` | Sin folio (LAB-01 Act. 6) | No formalizado | Asignación de privilegios previa a la existencia del registro formal de cambios (`CAT-03`). |
| `2026-10-25 22:50:09.372` | `postgres` | `ALTER TABLE clientes ADD COLUMN segmento VARCHAR(20)` | Sin folio (LAB-01 Act. 6) | No formalizado | Modificación estructural previa a la entrada en vigor de `POL-06`. |
| `2026-10-25 22:50:09.375` | `postgres` | `CREATE ROLE rol_temporal LOGIN PASSWORD '[CENSURADO]'` | Sin folio (LAB-01 Act. 6) | No formalizado | **Hallazgo doble:** creación de rol sin solicitud aprobada y exposición de contraseña en texto claro en la bitácora. |
| `2026-10-25 22:50:30.110` | `postgres` | `CREATE SCHEMA auditoria` / `CREATE TABLE auditoria.cambios_clientes` / `CREATE TRIGGER trg_auditoria_clientes` | Sin folio (LAB-01 Parte B) | No formalizado | Implementación de controles de auditoría ejecutada antes de establecer el flujo de solicitudes de cambio. |
| `2026-10-25 22:50:53.460` | `app_ventas` | `ALTER TABLE clientes DISABLE TRIGGER trg_auditoria_clientes` | Ninguno | **No** | **Hallazgo crítico de seguridad:** intento no autorizado de desactivar el disparador de auditoría desde cuenta de aplicación (bloqueado por el motor por falta de privilegios). |
| `2026-10-25 22:50:53.549` | `postgres` | `ALTER TABLE clientes DISABLE TRIGGER trg_auditoria_clientes` | Ninguno | **No** | **Hallazgo crítico de integridad:** desactivación efectiva del disparador de auditoría usando superusuario sin solicitud aprobada, creando una ventana ciega en `auditoria.cambios_clientes`. |
| `2026-10-25 22:50:53.554` | `postgres` | `ALTER TABLE clientes ENABLE TRIGGER trg_auditoria_clientes` | Ninguno | **No** | Reactivación del control tras ventana sin trazabilidad en `auditoria.cambios_clientes`; requiere investigación forense de cambios ocurridos en el intervalo. |
| `2026-11-19 23:05:10.120` | `postgres` | `CREATE SCHEMA gobierno` / `CREATE TABLE gobierno.solicitudes_cambio (...)` | Implementación `POL-06` | Sí (Actividad 7) | Creación de la infraestructura base de gobierno de cambios (en operación continua requeriría folio de infraestructura). |
| `2026-11-19 23:05:10.450` | `postgres` | `ALTER TABLE clientes ADD COLUMN canal_alta VARCHAR(20);` | **`CAM-2026-014`** | **Sí** | **— (Cambio conforme: aprobado por Comité de cambios y ejecutado dentro de ventana autorizada).** |

*(Nota de alcance: la creación de la vista `dba.bitacora` no figura en el listado anterior porque al momento de crearse el parámetro `log_statement` aún tenía el valor `none`, lo que constituye un hueco de evidencia declarado).*

---

## Respuestas a las Preguntas

### 1. ¿Qué cambios de la bitácora no tienen folio? Clasifícalos: ¿son de preparación del laboratorio o representan hallazgos?
Los cambios sin folio observados en `dba.bitacora` se dividen en dos categorías:

* **Cambios de preparación / construcción de infraestructura (pre-gobierno):**
  * Ajustes iniciales de permisos (`REVOKE UPDATE ON clientes FROM soporte_ana`, `GRANT UPDATE ON clientes TO app_ventas`) y adición de la columna `segmento` (LAB-01, Actividad 6).
  * Creación del esquema `auditoria`, la tabla `auditoria.cambios_clientes` y el disparador `trg_auditoria_clientes` (LAB-01, Parte B).
  * Creación del esquema `gobierno` y la tabla `gobierno.solicitudes_cambio` (LAB-03, Actividad 7).
  * *Clasificación:* Corresponden a la construcción inicial del entorno antes de que existiera formalmente `POL-06` y el catálogo `CAT-03`; no obstante, en un entorno productivo real toda implementación inicial debe quedar respaldada por un folio de proyecto o pase a producción.

* **Hallazgos reales de seguridad y control:**
  * Creación de `rol_temporal` con contraseña visible en texto claro en la bitácora (LAB-01, Actividad 6), que viola la protección de credenciales.
  * Intento de desactivación (`app_ventas`) y desactivación/reactivación efectiva (`postgres`) del disparador `trg_auditoria_clientes` sin solicitud aprobada (LAB-01, Actividad 14).
  * Hueco de evidencia en la creación de `dba.bitacora` cuando `log_statement` estaba en `none`.

### 2. La desactivación del disparador del LAB-01 (Actividad 14), ¿qué tan grave es como hallazgo? ¿Por qué? ¿Qué distingue la línea 163 de la 169?
* **Gravedad del hallazgo:** **Crítica.**
* **Por qué:** El disparador `trg_auditoria_clientes` es el único mecanismo que captura el valor anterior (`OLD.rfc`) y el valor nuevo (`NEW.rfc`) de un dato fiscal sensible. Al desactivarlo en producción, se abre una ventana ciega en la que un administrador o atacante puede alterar o falsificar el RFC de los clientes sin que quede registro en `auditoria.cambios_clientes`, comprometiendo la integridad probatoria de toda la auditoría.
* **Qué distingue la línea 163 de la línea 169:**
  * **Línea 163 (`usuario = app_ventas`):** Representa un **intento fallido**. El rol de aplicación `app_ventas` ejecutó la instrucción `ALTER TABLE clientes DISABLE TRIGGER ...`, la cual quedó escrita en la bitácora, pero PostgreSQL rechazó la operación inmediatamente con un error de permisos porque `app_ventas` no es propietario de la tabla `clientes`. Demuestra un intento anómalo o compromiso de credenciales de la aplicación, aunque el control preventivo del motor detuvo el ataque.
  * **Línea 169 (`usuario = postgres`):** Representa una **evasión exitosa del control**. Al ejecutarse con la cuenta de superusuario `postgres` (propietario de la tabla), el motor aceptó el comando y deshabilitó realmente el disparador hasta la línea 171 (`ENABLE TRIGGER`). Demuestra el riesgo operativo del uso directo de cuentas con privilegios máximos sin segregación de funciones ni autorización previa.

### 3. ¿Qué limitación tiene esta conciliación si `log_statement` estuvo en `none` durante algún periodo?
Se genera un **punto ciego o hueco de evidencia irreversible**. Durante el tiempo en que `log_statement` estuvo configurado en `none`, PostgreSQL no registró ninguna sentencia `DDL` ni `DML` en los archivos del colector (tal como ocurrió con la creación de la propia vista `dba.bitacora`). En consecuencia:
* La conciliación pierde **exhaustividad**: solo puede verificar los cambios posteriores a la activación de `log_statement = 'mod'`.
* El auditor no puede descartar que durante el periodo sin registro se hayan creado tablas ocultas, otorgado privilegios indebidos o alterado datos sensibles sin folio de autorización.

### 4. ¿Quién debería realizar la conciliación: el DBA que hizo los cambios u otra persona?
Debe realizarla **otra persona independiente** —específicamente **Auditoría Interna** o **Seguridad de la Información**—, nunca exclusivamente el mismo DBA que ejecutó los cambios. 

Por el principio de **segregación de funciones**, quien opera el servidor y aplica los cambios en producción no puede ser juez y parte sobre su propia actividad: si el mismo DBA realizara la conciliación, existiría conflicto de interés para omitir modificaciones sin folio, encubrir desactivaciones temporales de controles (como la línea 169) o justificar errores operativos. El rol del DBA como custodio se limita a extraer la bitácora íntegra (`dba.bitacora` con su huella SHA-256) y entregarla al área revisora para que esta realice el cruce independiente contra `gobierno.solicitudes_cambio`.