-- =====================================================================
-- 02_Consultas_Avanzadas.sql
-- 20 consultas SQL de analisis de negocio sobre el esquema de
-- 01_Esquema_y_Datos.sql (ecommerce_avanzado, MySQL 8.0)
-- =====================================================================

USE ecommerce_avanzado;

-- 1. Top 10 Productos Mas Vendidos (por ingresos generados)
SELECT
  p.id_producto,
  p.nombre,
  SUM(dv.subtotal) AS ingresos_totales
FROM detalle_ventas dv
JOIN productos p ON p.id_producto = dv.id_producto
JOIN ventas v ON v.id_venta = dv.id_venta
WHERE v.estado <> 'Cancelado'
GROUP BY p.id_producto, p.nombre
ORDER BY ingresos_totales DESC
LIMIT 10;

-- 2. Productos con Bajas Ventas (10% inferior segun unidades vendidas, incluye ventas = 0)
WITH ventas_por_producto AS (
  SELECT
    p.id_producto,
    p.nombre,
    COALESCE(SUM(dv.cantidad), 0) AS unidades_vendidas
  FROM productos p
  LEFT JOIN detalle_ventas dv ON dv.id_producto = p.id_producto
  LEFT JOIN ventas v ON v.id_venta = dv.id_venta AND v.estado <> 'Cancelado'
  GROUP BY p.id_producto, p.nombre
),
ranked AS (
  SELECT
    id_producto,
    nombre,
    unidades_vendidas,
    NTILE(10) OVER (ORDER BY unidades_vendidas ASC) AS decil
  FROM ventas_por_producto
)
SELECT id_producto, nombre, unidades_vendidas
FROM ranked
WHERE decil = 1
ORDER BY unidades_vendidas ASC;

-- 3. Clientes VIP (top 5 por LTV / total_gastado cacheado)
SELECT
  id_cliente,
  nombre,
  apellido,
  email,
  total_gastado,
  nivel_lealtad
FROM clientes
ORDER BY total_gastado DESC
LIMIT 5;

-- 4. Analisis de Ventas Mensuales
SELECT
  YEAR(fecha_venta) AS anio,
  MONTH(fecha_venta) AS mes,
  COUNT(*) AS num_ventas,
  SUM(total) AS total_ventas
FROM ventas
WHERE estado <> 'Cancelado'
GROUP BY YEAR(fecha_venta), MONTH(fecha_venta)
ORDER BY anio, mes;

-- 5. Crecimiento de Clientes (nuevos clientes por trimestre de registro)
SELECT
  YEAR(fecha_registro) AS anio,
  QUARTER(fecha_registro) AS trimestre,
  COUNT(*) AS nuevos_clientes
FROM clientes
GROUP BY YEAR(fecha_registro), QUARTER(fecha_registro)
ORDER BY anio, trimestre;

-- 6. Tasa de Compra Repetida (% de clientes con mas de una compra)
WITH compras_por_cliente AS (
  SELECT id_cliente, COUNT(*) AS num_compras
  FROM ventas
  WHERE estado <> 'Cancelado'
  GROUP BY id_cliente
)
SELECT
  COUNT(*) AS clientes_con_compra,
  SUM(CASE WHEN num_compras > 1 THEN 1 ELSE 0 END) AS clientes_con_recompra,
  ROUND(SUM(CASE WHEN num_compras > 1 THEN 1 ELSE 0 END) / COUNT(*) * 100, 2) AS pct_recompra
FROM compras_por_cliente;

-- 7. Productos Comprados Juntos Frecuentemente (self-join de detalle_ventas por id_venta)
SELECT
  a.id_producto AS id_producto_a,
  pa.nombre AS producto_a,
  b.id_producto AS id_producto_b,
  pb.nombre AS producto_b,
  COUNT(*) AS veces_comprados_juntos
