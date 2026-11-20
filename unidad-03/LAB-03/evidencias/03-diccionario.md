# 03 - Diccionario de Datos Operativo (Complemento de Gobierno)

## Atributos de Gobierno y Control no Almacenados en el Catálogo del Motor

| Columna | Clasificación (Unidad II) | Finalidad | Control aplicado | ¿Cambios auditados? | Regla de calidad |
|---|---|---|---|---|---|
| **`id`** | Identificador interno | Llave primaria subrogada para integridad referencial | Generación automática por secuencia (`PRIMARY KEY`), solo lectura para aplicación | Sí (`log_statement = 'mod'` en `DELETE`) | Único, no nulo (`NOT NULL`) y entero positivo |
| **`nombre`** | Dato personal (identificador directo) | Identificación del titular en contratos, pedidos y atención | Control de acceso basado en roles (`GRANT` / `REVOKE`) | Sí (`log_statement = 'mod'`) | No nulo (`NOT NULL`), longitud mínima válida sin caracteres de control |
| **`correo`** | Dato personal (contacto) | Envío de notificaciones, comprobantes y comunicación con el cliente | Control de acceso por rol y validación en aplicación | Sí (`log_statement = 'mod'`) | Formato válido (`^[^@\s]+@[^@\s]+\.[^@\s]+$`) y unicidad normalizada (`lower(correo)`) |
| **`telefono`** | Dato personal (contacto) | Contacto telefónico directo para seguimiento comercial y entregas | Vista enmascarada parcial para soporte (U2) y control de acceso por rol | Sí (`log_statement = 'mod'`) | Longitud numérica estándar (10 dígitos nacionales) |
| **`rfc`** | Dato personal (fiscal / sensible) | Emisión de comprobantes fiscales digitales (facturación) | Vista enmascarada para soporte (U2) y privilegios restringidos | Sí, disparador en `auditoria.cambios_clientes` (LAB-01 Parte B) + `log_statement = 'mod'` | Formato válido SAT (`^[A-ZÑ&]{3,4}[0-9]{6}[A-Z0-9]{3}$`, 12 o 13 caracteres) |
| **`edad`** | Dato personal (demográfico) | Analítica agregada y segmentación demográfica | Acceso restringido a consultas agregadas para analítica | Sí (`log_statement = 'mod'`) | Rango lógico válido entre `18` y `120` años (`edad BETWEEN 18 AND 120`) |
| **`ciudad`** | Dato personal (indirecto / ubicación) | Segmentación geográfica y planeación logística de envíos | Control de acceso estándar por rol operativo | Sí (`log_statement = 'mod'`) | Catálogo estandarizado de localidades (evitar variantes sin acento o abreviaturas) |
| **`codigo_postal`** | Dato personal (indirecto / ubicación) | Validación de domicilio fiscal y cálculo de cobertura/tarifas de envío | Control de acceso estándar por rol operativo | Sí (`log_statement = 'mod'`) | Cadena numérica exacta de 5 dígitos (`^[0-9]{5}$`) |
| **`fecha_alta`** | Metadato operativo interno | Control de antigüedad del cliente y trazabilidad de incorporación | Asignación automática por defecto (`DEFAULT now()` / `CURRENT_DATE`), sin edición manual | Sí (`log_statement = 'mod'`) | Fecha válida no nula y no posterior a la fecha actual del servidor |
| **`segmento`** | Dato interno de negocio | Clasificación comercial para descuentos, crédito y atención | Modificación restringida a roles comerciales autorizados | Sí (`log_statement = 'mod'`) | Valores pertenecientes al catálogo comercial aprobado |

---

## Respuestas a las Preguntas

### 1. ¿Qué ventaja tiene guardar el significado en `COMMENT` en lugar de solo en un documento aparte?
* **Sincronización y vigencia:** Al residir dentro de los metadatos del propio SGBD (`pg_description`), la descripción acompaña directamente a cada tabla y columna. Cuando un DBA o desarrollador modifica la estructura (por ejemplo, agrega o altera una columna), el comentario está inmediatamente visible en el mismo entorno, reduciendo el riesgo de que la documentación quede desactualizada respecto al esquema real.
* **Disponibilidad y portabilidad:** El significado de negocio se incluye automáticamente en los respaldos lógicos (`pg_dump`), puede consultarse de forma programática mediante vistas estándar (`information_schema.columns` junto con `col_description()`) o herramientas visuales como pgAdmin, y facilita exportar diccionarios actualizados en formato CSV sin depender de archivos externos dispersos.

### 2. ¿Quedaron registrados los `COMMENT` en la bitácora? ¿Con qué nivel de `log_statement`?
* **Sí, quedaron registrados en la bitácora de PostgreSQL.**
* **Nivel de `log_statement`:** En PostgreSQL, la instrucción `COMMENT ON ...` se clasifica internamente como una sentencia de definición de datos (**DDL**). Por ello, comienza a registrarse a partir de **`log_statement = 'ddl'`** y, en consecuencia, también queda registrada con el nivel configurado en el laboratorio (**`log_statement = 'mod'`**, que incluye tanto `ddl` como modificaciones de datos) y con **`log_statement = 'all'`**. Esto se comprueba consultando la vista `dba.bitacora` filtrando por `COMMENT ON`.

### 3. ¿Qué información del diccionario debe mantenerse fuera del motor? ¿Por qué?
* **Información que debe mantenerse fuera del motor:** Los detalles internos de implementación de controles de seguridad (por ejemplo, qué columnas específicas cuentan con disparadores silenciosos de auditoría, reglas exactas de enmascaramiento o cifrado, criterios y umbrales de detección de anomalías, matriz detallada de roles/privilegios operativos y procedimientos de respuesta ante incidentes), así como las políticas formales aprobadas por los propietarios.
* **Motivo:** En PostgreSQL, los metadatos y comentarios almacenados en los catálogos del sistema (`pg_class`, `pg_attribute`, `pg_description`, `information_schema`) son visibles para cualquier usuario autenticado que tenga permiso de conexión a la base de datos. Si se documentan allí los mecanismos de vigilancia o las brechas conocidas, un usuario malicioso o atacante con acceso básico podría inspeccionar el catálogo para identificar qué tablas no tienen disparadores, qué campos se auditan y cómo evadir los controles.