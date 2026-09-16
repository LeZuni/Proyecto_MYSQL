-- =====================================================================
-- 05_Triggers.sql
-- Proyecto BD Avanzada MySQL 8.0 - E-commerce (ecommerce_avanzado)
-- Triggers de integridad, auditoria y mantenimiento de contadores.
-- Requiere que 01_Esquema_y_Datos.sql ya haya sido ejecutado.
-- =====================================================================

USE ecommerce_avanzado;

-- =====================================================================
-- SECCION 0: TABLA DE APOYO PARA AUDITORIA DE PRECIOS
-- =====================================================================
-- No existia en 01_Esquema_y_Datos.sql: se crea aqui porque es de uso
-- exclusivo de los triggers de auditoria de precios/costos de productos.

CREATE TABLE log_cambios_precio (
  id_log           INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  id_producto      INT UNSIGNED NOT NULL,
  precio_anterior  DECIMAL(10,2) NOT NULL,
  precio_nuevo     DECIMAL(10,2) NOT NULL,
  costo_anterior   DECIMAL(10,2) NULL,
  costo_nuevo      DECIMAL(10,2) NULL,
  fecha_cambio     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  usuario_bd       VARCHAR(100) NULL,
  CONSTRAINT fk_lcp_producto FOREIGN KEY (id_producto) REFERENCES productos(id_producto)
) ENGINE=InnoDB;

-- =====================================================================
-- SECCION 1: TRIGGERS SOBRE PRODUCTOS
-- =====================================================================

DELIMITER $$

-- 1) Auditar cualquier cambio de precio o costo en un producto.
CREATE TRIGGER trg_auditar_cambio_precio
BEFORE UPDATE ON productos
FOR EACH ROW
BEGIN
  IF OLD.precio <> NEW.precio OR OLD.costo <> NEW.costo THEN
    INSERT INTO log_cambios_precio (id_producto, precio_anterior, precio_nuevo, costo_anterior, costo_nuevo, usuario_bd)
    VALUES (OLD.id_producto, OLD.precio, NEW.precio, OLD.costo, NEW.costo, CURRENT_USER());
  END IF;
END$$

-- 7) Mantener fecha_modificacion sincronizada en cada UPDATE de productos.
CREATE TRIGGER trg_set_fecha_modificacion_producto
BEFORE UPDATE ON productos
FOR EACH ROW
BEGIN
  SET NEW.fecha_modificacion = NOW();
END$$

-- 8) Impedir que un producto quede con stock negativo (mensaje descriptivo;
--    la tabla ya tiene chk_stock_no_negativo como ultima linea de defensa).
CREATE TRIGGER trg_impedir_stock_negativo
BEFORE UPDATE ON productos
FOR EACH ROW
BEGIN
  IF NEW.stock < 0 THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'No se puede dejar el stock del producto en un valor negativo.';
  END IF;
END$$

-- 13) Impedir precio <= 0, tanto al insertar como al actualizar productos
--     (mensaje descriptivo; la tabla ya tiene chk_precio_positivo).
CREATE TRIGGER trg_impedir_precio_cero_o_negativo_insert
BEFORE INSERT ON productos
FOR EACH ROW
BEGIN
  IF NEW.precio <= 0 THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'El precio del producto debe ser mayor que cero.';
  END IF;
END$$

CREATE TRIGGER trg_impedir_precio_cero_o_negativo_update
BEFORE UPDATE ON productos
FOR EACH ROW
BEGIN
  IF NEW.precio <= 0 THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'El precio del producto debe ser mayor que cero.';
  END IF;
END$$

-- 18) Asignar la categoria 'General' cuando no se indica id_categoria.
CREATE TRIGGER trg_categoria_general_default
BEFORE INSERT ON productos
FOR EACH ROW
BEGIN
  IF NEW.id_categoria IS NULL THEN
    SET NEW.id_categoria = (SELECT id_categoria FROM categorias WHERE nombre = 'General' LIMIT 1);
  END IF;
END$$