FROM detalle_ventas a
JOIN detalle_ventas b ON a.id_venta = b.id_venta AND a.id_producto < b.id_producto
JOIN productos pa ON pa.id_producto = a.id_producto
JOIN productos pb ON pb.id_producto = b.id_producto
GROUP BY a.id_producto, pa.nombre, b.id_producto, pb.nombre
ORDER BY veces_comprados_juntos DESC
LIMIT 20;

-- 8. Rotacion de Inventario por Categoria (costo de lo vendido / stock promedio)
SELECT
  c.id_categoria,
  c.nombre,
  COALESCE(sold.costo_vendido, 0) AS costo_vendido,
  inv.stock_promedio,
  ROUND(COALESCE(sold.costo_vendido, 0) / NULLIF(inv.stock_promedio, 0), 2) AS rotacion_inventario
FROM categorias c
JOIN (
  SELECT id_categoria, AVG(stock) AS stock_promedio
  FROM productos
  GROUP BY id_categoria
) inv ON inv.id_categoria = c.id_categoria
LEFT JOIN (
  SELECT p.id_categoria, SUM(dv.cantidad * p.costo) AS costo_vendido
  FROM detalle_ventas dv
  JOIN productos p ON p.id_producto = dv.id_producto
  GROUP BY p.id_categoria
) sold ON sold.id_categoria = c.id_categoria
ORDER BY rotacion_inventario DESC;

-- 9. Productos que Necesitan Reabastecimiento
SELECT
  id_producto,
  nombre,
  stock,
  stock_minimo,
  (stock_minimo - stock) AS unidades_faltantes
FROM productos
WHERE stock <= stock_minimo
ORDER BY unidades_faltantes DESC;

-- 10. Analisis de Carrito Abandonado
SELECT
  cl.id_cliente,
  cl.nombre,
  cl.apellido,
  cl.email,
  ca.id_carrito,
  ca.fecha_creacion,
  ca.fecha_actualizacion,
  p.id_producto,
  p.nombre AS producto,
  ci.cantidad
FROM carritos ca
JOIN clientes cl ON cl.id_cliente = ca.id_cliente
JOIN carrito_items ci ON ci.id_carrito = ca.id_carrito
JOIN productos p ON p.id_producto = ci.id_producto
WHERE ca.estado = 'Abandonado'
ORDER BY ca.fecha_actualizacion DESC;

-- 11. Rendimiento de Proveedores (ranking por ingresos generados)
SELECT
  pr.id_proveedor,
  pr.nombre,
  SUM(dv.subtotal) AS ingresos_generados,
  SUM(dv.cantidad) AS unidades_vendidas
FROM proveedores pr
JOIN productos p ON p.id_proveedor = pr.id_proveedor
JOIN detalle_ventas dv ON dv.id_producto = p.id_producto
JOIN ventas v ON v.id_venta = dv.id_venta AND v.estado <> 'Cancelado'
GROUP BY pr.id_proveedor, pr.nombre
ORDER BY ingresos_generados DESC;

-- 12. Analisis Geografico de Ventas (por ciudad / region del cliente)
SELECT
  cl.ciudad,
  cl.region,
  COUNT(DISTINCT v.id_venta) AS num_ventas,
  SUM(v.total) AS total_ventas
FROM ventas v
JOIN clientes cl ON cl.id_cliente = v.id_cliente
WHERE v.estado <> 'Cancelado'
GROUP BY cl.ciudad, cl.region
ORDER BY total_ventas DESC;

-- 13. Ventas por Hora del Dia
SELECT
  HOUR(fecha_venta) AS hora_del_dia,
  COUNT(*) AS num_ventas,
  SUM(total) AS total_ventas
FROM ventas
WHERE estado <> 'Cancelado'
GROUP BY HOUR(fecha_venta)
ORDER BY hora_del_dia;

-- 14. Impacto de Promociones (ventas antes / durante / despues de una promocion, sobre su categoria)
SELECT
  promo.codigo,
  CASE
    WHEN v.fecha_venta < promo.fecha_inicio THEN '1_Antes'
    WHEN v.fecha_venta BETWEEN promo.fecha_inicio AND promo.fecha_fin THEN '2_Durante'
    ELSE '3_Despues'
  END AS periodo,
  COUNT(DISTINCT v.id_venta) AS num_ventas,
  SUM(dv.subtotal) AS ingresos
