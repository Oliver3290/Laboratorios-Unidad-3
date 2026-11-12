# Informe 
### 1. Despliegue, edición y limitación
* **Despliegue del servidor:** Se desplegó una instancia local de **MongoDB Community Edition 9.0** ejecutándose como servicio en Windows (`MongoDB`) en `127.0.0.1:27017` con control de acceso habilitado (`security.authorization: enabled`). Se configuró una cuenta administrativa (`admin` en la base `admin`) y una cuenta de aplicación con privilegios restringidos (`app_ventas` con rol `readWrite` sobre la base `comercial`).
* **Qué no existe en Community:** Esta edición carece del subsistema nativo de auditoría de seguridad (`auditLog` / `setAuditConfig`), el cual está reservado exclusivamente para **MongoDB Enterprise** y **MongoDB Atlas**.
* **Cómo se verificó:** Se comprobó empíricamente en la Actividad 7 al activar el perfilador en nivel máximo (`nivel 2`), otorgar un rol administrativo (`dbAdmin`) mediante `db.grantRolesToUser()` y consultar tanto `comercial.system.profile` como la bitácora del servidor (`getLog`), obteniendo `0` coincidencias en ambas fuentes.

### 2. Perfilador
* **Configuración:** Se gestiona por base de datos mediante `db.setProfilingLevel(nivel, opciones)` en tiempo de ejecución o de forma persistente en `mongod.cfg` (`operationProfiling.mode`). Soporta tres niveles: `0` (desactivado por defecto), `1` (captura operaciones que superan `slowms` o cumplen una expresión `filter`, como `{ op: { $in: ["insert", "update", "remove"] } }`) y `2` (captura todas las operaciones).
* **Interpretación:** Almacena documentos estructurados en la colección encapsulada `system.profile` de cada base de datos. Cada registro permite identificar la operación (`op`), el espacio de nombres (`ns`), el comando exacto (`command`), el usuario (`user`), la dirección IP (`client`), el identificador de aplicación (`appName`), la marca de tiempo (`ts`) y métricas de rendimiento (`millis`, `docsExamined`, `nModified`, `ndeleted`).
* **Costo:** El nivel 2 introduce sobrecarga continua de CPU y escritura en disco al registrar cada lectura y escritura. Además, al almacenarse en una *capped collection* de 1 MB por defecto, una carga alta sobrescribe rápidamente los registros más antiguos.

### 3. Bitácora de `mongod`
* **Dónde se escribe:** Cuando se configura `systemLog.destination: file` y `systemLog.path` en `mongod.cfg` (junto con `logAppend: true`), los eventos se escriben de forma persistente en disco. Adicionalmente, `mongod` mantiene un búfer circular en memoria RAM con los últimos **1024 eventos** en formato JSON estructurado, consultable mediante `db.adminCommand({ getLog: "global" })`.
* **Accesos:** Registra eventos bajo el componente `ACCESS`, diferenciando autenticaciones válidas (`msg: "Successfully authenticated"`, `id: 5286306`, `result: 0`) de intentos fallidos (`msg: "Failed to authenticate"`, `id: 5286307`). Internamente distingue entre contraseña errónea (`AuthenticationFailed`, `result: 18`) y usuario inexistente (`UserNotFound`, `result: 11`), registrando también la IP cliente y el `appName`.
* **Cambios de configuración:** Cualquier modificación dinámica sobre el perfilador genera el evento `msg: "Profiler settings changed"`, detallando la configuración previa (`from`) y la nueva (`to`). Aunque el evento no incluye el campo `user`, permite atribuir el cambio correlacionando el identificador de conexión (`ctx`, por ejemplo `conn31`) con el evento `Successfully authenticated` previo dentro del mismo ciclo de ejecución del servidor.

### 4. Privilegios
* **Evidencia disponible:** Ninguna de forma nativa. Ni `system.profile` en nivel 2 ni `getLog` registran la ejecución de comandos de administración de roles o usuarios (`grantRolesToUser`, `revokeRolesFromUser`).
* **Control compensatorio:** Se creó la colección `auditoria.instantaneas_privilegios` para almacenar periódicamente fotografías del estado de los usuarios y sus roles (`db.getUsers()`), registrando la fecha (`momento`) y la cuenta que ejecutó la captura (`tomada_por`).
* **Límite del control:** Al comparar dos instantáneas consecutivas se puede confirmar **si** hubo una alteración de privilegios y **qué rol** se añadió o eliminó, pero **no** identifica **quién** ejecutó el cambio ni el **instante exacto** en que ocurrió (solo acota el intervalo temporal entre ambas capturas).

### 5. Conservación
* **Riesgos observados:**
  1. **Volatilidad tras reinicios:** Al reiniciar el servicio `MongoDB`, el perfilador regresa a `was: 0` y el búfer RAM de `getLog` se vacía por completo.
  2. **Sobrescritura circular:** El límite fijo de 1 MB de `system.profile` descarta silenciosamente los documentos más antiguos conforme llegan nuevos eventos.
  3. **Truncamiento de bitácora:** Sin `logAppend: true` en `mongod.cfg`, cada reinicio del servicio sobrescribe el archivo de bitácora en disco.
* **Exportación realizada:** Antes de reiniciar el servicio, se exportó el contenido de `system.profile` en formato Extended JSON (`evidencias/system-profile.json`) y los eventos de `getLog` en texto plano (`evidencias/bitacora-mongod.log`), generando sus sumas de verificación SHA-256 en `evidencias/hashes.sha256` para acreditar su integridad.