-- 14) Alertar cuando el stock cae al nivel minimo o por debajo de este.
CREATE TRIGGER trg_alerta_stock_bajo
AFTER UPDATE ON productos
FOR EACH ROW
BEGIN
  IF NEW.stock <= NEW.stock_minimo AND (OLD.stock > OLD.stock_minimo OR OLD.stock_minimo <> NEW.stock_minimo) THEN
    INSERT INTO alertas_stock (id_producto, stock_actual, stock_minimo, origen)
    VALUES (NEW.id_producto, NEW.stock, NEW.stock_minimo, 'Trigger');
  END IF;
END$$

-- 19) Mantener categorias.total_productos correcto ante altas, bajas y
--     cambios de categoria de un producto.
CREATE TRIGGER trg_contador_productos_categoria_insert
AFTER INSERT ON productos
FOR EACH ROW
BEGIN
  IF NEW.id_categoria IS NOT NULL THEN
    UPDATE categorias SET total_productos = total_productos + 1 WHERE id_categoria = NEW.id_categoria;
  END IF;
END$$

CREATE TRIGGER trg_contador_productos_categoria_delete
AFTER DELETE ON productos
FOR EACH ROW
BEGIN
  IF OLD.id_categoria IS NOT NULL THEN
    UPDATE categorias SET total_productos = GREATEST(total_productos - 1, 0) WHERE id_categoria = OLD.id_categoria;
  END IF;
END$$

CREATE TRIGGER trg_contador_productos_categoria_update
AFTER UPDATE ON productos
FOR EACH ROW
BEGIN
  IF NOT (OLD.id_categoria <=> NEW.id_categoria) THEN
    IF OLD.id_categoria IS NOT NULL THEN
      UPDATE categorias SET total_productos = GREATEST(total_productos - 1, 0) WHERE id_categoria = OLD.id_categoria;
    END IF;
    IF NEW.id_categoria IS NOT NULL THEN
      UPDATE categorias SET total_productos = total_productos + 1 WHERE id_categoria = NEW.id_categoria;
    END IF;
  END IF;
END$$

DELIMITER ;

-- =====================================================================
-- SECCION 2: TRIGGERS SOBRE CATEGORIAS
-- =====================================================================

DELIMITER $$

-- 4) Impedir borrar una categoria que todavia tiene productos asociados
--    (mensaje descriptivo; ya existe fk_productos_categoria ON DELETE RESTRICT).
CREATE TRIGGER trg_impedir_borrar_categoria_con_productos
BEFORE DELETE ON categorias
FOR EACH ROW
BEGIN
  IF EXISTS (SELECT 1 FROM productos WHERE id_categoria = OLD.id_categoria) THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'No se puede eliminar una categoria que todavia tiene productos asociados.';
  END IF;
END$$

DELIMITER ;

-- =====================================================================
-- SECCION 3: TRIGGERS SOBRE CLIENTES
-- =====================================================================

DELIMITER $$

-- 9) Capitalizar nombre y apellido del cliente al insertarlo.
CREATE TRIGGER trg_capitalizar_nombre_cliente
BEFORE INSERT ON clientes
FOR EACH ROW
BEGIN
  SET NEW.nombre   = CONCAT(UPPER(LEFT(NEW.nombre, 1)), LOWER(SUBSTRING(NEW.nombre, 2)));
  SET NEW.apellido = CONCAT(UPPER(LEFT(NEW.apellido, 1)), LOWER(SUBSTRING(NEW.apellido, 2)));
END$$

-- 16) Validar formato basico de email, tanto al insertar como al actualizar
--     clientes (mensaje descriptivo; ya existe chk_email_formato, mas laxo).
CREATE TRIGGER trg_validar_email_cliente_insert
BEFORE INSERT ON clientes
FOR EACH ROW
BEGIN
  IF NEW.email NOT REGEXP '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$' THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'El formato del email del cliente no es valido.';
  END IF;
END$$

CREATE TRIGGER trg_validar_email_cliente_update
BEFORE UPDATE ON clientes
FOR EACH ROW
BEGIN
  IF NEW.email NOT REGEXP '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$' THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'El formato del email del cliente no es valido.';
  END IF;
