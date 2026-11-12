# 10 - Respuesta Ejecutiva a Dirección

Con base exclusivamente en la evidencia recolectada mediante el perfilador (`system.profile`), la bitácora del servidor (`getLog`) y el control compensatorio implementado en MongoDB Community Edition, se responden las consultas sobre la trazabilidad de incidentes:

## 1. ¿Quién cambió el RFC de María García en la Actividad 2? ¿Y en la Actividad 3?

* **En la Actividad 2:** **No hay evidencia con esta edición.**
  * **Motivo técnico:** En MongoDB Community Edition el perfilador de base de datos se encuentra desactivado por defecto (`nivel 0`) y la bitácora estándar del servidor (`mongod`) no registra operaciones ordinarias de lectura o escritura que se ejecuten por debajo del umbral de consultas lentas (`slowms = 100 ms`). Al no existir auditoría nativa de operaciones CRUD en esta edición, la modificación pasó sin dejar rastro.
* **En la Actividad 3:** El usuario **`app_ventas@comercial`** (conectado desde `127.0.0.1`).
  * **Sustento en evidencia:** Al activar el perfilador en nivel 2, quedó registrado en `comercial.system.profile` el evento `op: "update"` sobre el documento `{ _id: 3 }` (María García) asignando `rfc: "GAMA780912XYZ"`, atribuido explícitamente al campo `user: "app_ventas@comercial"`.

## 2. ¿Cuándo y desde qué aplicación?

* **Para el cambio de la Actividad 2:** **No hay evidencia con esta edición.**
  * **Motivo técnico:** Al estar el perfilador apagado (`nivel 0`) y no registrarse operaciones de escritura rápidas en `mongod`, no existe marca de tiempo ni metadatos de conexión asociados a esa operación.
* **Para el cambio de la Actividad 3:**
  * **Cuándo:** En la marca de tiempo exacta (`ts` en formato `ISODate` UTC) registrada dentro del documento `op: "update"` de `comercial.system.profile` durante la ejecución de la Actividad 3 *(sustituir por el valor `ts` exacto de tu captura `03-perfilador-nivel2.png`, por ejemplo: `2026-10-25T22:52:55.120Z`)*.
  * **Desde qué aplicación:** Desde la aplicación identificada como **`app-ventas-web`**, dato capturado tanto en el campo `appName` del perfilador como en el atributo `attr.doc.application.name` al momento de la autenticación en la bitácora de `mongod`.

## 3. ¿Qué valor tenía antes?

* **No hay evidencia con esta edición.**
  * **Motivo técnico:** El perfilador de MongoDB (`system.profile`) registra únicamente la estructura del comando ejecutado por el cliente (`command.u: { $set: { rfc: "GAMA780912XYZ" } }`), es decir, el filtro de búsqueda y el nuevo valor asignado. MongoDB Community no almacena imágenes previas de los documentos (*pre-images*) en sus bitácoras ni dispone de disparadores nativos (*triggers*) a nivel de base de datos que respalden automáticamente el estado anterior del registro antes de sobrescribirlo.

## 4. ¿Cambió alguien los privilegios de `app_ventas`?

* **Respecto a quién ejecutó el cambio y cuándo ocurrió exactamente (evidencia nativa):** **No hay evidencia con esta edición.**
  * **Motivo técnico:** MongoDB Community Edition no audita ni registra comandos administrativos de gestión de usuarios o roles (`grantRolesToUser`, `revokeRolesFromUser`) en `system.profile` (incluso configurado en nivel 2) ni en la bitácora interna de `mongod` (`getLog`). La auditoría nativa de autorización y cambios de privilegios es una característica exclusiva de MongoDB Enterprise / Atlas.
* **Respecto a la detección del cambio mediante control compensatorio (Actividad 7):** Sí se constató que los privilegios de `app_ventas` fueron alterados temporalmente (se le añadió el rol `dbAdmin` sobre la base `comercial` además de su rol base `readWrite`, y posteriormente le fue revocado). Esto se comprobó al comparar dos registros consecutivos de la colección `auditoria.instantaneas_privilegios`, aunque dicho mecanismo solo permite confirmar que la alteración ocurrió en el intervalo entre ambas instantáneas, sin identificar al usuario responsable.