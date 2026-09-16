-- =====================================================================
-- 06_Eventos.sql
-- Proyecto BD Avanzada MySQL - E-commerce (ecommerce_avanzado)
-- Automatizacion mediante el Event Scheduler de MySQL 8.0
--
-- Contiene:
--   - Activacion del event_scheduler
--   - Tabla reporte_ventas_semanales (unica tabla nueva de este archivo)
--   - 20 CREATE EVENT que automatizan tareas de mantenimiento, limpieza,
--     reportes y analitica sobre las 40 tablas creadas en
--     01_Esquema_y_Datos.sql (no se vuelve a crear ninguna de esas tablas)
--
-- Todos los eventos se crean con ON COMPLETION PRESERVE para que
-- permanezcan visibles en SHOW EVENTS despues de cada ejecucion (en vez
-- de autoeliminarse, comportamiento por defecto de MySQL).
-- =====================================================================

USE ecommerce_avanzado;

-- El Event Scheduler es una variable GLOBAL: se activa una sola vez por
-- instancia de servidor. No se persiste tras un reinicio del contenedor
-- a menos que se configure event_scheduler=ON en el archivo de
-- configuracion de MySQL (my.cnf); en un entorno productivo real se
-- agregaria ahi para sobrevivir reinicios.
SET GLOBAL event_scheduler = ON;

-- =====================================================================
-- TABLA NUEVA: reporte_ventas_semanales
-- =====================================================================

CREATE TABLE reporte_ventas_semanales (
  id_reporte       INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  semana_inicio    DATE NOT NULL,
  semana_fin       DATE NOT NULL,
  total_ventas     DECIMAL(14,2) NOT NULL,
  cantidad_ventas  INT UNSIGNED NOT NULL,
  ticket_promedio  DECIMAL(10,2) NOT NULL,
  fecha_generacion DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (semana_inicio, semana_fin)
) ENGINE=InnoDB;

-- =====================================================================
-- SECCION 1: REPORTES Y AGREGACIONES
-- =====================================================================

-- 1) Genera el reporte de ventas de la semana que acaba de terminar
--    (7 dias que terminan ayer). ON DUPLICATE KEY UPDATE evita duplicar
--    filas si el evento se re-ejecuta manualmente sobre la misma semana.
DELIMITER $$

CREATE EVENT evt_generate_weekly_sales_report
ON SCHEDULE EVERY 1 WEEK
STARTS CURRENT_TIMESTAMP
ON COMPLETION PRESERVE
COMMENT 'Agrega ventas de la ultima semana en reporte_ventas_semanales'
DO
BEGIN
  DECLARE v_inicio    DATE;
  DECLARE v_fin       DATE;
  DECLARE v_total     DECIMAL(14,2);
  DECLARE v_cantidad  INT UNSIGNED;
  DECLARE v_ticket    DECIMAL(10,2);

  SET v_fin    = DATE_SUB(CURDATE(), INTERVAL 1 DAY);
  SET v_inicio = DATE_SUB(v_fin, INTERVAL 6 DAY);

  SELECT COALESCE(SUM(total), 0), COUNT(*)
    INTO v_total, v_cantidad
  FROM ventas
  WHERE DATE(fecha_venta) BETWEEN v_inicio AND v_fin
    AND estado <> 'Cancelado';

  SET v_ticket = IF(v_cantidad = 0, 0, v_total / v_cantidad);

  INSERT INTO reporte_ventas_semanales (semana_inicio, semana_fin, total_ventas, cantidad_ventas, ticket_promedio)
  VALUES (v_inicio, v_fin, v_total, v_cantidad, v_ticket)
  ON DUPLICATE KEY UPDATE
    total_ventas    = v_total,
    cantidad_ventas = v_cantidad,
    ticket_promedio = v_ticket,
    fecha_generacion = CURRENT_TIMESTAMP;
END$$

DELIMITER ;

-- =====================================================================
-- SECCION 2: LIMPIEZA Y MANTENIMIENTO
-- =====================================================================