### 6. Comparación
* **PostgreSQL (bitácora + disparadores):** Ofrece la trazabilidad más completa a nivel de datos, siendo el único entorno capaz de conservar el **valor anterior del dato** (`OLD`) ante actualizaciones o borrados, además de registrar cambios de privilegios (`GRANT`/`REVOKE`) y estructura (`DDL`).
* **MongoDB Community (perfilador + bitácora):** Permite auditar accesos, operaciones CRUD (cuando el perfilador está activo) y cambios en la configuración del perfilador, pero no registra valores anteriores de documentos ni cambios de privilegios, y depende de exportaciones periódicas para evitar pérdida de evidencia.
* **MongoDB Enterprise / Atlas (auditoría nativa):** Resuelve las carencias administrativas de Community al registrar de forma nativa y persistente cambios de roles, gestión de usuarios, operaciones DDL y comandos de configuración, aunque tampoco guarda imágenes previas de documentos sin mecanismos adicionales como *Change Streams* con *pre-images*.

### 7. Recomendación
Para emitir una recomendación fundamentada se distinguen los hechos comprobados en el laboratorio de los supuestos operativos de la organización:

* **Hechos verificados en este laboratorio:**
  * MongoDB Community Edition 9.0 no registra `grantRolesToUser` ni `revokeRolesFromUser` en `system.profile` ni en `getLog`.
  * La configuración dinámica del perfilador se pierde tras un reinicio del servicio y `system.profile` está limitado por defecto a 1 MB circular.
  * El control compensatorio mediante instantáneas detecta cambios de estado en los roles, pero no proporciona atribución de autoría ni marca de tiempo exacta.
* **Supuestos del entorno organizacional:**
  * La organización está sujeta a requisitos formales de cumplimiento o auditoría (como ISO 27001, PCI-DSS o normativas de protección de datos) que exigen atribución individual y no repudio.
  * Existe capacidad operativa para administrar infraestructura de monitoreo o presupuesto para licenciamiento comercial.
* **Recomendación técnica:**
  1. **Escenario con presupuesto y cumplimiento estricto (recomendado):** Migrar a **MongoDB Enterprise** o **MongoDB Atlas** y habilitar la auditoría nativa (`auditLog`) filtrando eventos de autorización (`grantRolesToUser`, `revokeRolesFromUser`, `createUser`, `dropUser`, `updateUser`), enviando los registros en tiempo real a un servidor **SIEM** externo de solo escritura (*append-only*).
  2. **Escenario con restricción presupuestaria (permanencia en Community):** Restringir el rol `userAdmin` / `userAdminAnyDatabase` exclusivamente a una cuenta de emergencia controlada bajo procedimiento formal, configurar `systemLog.path` con `logAppend: true` en `mongod.cfg`, y automatizar un proceso externo cada 5 a 15 minutos que tome instantáneas de `db.getUsers()`, compare diferencias y emita alertas inmediatas ante cualquier cambio de rol.

---

## 20. Preguntas de reflexión

### 1. ¿Por qué el perfilador no debe presentarse como un mecanismo de auditoría de seguridad?
Porque fue diseñado como una herramienta de diagnóstico de rendimiento, no de seguridad forense. Cualquier usuario con privilegios administrativos puede desactivarlo o vaciar `system.profile` (`db.system.profile.drop()`) sin dejar rastro de los datos eliminados; no registra eventos críticos de seguridad como cambios de privilegios o creación de usuarios; se desactiva automáticamente tras un reinicio si no está fijado en `mongod.cfg`; y sobrescribe registros antiguos al alcanzar su límite circular de 1 MB.

### 2. ¿Por qué el perfilador sí aporta trazabilidad aunque no sea auditoría?
Porque mientras permanece activo captura los metadatos esenciales de cada operación sobre los datos: identidad autenticada (`user`), origen de red (`client`), aplicación cliente (`appName`), marca de tiempo (`ts`), colección afectada (`ns`) y comando exacto (`command`). Esto permite reconstruir la secuencia de acciones ejecutadas por una aplicación o usuario y atribuir modificaciones específicas durante una investigación operativa.

### 3. ¿Qué riesgo introduce el nivel 2 al registrar filtros de consultas que pueden contener datos personales?
Al registrar el contenido completo de cada consulta (`command.filter`), los valores utilizados para buscar registros —como nombres completos, RFC, números telefónicos, correos electrónicos o identificadores sensibles— quedan almacenados en texto claro dentro de `system.profile` y en cualquier exportación posterior. Esto amplía la superficie de exposición de datos personales (PII), permitiendo que personal técnico con acceso a las bitácoras visualice información confidencial sin consultar las colecciones productivas.

### 4. ¿Qué diferencia hay entre detectar un cambio y atribuirlo a alguien?
* **Detectar un cambio** significa comprobar que el estado de un recurso o configuración fue alterado respecto a un punto de referencia anterior (por ejemplo, observar entre dos instantáneas que `app_ventas` recibió el rol `dbAdmin`).
* **Atribuirlo a alguien** implica establecer responsabilidad individual (rendición de cuentas), vinculando de forma verificable la ejecución del cambio con una identidad autenticada, una dirección de origen y una marca de tiempo exacta en el instante en que se produjo la acción.

### 5. ¿Por qué reconocer una limitación técnica es parte del trabajo profesional del DBA?
Porque asumir o presentar capacidades que el motor de base de datos no posee genera una falsa sensación de seguridad y expone a la organización a fallos de cumplimiento legal o forense. Documentar con precisión los límites de la herramienta permite al DBA diseñar controles compensatorios adecuados, establecer procedimientos operativos realistas y justificar técnicamente ante Dirección la inversión en licencias o controles adicionales.