END$$

-- 5) Registrar en auditoria_clientes el alta de cada cliente nuevo.
CREATE TRIGGER trg_log_nuevo_cliente
AFTER INSERT ON clientes
FOR EACH ROW
BEGIN
  INSERT INTO auditoria_clientes (id_cliente, accion, campo_modificado, valor_anterior, valor_nuevo, usuario_bd)
  VALUES (NEW.id_cliente, 'ALTA', NULL, NULL, CONCAT(NEW.nombre, ' ', NEW.apellido, ' <', NEW.email, '>'), CURRENT_USER());
END$$

DELIMITER ;

-- =====================================================================
-- SECCION 4: TRIGGERS SOBRE VENTAS
-- =====================================================================

DELIMITER $$

-- 6) Al registrar una venta nueva, sumar su total al total_gastado del
--    cliente y actualizar su fecha_ultima_compra (dos comportamientos de
--    la lista de 20, cubiertos por un unico trigger porque ambos dependen
--    del mismo evento AFTER INSERT ON ventas).
--    NOTA / limitacion conocida: al momento del INSERT de la venta, NEW.total
--    normalmente vale 0.00 (el total real se calcula despues, cuando se
--    insertan sus detalle_ventas, via trg_recalcular_total_venta_insert).
--    Este trigger queda implementado tal como lo pide la especificacion;
--    en un flujo real conviene recalcular total_gastado con un proceso
--    batch/procedimiento que sume ventas.total ya consolidado.
CREATE TRIGGER trg_actualizar_total_gastado_y_ultima_compra
AFTER INSERT ON ventas
FOR EACH ROW
BEGIN
  UPDATE clientes
  SET total_gastado = total_gastado + NEW.total,
      fecha_ultima_compra = NEW.fecha_venta
  WHERE id_cliente = NEW.id_cliente;
END$$

-- 12) Registrar en log_estado_pedido cada cambio de estado de una venta.
CREATE TRIGGER trg_log_estado_pedido
AFTER UPDATE ON ventas
FOR EACH ROW
BEGIN
  IF OLD.estado <> NEW.estado THEN
    INSERT INTO log_estado_pedido (id_venta, estado_anterior, estado_nuevo, usuario_bd)
    VALUES (NEW.id_venta, OLD.estado, NEW.estado, CURRENT_USER());
  END IF;
END$$

-- 15) Archivar la venta y su detalle antes de permitir que se elimine.
--     Debe ser BEFORE DELETE: en ese momento la venta y sus detalle_ventas
--     todavia existen. No se puede depender de un trigger AFTER DELETE en
--     detalle_ventas para esto, porque los borrados en cascada disparados
--     por una FK (ON DELETE CASCADE) NO activan triggers en MySQL/InnoDB.
CREATE TRIGGER trg_archivar_venta_eliminada
BEFORE DELETE ON ventas
FOR EACH ROW
BEGIN
  INSERT INTO ventas_archivadas (id_venta_original, id_cliente_original, fecha_venta_original, estado, total, id_sucursal_original)
  VALUES (OLD.id_venta, OLD.id_cliente, OLD.fecha_venta, OLD.estado, OLD.total, OLD.id_sucursal);

  INSERT INTO detalle_ventas_archivadas (id_detalle_original, id_venta_original, id_producto_original, cantidad, precio_unitario_congelado)
  SELECT id_detalle, id_venta, id_producto, cantidad, precio_unitario_congelado
  FROM detalle_ventas
  WHERE id_venta = OLD.id_venta;
END$$

DELIMITER ;

-- =====================================================================
-- SECCION 5: TRIGGERS SOBRE DETALLE_VENTAS
-- =====================================================================

DELIMITER $$

-- 2) Verificar que hay stock suficiente antes de permitir la venta.
CREATE TRIGGER trg_verificar_stock_venta
BEFORE INSERT ON detalle_ventas
FOR EACH ROW
BEGIN
  DECLARE v_stock_actual INT;

  SELECT stock INTO v_stock_actual FROM productos WHERE id_producto = NEW.id_producto;

  IF v_stock_actual IS NULL THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'El producto de la venta no existe.';
  ELSEIF NEW.cantidad > v_stock_actual THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Stock insuficiente para completar la venta de este producto.';
  END IF;