-- 2) Limpia registros de staging con mas de 7 dias de antiguedad.
CREATE EVENT evt_cleanup_temp_tables_daily
ON SCHEDULE EVERY 1 DAY
STARTS CURRENT_TIMESTAMP
ON COMPLETION PRESERVE
COMMENT 'Elimina filas de staging_temporal con mas de 7 dias'
DO
  DELETE FROM staging_temporal WHERE fecha_creacion < DATE_SUB(NOW(), INTERVAL 7 DAY);

-- 3) "Archiva" (en este proyecto academico, borra) logs de mas de 6 meses.
--    NOTA: en un escenario productivo real estas filas se moverian primero
--    a una tabla historica (p.ej. log_intentos_login_historico) antes de
--    borrarse de la tabla operativa; aqui se simplifica a un DELETE directo
--    porque el alcance del proyecto no incluye tablas historicas para logs.
DELIMITER $$

CREATE EVENT evt_archive_old_logs_monthly
ON SCHEDULE EVERY 1 MONTH
STARTS CURRENT_TIMESTAMP
ON COMPLETION PRESERVE
COMMENT 'Purga logs de login y de consistencia con mas de 6 meses (aproximacion de archivado)'
DO
BEGIN
  DELETE FROM log_intentos_login WHERE fecha_intento < DATE_SUB(NOW(), INTERVAL 6 MONTH);
  DELETE FROM log_consistencia_datos WHERE fecha_chequeo < DATE_SUB(NOW(), INTERVAL 6 MONTH);
END$$

DELIMITER ;

-- 4) Desactiva promociones cuya fecha_fin ya paso.
CREATE EVENT evt_deactivate_expired_promotions_hourly
ON SCHEDULE EVERY 1 HOUR
STARTS CURRENT_TIMESTAMP
ON COMPLETION PRESERVE
COMMENT 'Marca activa=FALSE en promociones vencidas'
DO
  UPDATE promociones SET activa = FALSE WHERE fecha_fin < NOW() AND activa = TRUE;

-- 5) Recalcula el nivel de lealtad de todos los clientes segun su gasto
--    total. Se programa para ejecutarse a las 02:00 AM del dia siguiente,
--    simulando una ventana de mantenimiento nocturno de bajo trafico.
CREATE EVENT evt_recalculate_customer_loyalty_tiers_nightly
ON SCHEDULE EVERY 1 DAY
STARTS TIMESTAMP(CURDATE() + INTERVAL 1 DAY, '02:00:00')
ON COMPLETION PRESERVE
COMMENT 'Recalcula nivel_lealtad (Bronce/Plata/Oro) segun total_gastado'
DO
  UPDATE clientes
  SET nivel_lealtad = CASE
    WHEN total_gastado >= 2000 THEN 'Oro'
    WHEN total_gastado >= 500  THEN 'Plata'
    ELSE 'Bronce'
  END;

-- =====================================================================
-- SECCION 3: INVENTARIO
-- =====================================================================

-- 6) Genera alertas de reabastecimiento para productos con stock por
--    debajo (o igual) al minimo, evitando duplicar si ya existe una
--    alerta sin atender (atendida = FALSE) para ese producto.
CREATE EVENT evt_generate_reorder_list_daily
ON SCHEDULE EVERY 1 DAY
STARTS CURRENT_TIMESTAMP
ON COMPLETION PRESERVE
COMMENT 'Inserta en alertas_stock los productos con stock <= stock_minimo sin alerta pendiente'
DO
  INSERT INTO alertas_stock (id_producto, stock_actual, stock_minimo, origen)
  SELECT p.id_producto, p.stock, p.stock_minimo, 'Evento'
  FROM productos p
  WHERE p.stock <= p.stock_minimo
    AND p.activo = TRUE
    AND p.eliminado = FALSE
    AND NOT EXISTS (
      SELECT 1 FROM alertas_stock a
      WHERE a.id_producto = p.id_producto AND a.atendida = FALSE
    );

