# 04 - Catálogo Mínimo de Datos

## Inventario Integrado de Activos de Datos (PostgreSQL y MongoDB)

| ID | Conjunto de datos | Motor | Ubicación | Propietario | Custodio | Clasificación | Contiene datos personales | Finalidad | Conservación | Diccionario |
|---|---|---|---|---|---|---|---|---|---|---|
| **CAT-01** | Clientes | PostgreSQL 18 | `127.0.0.1:5432 / comercial / public.clientes` | Gerencia Comercial | DBA | Confidencial | Sí | Operación comercial, facturación y contacto de clientes | Activo durante la relación comercial + 5 años por obligación fiscal (`POL-03`) | `diccionario-clientes.csv` |
| **CAT-02** | Auditoría de clientes | PostgreSQL 18 | `127.0.0.1:5432 / comercial / auditoria.cambios_clientes` | Auditoría Interna / Seguridad de la Información | DBA (solo adición vía disparador y lectura) | Confidencial / Restringido | Sí (valores previos y nuevos de `rfc`) | Trazabilidad e investigación forense de modificaciones sobre datos sensibles | Mínimo 12 meses en línea + 3 años en archivo histórico inmutable (`POL-03`) | Metadatos de sistema (`information_schema` / DDL LAB-01) |
| **CAT-03** | Registro de cambios | PostgreSQL 18 | `127.0.0.1:5432 / comercial / gobierno.solicitudes_cambio` | Gerencia de TI / Comité de Cambios | DBA | Interno / Uso restringido | No | Control formal y conciliación de cambios autorizados en producción | Mínimo 12 meses para auditorías trimestrales y anuales (`POL-03`, `POL-06`) | Metadatos de sistema (`information_schema` / `sql/04-registro-cambios.sql`) |
| **CAT-04** | Clientes (tienda) | MongoDB 9.0 | `127.0.0.1:27017 / comercial / clientes` | Gerencia Comercial | DBA | Confidencial | Sí | Operación de tienda en línea, perfil web de clientes y seguimiento de pedidos | Activo durante la relación comercial + periodo de retención fiscal/comercial | Esquema documental en expediente de aplicación (`LAB-02`) |
| **CAT-05** | Perfilado | MongoDB 9.0 | `127.0.0.1:27017 / comercial / system.profile` | Seguridad de la Información / Auditoría Interna | DBA | Confidencial / Restringido | Sí (filtros `command.q` y actualizaciones `command.u`) | Diagnóstico de rendimiento y trazabilidad operativa de consultas y escrituras | Volátil en motor (1 MB circular); exportación periódica JSON + SHA-256 conservada 90 días (`POL-03`) | Estructura estándar `system.profile` (`LAB-02/evidencias/system-profile.json`) |

*(Nota de inventario: además de las tablas base anteriores, la vista `127.0.0.1:5432 / comercial / dba.bitacora` constituye un activo de información confidencial bajo propiedad de Seguridad de la Información y custodia del DBA, ya que expone registros operativos y sentencias ejecutadas en el servidor).*

---

## Respuestas a las Preguntas

### 1. ¿Por qué CAT-02 y CAT-05 contienen datos personales aunque su propósito sea la auditoría?
Porque para cumplir su función de trazabilidad e investigación forense, los mecanismos de auditoría y perfilado capturan el **contenido literal de las operaciones** ejecutadas sobre las tablas o colecciones productivas:
* En **CAT-02 (`auditoria.cambios_clientes`)**, el disparador registra tanto el valor anterior (`OLD`) como el nuevo (`NEW`) de atributos sensibles modificados (como el `rfc` del cliente), almacenando directamente datos fiscales identificables.
* En **CAT-05 (`comercial.system.profile`)**, cuando el perfilador opera en nivel 2 o captura escrituras, guarda los predicados de búsqueda (`command.q`) y documentos de actualización (`command.u`), los cuales contienen nombres, correos electrónicos, teléfonos o RFC utilizados para localizar o actualizar clientes.

Por esta razón, los repositorios de auditoría heredan el nivel de clasificación **Confidencial / Restringido** de los datos que supervisan y deben protegerse con controles de acceso estrictos y plazos de retención definidos.

### 2. ¿Qué pasa si CAT-01 y CAT-04 tienen propietarios distintos y el RFC de un cliente difiere entre ambos motores?
Se produce un **conflicto de autoridad y pérdida de integridad referencial de negocio**:
* **Ausencia de fuente única de verdad (*Single Source of Truth*):** Al existir dos propietarios distintos, ninguno tiene autoridad única para decidir cuál de los dos valores del RFC es el correcto, bloqueando la resolución de inconsistencias.
* **Impacto operativo y fiscal:** El sistema de facturación (PostgreSQL, CAT-01) y la tienda en línea (MongoDB, CAT-04) operarán con datos fiscales contradictorios, provocando rechazo de comprobantes fiscales (CFDI), errores en validación de identidad o duplicidad de cuentas.
* **Dilución de responsabilidad:** Ante una discrepancia o modificación indebida, resulta ambiguo determinar qué área debe validar la documentación del cliente y aprobar la sincronización. Por ello, ambas colecciones/tablas deben compartir el mismo propietario de dominio (**Gerencia Comercial**) y contar con una regla clara sobre cuál motor actúa como maestro.

### 3. ¿Qué información del catálogo cambia con más frecuencia y quién debe actualizarla?
* **Qué información cambia con más frecuencia:**
  1. **Metadatos técnicos y volumetría:** El número estimado de filas (`reltuples`), el tamaño en disco (`tamano`) y la incorporación de nuevas tablas, vistas o colecciones derivadas de despliegues en producción.
  2. **Metadatos operativos de acceso:** La lista de aplicaciones o roles autorizados conforme se incorporan o dan de baja servicios.
* **Quién debe actualizarla:**
  * El **DBA (Custodio)** debe actualizar los metadatos técnicos (ubicación, tamaño, nuevas estructuras y enlaces a diccionarios) cada vez que se ejecute un cambio aprobado en producción (vinculado al control de cambios `CAT-03`).
  * El **Propietario del dato** (Gerencia Comercial o Seguridad de la Información, según el activo) debe actualizar o aprobar formalmente cualquier cambio en la clasificación, finalidad, reglas de retención o autorización de nuevos consumidores.