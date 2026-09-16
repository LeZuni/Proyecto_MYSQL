-- =====================================================================
-- 07_Procedimientos_Almacenados.sql
-- Proyecto BD Avanzada MySQL 8.0 - E-commerce (ecommerce_avanzado)
-- Procedimientos almacenados de negocio (CRUD compuesto, transacciones,
-- reportes y utilidades de seguridad).
--
-- Requiere que ya se haya ejecutado 01_Esquema_y_Datos.sql sobre la base
-- de datos ecommerce_avanzado. Ademas, en tiempo de EJECUCION (CALL), los
-- siguientes procedimientos dependen de objetos definidos en otros
-- archivos de este mismo proyecto (se desarrollan en paralelo, por lo que
-- pueden no existir todavia cuando este script se ejecuta por primera
-- vez; el CREATE PROCEDURE en si no valida su existencia, solo el CALL):
--   - Funciones de 03_Funciones.sql: fn_VerificarStockDisponible,
--     fn_CalcularTotalVenta, fn_ObtenerPrecioActual, fn_ValidarFormatoEmail,
--     fn_ValidarComplejidadContrasena, fn_DeterminarNivelLealtad,
--     fn_CalcularIVA.
--   - Roles de 04_Seguridad.sql: Administrador_Sistema, Gerente_Marketing,
--     Analista_Datos, Empleado_Inventario, Atencion_Cliente,
--     Auditor_Financiero, Visitante (usados por sp_OtorgarPermiso y
--     sp_RevocarPermiso).
-- Tambien se apoya en los triggers ya existentes de 05_Triggers.sql
-- (trg_verificar_stock_venta, trg_decrementar_stock,
-- trg_recalcular_total_venta_insert/update/delete, trg_log_estado_pedido,
-- trg_log_nuevo_cliente, entre otros): donde un trigger ya garantiza un
-- efecto (p.ej. descontar stock o recalcular ventas.total al insertar en
-- detalle_ventas), los procedimientos de este archivo NO repiten esa
-- logica a mano para evitar duplicar el efecto (p.ej. descontar el stock
-- dos veces).
--
-- CONTENIDO: 23 CREATE PROCEDURE en total.
--   - Los 20 procedimientos pedidos en el enunciado del proyecto.
--   - 3 procedimientos ADICIONALES de soporte, no pedidos explicitamente
--     en la lista de 20, pero necesarios por decisiones de seguridad
--     simplificadas de este proyecto academico:
--       1) sp_LoginCliente: la lista de 20 no incluye un flujo de login,
--          pero la tabla log_intentos_login (01_Esquema_y_Datos.sql) y el
--          evento de deteccion de fraude (06_Eventos.sql) solo tienen
--          sentido si algo primero escribe intentos de login reales. Este
--          procedimiento simula la autenticacion de los CLIENTES de la
--          tienda (capa de aplicacion, contra clientes.contrasena_hash),
--          NO la autenticacion de usuarios/roles del propio servidor
--          MySQL (esa se gestiona con CREATE USER/GRANT en
--          04_Seguridad.sql).
--       2) sp_OtorgarPermiso y 3) sp_RevocarPermiso: la tabla log_permisos
--          (01_Esquema_y_Datos.sql) esta pensada para auditar GRANT/REVOKE
--          de roles, pero MySQL NO dispara triggers ante sentencias DCL
--          (GRANT/REVOKE/CREATE USER no son eventos DML), por lo que un
--          trigger real es imposible para ese requisito (ver tambien el
--          comentario de la Seccion 7 de 05_Triggers.sql). En su lugar,
--          estos dos procedimientos envuelven el GRANT/REVOKE en SQL
--          dinamico y registran manualmente el evento en log_permisos,
--          que es la unica forma de auditar DCL con los objetos que
--          ofrece MySQL 8.0 (procedimientos, no triggers).
-- =====================================================================

USE ecommerce_avanzado;