END$$

-- 3) Descontar del stock la cantidad vendida.
CREATE TRIGGER trg_decrementar_stock
AFTER INSERT ON detalle_ventas
FOR EACH ROW
BEGIN
  UPDATE productos SET stock = stock - NEW.cantidad WHERE id_producto = NEW.id_producto;
END$$

-- 11) Recalcular ventas.total como la suma de subtotal de su detalle,
--     ante inserciones, actualizaciones o borrados de detalle_ventas.
CREATE TRIGGER trg_recalcular_total_venta_insert
AFTER INSERT ON detalle_ventas
FOR EACH ROW
BEGIN
  UPDATE ventas
  SET total = (SELECT COALESCE(SUM(subtotal), 0) FROM detalle_ventas WHERE id_venta = NEW.id_venta)
  WHERE id_venta = NEW.id_venta;
END$$

CREATE TRIGGER trg_recalcular_total_venta_update
AFTER UPDATE ON detalle_ventas
FOR EACH ROW
BEGIN
  UPDATE ventas
  SET total = (SELECT COALESCE(SUM(subtotal), 0) FROM detalle_ventas WHERE id_venta = NEW.id_venta)
  WHERE id_venta = NEW.id_venta;
END$$

CREATE TRIGGER trg_recalcular_total_venta_delete
AFTER DELETE ON detalle_ventas
FOR EACH ROW
BEGIN
  UPDATE ventas
  SET total = (SELECT COALESCE(SUM(subtotal), 0) FROM detalle_ventas WHERE id_venta = OLD.id_venta)
  WHERE id_venta = OLD.id_venta;
END$$

DELIMITER ;

-- =====================================================================
-- SECCION 6: TRIGGERS SOBRE REFERIDOS_CLIENTES
-- =====================================================================

DELIMITER $$

-- 17) Impedir que un cliente se autorrefiera (mensaje descriptivo;
--     ya existe chk_no_autoreferido, este trigger solo mejora el mensaje).
CREATE TRIGGER trg_impedir_autoreferido
BEFORE INSERT ON referidos_clientes
FOR EACH ROW
BEGIN
  IF NEW.id_cliente_referidor = NEW.id_cliente_referido THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Un cliente no puede referirse a si mismo.';
  END IF;
END$$

DELIMITER ;

-- =====================================================================
-- SECCION 7: TRIGGERS SOBRE PROMOCIONES
-- =====================================================================
-- Comportamiento 20 de la lista original era "log de cambios de permisos".
-- Eso NO puede implementarse como trigger real: los triggers de MySQL
-- reaccionan a eventos DML (INSERT/UPDATE/DELETE) sobre tablas, pero MySQL
-- no dispara triggers ante sentencias DCL como GRANT/REVOKE/CREATE USER.
-- Ese registro de auditoria de permisos (tabla log_permisos, ya existente
-- en 01_Esquema_y_Datos.sql) se implementa en su lugar mediante
-- procedimientos almacenados que envuelven las operaciones de permisos y
-- registran manualmente el evento en log_permisos: ver
-- 07_Procedimientos_Almacenados.sql.
-- En su reemplazo, este archivo suma como comportamiento 20 un trigger DML
-- legitimo adicional sobre promociones:

DELIMITER $$

-- 20) Marcar una promocion como agotada automaticamente cuando alcanza su
--     limite de usos. Debe ser BEFORE UPDATE (no AFTER) porque necesita
--     modificar NEW.activa antes de que la fila se escriba.
CREATE TRIGGER trg_marcar_promocion_agotada
BEFORE UPDATE ON promociones
FOR EACH ROW
BEGIN
  IF NEW.usos_maximos IS NOT NULL AND NEW.usos_actuales >= NEW.usos_maximos THEN
    SET NEW.activa = FALSE;
  END IF;
END$$

DELIMITER ;