-- 7) "Reconstruye" indices de todas las tablas del esquema. MySQL/InnoDB
--    no ofrece un comando real de "rebuild index" equivalente al de otros
--    motores; ANALYZE TABLE actualiza las estadisticas de indices que usa
--    el optimizador y es la aproximacion practica disponible, por lo que
--    se usa aqui recorriendo information_schema.TABLES con un cursor y
--    SQL dinamico (PREPARE/EXECUTE) por cada tabla del esquema.
DELIMITER $$

CREATE EVENT evt_rebuild_indexes_weekly
ON SCHEDULE EVERY 1 WEEK
STARTS CURRENT_TIMESTAMP
ON COMPLETION PRESERVE
COMMENT 'ANALYZE TABLE de todas las tablas del esquema (aproximacion a "rebuild index", inexistente en MySQL)'
DO
BEGIN
  DECLARE v_done   INT DEFAULT FALSE;
  DECLARE v_tabla  VARCHAR(100);
  DECLARE cur_tablas CURSOR FOR
    SELECT TABLE_NAME
    FROM information_schema.TABLES
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_TYPE = 'BASE TABLE';
  DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_done = TRUE;

  OPEN cur_tablas;
  tablas_loop: LOOP
    FETCH cur_tablas INTO v_tabla;
    IF v_done THEN
      LEAVE tablas_loop;
    END IF;

    SET @sql_dinamico = CONCAT('ANALYZE TABLE `', v_tabla, '`');
    PREPARE stmt_analyze FROM @sql_dinamico;
    EXECUTE stmt_analyze;
    DEALLOCATE PREPARE stmt_analyze;
  END LOOP;
  CLOSE cur_tablas;
END$$

DELIMITER ;

-- =====================================================================
-- SECCION 4: CLIENTES
-- =====================================================================

-- 8) Suspende cuentas sin compras en el ultimo anio (o sin ninguna compra).
CREATE EVENT evt_suspend_inactive_accounts_quarterly
ON SCHEDULE EVERY 3 MONTH
STARTS CURRENT_TIMESTAMP
ON COMPLETION PRESERVE
COMMENT 'Marca activo=FALSE en clientes sin compras en el ultimo anio'
DO
  UPDATE clientes
  SET activo = FALSE
  WHERE (fecha_ultima_compra IS NULL OR fecha_ultima_compra < DATE_SUB(NOW(), INTERVAL 1 YEAR))
    AND activo = TRUE;

-- =====================================================================
-- SECCION 5: VENTAS Y ANALITICA
-- =====================================================================

-- 9) Agrega en resumen_ventas_diarias las ventas del dia anterior.
DELIMITER $$

CREATE EVENT evt_aggregate_daily_sales_data
ON SCHEDULE EVERY 1 DAY
STARTS CURRENT_TIMESTAMP
ON COMPLETION PRESERVE
COMMENT 'Agrega ventas del dia anterior en resumen_ventas_diarias'
DO
BEGIN
  DECLARE v_fecha  DATE;
  DECLARE v_total  DECIMAL(14,2);
  DECLARE v_num    INT UNSIGNED;
  DECLARE v_ticket DECIMAL(10,2);

  SET v_fecha = DATE_SUB(CURDATE(), INTERVAL 1 DAY);

  SELECT COALESCE(SUM(total), 0), COUNT(*)
    INTO v_total, v_num
  FROM ventas
  WHERE DATE(fecha_venta) = v_fecha
    AND estado <> 'Cancelado';

  SET v_ticket = IF(v_num = 0, 0, v_total / v_num);

  INSERT INTO resumen_ventas_diarias (fecha, total_ventas, num_ventas, ticket_promedio)
  VALUES (v_fecha, v_total, v_num, v_ticket)
  ON DUPLICATE KEY UPDATE
    total_ventas    = v_total,
    num_ventas      = v_num,
    ticket_promedio = v_ticket,
    fecha_calculo   = CURRENT_TIMESTAMP;
END$$

DELIMITER ;