DROP PROCEDURE IF EXISTS sp_RealizarVenta;
DROP PROCEDURE IF EXISTS sp_AgregarProducto;
DROP PROCEDURE IF EXISTS sp_ActualizarDireccionCliente;
DROP PROCEDURE IF EXISTS sp_ProcesarDevolucion;
DROP PROCEDURE IF EXISTS sp_ObtenerHistorialCompras;
DROP PROCEDURE IF EXISTS sp_AjustarStockManual;
DROP PROCEDURE IF EXISTS sp_EliminarClienteSeguro;
DROP PROCEDURE IF EXISTS sp_AplicarDescuentoCategoria;
DROP PROCEDURE IF EXISTS sp_GenerarReporteMensual;
DROP PROCEDURE IF EXISTS sp_CambiarEstadoPedido;
DROP PROCEDURE IF EXISTS sp_RegistrarCliente;
DROP PROCEDURE IF EXISTS sp_ObtenerDetalleProducto;
DROP PROCEDURE IF EXISTS sp_FusionarCuentasCliente;
DROP PROCEDURE IF EXISTS sp_AsignarProveedor;
DROP PROCEDURE IF EXISTS sp_BuscarProductosFiltro;
DROP PROCEDURE IF EXISTS sp_DashboardAdmin;
DROP PROCEDURE IF EXISTS sp_ProcesarPago;
DROP PROCEDURE IF EXISTS sp_AnadirResenaProducto;
DROP PROCEDURE IF EXISTS sp_ObtenerProductosRelacionados;
DROP PROCEDURE IF EXISTS sp_MoverProductosEntreCategorias;
DROP PROCEDURE IF EXISTS sp_LoginCliente;
DROP PROCEDURE IF EXISTS sp_OtorgarPermiso;
DROP PROCEDURE IF EXISTS sp_RevocarPermiso;

DELIMITER $$

-- ---------------------------------------------------------------------
-- 1. sp_RealizarVenta
--    Crea una venta y su detalle dentro de una unica transaccion.
--    USO: el llamador debe crear y poblar una tabla temporal
--    tmp_venta_items(id_producto, cantidad) ANTES de invocar este
--    procedimiento, por ejemplo:
--
--      CREATE TEMPORARY TABLE IF NOT EXISTS tmp_venta_items (
--        id_producto INT UNSIGNED,
--        cantidad    INT UNSIGNED
--      );
--      INSERT INTO tmp_venta_items (id_producto, cantidad) VALUES (5, 2), (9, 1);
--      CALL sp_RealizarVenta(3, 1, NULL);
--
--    El procedimiento valida el stock de cada linea con
--    fn_VerificarStockDisponible antes de insertarla; si falta stock hace
--    ROLLBACK de toda la venta y relanza el error (SIGNAL) al llamador.
--    NOTA: no decrementa el stock ni recalcula ventas.total a mano: los
--    triggers trg_decrementar_stock y trg_recalcular_total_venta_insert
--    (05_Triggers.sql) ya lo hacen automaticamente en cada INSERT sobre
--    detalle_ventas. Al finalizar (con exito o con error) se elimina la
--    tabla temporal, por lo que cada llamada requiere volver a crearla
--    y poblarla.
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_RealizarVenta(
  IN p_id_cliente   INT,
  IN p_id_sucursal  INT,
  IN p_id_promocion INT
)
BEGIN
  DECLARE v_id_venta   INT UNSIGNED;
  DECLARE v_id_producto INT;
  DECLARE v_cantidad    INT;
  DECLARE v_fin         INT DEFAULT 0;

  DECLARE cur_items CURSOR FOR SELECT id_producto, cantidad FROM tmp_venta_items;
  DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_fin = 1;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    ROLLBACK;
    RESIGNAL;
  END;

  START TRANSACTION;

  INSERT INTO ventas (id_cliente, id_sucursal, id_promocion, estado, total)
  VALUES (p_id_cliente, p_id_sucursal, p_id_promocion, 'Pendiente de Pago', 0.00);
  SET v_id_venta = LAST_INSERT_ID();

  OPEN cur_items;
  bucle_items: LOOP
    FETCH cur_items INTO v_id_producto, v_cantidad;
    IF v_fin = 1 THEN
      LEAVE bucle_items;
    END IF;

    IF NOT fn_VerificarStockDisponible(v_id_producto, v_cantidad) THEN
      SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Stock insuficiente para completar la venta';
    END IF;

    INSERT INTO detalle_ventas (id_venta, id_producto, cantidad, precio_unitario_congelado)
    VALUES (v_id_venta, v_id_producto, v_cantidad, fn_ObtenerPrecioActual(v_id_producto));
  END LOOP;
  CLOSE cur_items;

  COMMIT;

  DROP TEMPORARY TABLE IF EXISTS tmp_venta_items;

  SELECT v_id_venta AS id_venta_generada;
