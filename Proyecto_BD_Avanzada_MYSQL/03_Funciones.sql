-- =====================================================================
-- 03_Funciones.sql
-- Proyecto de Base de Datos para un E-commerce — Funciones almacenadas
-- Motor: MySQL 8.x
-- Requiere que 01_Esquema_y_Datos.sql ya haya sido ejecutado sobre
-- la base de datos ecommerce_avanzado.
-- =====================================================================

-- Permite crear funciones que leen/escriben datos sin exigir DETERMINISTIC
-- estricto cuando el binlog está en modo STATEMENT/MIXED (evita el error
-- "This function has none of DETERMINISTIC..." en modo estricto).
SET GLOBAL log_bin_trust_function_creators = 1;

USE ecommerce_avanzado;

DROP FUNCTION IF EXISTS fn_CalcularTotalVenta;
DROP FUNCTION IF EXISTS fn_VerificarStockDisponible;
DROP FUNCTION IF EXISTS fn_ObtenerPrecioActual;
DROP FUNCTION IF EXISTS fn_CalcularEdadCliente;
DROP FUNCTION IF EXISTS fn_FormatearNombreCompleto;
DROP FUNCTION IF EXISTS fn_EsClienteNuevo;
DROP FUNCTION IF EXISTS fn_CalcularCostoEnvio;
DROP FUNCTION IF EXISTS fn_AplicarDescuento;
DROP FUNCTION IF EXISTS fn_ObtenerFechaUltimaCompra;
DROP FUNCTION IF EXISTS fn_ValidarFormatoEmail;
DROP FUNCTION IF EXISTS fn_ObtenerNombreCategoria;
DROP FUNCTION IF EXISTS fn_ContarVentasCliente;
DROP FUNCTION IF EXISTS fn_DiasDesdeUltimaCompra;
DROP FUNCTION IF EXISTS fn_DeterminarNivelLealtad;
DROP FUNCTION IF EXISTS fn_GenerarSKU;
DROP FUNCTION IF EXISTS fn_CalcularIVA;
DROP FUNCTION IF EXISTS fn_SumarStockPorCategoria;
DROP FUNCTION IF EXISTS fn_EstimarFechaEntrega;
DROP FUNCTION IF EXISTS fn_ConvertirMoneda;
DROP FUNCTION IF EXISTS fn_ValidarComplejidadContrasena;

DELIMITER $$

-- ---------------------------------------------------------------------
-- 1. fn_CalcularTotalVenta
--    Suma el subtotal de todas las líneas de detalle_ventas de una venta.
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_CalcularTotalVenta(p_id_venta INT)
RETURNS DECIMAL(12,2)
READS SQL DATA
BEGIN
  DECLARE v_total DECIMAL(12,2);
  SELECT COALESCE(SUM(subtotal), 0.00)
    INTO v_total
    FROM detalle_ventas
    WHERE id_venta = p_id_venta;
  RETURN v_total;
END$$

-- ---------------------------------------------------------------------
-- 2. fn_VerificarStockDisponible
--    TRUE si el stock actual del producto alcanza la cantidad solicitada.
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_VerificarStockDisponible(p_id_producto INT, p_cantidad INT)
RETURNS BOOLEAN
READS SQL DATA
BEGIN
  DECLARE v_stock INT;
  SELECT stock INTO v_stock FROM productos WHERE id_producto = p_id_producto;
  RETURN COALESCE(v_stock, 0) >= p_cantidad;
END$$

-- ---------------------------------------------------------------------
-- 3. fn_ObtenerPrecioActual
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_ObtenerPrecioActual(p_id_producto INT)
RETURNS DECIMAL(10,2)
READS SQL DATA
BEGIN
  DECLARE v_precio DECIMAL(10,2);
  SELECT precio INTO v_precio FROM productos WHERE id_producto = p_id_producto;
  RETURN v_precio;
END$$

-- ---------------------------------------------------------------------
-- 4. fn_CalcularEdadCliente
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_CalcularEdadCliente(p_id_cliente INT)
RETURNS INT
READS SQL DATA
BEGIN
  DECLARE v_fecha_nacimiento DATE;
  SELECT fecha_nacimiento INTO v_fecha_nacimiento
    FROM clientes WHERE id_cliente = p_id_cliente;
  IF v_fecha_nacimiento IS NULL THEN
    RETURN NULL;
  END IF;
  RETURN TIMESTAMPDIFF(YEAR, v_fecha_nacimiento, CURDATE());
END$$

-- ---------------------------------------------------------------------
-- 5. fn_FormatearNombreCompleto
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_FormatearNombreCompleto(p_id_cliente INT)
RETURNS VARCHAR(200)
READS SQL DATA
BEGIN
  DECLARE v_nombre_completo VARCHAR(200);
  SELECT CONCAT(nombre, ' ', apellido) INTO v_nombre_completo
    FROM clientes WHERE id_cliente = p_id_cliente;
  RETURN v_nombre_completo;
END$$