-- 10) Busca ventas sin ningun detalle asociado (inconsistencia de datos)
--     y las registra, evitando duplicar el mismo hallazgo el mismo dia.
CREATE EVENT evt_check_data_consistency_nightly
ON SCHEDULE EVERY 1 DAY
STARTS TIMESTAMP(CURDATE() + INTERVAL 1 DAY, '02:00:00')
ON COMPLETION PRESERVE
COMMENT 'Detecta ventas sin detalle_ventas asociado y las registra en log_consistencia_datos'
DO
  INSERT INTO log_consistencia_datos (tipo_inconsistencia, id_referencia, descripcion)
  SELECT 'Venta_Sin_Detalle', v.id_venta,
         CONCAT('La venta ', v.id_venta, ' no tiene ninguna fila en detalle_ventas')
  FROM ventas v
  LEFT JOIN detalle_ventas d ON d.id_venta = v.id_venta
  WHERE d.id_detalle IS NULL
    AND NOT EXISTS (
      SELECT 1 FROM log_consistencia_datos l
      WHERE l.tipo_inconsistencia = 'Venta_Sin_Detalle'
        AND l.id_referencia = v.id_venta
        AND DATE(l.fecha_chequeo) = CURDATE()
    );

-- 11) Genera notificaciones de cumpleanos para clientes activos cuyo
--     dia/mes de nacimiento coincide con la fecha actual.
CREATE EVENT evt_send_birthday_greetings_daily
ON SCHEDULE EVERY 1 DAY
STARTS CURRENT_TIMESTAMP
ON COMPLETION PRESERVE
COMMENT 'Inserta en notificaciones_cumpleanos los clientes que cumplen anios hoy'
DO
  INSERT INTO notificaciones_cumpleanos (id_cliente, fecha_generado, mensaje)
  SELECT c.id_cliente, CURDATE(),
         CONCAT('Feliz cumpleanos, ', c.nombre, ' ', c.apellido, '! Disfruta un descuento especial en tu dia.')
  FROM clientes c
  WHERE MONTH(c.fecha_nacimiento) = MONTH(CURDATE())
    AND DAY(c.fecha_nacimiento) = DAY(CURDATE())
    AND c.activo = TRUE
    AND NOT EXISTS (
      SELECT 1 FROM notificaciones_cumpleanos n
      WHERE n.id_cliente = c.id_cliente AND n.fecha_generado = CURDATE()
    );

-- 12) Recalcula el ranking de productos populares combinando visitas y
--     ventas de las ultimas 24 horas, usando RANK() OVER para la posicion.
CREATE EVENT evt_update_product_rankings_hourly
ON SCHEDULE EVERY 1 HOUR
STARTS CURRENT_TIMESTAMP
ON COMPLETION PRESERVE
COMMENT 'Calcula ranking_productos_popular con visitas y ventas de las ultimas 24h'
DO
  INSERT INTO ranking_productos_popular (id_producto, fecha_calculo, num_vistas_periodo, num_ventas_periodo, posicion)
  WITH visitas AS (
    SELECT id_producto, COUNT(*) AS num_vistas
    FROM visitas_productos
    WHERE fecha_visita >= DATE_SUB(NOW(), INTERVAL 24 HOUR)
    GROUP BY id_producto
  ),
  ventas_prod AS (
    SELECT dv.id_producto, SUM(dv.cantidad) AS num_ventas
    FROM detalle_ventas dv
    INNER JOIN ventas v ON v.id_venta = dv.id_venta
    WHERE v.fecha_venta >= DATE_SUB(NOW(), INTERVAL 24 HOUR)
      AND v.estado <> 'Cancelado'
    GROUP BY dv.id_producto
  ),
  combinado AS (
    SELECT p.id_producto,
           COALESCE(vi.num_vistas, 0) AS num_vistas_periodo,
           COALESCE(vp.num_ventas, 0) AS num_ventas_periodo
    FROM productos p
    LEFT JOIN visitas vi ON vi.id_producto = p.id_producto
    LEFT JOIN ventas_prod vp ON vp.id_producto = p.id_producto
    WHERE COALESCE(vi.num_vistas, 0) > 0 OR COALESCE(vp.num_ventas, 0) > 0
  )
  SELECT id_producto, NOW(), num_vistas_periodo, num_ventas_periodo,
         RANK() OVER (ORDER BY num_ventas_periodo DESC, num_vistas_periodo DESC) AS posicion
  FROM combinado;