END$$

-- ---------------------------------------------------------------------
-- 2. sp_AgregarProducto
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_AgregarProducto(
  IN p_nombre       VARCHAR(150),
  IN p_descripcion  TEXT,
  IN p_precio       DECIMAL(10,2),
  IN p_costo        DECIMAL(10,2),
  IN p_stock        INT,
  IN p_sku          VARCHAR(50),
  IN p_id_categoria INT,
  IN p_id_proveedor INT,
  IN p_peso_kg      DECIMAL(6,3)
)
BEGIN
  INSERT INTO productos (nombre, descripcion, precio, costo, stock, sku, id_categoria, id_proveedor, peso_kg)
  VALUES (p_nombre, p_descripcion, p_precio, p_costo, p_stock, p_sku, p_id_categoria, p_id_proveedor, p_peso_kg);

  SELECT LAST_INSERT_ID() AS id_producto_generado;
END$$

-- ---------------------------------------------------------------------
-- 3. sp_ActualizarDireccionCliente
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_ActualizarDireccionCliente(
  IN p_id_cliente      INT,
  IN p_nueva_direccion VARCHAR(255)
)
BEGIN
  UPDATE clientes
    SET direccion_envio = p_nueva_direccion
    WHERE id_cliente = p_id_cliente;
END$$

-- ---------------------------------------------------------------------
-- 4. sp_ProcesarDevolucion
--    Transaccional: registra la devolucion, repone stock del producto y
--    acredita saldo_credito al cliente dueno de la venta original.
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_ProcesarDevolucion(
  IN p_id_detalle        INT,
  IN p_cantidad_devuelta INT,
  IN p_motivo            VARCHAR(255)
)
BEGIN
  DECLARE v_id_producto     INT;
  DECLARE v_id_venta        INT;
  DECLARE v_id_cliente      INT;
  DECLARE v_precio_unitario DECIMAL(10,2);
  DECLARE v_monto_credito   DECIMAL(10,2);

  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    ROLLBACK;
    RESIGNAL;
  END;

  START TRANSACTION;

  SELECT dv.id_producto, dv.id_venta, dv.precio_unitario_congelado
    INTO v_id_producto, v_id_venta, v_precio_unitario
    FROM detalle_ventas dv
    WHERE dv.id_detalle = p_id_detalle;

  IF v_id_producto IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El detalle de venta indicado no existe';
  END IF;

  SELECT v.id_cliente INTO v_id_cliente FROM ventas v WHERE v.id_venta = v_id_venta;

  SET v_monto_credito = ROUND(v_precio_unitario * p_cantidad_devuelta, 2);

  INSERT INTO devoluciones (id_detalle, cantidad_devuelta, motivo, monto_credito, estado)
  VALUES (p_id_detalle, p_cantidad_devuelta, p_motivo, v_monto_credito, 'Procesada');

  UPDATE productos SET stock = stock + p_cantidad_devuelta WHERE id_producto = v_id_producto;

  UPDATE clientes SET saldo_credito = saldo_credito + v_monto_credito WHERE id_cliente = v_id_cliente;

  COMMIT;
END$$

-- ---------------------------------------------------------------------
-- 5. sp_ObtenerHistorialCompras
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_ObtenerHistorialCompras(IN p_id_cliente INT)
BEGIN
  SELECT v.id_venta, v.fecha_venta, v.estado, v.total, v.metodo_pago,
         d.id_detalle, d.id_producto, p.nombre AS nombre_producto,
         d.cantidad, d.precio_unitario_congelado, d.subtotal
    FROM ventas v
    JOIN detalle_ventas d ON d.id_venta = v.id_venta
    JOIN productos p ON p.id_producto = d.id_producto
    WHERE v.id_cliente = p_id_cliente
    ORDER BY v.fecha_venta DESC, v.id_venta, d.id_detalle;
END$$

