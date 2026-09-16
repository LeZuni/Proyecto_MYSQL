# Proyecto de Base de Datos para un E-commerce

## Descripción

Este proyecto diseña e implementa el núcleo de una base de datos MySQL 8.0 para una tienda en línea, cubriendo el catálogo de productos, categorías, proveedores, clientes y el ciclo de vida completo de las ventas (carrito, venta, detalle, devoluciones). Además de las 6 entidades principales del enunciado, se agregaron ~34 tablas de soporte (promociones, carritos, reseñas, auditoría, logs, reportes cacheados, respaldos, etc.) necesarias para implementar de forma realista 20 consultas analíticas, 20 funciones, 20 reglas de seguridad, 20 triggers, 20 eventos programados y 20 procedimientos almacenados solicitados.

## Integrantes

- Lesli Zuñiga

## Motor de base de datos

MySQL 8.0 (probado contra `mysql:8.0` vía Docker). El proyecto usa características de MySQL 8 como funciones de ventana (`NTILE`, `LAG`, `RANK`), CTEs, `CHECK` constraints, columnas generadas (`GENERATED ALWAYS AS ... STORED`), roles (`CREATE ROLE`) y el Event Scheduler.

## Instrucciones de ejecución

Ejecutar los scripts **en este orden exacto** contra un servidor MySQL 8.0 vacío (cada script depende de que el anterior ya haya corrido):

```bash
mysql -h 127.0.0.1 -P 3306 -u root -p < 01_Esquema_y_Datos.sql
mysql -h 127.0.0.1 -P 3306 -u root -p ecommerce_avanzado < 02_Consultas_Avanzadas.sql
mysql -h 127.0.0.1 -P 3306 -u root -p ecommerce_avanzado < 03_Funciones.sql
mysql -h 127.0.0.1 -P 3306 -u root -p ecommerce_avanzado < 04_Seguridad.sql
mysql -h 127.0.0.1 -P 3306 -u root -p ecommerce_avanzado < 05_Triggers.sql
mysql -h 127.0.0.1 -P 3306 -u root -p ecommerce_avanzado < 06_Eventos.sql
mysql -h 127.0.0.1 -P 3306 -u root -p ecommerce_avanzado < 07_Procedimientos_Almacenados.sql
mysql -h 127.0.0.1 -P 3306 -u root -p ecommerce_avanzado < 04_Seguridad.sql   # segunda pasada: activa los permisos diferidos (ver nota abajo)
```

**Importante**: `04_Seguridad.sql` otorga permisos sobre objetos que se crean después de él en la secuencia (la tabla `log_cambios_precio` de `05_Triggers.sql` y los procedimientos `sp_GenerarReporteMensual`/`sp_DashboardAdmin`/`sp_AplicarDescuentoCategoria` de `07_Procedimientos_Almacenados.sql`). El script detecta esto automáticamente y emite un `AVISO` sin fallar; simplemente **vuelve a ejecutar `04_Seguridad.sql` una segunda vez al final**, después de correr `07`, para que esos permisos queden efectivos (el script es idempotente, seguro de correr varias veces). Se verificó que este flujo funciona correctamente de extremo a extremo.

`01_Esquema_y_Datos.sql` crea la base de datos `ecommerce_avanzado` (con `DROP DATABASE IF EXISTS` al inicio, para poder re-ejecutar el proyecto completo desde cero) y la puebla con datos de ejemplo generados mediante un procedimiento temporal (evita cientos de `INSERT` manuales), suficientes para que las consultas analíticas de `02` devuelvan resultados no triviales (múltiples meses de ventas, clientes VIP, productos con bajo stock, carritos abandonados, reseñas, intentos de login fallidos, etc.).

Si se usa un contenedor Docker de MySQL, por ejemplo:

```bash
docker exec -i <nombre_contenedor> mysql -u root -p<password> < 01_Esquema_y_Datos.sql
docker exec -i <nombre_contenedor> mysql -u root -p<password> ecommerce_avanzado < 02_Consultas_Avanzadas.sql
# ... y así sucesivamente para 03 a 07
```

## Estructura de archivos

