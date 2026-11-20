# 01 - Calidad de Datos desde la Operación

## Registro de Hallazgos

| # | Hallazgo | Registros (`id`) | Regla de calidad | ¿Quién decide la corrección? | Acción propuesta |
|---|---|---|---|---|---|
| **C1** | Posible cliente duplicado | `1, 7` | Unicidad del correo electrónico normalizado (`lower(correo)`) | Gerencia Comercial (Propietario del dato) | Validar con el área comercial y el cliente si ambos registros corresponden a la misma persona para consolidarlos y dar de baja el duplicado mediante solicitud autorizada. |
| **C2** | RFC incompleto (12 caracteres en lugar de 13) | `7` | Formato válido de RFC (`^[A-ZÑ&]{3,4}[0-9]{6}[A-Z0-9]{3}$`) | Gerencia Comercial (Propietario del dato, con soporte documental) | Solicitar la Constancia de Situación Fiscal a la cliente Ana López para obtener la homoclave completa de 3 caracteres y autorizar la actualización. |
| **C3** | Correo electrónico con formato no válido (`sin-correo`) | `8` | Formato estructural de correo electrónico (`^[^@\s]+@[^@\s]+\.[^@\s]+$`) | Gerencia Comercial (Propietario del dato) | Contactar al cliente Jorge Díaz por vía telefónica o en sucursal para recabar una dirección de correo válida y actualizar el registro. |
| **C4** | Edad fuera de rango lógico (`-3`) | `8` | Rango válido de edad para clientes (`18 <= edad <= 120`) | Gerencia Comercial (Propietario del dato) | Verificar la identificación oficial o fecha de nacimiento del cliente Jorge Díaz y corregir el valor negativo capturado por error. |
| **C5** | RFC ausente (`NULL`) | `8` | Completitud de atributos fiscales obligatorios (`rfc IS NOT NULL`) | Gerencia Comercial (Propietario del dato) | Requerir el RFC del cliente antes de habilitar operaciones de facturación o crédito. |

## Respuestas a las Preguntas

### 1. ¿Por qué el DBA no debe corregir por su cuenta el RFC del registro 7?
Porque el DBA actúa como **custodio del dato** (*data custodian*), no como **propietario del dato** (*data owner*). La responsabilidad del DBA es operar, resguardar y proteger la integridad técnica de la base de datos, pero no tiene autoridad ni contexto de negocio para decidir cuál es el valor real de un atributo comercial ni para suponer el carácter faltante de una homoclave oficial. La decisión de modificar un dato pertenece exclusivamente a la **Gerencia Comercial**, quien debe validar la documentación del cliente y emitir una autorización formal antes de que el DBA aplique el cambio.

### 2. ¿Qué restricción (`CHECK`, `UNIQUE`) habría evitado cada hallazgo? ¿Quién debería aprobar agregarla?
* **C1 (Correo duplicado insensible a mayúsculas):** Un índice único funcional sobre el correo en minúsculas:
  `CREATE UNIQUE INDEX idx_clientes_correo_unico ON clientes (lower(correo));` *(una restricción `UNIQUE(correo)` simple no evitaría diferencias entre mayúsculas y minúsculas)*.
* **C2 (RFC incompleto o con formato inválido):** Una restricción de verificación de patrón:
  `ALTER TABLE clientes ADD CONSTRAINT chk_clientes_rfc CHECK (rfc ~ '^[A-ZÑ&]{3,4}[0-9]{6}[A-Z0-9]{3}$');`
* **C3 (Correo con formato inválido):** Una restricción de verificación de formato:
  `ALTER TABLE clientes ADD CONSTRAINT chk_clientes_correo CHECK (correo ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$');`
* **C4 (Edad fuera de rango):** Una restricción de intervalo numérico:
  `ALTER TABLE clientes ADD CONSTRAINT chk_clientes_edad CHECK (edad BETWEEN 18 AND 120);`
* **C5 (RFC ausente):** Una restricción de obligatoriedad `NOT NULL` en la columna `rfc`, en caso de que la regla de negocio exija RFC para todo alta de cliente.

**¿Quién debería aprobar agregarla?** La **Gerencia Comercial** (como propietario del dato que define las reglas de negocio sobre `clientes`), en coordinación con el responsable de la **aplicación de ventas**, para garantizar que los formularios de captura validen esos mismos criterios antes de enviar los datos y evitar rechazos inesperados en la operación diaria.

### 3. Si el DBA corrige un dato, ¿qué mecanismo del LAB-01 (Parte B) dejará evidencia del cambio?
El **disparador de auditoría del dato** (`TRIGGER` sobre la tabla `clientes`) implementado en la Parte B del LAB-01, el cual captura automáticamente cada operación `UPDATE` y registra en la tabla de auditoría el usuario que ejecutó la modificación, la fecha y hora exacta, el identificador del registro afectado (`id`), el **valor anterior** (`OLD.rfc`) y el **valor nuevo** (`NEW.rfc`), complementado a nivel de servidor por el registro de sentencias de modificación (`log_statement = 'mod'`).