-- =====================================================================
-- SECCION 6: RESPALDOS
-- =====================================================================

-- 13) Copia el estado actual de las tablas criticas hacia sus tablas de
--     respaldo homonimas y registra cada copia en respaldo_log.
--     NOTA: un EVENT corre dentro del motor de MySQL y no puede invocar
--     mysqldump ni ningun proceso del sistema operativo; esta rutina es
--     una aproximacion logica de "respaldo" dentro del mismo esquema,
--     no un respaldo fisico/externo real.
DELIMITER $$

CREATE EVENT evt_backup_critical_tables_daily
ON SCHEDULE EVERY 1 DAY
STARTS CURRENT_TIMESTAMP
ON COMPLETION PRESERVE
COMMENT 'Copia productos/clientes/ventas a sus tablas de respaldo (aproximacion logica, no reemplaza mysqldump)'
DO
BEGIN
  DECLARE v_filas BIGINT UNSIGNED;

  INSERT INTO respaldo_productos (id_producto, nombre, precio, costo, stock, sku)
  SELECT id_producto, nombre, precio, costo, stock, sku FROM productos;
  SET v_filas = ROW_COUNT();
  INSERT INTO respaldo_log (nombre_tabla, filas_respaldadas, estado)
  VALUES ('productos', v_filas, 'Exitoso');

  INSERT INTO respaldo_clientes (id_cliente, nombre, apellido, email, total_gastado)
  SELECT id_cliente, nombre, apellido, email, total_gastado FROM clientes;
  SET v_filas = ROW_COUNT();
  INSERT INTO respaldo_log (nombre_tabla, filas_respaldadas, estado)
  VALUES ('clientes', v_filas, 'Exitoso');

  INSERT INTO respaldo_ventas (id_venta, id_cliente, fecha_venta, estado, total)
  SELECT id_venta, id_cliente, fecha_venta, estado, total FROM ventas;
  SET v_filas = ROW_COUNT();
  INSERT INTO respaldo_log (nombre_tabla, filas_respaldadas, estado)
  VALUES ('ventas', v_filas, 'Exitoso');
END$$

DELIMITER ;

-- =====================================================================
-- SECCION 7: CARRITOS
-- =====================================================================

-- 14) Marca como abandonados los carritos activos sin actividad en 72h.
CREATE EVENT evt_clear_abandoned_carts_daily
ON SCHEDULE EVERY 1 DAY
STARTS CURRENT_TIMESTAMP
ON COMPLETION PRESERVE
COMMENT 'Marca estado=Abandonado en carritos activos inactivos por 72 horas'
DO
  UPDATE carritos
  SET estado = 'Abandonado'
  WHERE fecha_actualizacion < DATE_SUB(NOW(), INTERVAL 72 HOUR)
    AND estado = 'Activo';

-- =====================================================================
-- SECCION 8: KPIs Y VISTAS MATERIALIZADAS
-- =====================================================================

-- 15) Calcula los KPIs del mes anterior (ventas, num_ventas, clientes
--     nuevos, ticket promedio y margen total usando productos.costo).
DELIMITER $$