-- ---------------------------------------------------------------------
-- 6. fn_EsClienteNuevo
--    TRUE si la primera compra del cliente ocurrió hace menos de
--    dias_cliente_nuevo días (configuracion_sistema). FALSE si nunca
--    ha comprado.
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_EsClienteNuevo(p_id_cliente INT)
RETURNS BOOLEAN
READS SQL DATA
BEGIN
  DECLARE v_primera_compra DATETIME;
  DECLARE v_dias_cliente_nuevo INT;

  SELECT MIN(fecha_venta) INTO v_primera_compra
    FROM ventas WHERE id_cliente = p_id_cliente;

  IF v_primera_compra IS NULL THEN
    RETURN FALSE;
  END IF;

  SELECT CAST(valor AS UNSIGNED) INTO v_dias_cliente_nuevo
    FROM configuracion_sistema WHERE clave = 'dias_cliente_nuevo';

  RETURN DATEDIFF(NOW(), v_primera_compra) < v_dias_cliente_nuevo;
END$$

-- ---------------------------------------------------------------------
-- 7. fn_CalcularCostoEnvio
--    peso_kg del producto * cantidad * costo_envio_por_kg (config).
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_CalcularCostoEnvio(p_id_producto INT, p_cantidad INT)
RETURNS DECIMAL(10,2)
READS SQL DATA
BEGIN
  DECLARE v_peso_kg DECIMAL(6,3);
  DECLARE v_costo_por_kg DECIMAL(10,4);

  SELECT peso_kg INTO v_peso_kg FROM productos WHERE id_producto = p_id_producto;
  SELECT CAST(valor AS DECIMAL(10,4)) INTO v_costo_por_kg
    FROM configuracion_sistema WHERE clave = 'costo_envio_por_kg';

  RETURN ROUND(COALESCE(v_peso_kg, 0) * p_cantidad * COALESCE(v_costo_por_kg, 0), 2);
END$$

-- ---------------------------------------------------------------------
-- 8. fn_AplicarDescuento
--    Función pura: monto - (monto * porcentaje / 100).
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_AplicarDescuento(p_monto DECIMAL(10,2), p_porcentaje DECIMAL(5,2))
RETURNS DECIMAL(10,2)
DETERMINISTIC
NO SQL
BEGIN
  RETURN ROUND(p_monto - (p_monto * p_porcentaje / 100), 2);
END$$

-- ---------------------------------------------------------------------
-- 9. fn_ObtenerFechaUltimaCompra
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_ObtenerFechaUltimaCompra(p_id_cliente INT)
RETURNS DATETIME
READS SQL DATA
BEGIN
  DECLARE v_fecha DATETIME;
  SELECT fecha_ultima_compra INTO v_fecha
    FROM clientes WHERE id_cliente = p_id_cliente;
  RETURN v_fecha;
END$$

-- ---------------------------------------------------------------------
-- 10. fn_ValidarFormatoEmail
--     Validación básica de formato de email vía REGEXP.
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_ValidarFormatoEmail(p_email VARCHAR(150))
RETURNS BOOLEAN
DETERMINISTIC
NO SQL
BEGIN
  RETURN p_email REGEXP '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$';
END$$

-- ---------------------------------------------------------------------
-- 11. fn_ObtenerNombreCategoria
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_ObtenerNombreCategoria(p_id_producto INT)
RETURNS VARCHAR(100)
READS SQL DATA
BEGIN
  DECLARE v_nombre_categoria VARCHAR(100);
  SELECT c.nombre INTO v_nombre_categoria
    FROM productos p
    LEFT JOIN categorias c ON c.id_categoria = p.id_categoria
    WHERE p.id_producto = p_id_producto;
  RETURN COALESCE(v_nombre_categoria, 'Sin categoria');
END$$

-- ---------------------------------------------------------------------
-- 12. fn_ContarVentasCliente
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_ContarVentasCliente(p_id_cliente INT)
RETURNS INT
READS SQL DATA
BEGIN
  DECLARE v_conteo INT;
  SELECT COUNT(*) INTO v_conteo FROM ventas WHERE id_cliente = p_id_cliente;
  RETURN v_conteo;
END$$

-- ---------------------------------------------------------------------
-- 13. fn_DiasDesdeUltimaCompra
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_DiasDesdeUltimaCompra(p_id_cliente INT)
RETURNS INT
READS SQL DATA
BEGIN
  DECLARE v_fecha_ultima_compra DATETIME;
  SELECT fecha_ultima_compra INTO v_fecha_ultima_compra
    FROM clientes WHERE id_cliente = p_id_cliente;
  IF v_fecha_ultima_compra IS NULL THEN
    RETURN NULL;
  END IF;
  RETURN DATEDIFF(NOW(), v_fecha_ultima_compra);
END$$

