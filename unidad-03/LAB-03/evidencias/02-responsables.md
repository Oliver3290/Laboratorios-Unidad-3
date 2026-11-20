# 02 - Matriz de Propietarios, Custodios y Usuarios

## Matriz Ampliada de Gobierno de Datos

| Conjunto de datos | Propietario | Custodio | Usuarios autorizados | Quién aprueba accesos | Quién aprueba correcciones |
|---|---|---|---|---|---|
| **`comercial.public.clientes` (PostgreSQL)** | Gerencia Comercial | DBA | Aplicación de ventas (`app_ventas`), personal de soporte y analistas autorizados (solo lectura) | Gerencia Comercial | Gerencia Comercial (con soporte documental del cliente) |
| **`auditoria.cambios_clientes` (PostgreSQL)** | Auditoría Interna / Seguridad de la Información | DBA (privilegios restringidos: inserción vía disparador y lectura; sin `UPDATE` ni `DELETE`) | Auditoría Interna, Oficial de Seguridad y DBA (solo lectura) | Auditoría Interna / Seguridad de la Información | No aplica (registro inmutable de solo adición; no se corrige para preservar su validez probatoria) |
| **Bitácora de PostgreSQL (`pg_log` y vista `dba.bitacora`)** | Seguridad de la Información / Auditoría Interna | DBA / Administrador de Sistemas | DBA y Auditoría Interna (solo lectura) | Seguridad de la Información / Gerencia de TI | No aplica (registro inmutable del sistema; cualquier alteración invalida la evidencia) |
| **`comercial.clientes` (MongoDB)** | Gerencia Comercial | DBA | Aplicación de ventas (`app_ventas` con rol `readWrite`) y soporte autorizado | Gerencia Comercial | Gerencia Comercial |
| **`comercial.system.profile` (MongoDB)** | Seguridad de la Información / Auditoría Interna | DBA | DBA y Auditoría Interna (solo lectura) | Seguridad de la Información / Gerencia de TI | No aplica (colección encapsulada de trazabilidad de solo adición; no debe modificarse manualmente) |

---

## Respuestas a las Preguntas

### 1. ¿Por qué el propietario de `auditoria.cambios_clientes` no debería ser el mismo que opera `clientes`?
Por el principio de **segregación de funciones** e **independencia de la evidencia**. Quien opera o posee la tabla productiva `clientes` (Gerencia Comercial o los usuarios operativos de la aplicación) tiene interés directo sobre los registros comerciales. Si además fuera propietario de `auditoria.cambios_clientes`, tendría autoridad para decidir qué cambios se registran, quién consulta la bitácora de auditoría o cuándo depurarla, lo que permitiría ocultar modificaciones indebidas o errores operativos. Asignar la propiedad a un ente independiente (Auditoría Interna o Seguridad de la Información) garantiza que la pista de auditoría sea imparcial, íntegra y confiable durante una revisión.

### 2. ¿Quién debería poder leer las bitácoras y la vista `dba.bitacora`? Relaciónalo con lo observado en el LAB-01 (secretos en la bitácora).
* **Quién debería leerlas:** Exclusivamente el **DBA** (como custodio para diagnóstico técnico y exportación de evidencias) y el personal de **Auditoría Interna / Seguridad de la Información**, aplicando el principio de mínimo privilegio. Los usuarios de aplicación (`app_ventas`), desarrolladores y usuarios finales nunca deben tener permisos `SELECT` sobre `dba.bitacora` ni acceso de lectura a los archivos `.log` del servidor.
* **Relación con el LAB-01 (secretos en la bitácora):** En el LAB-01 se comprobó que al registrar sentencias completas (`log_statement = 'mod'` o `'ddl'`), comandos administrativos como `CREATE ROLE ... WITH PASSWORD '...'` o `ALTER USER ... WITH PASSWORD '...'` quedan escritos **en texto claro** tanto en el archivo de bitácora como en la salida de la vista `dba.bitacora` (al igual que datos personales enviados en sentencias `INSERT` o `UPDATE`). Si un usuario ordinario o una aplicación comprometida pudiera consultar `dba.bitacora`, obtendría credenciales de otros roles y escalaría privilegios en todo el servidor.

### 3. ¿Qué ocurre con la responsabilidad sobre un dato cuando nadie la tiene asignada? Relaciónalo con el problema inicial de la unidad.
* **Qué ocurre:** Se genera un vacío de gobernanza en el que nadie define las reglas de validez del dato, nadie autoriza ni valida correcciones cuando surgen inconsistencias, nadie controla quién puede consultarlo ni cuánto tiempo debe conservarse, y ante un incidente nadie rinde cuentas. Como consecuencia, los errores de calidad se acumulan o el DBA se ve obligado a tomar decisiones de negocio que exceden su rol técnico.
* **Relación con el problema inicial de la unidad:** Al inicio de la Unidad III se planteó que los mecanismos técnicos (bitácoras, disparadores y perfilador) responden únicamente *qué* ocurrió, pero por sí solos no pueden responder *"¿De quién es este dato? ¿Quién decide si el RFC de un cliente puede corregirse?"* ni *"¿Qué regla se incumplió?"*. Sin un propietario formalmente asignado, la evidencia técnica queda incompleta: se puede detectar que un RFC tiene 12 caracteres o que fue modificado, pero no existe autoridad responsable que determine cuál es el valor correcto ni si la operación fue legítima o indebida.