| Archivo | Contenido |
|---|---|
| `01_Esquema_y_Datos.sql` | Las 6 entidades base + ~33 tablas de soporte (todas las `CREATE TABLE`, salvo las 2 excepciones abajo), datos de ejemplo. |
| `02_Consultas_Avanzadas.sql` | 20 consultas de análisis y reporteo de negocio. |
| `03_Funciones.sql` | 20 funciones (`CREATE FUNCTION`) de lógica de negocio reutilizable. |
| `04_Seguridad.sql` | Roles, usuarios, `GRANT`/`REVOKE`, vistas de seguridad, política de contraseñas. |
| `05_Triggers.sql` | Tabla `log_cambios_precio` + 20 triggers de integridad y automatización. |
| `06_Eventos.sql` | Tabla `reporte_ventas_semanales` + activación del Event Scheduler + 20 eventos programados. |
| `07_Procedimientos_Almacenados.sql` | 20 procedimientos almacenados (+3 de soporte necesarios por las simplificaciones de seguridad, documentados abajo). |

## Decisiones de diseño y desviaciones del enunciado

- **`contrasena_hash` en vez de `contraseña`**: se evitó el carácter `ñ` en el nombre de la columna por portabilidad entre herramientas/collations. Almacena un hash (`SHA2`), nunca texto plano.
- **Esquema extendido**: para que las 100 funcionalidades solicitadas fueran implementables de verdad (no solo declarativamente), se agregaron columnas extra a las tablas base (ej. `productos.peso_kg`, `productos.stock_minimo`, `clientes.total_gastado`, `clientes.nivel_lealtad`, `ventas.id_sucursal`) y tablas de soporte nuevas (promociones, carritos, reseñas, logs de auditoría, reportes cacheados, respaldos, etc.).

## Simplificaciones académicas necesarias

Algunos requisitos del enunciado no son 100% viables en MySQL puro; se documentan aquí las aproximaciones usadas:

- **Auditoría de logins fallidos**: `log_intentos_login` audita el login de **clientes de la tienda** (validado por el procedimiento `sp_LoginCliente` contra `contrasena_hash`), no las conexiones reales al servidor MySQL — eso requeriría el plugin `audit_log` de MySQL Enterprise, fuera de alcance académico.
- **Log de cambios de permisos**: los triggers de MySQL solo reaccionan a sentencias DML (`INSERT`/`UPDATE`/`DELETE`), no a DCL (`GRANT`/`REVOKE`). Se implementa en cambio como los procedimientos `sp_OtorgarPermiso`/`sp_RevocarPermiso`, que ejecutan el `GRANT`/`REVOKE` vía SQL dinámico y registran manualmente en `log_permisos`.
- **Seguridad por sucursal (row-level security)**: MySQL no tiene RLS nativo. Se simula con la vista `v_ventas_mi_sucursal`, filtrada por `mapeo_usuario_sucursal` + `CURRENT_USER()`; los usuarios de sucursal reciben privilegios sobre la vista, no sobre `ventas` directamente.
- **Backup lógico diario vía evento programado**: un `EVENT` corre dentro del servidor y no puede invocar `mysqldump` ni procesos del sistema operativo. Se simula copiando (`INSERT...SELECT`) las tablas críticas a tablas espejo (`respaldo_productos`, `respaldo_clientes`, `respaldo_ventas`). Un backup real de producción requeriría herramientas de sistema operativo fuera del alcance de SQL puro.
- **"Reconstruir índices"**: MySQL/InnoDB no tiene un "index rebuild" equivalente al de otros motores. Se usa `ANALYZE TABLE` (refresca estadísticas) como aproximación más liviana que `OPTIMIZE TABLE` (reconstruye la tabla completa).
- **"Vistas materializadas"**: MySQL no las soporta nativamente. Se implementan como tablas normales (`resumen_ventas_diarias`, `snapshot_stock_diario`, `ranking_productos_popular`, `kpis_mensuales`) refrescadas periódicamente por eventos.
- **Detección de fraude y proyección de demanda**: no hay motor de Machine Learning nativo en MySQL. Se usan reglas fijas simples (ej. ráfagas de logins fallidos) y un promedio móvil de 3 meses respectivamente, documentados como aproximaciones académicas y no modelos predictivos reales.

## Verificación rápida

Tras ejecutar los 7 scripts en orden:

```sql
-- Confirmar volumen de datos
SELECT COUNT(*) FROM productos;
SELECT COUNT(*) FROM ventas;

-- Probar una consulta analítica
-- (ver 02_Consultas_Avanzadas.sql, consulta #1: Top 10 productos más vendidos)

-- Probar un trigger end-to-end: insertar una venta y un detalle, y confirmar que
-- el stock del producto baja y el total de la venta se recalcula automáticamente.

-- Confirmar permisos de un rol restringido
SHOW GRANTS FOR 'inventory_user'@'%';
```