-- =====================================================================
-- SECCION 8: SINCRONIZACION INICIAL DE categorias.total_productos
-- =====================================================================
-- Ajuste adicional (no forma parte de la lista de 20 triggers): los datos
-- de ejemplo de 01_Esquema_y_Datos.sql insertaron 80 productos sin pasar
-- por estos triggers, por lo que categorias.total_productos quedo en 0
-- para todas las categorias. Se sincroniza una sola vez aqui para que, de
-- aqui en adelante, los triggers de la Seccion 1 mantengan el contador
-- correcto sobre una base consistente.
UPDATE categorias c
SET c.total_productos = (
  SELECT COUNT(*) FROM productos p WHERE p.id_categoria = c.id_categoria
);

-- =====================================================================
-- RESUMEN: LISTA DE 20 COMPORTAMIENTOS Y TRIGGERS FISICOS QUE LOS IMPLEMENTAN
-- =====================================================================
--  1. Auditar cambio de precio/costo de un producto
--       -> trg_auditar_cambio_precio                              (1 trigger)
--  2. Verificar stock suficiente antes de vender
--       -> trg_verificar_stock_venta                               (1 trigger)
--  3. Decrementar stock tras una venta
--       -> trg_decrementar_stock                                   (1 trigger)
--  4. Impedir borrar una categoria con productos
--       -> trg_impedir_borrar_categoria_con_productos              (1 trigger)
--  5. Log de alta de cliente nuevo
--       -> trg_log_nuevo_cliente                                   (1 trigger)
--  6. Actualizar total_gastado del cliente al registrar una venta
--       -> trg_actualizar_total_gastado_y_ultima_compra            (1 trigger, compartido con el punto 7)
--  7. Actualizar fecha de ultima compra del cliente
--       -> trg_actualizar_total_gastado_y_ultima_compra            (mismo trigger que el punto 6)
--  8. Sincronizar fecha_modificacion de productos en cada UPDATE
--       -> trg_set_fecha_modificacion_producto                     (1 trigger)
--  9. Impedir stock negativo en productos
--       -> trg_impedir_stock_negativo                              (1 trigger)
-- 10. Capitalizar nombre/apellido de clientes nuevos
--       -> trg_capitalizar_nombre_cliente                          (1 trigger)
-- 11. Recalcular ventas.total ante cambios en su detalle
--       -> trg_recalcular_total_venta_insert/update/delete         (3 triggers)
-- 12. Log de cambio de estado de un pedido
--       -> trg_log_estado_pedido                                   (1 trigger)
-- 13. Impedir precio <= 0 en productos
--       -> trg_impedir_precio_cero_o_negativo_insert/_update       (2 triggers)
-- 14. Alertar cuando el stock baja al minimo o por debajo
--       -> trg_alerta_stock_bajo                                   (1 trigger)
-- 15. Archivar una venta (y su detalle) antes de eliminarla
--       -> trg_archivar_venta_eliminada                            (1 trigger)
-- 16. Validar formato de email de clientes
--       -> trg_validar_email_cliente_insert/_update                (2 triggers)
-- 17. Impedir que un cliente se autorrefiera
--       -> trg_impedir_autoreferido                                (1 trigger)
-- 18. Asignar categoria 'General' por defecto si no se indica una
--       -> trg_categoria_general_default                           (1 trigger)
-- 19. Mantener categorias.total_productos correcto
--       -> trg_contador_productos_categoria_insert/delete/update   (3 triggers)
-- 20. (Reemplazo de "log de cambios de permisos", no implementable como
--     trigger porque MySQL no dispara triggers ante GRANT/REVOKE; ver
--     comentario de la Seccion 7 y 07_Procedimientos_Almacenados.sql)
--     Marcar promociones agotadas automaticamente
--       -> trg_marcar_promocion_agotada                            (1 trigger)
--
-- TOTAL: 20 comportamientos conceptuales implementados con 25 sentencias
-- CREATE TRIGGER fisicas (ademas de 1 CREATE TABLE de apoyo y 1 UPDATE de
-- sincronizacion inicial de contador, ambos fuera de la lista de 20).
-- =====================================================================