CREATE EVENT evt_calculate_monthly_kpis
ON SCHEDULE EVERY 1 MONTH
STARTS CURRENT_TIMESTAMP
ON COMPLETION PRESERVE
COMMENT 'Calcula KPIs del mes anterior en kpis_mensuales'
DO
BEGIN
  DECLARE v_anio             SMALLINT UNSIGNED;
  DECLARE v_mes              TINYINT UNSIGNED;
  DECLARE v_ventas_totales   DECIMAL(14,2);
  DECLARE v_num_ventas       INT UNSIGNED;
  DECLARE v_nuevos_clientes  INT UNSIGNED;
  DECLARE v_ticket_promedio  DECIMAL(10,2);
  DECLARE v_margen_total     DECIMAL(14,2);

  SET v_anio = YEAR(DATE_SUB(CURDATE(), INTERVAL 1 MONTH));
  SET v_mes  = MONTH(DATE_SUB(CURDATE(), INTERVAL 1 MONTH));

  SELECT COALESCE(SUM(total), 0), COUNT(*)
    INTO v_ventas_totales, v_num_ventas
  FROM ventas
  WHERE YEAR(fecha_venta) = v_anio
    AND MONTH(fecha_venta) = v_mes
    AND estado <> 'Cancelado';

  SET v_ticket_promedio = IF(v_num_ventas = 0, 0, v_ventas_totales / v_num_ventas);

  SELECT COUNT(*)
    INTO v_nuevos_clientes
  FROM clientes
  WHERE YEAR(fecha_registro) = v_anio
    AND MONTH(fecha_registro) = v_mes;

  SELECT COALESCE(SUM((dv.precio_unitario_congelado - p.costo) * dv.cantidad), 0)
    INTO v_margen_total
  FROM detalle_ventas dv
  INNER JOIN ventas v ON v.id_venta = dv.id_venta
  INNER JOIN productos p ON p.id_producto = dv.id_producto
  WHERE YEAR(v.fecha_venta) = v_anio
    AND MONTH(v.fecha_venta) = v_mes
    AND v.estado <> 'Cancelado';

  INSERT INTO kpis_mensuales (anio, mes, ventas_totales, num_ventas, nuevos_clientes, ticket_promedio, margen_total)
  VALUES (v_anio, v_mes, v_ventas_totales, v_num_ventas, v_nuevos_clientes, v_ticket_promedio, v_margen_total)
  ON DUPLICATE KEY UPDATE
    ventas_totales  = v_ventas_totales,
    num_ventas      = v_num_ventas,
    nuevos_clientes = v_nuevos_clientes,
    ticket_promedio = v_ticket_promedio,
    margen_total    = v_margen_total,
    fecha_calculo   = CURRENT_TIMESTAMP;
END$$

DELIMITER ;

-- 16) Refresca la "vista materializada" de stock diario. MySQL no tiene
--     vistas materializadas nativas (a diferencia de PostgreSQL/Oracle);
--     la aproximacion usual es una tabla normal que se refresca por
--     evento, que es exactamente lo que hace snapshot_stock_diario aqui.
CREATE EVENT evt_refresh_materialized_views_nightly
ON SCHEDULE EVERY 1 DAY
STARTS TIMESTAMP(CURDATE() + INTERVAL 1 DAY, '02:00:00')
ON COMPLETION PRESERVE
COMMENT 'Refresca snapshot_stock_diario (tabla usada como vista materializada, inexistente de forma nativa en MySQL)'
DO
  INSERT INTO snapshot_stock_diario (id_producto, stock_al_cierre, fecha)
  SELECT id_producto, stock, CURDATE()
  FROM productos
  ON DUPLICATE KEY UPDATE stock_al_cierre = VALUES(stock_al_cierre);

-- =====================================================================
-- SECCION 9: OBSERVABILIDAD Y SEGURIDAD
-- =====================================================================

-- 17) Registra el tamano de cada tabla del esquema (datos e indices) a
--     partir de information_schema.TABLES.
CREATE EVENT evt_log_database_size_weekly
ON SCHEDULE EVERY 1 WEEK
STARTS CURRENT_TIMESTAMP
ON COMPLETION PRESERVE
COMMENT 'Registra tamano de datos/indices por tabla en tamano_bd_log'
DO
  INSERT INTO tamano_bd_log (nombre_tabla, filas_aprox, tamano_datos_mb, tamano_indices_mb)
  SELECT TABLE_NAME,
         TABLE_ROWS,
         ROUND(DATA_LENGTH / 1024 / 1024, 2),
         ROUND(INDEX_LENGTH / 1024 / 1024, 2)
  FROM information_schema.TABLES
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_TYPE = 'BASE TABLE';

