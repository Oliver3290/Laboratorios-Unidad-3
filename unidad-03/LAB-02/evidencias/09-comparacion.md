# 09 - Comparación de Escenarios de Trazabilidad

## Matriz Comparativa

| Evento auditable | PostgreSQL (bitácora + disparador) | MongoDB Community (perfilador + bitácora) | MongoDB Enterprise / Atlas (auditoría nativa) |
|---|---|---|---|
| **Acceso exitoso** | Sí (observado) | Sí (observado) | Sí (Documentado, no practicado) |
| **Acceso fallido** | Sí (observado) | Sí (observado) | Sí (Documentado, no practicado) |
| **Cambio de privilegios** | Sí (observado) | Parcial (no se registra nativamente en bitácora ni perfilador; solo se detecta mediante control compensatorio de instantáneas periódicas, sin autor ni hora exacta) | Sí (Documentado, no practicado — registra eventos como `grantRolesToUser` y `revokeRolesFromUser` con autor y marca de tiempo) |
| **Cambio de estructura** | Sí (observado) | Parcial (comandos como `create`, `drop` o `createIndexes` se capturan solo si el perfilador está activo en nivel 2, sin persistencia tras reinicios por defecto) | Sí (Documentado, no practicado — registra eventos DDL nativos como `createCollection`, `dropCollection` e índices) |
| **Modificación de datos** | Sí (observado) | Sí (observado) | Parcial (Documentado, no practicado — registra escrituras solo si se habilita `auditAuthorizationSuccess: true`) |
| **Valor anterior del dato** | Sí (observado) | No | No (Documentado, no practicado — registra el comando ejecutado, no la imagen previa del documento; requiere *Change Streams* con *pre-images*) |
| **Lectura de datos sensibles** | Parcial (con `log_statement = 'mod'` o `'ddl'` no se registran los `SELECT`; requiere `log_statement = 'all'` con alto costo de rendimiento o extensiones como `pgAudit`) | Parcial (solo se registra con el perfilador en nivel 2, lo que degrada el rendimiento y satura rápido el límite circular de 1 MB; al filtrar escrituras se pierde) | Parcial (Documentado, no practicado — registra consultas `find` únicamente si se activa `auditAuthorizationSuccess: true` y se filtra por colección o rol) |
| **Cambio de configuración del registro** | Parcial (cambios vía SQL como `ALTER SYSTEM` o `SET` se registran según el nivel de bitácora, pero editar `postgresql.conf` directamente en disco no deja el usuario responsable) | Sí (observado) | Sí (Documentado, no practicado — registra comandos administrativos como `setParameter` y cambios en la configuración de auditoría) |

## Síntesis de Hallazgos

* **PostgreSQL (Bitácora + Disparador):** Ofrece la mayor granularidad a nivel de datos gracias a los disparadores (`TRIGGER`), siendo el único escenario practicado capaz de conservar el **valor anterior del dato** (`OLD`) ante actualizaciones o eliminaciones, además de auditar privilegios (`GRANT`/`REVOKE`) y estructura (`DDL`) de forma nativa.
* **MongoDB Community (Perfilador + Bitácora):** Permite rastrear operaciones CRUD, accesos y cambios en la configuración del perfilador (`Profiler settings changed`), pero carece de auditoría nativa sobre cambios de roles/privilegios y no guarda el estado previo de los documentos modificados. Además, su almacenamiento es volátil o circular si no se exporta periódicamente.
* **MongoDB Enterprise / Atlas (Auditoría Nativa):** Cubre la principal brecha de seguridad de la edición Community al auditar de forma nativa y persistente los cambios de privilegios, gestión de usuarios, operaciones DDL y eventos administrativos sin depender de instantáneas manuales.