-- ---------------------------------------------------------------------
-- 6. sp_AjustarStockManual
--    p_cantidad_ajustada puede ser positiva (entrada de mercancia) o
--    negativa (merma/perdida); se valida que el resultado no sea negativo
--    antes de aplicar el UPDATE.
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_AjustarStockManual(
  IN p_id_producto       INT,
  IN p_cantidad_ajustada INT,
  IN p_motivo            VARCHAR(255)
)
BEGIN
  DECLARE v_stock_actual INT;

  SELECT stock INTO v_stock_actual FROM productos WHERE id_producto = p_id_producto;

  IF v_stock_actual IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Producto no encontrado';
  END IF;

  IF (v_stock_actual + p_cantidad_ajustada) < 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El ajuste dejaria el stock en un valor negativo';
  END IF;

  UPDATE productos SET stock = stock + p_cantidad_ajustada WHERE id_producto = p_id_producto;

  INSERT INTO log_ajustes_stock (id_producto, cantidad_ajustada, motivo, usuario_bd)
  VALUES (p_id_producto, p_cantidad_ajustada, p_motivo, CURRENT_USER());
END$$

-- ---------------------------------------------------------------------
-- 7. sp_EliminarClienteSeguro
--    Anonimiza en lugar de borrar fisicamente al cliente.
--    A proposito NO abre su propia transaccion (START TRANSACTION/COMMIT):
--    en MySQL, ejecutar START TRANSACTION mientras ya se esta dentro de
--    una transaccion hace un COMMIT implicito de la transaccion en curso,
--    lo que romperia la atomicidad de sp_FusionarCuentasCliente (que SI
--    es transaccional y llama a este procedimiento). Al no gestionar su
--    propia transaccion, este procedimiento es seguro tanto si se llama
--    de forma independiente (bajo autocommit) como si se llama anidado
--    dentro de la transaccion de otro procedimiento.
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_EliminarClienteSeguro(IN p_id_cliente INT)
BEGIN
  UPDATE clientes
    SET nombre          = 'Cliente',
        apellido        = 'Anonimizado',
        email           = CONCAT('anon_', p_id_cliente, '@anon.local'),
        direccion_envio = NULL,
        anonimizado     = TRUE,
        activo          = FALSE
    WHERE id_cliente = p_id_cliente;

  INSERT INTO auditoria_clientes (id_cliente, accion, usuario_bd)
  VALUES (p_id_cliente, 'ANONIMIZACION', CURRENT_USER());
END$$

-- ---------------------------------------------------------------------
-- 8. sp_AplicarDescuentoCategoria
--    Crea una promocion de tipo Porcentaje vigente por 30 dias para
--    todos los productos de una categoria.
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_AplicarDescuentoCategoria(
  IN p_id_categoria INT,
  IN p_porcentaje   DECIMAL(5,2)
)
BEGIN
  DECLARE v_codigo VARCHAR(30);
  SET v_codigo = CONCAT('AUTO-C', p_id_categoria, '-', UNIX_TIMESTAMP());

  INSERT INTO promociones (codigo, descripcion, tipo_descuento, valor_descuento, id_categoria, fecha_inicio, fecha_fin, activa)
  VALUES (
    v_codigo,
    CONCAT('Descuento automatico del ', p_porcentaje, '% para la categoria ', p_id_categoria),
    'Porcentaje',
    p_porcentaje,
    p_id_categoria,
    NOW(),
    DATE_ADD(NOW(), INTERVAL 30 DAY),
    TRUE
  );

  SELECT LAST_INSERT_ID() AS id_promocion_generada;
END$$

-- ---------------------------------------------------------------------
-- 9. sp_GenerarReporteMensual
--    Calcula agregados de ventas/margen del anio/mes indicado e
--    inserta/actualiza la fila correspondiente en kpis_mensuales
--    (misma logica que evt_calculate_monthly_kpis de 06_Eventos.sql,
--    pero parametrizable a cualquier mes, no solo "el mes anterior").
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_GenerarReporteMensual(
  IN p_anio INT,
  IN p_mes  INT
)
BEGIN
  DECLARE v_ventas_totales  DECIMAL(14,2);
  DECLARE v_num_ventas      INT UNSIGNED;
  DECLARE v_nuevos_clientes INT UNSIGNED;
  DECLARE v_ticket_promedio DECIMAL(10,2);
  DECLARE v_margen_total    DECIMAL(14,2);

  SELECT COALESCE(SUM(total), 0), COUNT(*)
    INTO v_ventas_totales, v_num_ventas
    FROM ventas
    WHERE estado <> 'Cancelado'
      AND YEAR(fecha_venta) = p_anio
      AND MONTH(fecha_venta) = p_mes;

  SET v_ticket_promedio = IF(v_num_ventas = 0, 0, ROUND(v_ventas_totales / v_num_ventas, 2));

  SELECT COUNT(*) INTO v_nuevos_clientes
    FROM clientes
    WHERE YEAR(fecha_registro) = p_anio AND MONTH(fecha_registro) = p_mes;

  SELECT COALESCE(SUM((dv.precio_unitario_congelado - p.costo) * dv.cantidad), 0)
    INTO v_margen_total
    FROM detalle_ventas dv
    JOIN ventas v ON v.id_venta = dv.id_venta
    JOIN productos p ON p.id_producto = dv.id_producto
    WHERE v.estado <> 'Cancelado'
      AND YEAR(v.fecha_venta) = p_anio
      AND MONTH(v.fecha_venta) = p_mes;

  INSERT INTO kpis_mensuales (anio, mes, ventas_totales, num_ventas, nuevos_clientes, ticket_promedio, margen_total)
  VALUES (p_anio, p_mes, v_ventas_totales, v_num_ventas, v_nuevos_clientes, v_ticket_promedio, v_margen_total)
  ON DUPLICATE KEY UPDATE
    ventas_totales  = v_ventas_totales,
    num_ventas      = v_num_ventas,
    nuevos_clientes = v_nuevos_clientes,
    ticket_promedio = v_ticket_promedio,
    margen_total    = v_margen_total,
    fecha_calculo   = CURRENT_TIMESTAMP;