-- 18) Regla simple de deteccion de fraude: clientes con 5 o mas intentos
--     de login fallidos en la ultima hora. Es una regla fija de umbral,
--     no un modelo de machine learning real; sirve como ejemplo didactico
--     de automatizacion de seguridad basica con el Event Scheduler.
CREATE EVENT evt_detect_fraudulent_activity_hourly
ON SCHEDULE EVERY 1 HOUR
STARTS CURRENT_TIMESTAMP
ON COMPLETION PRESERVE
COMMENT 'Regla fija (>=5 logins fallidos/hora) para marcar actividad sospechosa; no es deteccion por ML'
DO
  INSERT INTO log_actividad_fraudulenta (id_cliente, tipo_alerta, detalle)
  SELECT l.id_cliente,
         'Multiples_Intentos_Fallidos',
         CONCAT(COUNT(*), ' intentos de login fallidos en la ultima hora')
  FROM log_intentos_login l
  WHERE l.exitoso = FALSE
    AND l.fecha_intento >= DATE_SUB(NOW(), INTERVAL 1 HOUR)
    AND l.id_cliente IS NOT NULL
  GROUP BY l.id_cliente
  HAVING COUNT(*) >= 5
     AND NOT EXISTS (
       SELECT 1 FROM log_actividad_fraudulenta f
       WHERE f.id_cliente = l.id_cliente
         AND f.tipo_alerta = 'Multiples_Intentos_Fallidos'
         AND f.fecha_deteccion >= DATE_SUB(NOW(), INTERVAL 1 HOUR)
     );

-- =====================================================================
-- SECCION 10: PROVEEDORES Y DEPURACION
-- =====================================================================

-- 19) Agrega en reporte_rendimiento_proveedores unidades vendidas e
--     ingresos del mes anterior por proveedor (productos -> detalle_ventas -> ventas).
DELIMITER $$

CREATE EVENT evt_generate_supplier_performance_report_monthly
ON SCHEDULE EVERY 1 MONTH
STARTS CURRENT_TIMESTAMP
ON COMPLETION PRESERVE
COMMENT 'Calcula rendimiento de proveedores del mes anterior'
DO
BEGIN
  DECLARE v_anio SMALLINT UNSIGNED;
  DECLARE v_mes  TINYINT UNSIGNED;

  SET v_anio = YEAR(DATE_SUB(CURDATE(), INTERVAL 1 MONTH));
  SET v_mes  = MONTH(DATE_SUB(CURDATE(), INTERVAL 1 MONTH));

  INSERT INTO reporte_rendimiento_proveedores (id_proveedor, anio, mes, unidades_vendidas, ingresos_generados)
  SELECT p.id_proveedor, v_anio, v_mes,
         SUM(dv.cantidad) AS unidades_vendidas,
         SUM(dv.subtotal) AS ingresos_generados
  FROM productos p
  INNER JOIN detalle_ventas dv ON dv.id_producto = p.id_producto
  INNER JOIN ventas v ON v.id_venta = dv.id_venta
  WHERE YEAR(v.fecha_venta) = v_anio
    AND MONTH(v.fecha_venta) = v_mes
    AND v.estado <> 'Cancelado'
    AND p.id_proveedor IS NOT NULL
  GROUP BY p.id_proveedor
  ON DUPLICATE KEY UPDATE
    unidades_vendidas  = VALUES(unidades_vendidas),
    ingresos_generados = VALUES(ingresos_generados),
    fecha_generacion   = CURRENT_TIMESTAMP;
END$$

DELIMITER ;

-- 20) Purga definitivamente productos marcados como eliminados (soft
--     delete) hace mas de 30 dias.
CREATE EVENT evt_purge_soft_deleted_records_weekly
ON SCHEDULE EVERY 1 WEEK
STARTS CURRENT_TIMESTAMP
ON COMPLETION PRESERVE
COMMENT 'Elimina fisicamente productos con soft delete de mas de 30 dias'
DO
  DELETE FROM productos
  WHERE eliminado = TRUE
    AND fecha_eliminacion < DATE_SUB(NOW(), INTERVAL 30 DAY);

-- =====================================================================
-- FIN DE 06_Eventos.sql
-- =====================================================================