FROM promociones promo
JOIN productos p ON p.id_categoria = promo.id_categoria
JOIN detalle_ventas dv ON dv.id_producto = p.id_producto
JOIN ventas v ON v.id_venta = dv.id_venta AND v.estado <> 'Cancelado'
WHERE promo.codigo = 'ROPA15'
GROUP BY promo.codigo, periodo
ORDER BY periodo;

-- 15. Analisis de Cohort (retencion mensual de clientes segun mes de registro)
WITH cohortes AS (
  SELECT id_cliente, DATE_FORMAT(fecha_registro, '%Y-%m-01') AS mes_cohorte
  FROM clientes
),
compras_mensuales AS (
  SELECT id_cliente, DATE_FORMAT(fecha_venta, '%Y-%m-01') AS mes_compra
  FROM ventas
  WHERE estado <> 'Cancelado'
  GROUP BY id_cliente, DATE_FORMAT(fecha_venta, '%Y-%m-01')
),
actividad_cohorte AS (
  SELECT
    co.mes_cohorte,
    TIMESTAMPDIFF(MONTH, co.mes_cohorte, cm.mes_compra) AS mes_offset,
    COUNT(DISTINCT co.id_cliente) AS clientes_activos
  FROM cohortes co
  JOIN compras_mensuales cm ON cm.id_cliente = co.id_cliente
  WHERE cm.mes_compra >= co.mes_cohorte
  GROUP BY co.mes_cohorte, mes_offset
),
tamano_cohorte AS (
  SELECT mes_cohorte, COUNT(*) AS total_clientes
  FROM cohortes
  GROUP BY mes_cohorte
)
SELECT
  ac.mes_cohorte,
  tc.total_clientes,
  ac.mes_offset,
  ac.clientes_activos,
  ROUND(ac.clientes_activos / tc.total_clientes * 100, 2) AS pct_retencion
FROM actividad_cohorte ac
JOIN tamano_cohorte tc ON tc.mes_cohorte = ac.mes_cohorte
ORDER BY ac.mes_cohorte, ac.mes_offset;

-- 16. Margen de Beneficio por Producto
SELECT
  id_producto,
  nombre,
  precio,
  costo,
  ROUND((precio - costo) / precio, 4) AS margen_porcentual
FROM productos
WHERE precio > 0
ORDER BY margen_porcentual DESC;

-- 17. Tiempo Promedio Entre Compras (por cliente, usando LAG sobre ventas)
WITH ventas_ordenadas AS (
  SELECT
    id_cliente,
    fecha_venta,
    LAG(fecha_venta) OVER (PARTITION BY id_cliente ORDER BY fecha_venta) AS fecha_anterior
  FROM ventas
  WHERE estado <> 'Cancelado'
),
diferencias AS (
  SELECT
    id_cliente,
    DATEDIFF(fecha_venta, fecha_anterior) AS dias_entre_compras
  FROM ventas_ordenadas
  WHERE fecha_anterior IS NOT NULL
)
SELECT
  id_cliente,
  COUNT(*) AS num_intervalos,
  ROUND(AVG(dias_entre_compras), 2) AS promedio_dias_entre_compras
FROM diferencias
GROUP BY id_cliente
ORDER BY promedio_dias_entre_compras;

-- 18. Productos Mas Vistos vs. Comprados
SELECT
  p.id_producto,
  p.nombre,
  COALESCE(vis.num_visitas, 0) AS num_visitas,
  COALESCE(comp.unidades_compradas, 0) AS unidades_compradas,
  ROUND(COALESCE(vis.num_visitas, 0) / NULLIF(COALESCE(comp.unidades_compradas, 0), 0), 2) AS ratio_visitas_por_unidad_comprada