END$$

-- ---------------------------------------------------------------------
-- 10. sp_CambiarEstadoPedido
--     El log de log_estado_pedido lo genera automaticamente
--     trg_log_estado_pedido (05_Triggers.sql) en cada UPDATE que cambie
--     el estado; este procedimiento solo valida el nuevo estado contra
--     los 5 valores del ENUM antes de aplicar el cambio.
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_CambiarEstadoPedido(
  IN p_id_venta     INT,
  IN p_nuevo_estado VARCHAR(30)
)
BEGIN
  IF p_nuevo_estado NOT IN ('Pendiente de Pago','Procesando','Enviado','Entregado','Cancelado') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Estado de pedido no valido';
  END IF;

  UPDATE ventas SET estado = p_nuevo_estado WHERE id_venta = p_id_venta;
END$$

-- ---------------------------------------------------------------------
-- 11. sp_RegistrarCliente
--     El alta en auditoria_clientes (accion='ALTA') la genera
--     automaticamente trg_log_nuevo_cliente (05_Triggers.sql) tras el
--     INSERT; este procedimiento se encarga de las validaciones previas.
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_RegistrarCliente(
  IN p_nombre         VARCHAR(100),
  IN p_apellido       VARCHAR(100),
  IN p_email          VARCHAR(150),
  IN p_password_plano VARCHAR(255),
  IN p_direccion      VARCHAR(255)
)
BEGIN
  IF NOT fn_ValidarFormatoEmail(p_email) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Formato de correo electronico invalido';
  END IF;

  IF NOT fn_ValidarComplejidadContrasena(p_password_plano) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La contrasena no cumple los requisitos minimos de complejidad';
  END IF;

  IF EXISTS (SELECT 1 FROM clientes WHERE email = p_email) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Ya existe un cliente registrado con ese correo electronico';
  END IF;

  INSERT INTO clientes (nombre, apellido, email, contrasena_hash, direccion_envio)
  VALUES (p_nombre, p_apellido, p_email, SHA2(p_password_plano, 256), p_direccion);

  SELECT LAST_INSERT_ID() AS id_cliente_generado;
END$$

-- ---------------------------------------------------------------------
-- 12. sp_ObtenerDetalleProducto
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_ObtenerDetalleProducto(IN p_id_producto INT)
BEGIN
  SELECT p.id_producto, p.nombre, p.descripcion, p.precio, p.costo, p.stock,
         p.sku, p.activo, p.peso_kg, p.stock_minimo, p.ubicacion_almacen,
         c.id_categoria, c.nombre AS nombre_categoria,
         pr.id_proveedor, pr.nombre AS nombre_proveedor, pr.email_contacto AS proveedor_email
    FROM productos p
    LEFT JOIN categorias c ON c.id_categoria = p.id_categoria
    LEFT JOIN proveedores pr ON pr.id_proveedor = p.id_proveedor
    WHERE p.id_producto = p_id_producto;
END$$