-- ---------------------------------------------------------------------
-- 14. fn_DeterminarNivelLealtad
--     Umbrales leídos de configuracion_sistema (umbral_lealtad_plata=500,
--     umbral_lealtad_oro=2000).
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_DeterminarNivelLealtad(p_total_gastado DECIMAL(12,2))
RETURNS VARCHAR(20)
READS SQL DATA
BEGIN
  DECLARE v_umbral_plata DECIMAL(12,2);
  DECLARE v_umbral_oro DECIMAL(12,2);

  SELECT CAST(valor AS DECIMAL(12,2)) INTO v_umbral_plata
    FROM configuracion_sistema WHERE clave = 'umbral_lealtad_plata';
  SELECT CAST(valor AS DECIMAL(12,2)) INTO v_umbral_oro
    FROM configuracion_sistema WHERE clave = 'umbral_lealtad_oro';

  IF p_total_gastado >= v_umbral_oro THEN
    RETURN 'Oro';
  ELSEIF p_total_gastado >= v_umbral_plata THEN
    RETURN 'Plata';
  ELSE
    RETURN 'Bronce';
  END IF;
END$$

-- ---------------------------------------------------------------------
-- 15. fn_GenerarSKU
--     Genera un SKU tipo CAT{id}-{iniciales del nombre}-{numero aleatorio}.
--     No es determinística (usa RAND()).
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_GenerarSKU(p_nombre VARCHAR(150), p_id_categoria INT)
RETURNS VARCHAR(50)
NOT DETERMINISTIC
NO SQL
BEGIN
  DECLARE v_iniciales VARCHAR(10);
  DECLARE v_aleatorio VARCHAR(6);

  SET v_iniciales = UPPER(LEFT(REPLACE(REPLACE(p_nombre, ' ', ''), '-', ''), 6));
  SET v_aleatorio = LPAD(FLOOR(RAND() * 100000), 5, '0');

  RETURN CONCAT('CAT', COALESCE(p_id_categoria, 0), '-', v_iniciales, '-', v_aleatorio);
END$$

-- ---------------------------------------------------------------------
-- 16. fn_CalcularIVA
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_CalcularIVA(p_monto DECIMAL(12,2))
RETURNS DECIMAL(12,2)
READS SQL DATA
BEGIN
  DECLARE v_tasa_iva DECIMAL(6,4);
  SELECT CAST(valor AS DECIMAL(6,4)) INTO v_tasa_iva
    FROM configuracion_sistema WHERE clave = 'tasa_iva';
  RETURN ROUND(p_monto * v_tasa_iva, 2);
END$$

-- ---------------------------------------------------------------------
-- 17. fn_SumarStockPorCategoria
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_SumarStockPorCategoria(p_id_categoria INT)
RETURNS INT
READS SQL DATA
BEGIN
  DECLARE v_stock_total INT;
  SELECT COALESCE(SUM(stock), 0) INTO v_stock_total
    FROM productos WHERE id_categoria = p_id_categoria;
  RETURN v_stock_total;
END$$

-- ---------------------------------------------------------------------
-- 18. fn_EstimarFechaEntrega
--     Bogota: 2 días. Otras ciudades: 5 días.
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_EstimarFechaEntrega(p_id_cliente INT)
RETURNS DATE
READS SQL DATA
BEGIN
  DECLARE v_ciudad VARCHAR(100);
  DECLARE v_dias_entrega INT;

  SELECT ciudad INTO v_ciudad FROM clientes WHERE id_cliente = p_id_cliente;

  SET v_dias_entrega = CASE
    WHEN v_ciudad = 'Bogota' THEN 2
    WHEN v_ciudad IN ('Medellin', 'Cali') THEN 3
    WHEN v_ciudad IS NULL THEN 7
    ELSE 5
  END;

  RETURN DATE_ADD(CURDATE(), INTERVAL v_dias_entrega DAY);
END$$

-- ---------------------------------------------------------------------
-- 19. fn_ConvertirMoneda
--     Si p_moneda = 'USD' divide por tasa_cambio_usd; en otro caso
--     devuelve el monto sin cambios.
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_ConvertirMoneda(p_monto DECIMAL(12,2), p_moneda VARCHAR(10))
RETURNS DECIMAL(12,2)
READS SQL DATA
BEGIN
  DECLARE v_tasa_cambio_usd DECIMAL(12,4);

  IF UPPER(p_moneda) = 'USD' THEN
    SELECT CAST(valor AS DECIMAL(12,4)) INTO v_tasa_cambio_usd
      FROM configuracion_sistema WHERE clave = 'tasa_cambio_usd';
    RETURN ROUND(p_monto / v_tasa_cambio_usd, 2);
  ELSE
    RETURN p_monto;
  END IF;
END$$

-- ---------------------------------------------------------------------
-- 20. fn_ValidarComplejidadContrasena
--     TRUE si longitud >= 8 y contiene al menos una mayúscula, un
--     número y un símbolo.
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_ValidarComplejidadContrasena(p_password VARCHAR(255))
RETURNS BOOLEAN
DETERMINISTIC
NO SQL
BEGIN
  RETURN LENGTH(p_password) >= 8
     AND p_password REGEXP '[A-Z]'
     AND p_password REGEXP '[0-9]'
     AND p_password REGEXP '[^A-Za-z0-9]';
END$$

DELIMITER ;

-- =====================================================================
-- FIN DE 03_Funciones.sql
-- =====================================================================