FROM productos p
LEFT JOIN (
  SELECT id_producto, COUNT(*) AS num_visitas
  FROM visitas_productos
  GROUP BY id_producto
) vis ON vis.id_producto = p.id_producto
LEFT JOIN (
  SELECT id_producto, SUM(cantidad) AS unidades_compradas
  FROM detalle_ventas
  GROUP BY id_producto
) comp ON comp.id_producto = p.id_producto
ORDER BY num_visitas DESC;

-- 19. Segmentacion RFM (Recencia, Frecuencia, Monetario con NTILE(5))
WITH base_rfm AS (
  SELECT
    c.id_cliente,
    c.nombre,
    c.apellido,
    DATEDIFF(NOW(), c.fecha_ultima_compra) AS recencia_dias,
    COUNT(v.id_venta) AS frecuencia,
    c.total_gastado AS monetario
  FROM clientes c
  LEFT JOIN ventas v ON v.id_cliente = c.id_cliente AND v.estado <> 'Cancelado'
  WHERE c.fecha_ultima_compra IS NOT NULL
  GROUP BY c.id_cliente, c.nombre, c.apellido, c.fecha_ultima_compra, c.total_gastado
),
scored_rfm AS (
  SELECT
    base_rfm.*,
    NTILE(5) OVER (ORDER BY recencia_dias DESC) AS r_score,
    NTILE(5) OVER (ORDER BY frecuencia ASC)     AS f_score,
    NTILE(5) OVER (ORDER BY monetario ASC)      AS m_score
  FROM base_rfm
)
SELECT
  id_cliente,
  nombre,
  apellido,
  recencia_dias,
  frecuencia,
  monetario,
  r_score,
  f_score,
  m_score,
  CONCAT(r_score, f_score, m_score) AS codigo_rfm,
  CASE
    WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4 THEN 'Campeon'
    WHEN r_score <= 2 AND f_score >= 4 AND m_score >= 4 THEN 'En riesgo'
    WHEN r_score >= 4 AND f_score <= 2 THEN 'Nuevo cliente'
    WHEN r_score <= 2 AND f_score <= 2 AND m_score <= 2 THEN 'Perdido'
    ELSE 'Regular'
  END AS segmento_rfm
FROM scored_rfm
ORDER BY monetario DESC;

-- 20. Prediccion de Demanda Simple
-- NOTA: esta es una aproximacion simple (promedio movil de los ultimos 3 meses con
-- datos historicos disponibles), NO un modelo estadistico real: no contempla
-- estacionalidad, tendencia, ni variables externas.
WITH ventas_mensuales_categoria AS (
  SELECT
    p.id_categoria,
    YEAR(v.fecha_venta) AS anio,
    MONTH(v.fecha_venta) AS mes,
    SUM(dv.cantidad) AS unidades_vendidas
  FROM detalle_ventas dv
  JOIN ventas v ON v.id_venta = dv.id_venta AND v.estado <> 'Cancelado'
  JOIN productos p ON p.id_producto = dv.id_producto
  GROUP BY p.id_categoria, YEAR(v.fecha_venta), MONTH(v.fecha_venta)
),
ultimos_3_meses AS (
  SELECT
    id_categoria,
    anio,
    mes,
    unidades_vendidas,
    ROW_NUMBER() OVER (PARTITION BY id_categoria ORDER BY anio DESC, mes DESC) AS rn
  FROM ventas_mensuales_categoria
)
SELECT
  c.id_categoria,
  c.nombre,
  ROUND(AVG(u.unidades_vendidas), 2) AS promedio_movil_3_meses,
  ROUND(AVG(u.unidades_vendidas), 0) AS proyeccion_proximo_mes
FROM ultimos_3_meses u
JOIN categorias c ON c.id_categoria = u.id_categoria
WHERE u.rn <= 3
GROUP BY c.id_categoria, c.nombre
ORDER BY proyeccion_proximo_mes DESC;

-- =====================================================================
-- FIN DE 02_Consultas_Avanzadas.sql
-- =====================================================================