-- ---------------------------------------------------------------------
-- 13. sp_FusionarCuentasCliente
--     Transaccional: reasigna las ventas y resenas del cliente duplicado
--     hacia el cliente principal y luego anonimiza al duplicado (llamando
--     a sp_EliminarClienteSeguro, que NO abre su propia transaccion, ver
--     su comentario, para no cortar esta transaccion a la mitad).
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_FusionarCuentasCliente(
  IN p_id_cliente_principal  INT,
  IN p_id_cliente_duplicado  INT
)
BEGIN
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    ROLLBACK;
    RESIGNAL;
  END;

  IF p_id_cliente_principal = p_id_cliente_duplicado THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El cliente principal y el duplicado no pueden ser el mismo';
  END IF;

  START TRANSACTION;

  UPDATE ventas SET id_cliente = p_id_cliente_principal WHERE id_cliente = p_id_cliente_duplicado;

  -- Reasignar resenas evitando violar la UNIQUE(id_producto, id_cliente):
  -- UPDATE IGNORE mueve las que no chocan y deja intactas (con el
  -- id_cliente del duplicado) las que colisionan porque el cliente
  -- principal ya reseno ese mismo producto; esas ultimas se descartan
  -- con el DELETE siguiente, ya que la resena del principal prevalece.
  UPDATE IGNORE resenas_productos
    SET id_cliente = p_id_cliente_principal
    WHERE id_cliente = p_id_cliente_duplicado;

  DELETE FROM resenas_productos WHERE id_cliente = p_id_cliente_duplicado;

  CALL sp_EliminarClienteSeguro(p_id_cliente_duplicado);

  COMMIT;
END$$

-- ---------------------------------------------------------------------
-- 14. sp_AsignarProveedor
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_AsignarProveedor(
  IN p_id_producto  INT,
  IN p_id_proveedor INT
)
BEGIN
  UPDATE productos SET id_proveedor = p_id_proveedor WHERE id_producto = p_id_producto;
END$$

-- ---------------------------------------------------------------------
-- 15. sp_BuscarProductosFiltro
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_BuscarProductosFiltro(
  IN p_nombre        VARCHAR(150),
  IN p_id_categoria  INT,
  IN p_precio_min    DECIMAL(10,2),
  IN p_precio_max    DECIMAL(10,2)
)
BEGIN
  SELECT p.id_producto, p.nombre, p.precio, p.stock, p.sku,
         p.id_categoria, p.id_proveedor, p.activo
    FROM productos p
    WHERE (p_nombre IS NULL OR p.nombre LIKE CONCAT('%', p_nombre, '%'))
      AND (p_id_categoria IS NULL OR p.id_categoria = p_id_categoria)
      AND (p_precio_min IS NULL OR p.precio >= p_precio_min)
      AND (p_precio_max IS NULL OR p.precio <= p_precio_max)
      AND p.eliminado = FALSE
    ORDER BY p.nombre;
END$$

-- ---------------------------------------------------------------------
-- 16. sp_DashboardAdmin
--     Devuelve varios result sets en una sola llamada: ventas de hoy,
--     nuevos clientes de hoy, top 5 productos del mes en curso y alertas
--     de stock pendientes de atender.
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_DashboardAdmin()
BEGIN
  -- 1) Ventas de hoy (conteo y suma)
  SELECT COUNT(*) AS num_ventas_hoy, COALESCE(SUM(total), 0) AS total_ventas_hoy
    FROM ventas
    WHERE DATE(fecha_venta) = CURDATE()
      AND estado <> 'Cancelado';

  -- 2) Nuevos clientes de hoy
  SELECT COUNT(*) AS nuevos_clientes_hoy
    FROM clientes
    WHERE DATE(fecha_registro) = CURDATE();

  -- 3) Top 5 productos del mes en curso (por unidades vendidas)
  SELECT p.id_producto, p.nombre, SUM(d.cantidad) AS unidades_vendidas
    FROM detalle_ventas d
    JOIN ventas v ON v.id_venta = d.id_venta
    JOIN productos p ON p.id_producto = d.id_producto
    WHERE YEAR(v.fecha_venta) = YEAR(CURDATE())
      AND MONTH(v.fecha_venta) = MONTH(CURDATE())
      AND v.estado <> 'Cancelado'
    GROUP BY p.id_producto, p.nombre
    ORDER BY unidades_vendidas DESC
    LIMIT 5;

  -- 4) Alertas de stock pendientes de atender
  SELECT a.id_alerta, a.id_producto, p.nombre, a.stock_actual, a.stock_minimo,
         a.origen, a.fecha_alerta
    FROM alertas_stock a
    JOIN productos p ON p.id_producto = a.id_producto
    WHERE a.atendida = FALSE
    ORDER BY a.fecha_alerta DESC;
END$$

-- ---------------------------------------------------------------------
-- 17. sp_ProcesarPago
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_ProcesarPago(
  IN p_id_venta    INT,
  IN p_metodo_pago VARCHAR(30)
)
BEGIN
  UPDATE ventas
    SET estado = 'Procesando', fecha_pago = NOW(), metodo_pago = p_metodo_pago
    WHERE id_venta = p_id_venta;
END$$

-- ---------------------------------------------------------------------
-- 18. sp_AnadirResenaProducto
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_AnadirResenaProducto(
  IN p_id_producto  INT,
  IN p_id_cliente   INT,
  IN p_calificacion TINYINT,
  IN p_comentario   TEXT
)
BEGIN
  IF p_calificacion < 1 OR p_calificacion > 5 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La calificacion debe estar entre 1 y 5';
  END IF;

  INSERT INTO resenas_productos (id_producto, id_cliente, calificacion, comentario)
  VALUES (p_id_producto, p_id_cliente, p_calificacion, p_comentario);
END$$

-- ---------------------------------------------------------------------
-- 19. sp_ObtenerProductosRelacionados
--     Self-join de detalle_ventas por id_venta: productos comprados junto
--     con p_id_producto, agrupados y ordenados por frecuencia.
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_ObtenerProductosRelacionados(IN p_id_producto INT)
BEGIN
  SELECT d2.id_producto AS id_producto_relacionado,
         p.nombre AS nombre_producto,
         COUNT(*) AS veces_comprado_junto
    FROM detalle_ventas d1
    JOIN detalle_ventas d2 ON d2.id_venta = d1.id_venta AND d2.id_producto <> d1.id_producto
    JOIN productos p ON p.id_producto = d2.id_producto
    WHERE d1.id_producto = p_id_producto
    GROUP BY d2.id_producto, p.nombre
    ORDER BY veces_comprado_junto DESC
    LIMIT 10;
END$$

-- ---------------------------------------------------------------------
-- 20. sp_MoverProductosEntreCategorias
--     El recalculo de categorias.total_productos para ambas categorias
--     lo realiza automaticamente trg_contador_productos_categoria_update
--     (05_Triggers.sql) al detectar el cambio de id_categoria.
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_MoverProductosEntreCategorias(
  IN p_id_categoria_origen  INT,
  IN p_id_categoria_destino INT
)
BEGIN
  UPDATE productos
    SET id_categoria = p_id_categoria_destino
    WHERE id_categoria = p_id_categoria_origen;
END$$

-- ---------------------------------------------------------------------
-- 21. sp_LoginCliente  [ADICIONAL DE SOPORTE]
--     Simula la autenticacion de los CLIENTES de la tienda (aplicacion),
--     NO la autenticacion de usuarios/roles del servidor MySQL (esa la
--     gestiona 04_Seguridad.sql con CREATE USER/GRANT). Compara el hash
--     SHA2 de la contrasena en texto plano contra clientes.contrasena_hash
--     y deja constancia de cada intento (exitoso o no) en
--     log_intentos_login, tabla que ya existia en 01_Esquema_y_Datos.sql
--     y que ademas alimenta evt_detect_fraudulent_activity_hourly
--     (06_Eventos.sql).
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_LoginCliente(
  IN p_email          VARCHAR(150),
  IN p_password_plano VARCHAR(255)
)
BEGIN
  DECLARE v_id_cliente INT;
  DECLARE v_hash       VARCHAR(255);
  DECLARE v_activo     BOOLEAN;

  SELECT id_cliente, contrasena_hash, activo
    INTO v_id_cliente, v_hash, v_activo
    FROM clientes
    WHERE email = p_email
    LIMIT 1;

  IF v_id_cliente IS NULL THEN
    INSERT INTO log_intentos_login (email_intento, id_cliente, exitoso, motivo_fallo)
    VALUES (p_email, NULL, FALSE, 'Email no registrado');

    SELECT FALSE AS login_exitoso, NULL AS id_cliente, 'Credenciales invalidas' AS mensaje;

  ELSEIF v_activo = FALSE THEN
    INSERT INTO log_intentos_login (email_intento, id_cliente, exitoso, motivo_fallo)
    VALUES (p_email, v_id_cliente, FALSE, 'Cuenta inactiva o anonimizada');

    SELECT FALSE AS login_exitoso, NULL AS id_cliente, 'Cuenta inactiva' AS mensaje;

  ELSEIF SHA2(p_password_plano, 256) = v_hash THEN
    INSERT INTO log_intentos_login (email_intento, id_cliente, exitoso)
    VALUES (p_email, v_id_cliente, TRUE);

    SELECT TRUE AS login_exitoso, v_id_cliente AS id_cliente, 'Login exitoso' AS mensaje;

  ELSE
    INSERT INTO log_intentos_login (email_intento, id_cliente, exitoso, motivo_fallo)
    VALUES (p_email, v_id_cliente, FALSE, 'Contrasena incorrecta');

    SELECT FALSE AS login_exitoso, NULL AS id_cliente, 'Credenciales invalidas' AS mensaje;
  END IF;
END$$

-- ---------------------------------------------------------------------
-- 22. sp_OtorgarPermiso  [ADICIONAL DE SOPORTE]
--     MySQL no dispara triggers ante sentencias DCL (GRANT/REVOKE), por lo
--     que no existe forma de auditar un GRANT con un trigger real; este
--     procedimiento reemplaza esa auditoria envolviendo el GRANT en SQL
--     dinamico y registrando el evento en log_permisos. Por seguridad,
--     p_rol se valida contra la lista cerrada de roles definidos en
--     04_Seguridad.sql (nunca se interpola sin validar) y p_usuario se
--     valida con una expresion regular que solo permite los caracteres
--     validos de un identificador de cuenta de MySQL ('usuario'@'host').
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_OtorgarPermiso(
  IN p_rol     VARCHAR(100),
  IN p_usuario VARCHAR(100)
)
BEGIN
  IF p_rol NOT IN ('Administrador_Sistema','Gerente_Marketing','Analista_Datos',
                    'Empleado_Inventario','Atencion_Cliente','Auditor_Financiero','Visitante') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Rol no reconocido; operacion de GRANT abortada por seguridad';
  END IF;

  IF p_usuario NOT REGEXP '^[A-Za-z0-9_.%@''-]+$' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Nombre de usuario con caracteres no permitidos';
  END IF;

  SET @sql_grant = CONCAT('GRANT `', p_rol, '` TO ', p_usuario);
  PREPARE stmt_grant FROM @sql_grant;
  EXECUTE stmt_grant;
  DEALLOCATE PREPARE stmt_grant;

  INSERT INTO log_permisos (usuario_bd, rol_afectado, accion, detalle, ejecutado_por)
  VALUES (p_usuario, p_rol, 'GRANT', CONCAT('Rol ', p_rol, ' otorgado a ', p_usuario), CURRENT_USER());
END$$

-- ---------------------------------------------------------------------
-- 23. sp_RevocarPermiso  [ADICIONAL DE SOPORTE]
--     Analogo a sp_OtorgarPermiso, pero para REVOKE; existe por la misma
--     limitacion de MySQL frente a triggers y sentencias DCL.
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_RevocarPermiso(
  IN p_rol     VARCHAR(100),
  IN p_usuario VARCHAR(100)
)
BEGIN
  IF p_rol NOT IN ('Administrador_Sistema','Gerente_Marketing','Analista_Datos',
                    'Empleado_Inventario','Atencion_Cliente','Auditor_Financiero','Visitante') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Rol no reconocido; operacion de REVOKE abortada por seguridad';
  END IF;

  IF p_usuario NOT REGEXP '^[A-Za-z0-9_.%@''-]+$' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Nombre de usuario con caracteres no permitidos';
  END IF;

  SET @sql_revoke = CONCAT('REVOKE `', p_rol, '` FROM ', p_usuario);
  PREPARE stmt_revoke FROM @sql_revoke;
  EXECUTE stmt_revoke;
  DEALLOCATE PREPARE stmt_revoke;

  INSERT INTO log_permisos (usuario_bd, rol_afectado, accion, detalle, ejecutado_por)
  VALUES (p_usuario, p_rol, 'REVOKE', CONCAT('Rol ', p_rol, ' revocado de ', p_usuario), CURRENT_USER());
END$$

DELIMITER ;

-- =====================================================================
-- FIN DE 07_Procedimientos_Almacenados.sql
-- =====================================================================
