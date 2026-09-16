-- =====================================================================
-- 01_Esquema_y_Datos.sql
-- Proyecto de Base de Datos para un E-commerce — Esquema completo y datos de ejemplo
-- Motor: MySQL 8.x
-- Nota: la tabla log_cambios_precio se crea en 05_Triggers.sql y la tabla
--       reporte_ventas_semanales se crea en 06_Eventos.sql (según el enunciado).
-- Nota: la columna "contraseña" del enunciado se llama aquí contrasena_hash
--       (evita el caracter "ñ" en identificadores por portabilidad).
-- =====================================================================

DROP DATABASE IF EXISTS ecommerce_avanzado;
CREATE DATABASE ecommerce_avanzado CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE ecommerce_avanzado;

-- =====================================================================
-- SECCIÓN 1: TABLAS DE CONFIGURACIÓN Y ORGANIZACIÓN
-- =====================================================================

CREATE TABLE configuracion_sistema (
  clave        VARCHAR(80) PRIMARY KEY,
  valor        VARCHAR(255) NOT NULL,
  descripcion  VARCHAR(255) NULL
) ENGINE=InnoDB;

CREATE TABLE sucursales (
  id_sucursal  INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  nombre       VARCHAR(100) NOT NULL UNIQUE,
  ciudad       VARCHAR(100) NULL,
  direccion    VARCHAR(255) NULL,
  activa       BOOLEAN NOT NULL DEFAULT TRUE
) ENGINE=InnoDB;

CREATE TABLE mapeo_usuario_sucursal (
  usuario_bd   VARCHAR(100) PRIMARY KEY,
  id_sucursal  INT UNSIGNED NOT NULL,
  CONSTRAINT fk_mus_sucursal FOREIGN KEY (id_sucursal) REFERENCES sucursales(id_sucursal)
) ENGINE=InnoDB;

-- =====================================================================
-- SECCIÓN 2: CATÁLOGO (CATEGORÍAS, PROVEEDORES, PRODUCTOS)
-- =====================================================================

CREATE TABLE categorias (
  id_categoria     INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  nombre           VARCHAR(100) NOT NULL UNIQUE,
  descripcion      TEXT NULL,
  total_productos  INT UNSIGNED NOT NULL DEFAULT 0,
  fecha_creacion   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE proveedores (
  id_proveedor       INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  nombre             VARCHAR(150) NOT NULL,
  email_contacto     VARCHAR(150) NULL UNIQUE,
  telefono_contacto  VARCHAR(30) NULL,
  activo             BOOLEAN NOT NULL DEFAULT TRUE
) ENGINE=InnoDB;

CREATE TABLE promociones (
  id_promocion     INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  codigo           VARCHAR(30) NOT NULL UNIQUE,
  descripcion      VARCHAR(255) NULL,
  tipo_descuento   ENUM('Porcentaje','Monto_Fijo') NOT NULL,
  valor_descuento  DECIMAL(10,2) NOT NULL,
  id_categoria     INT UNSIGNED NULL,
  fecha_inicio     DATETIME NOT NULL,
  fecha_fin        DATETIME NOT NULL,
  activa           BOOLEAN NOT NULL DEFAULT TRUE,
  usos_maximos     INT UNSIGNED NULL,
  usos_actuales    INT UNSIGNED NOT NULL DEFAULT 0,
  CONSTRAINT chk_promo_fechas CHECK (fecha_fin > fecha_inicio),
  CONSTRAINT fk_promo_categoria FOREIGN KEY (id_categoria) REFERENCES categorias(id_categoria) ON DELETE SET NULL
) ENGINE=InnoDB;

CREATE TABLE productos (
  id_producto         INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  nombre              VARCHAR(150) NOT NULL UNIQUE,
  descripcion         LONGTEXT NULL,
  precio              DECIMAL(10,2) NOT NULL,
  costo               DECIMAL(10,2) NOT NULL,
  stock               INT NOT NULL DEFAULT 0,
  sku                 VARCHAR(50) NOT NULL UNIQUE,
  fecha_creacion      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  activo              BOOLEAN NOT NULL DEFAULT TRUE,
  id_categoria        INT UNSIGNED NULL,
  id_proveedor        INT UNSIGNED NULL,
  peso_kg             DECIMAL(6,3) NOT NULL DEFAULT 0.000,
  stock_minimo        INT UNSIGNED NOT NULL DEFAULT 5,
  ubicacion_almacen   VARCHAR(100) NULL,
  fecha_modificacion  DATETIME NULL,
  eliminado           BOOLEAN NOT NULL DEFAULT FALSE,
  fecha_eliminacion   DATETIME NULL,
  CONSTRAINT chk_precio_positivo   CHECK (precio > 0),
  CONSTRAINT chk_costo_no_negativo CHECK (costo >= 0),
  CONSTRAINT chk_stock_no_negativo CHECK (stock >= 0),
  CONSTRAINT fk_productos_categoria FOREIGN KEY (id_categoria) REFERENCES categorias(id_categoria) ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_productos_proveedor FOREIGN KEY (id_proveedor) REFERENCES proveedores(id_proveedor) ON DELETE SET NULL ON UPDATE CASCADE,
  INDEX idx_productos_categoria (id_categoria),
  INDEX idx_productos_proveedor (id_proveedor),
  INDEX idx_productos_activo (activo)
) ENGINE=InnoDB;

-- =====================================================================
-- SECCIÓN 3: CLIENTES, VENTAS Y DETALLE DE VENTAS
-- =====================================================================

CREATE TABLE clientes (
  id_cliente          INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  nombre              VARCHAR(100) NOT NULL,
  apellido            VARCHAR(100) NOT NULL,
  email               VARCHAR(150) NOT NULL UNIQUE,
  contrasena_hash     VARCHAR(255) NOT NULL,
  direccion_envio     VARCHAR(255) NULL,
  fecha_registro      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  fecha_nacimiento    DATE NULL,
  ciudad              VARCHAR(100) NULL,
  region              VARCHAR(100) NULL,
  total_gastado       DECIMAL(12,2) NOT NULL DEFAULT 0.00,
  fecha_ultima_compra DATETIME NULL,
  nivel_lealtad       ENUM('Bronce','Plata','Oro') NOT NULL DEFAULT 'Bronce',
  saldo_credito       DECIMAL(10,2) NOT NULL DEFAULT 0.00,
  activo              BOOLEAN NOT NULL DEFAULT TRUE,
  anonimizado         BOOLEAN NOT NULL DEFAULT FALSE,
  CONSTRAINT chk_email_formato CHECK (email LIKE '%_@_%.__%'),
  INDEX idx_clientes_ciudad (ciudad),
  INDEX idx_clientes_region (region),
  INDEX idx_clientes_activo (activo)
) ENGINE=InnoDB;

CREATE TABLE ventas (
  id_venta      INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  id_cliente    INT UNSIGNED NOT NULL,
  fecha_venta   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  estado        ENUM('Pendiente de Pago','Procesando','Enviado','Entregado','Cancelado') NOT NULL DEFAULT 'Pendiente de Pago',
  total         DECIMAL(12,2) NOT NULL DEFAULT 0.00,
  id_sucursal   INT UNSIGNED NOT NULL,
  id_promocion  INT UNSIGNED NULL,
  fecha_pago    DATETIME NULL,
  metodo_pago   VARCHAR(30) NULL,
  CONSTRAINT fk_ventas_cliente    FOREIGN KEY (id_cliente)   REFERENCES clientes(id_cliente)     ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_ventas_sucursal   FOREIGN KEY (id_sucursal)  REFERENCES sucursales(id_sucursal)  ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_ventas_promocion  FOREIGN KEY (id_promocion) REFERENCES promociones(id_promocion) ON DELETE SET NULL ON UPDATE CASCADE,
  INDEX idx_ventas_cliente (id_cliente),
  INDEX idx_ventas_fecha (fecha_venta),
  INDEX idx_ventas_estado (estado),
  INDEX idx_ventas_sucursal (id_sucursal)
) ENGINE=InnoDB;

CREATE TABLE detalle_ventas (
  id_detalle                 INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  id_venta                   INT UNSIGNED NOT NULL,
  id_producto                INT UNSIGNED NOT NULL,
  cantidad                   INT UNSIGNED NOT NULL,
  precio_unitario_congelado  DECIMAL(10,2) NOT NULL,
  subtotal                   DECIMAL(12,2) GENERATED ALWAYS AS (cantidad * precio_unitario_congelado) STORED,
  CONSTRAINT chk_cantidad_positiva CHECK (cantidad > 0),
  CONSTRAINT fk_detalle_venta    FOREIGN KEY (id_venta)    REFERENCES ventas(id_venta)     ON DELETE CASCADE  ON UPDATE CASCADE,
  CONSTRAINT fk_detalle_producto FOREIGN KEY (id_producto) REFERENCES productos(id_producto) ON DELETE RESTRICT ON UPDATE CASCADE,
  INDEX idx_detalle_venta (id_venta),
  INDEX idx_detalle_producto (id_producto)
) ENGINE=InnoDB;

-- =====================================================================
-- SECCIÓN 4: PROMOCIONES/CARRITO/SOCIAL (carritos, reseñas, referidos)
-- =====================================================================

CREATE TABLE carritos (
  id_carrito           INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  id_cliente           INT UNSIGNED NOT NULL,
  fecha_creacion       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  fecha_actualizacion  DATETIME NULL,
  estado               ENUM('Activo','Abandonado','Convertido') NOT NULL DEFAULT 'Activo',
  CONSTRAINT fk_carrito_cliente FOREIGN KEY (id_cliente) REFERENCES clientes(id_cliente)
) ENGINE=InnoDB;

CREATE TABLE carrito_items (
  id_item        INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  id_carrito     INT UNSIGNED NOT NULL,
  id_producto    INT UNSIGNED NOT NULL,
  cantidad       INT UNSIGNED NOT NULL DEFAULT 1,
  fecha_agregado DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (id_carrito, id_producto),
  CONSTRAINT fk_ci_carrito  FOREIGN KEY (id_carrito)  REFERENCES carritos(id_carrito) ON DELETE CASCADE,
  CONSTRAINT fk_ci_producto FOREIGN KEY (id_producto) REFERENCES productos(id_producto)
) ENGINE=InnoDB;

CREATE TABLE resenas_productos (
  id_resena     INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  id_producto   INT UNSIGNED NOT NULL,
  id_cliente    INT UNSIGNED NOT NULL,
  calificacion  TINYINT UNSIGNED NOT NULL,
  comentario    TEXT NULL,
  fecha_resena  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  aprobada      BOOLEAN NOT NULL DEFAULT FALSE,
  UNIQUE (id_producto, id_cliente),
  CONSTRAINT chk_calificacion CHECK (calificacion BETWEEN 1 AND 5),
  CONSTRAINT fk_resena_producto FOREIGN KEY (id_producto) REFERENCES productos(id_producto),
  CONSTRAINT fk_resena_cliente  FOREIGN KEY (id_cliente)  REFERENCES clientes(id_cliente)
) ENGINE=InnoDB;

CREATE TABLE referidos_clientes (
  id_referido           INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  id_cliente_referidor  INT UNSIGNED NOT NULL,
  id_cliente_referido   INT UNSIGNED NOT NULL UNIQUE,
  fecha_referido        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  recompensa_aplicada   BOOLEAN NOT NULL DEFAULT FALSE,
  CONSTRAINT chk_no_autoreferido CHECK (id_cliente_referidor <> id_cliente_referido),
  CONSTRAINT fk_ref_referidor FOREIGN KEY (id_cliente_referidor) REFERENCES clientes(id_cliente),
  CONSTRAINT fk_ref_referido  FOREIGN KEY (id_cliente_referido)  REFERENCES clientes(id_cliente)
) ENGINE=InnoDB;

-- =====================================================================
-- SECCIÓN 5: VISITAS, RANKING Y PRODUCTOS RELACIONADOS
-- =====================================================================

CREATE TABLE visitas_productos (
  id_visita     INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  id_producto   INT UNSIGNED NOT NULL,
  id_cliente    INT UNSIGNED NULL,
  fecha_visita  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  ip_origen     VARCHAR(45) NULL,
  CONSTRAINT fk_visita_producto FOREIGN KEY (id_producto) REFERENCES productos(id_producto),
  CONSTRAINT fk_visita_cliente  FOREIGN KEY (id_cliente)  REFERENCES clientes(id_cliente) ON DELETE SET NULL
) ENGINE=InnoDB;

CREATE TABLE ranking_productos_popular (
  id_ranking          INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  id_producto         INT UNSIGNED NOT NULL,
  fecha_calculo       DATETIME NOT NULL,
  num_vistas_periodo  INT UNSIGNED NOT NULL DEFAULT 0,
  num_ventas_periodo  INT UNSIGNED NOT NULL DEFAULT 0,
  posicion            INT UNSIGNED NULL,
  CONSTRAINT fk_rank_producto FOREIGN KEY (id_producto) REFERENCES productos(id_producto)
) ENGINE=InnoDB;

CREATE TABLE productos_relacionados (
  id_relacion             INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  id_producto_a           INT UNSIGNED NOT NULL,
  id_producto_b           INT UNSIGNED NOT NULL,
  veces_comprados_juntos  INT UNSIGNED NOT NULL DEFAULT 0,
  fecha_calculo           DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (id_producto_a, id_producto_b),
  CONSTRAINT chk_par_ordenado CHECK (id_producto_a < id_producto_b),
  CONSTRAINT fk_pr_a FOREIGN KEY (id_producto_a) REFERENCES productos(id_producto),
  CONSTRAINT fk_pr_b FOREIGN KEY (id_producto_b) REFERENCES productos(id_producto)
) ENGINE=InnoDB;

-- =====================================================================
-- SECCIÓN 6: AUDITORÍA Y LOGS
-- =====================================================================

CREATE TABLE auditoria_clientes (
  id_auditoria      INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  id_cliente        INT UNSIGNED NULL,
  accion            ENUM('ALTA','MODIFICACION','BAJA','ANONIMIZACION') NOT NULL,
  campo_modificado  VARCHAR(100) NULL,
  valor_anterior    VARCHAR(255) NULL,
  valor_nuevo       VARCHAR(255) NULL,
  fecha_evento      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  usuario_bd        VARCHAR(100) NULL,
  CONSTRAINT fk_ac_cliente FOREIGN KEY (id_cliente) REFERENCES clientes(id_cliente) ON DELETE SET NULL
) ENGINE=InnoDB;

CREATE TABLE alertas_stock (
  id_alerta     INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  id_producto   INT UNSIGNED NOT NULL,
  stock_actual  INT NOT NULL,
  stock_minimo  INT NOT NULL,
  origen        ENUM('Trigger','Evento') NOT NULL DEFAULT 'Trigger',
  fecha_alerta  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  atendida      BOOLEAN NOT NULL DEFAULT FALSE,
  CONSTRAINT fk_alerta_producto FOREIGN KEY (id_producto) REFERENCES productos(id_producto)
) ENGINE=InnoDB;

CREATE TABLE log_estado_pedido (
  id_log          INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  id_venta        INT UNSIGNED NOT NULL,
  estado_anterior VARCHAR(30) NULL,
  estado_nuevo    VARCHAR(30) NOT NULL,
  fecha_cambio    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  usuario_bd      VARCHAR(100) NULL,
  CONSTRAINT fk_lep_venta FOREIGN KEY (id_venta) REFERENCES ventas(id_venta)
) ENGINE=InnoDB;

CREATE TABLE log_permisos (
  id_log         INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  usuario_bd     VARCHAR(100) NOT NULL,
  rol_afectado   VARCHAR(100) NULL,
  accion         ENUM('GRANT','REVOKE','CREATE_ROLE','DROP_ROLE','CREATE_USER','DROP_USER') NOT NULL,
  detalle        VARCHAR(255) NULL,
  ejecutado_por  VARCHAR(100) NULL,
  fecha_evento   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE log_intentos_login (
  id_intento    INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  email_intento VARCHAR(150) NOT NULL,
  id_cliente    INT UNSIGNED NULL,
  exitoso       BOOLEAN NOT NULL,
  ip_origen     VARCHAR(45) NULL,
  fecha_intento DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  motivo_fallo  VARCHAR(255) NULL,
  CONSTRAINT fk_lil_cliente FOREIGN KEY (id_cliente) REFERENCES clientes(id_cliente) ON DELETE SET NULL
) ENGINE=InnoDB;

CREATE TABLE log_actividad_fraudulenta (
  id_alerta       INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  id_cliente      INT UNSIGNED NULL,
  id_venta        INT UNSIGNED NULL,
  tipo_alerta     VARCHAR(100) NOT NULL,
  detalle         VARCHAR(255) NULL,
  fecha_deteccion DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  revisada        BOOLEAN NOT NULL DEFAULT FALSE,
  CONSTRAINT fk_laf_cliente FOREIGN KEY (id_cliente) REFERENCES clientes(id_cliente) ON DELETE SET NULL,
  CONSTRAINT fk_laf_venta   FOREIGN KEY (id_venta)   REFERENCES ventas(id_venta) ON DELETE SET NULL
) ENGINE=InnoDB;

CREATE TABLE log_consistencia_datos (
  id_check            INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  fecha_chequeo       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  tipo_inconsistencia VARCHAR(100) NOT NULL,
  id_referencia       INT UNSIGNED NULL,
  descripcion         VARCHAR(255) NULL
) ENGINE=InnoDB;

CREATE TABLE log_ajustes_stock (
  id_ajuste         INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  id_producto       INT UNSIGNED NOT NULL,
  cantidad_ajustada INT NOT NULL,
  motivo            VARCHAR(255) NOT NULL,
  usuario_bd        VARCHAR(100) NULL,
  fecha_ajuste      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_las_producto FOREIGN KEY (id_producto) REFERENCES productos(id_producto)
) ENGINE=InnoDB;

-- =====================================================================
-- SECCIÓN 7: ARCHIVADO, RESPALDO Y STAGING
-- =====================================================================

CREATE TABLE ventas_archivadas (
  id_venta_original     INT UNSIGNED PRIMARY KEY,
  id_cliente_original   INT UNSIGNED NOT NULL,
  fecha_venta_original  TIMESTAMP NOT NULL,
  estado                VARCHAR(30) NOT NULL,
  total                 DECIMAL(12,2) NOT NULL,
  id_sucursal_original  INT UNSIGNED NOT NULL,
  fecha_archivado       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE detalle_ventas_archivadas (
  id_detalle_original       INT UNSIGNED PRIMARY KEY,
  id_venta_original         INT UNSIGNED NOT NULL,
  id_producto_original      INT UNSIGNED NOT NULL,
  cantidad                  INT NOT NULL,
  precio_unitario_congelado DECIMAL(10,2) NOT NULL,
  fecha_archivado           DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE respaldo_log (
  id_backup          INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  nombre_tabla       VARCHAR(100) NOT NULL,
  fecha_backup       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  filas_respaldadas  BIGINT UNSIGNED NOT NULL DEFAULT 0,
  estado             ENUM('Exitoso','Fallido') NOT NULL DEFAULT 'Exitoso'
) ENGINE=InnoDB;

CREATE TABLE respaldo_productos (
  id_producto    INT UNSIGNED NOT NULL,
  nombre         VARCHAR(150) NOT NULL,
  precio         DECIMAL(10,2) NOT NULL,
  costo          DECIMAL(10,2) NOT NULL,
  stock          INT NOT NULL,
  sku            VARCHAR(50) NOT NULL,
  fecha_respaldo DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id_producto, fecha_respaldo)
) ENGINE=InnoDB;

CREATE TABLE respaldo_clientes (
  id_cliente     INT UNSIGNED NOT NULL,
  nombre         VARCHAR(100) NOT NULL,
  apellido       VARCHAR(100) NOT NULL,
  email          VARCHAR(150) NOT NULL,
  total_gastado  DECIMAL(12,2) NOT NULL,
  fecha_respaldo DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id_cliente, fecha_respaldo)
) ENGINE=InnoDB;

CREATE TABLE respaldo_ventas (
  id_venta       INT UNSIGNED NOT NULL,
  id_cliente     INT UNSIGNED NOT NULL,
  fecha_venta    TIMESTAMP NOT NULL,
  estado         VARCHAR(30) NOT NULL,
  total          DECIMAL(12,2) NOT NULL,
  fecha_respaldo DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id_venta, fecha_respaldo)
) ENGINE=InnoDB;

CREATE TABLE staging_temporal (
  id_staging     INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  tipo_proceso   VARCHAR(50) NOT NULL,
  contenido      JSON NULL,
  fecha_creacion DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- =====================================================================
-- SECCIÓN 8: REPORTES AGREGADOS / ANALÍTICA CACHEADA
-- =====================================================================

CREATE TABLE resumen_ventas_diarias (
  id_resumen      INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  fecha           DATE NOT NULL UNIQUE,
  total_ventas    DECIMAL(14,2) NOT NULL,
  num_ventas      INT UNSIGNED NOT NULL,
  ticket_promedio DECIMAL(10,2) NOT NULL,
  fecha_calculo   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE kpis_mensuales (
  id_kpi          INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  anio            SMALLINT UNSIGNED NOT NULL,
  mes             TINYINT UNSIGNED NOT NULL,
  ventas_totales  DECIMAL(14,2) NOT NULL,
  num_ventas      INT UNSIGNED NOT NULL,
  nuevos_clientes INT UNSIGNED NOT NULL,
  ticket_promedio DECIMAL(10,2) NOT NULL,
  margen_total    DECIMAL(14,2) NOT NULL,
  fecha_calculo   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (anio, mes)
) ENGINE=InnoDB;

CREATE TABLE snapshot_stock_diario (
  id_snapshot      INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  id_producto      INT UNSIGNED NOT NULL,
  stock_al_cierre  INT UNSIGNED NOT NULL,
  fecha            DATE NOT NULL,
  UNIQUE (id_producto, fecha),
  CONSTRAINT fk_ssd_producto FOREIGN KEY (id_producto) REFERENCES productos(id_producto)
) ENGINE=InnoDB;

CREATE TABLE segmentacion_rfm (
  id_segmento        INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  id_cliente         INT UNSIGNED NOT NULL UNIQUE,
  recencia_dias      INT NOT NULL,
  frecuencia_compras INT NOT NULL,
  monetario_total    DECIMAL(12,2) NOT NULL,
  segmento_rfm       VARCHAR(30) NOT NULL,
  fecha_calculo      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_rfm_cliente FOREIGN KEY (id_cliente) REFERENCES clientes(id_cliente)
) ENGINE=InnoDB;

CREATE TABLE proyeccion_demanda (
  id_proyeccion        INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  id_categoria         INT UNSIGNED NOT NULL,
  mes_proyectado       TINYINT UNSIGNED NOT NULL,
  anio_proyectado      SMALLINT UNSIGNED NOT NULL,
  unidades_proyectadas DECIMAL(10,2) NOT NULL,
  metodo               VARCHAR(50) NOT NULL DEFAULT 'Promedio_Movil_3_Meses',
  fecha_calculo        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (id_categoria, mes_proyectado, anio_proyectado),
  CONSTRAINT fk_pd_categoria FOREIGN KEY (id_categoria) REFERENCES categorias(id_categoria)
) ENGINE=InnoDB;

CREATE TABLE reporte_rendimiento_proveedores (
  id_reporte         INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  id_proveedor       INT UNSIGNED NOT NULL,
  anio               SMALLINT UNSIGNED NOT NULL,
  mes                TINYINT UNSIGNED NOT NULL,
  unidades_vendidas  INT UNSIGNED NOT NULL,
  ingresos_generados DECIMAL(14,2) NOT NULL,
  fecha_generacion   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (id_proveedor, anio, mes),
  CONSTRAINT fk_rrp_proveedor FOREIGN KEY (id_proveedor) REFERENCES proveedores(id_proveedor)
) ENGINE=InnoDB;

CREATE TABLE tamano_bd_log (
  id_log            INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  fecha_registro    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  nombre_tabla      VARCHAR(100) NOT NULL,
  filas_aprox       BIGINT UNSIGNED NOT NULL,
  tamano_datos_mb   DECIMAL(10,2) NOT NULL,
  tamano_indices_mb DECIMAL(10,2) NOT NULL
) ENGINE=InnoDB;

CREATE TABLE notificaciones_cumpleanos (
  id_notificacion INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  id_cliente      INT UNSIGNED NOT NULL,
  fecha_generado  DATE NOT NULL,
  mensaje         VARCHAR(255) NOT NULL,
  enviada         BOOLEAN NOT NULL DEFAULT FALSE,
  CONSTRAINT fk_nc_cliente FOREIGN KEY (id_cliente) REFERENCES clientes(id_cliente)
) ENGINE=InnoDB;

-- =====================================================================
-- SECCIÓN 9: DEVOLUCIONES
-- =====================================================================

CREATE TABLE devoluciones (
  id_devolucion     INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  id_detalle        INT UNSIGNED NOT NULL,
  cantidad_devuelta INT UNSIGNED NOT NULL,
  motivo            VARCHAR(255) NULL,
  fecha_devolucion  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  monto_credito     DECIMAL(10,2) NOT NULL,
  estado            ENUM('Procesada','Rechazada') NOT NULL DEFAULT 'Procesada',
  CONSTRAINT fk_dev_detalle FOREIGN KEY (id_detalle) REFERENCES detalle_ventas(id_detalle)
) ENGINE=InnoDB;

-- =====================================================================
-- SECCIÓN 10: DATOS DE EJEMPLO — TABLAS DE DIMENSIÓN (manuales)
-- =====================================================================

INSERT INTO configuracion_sistema (clave, valor, descripcion) VALUES
('tasa_iva', '0.19', 'Tasa de IVA aplicada sobre el total de una venta'),
('tasa_cambio_usd', '4000', 'Tasa de cambio fija de la moneda local a USD'),
('dias_cliente_nuevo', '30', 'Dias desde la primera compra para considerar un cliente como nuevo'),
('horas_carrito_abandonado', '72', 'Horas de inactividad para marcar un carrito como abandonado'),
('meses_inactividad_suspension', '12', 'Meses sin compras para suspender una cuenta de cliente'),
('dias_retencion_logs', '180', 'Dias de retencion antes de archivar logs'),
('dias_purga_soft_delete', '30', 'Dias antes de purgar definitivamente un registro marcado como eliminado'),
('umbral_lealtad_plata', '500', 'Gasto total minimo para nivel de lealtad Plata'),
('umbral_lealtad_oro', '2000', 'Gasto total minimo para nivel de lealtad Oro'),
('costo_envio_por_kg', '3.5', 'Costo de envio por kilogramo de peso');

INSERT INTO sucursales (nombre, ciudad, direccion, activa) VALUES
('Sucursal Centro', 'Bogota', 'Cra 7 # 20-30', TRUE),
('Sucursal Norte', 'Bogota', 'Calle 140 # 15-10', TRUE),
('Sucursal Medellin', 'Medellin', 'Cra 43A # 5-15', TRUE),
('Sucursal Cali', 'Cali', 'Av 6N # 25-40', TRUE);

INSERT INTO categorias (nombre, descripcion) VALUES
('Electronica', 'Dispositivos electronicos, computadores y accesorios'),
('Ropa', 'Prendas de vestir para todas las edades'),
('Hogar', 'Articulos para el hogar y decoracion'),
('Deportes', 'Articulos deportivos y de ejercicio'),
('Belleza', 'Productos de cuidado personal y belleza'),
('Alimentos', 'Alimentos empacados y snacks'),
('Juguetes', 'Juguetes y juegos para ninos'),
('Libros', 'Libros fisicos de distintos generos'),
('Mascotas', 'Articulos y alimento para mascotas'),
('General', 'Categoria por defecto para productos sin clasificar');

INSERT INTO proveedores (nombre, email_contacto, telefono_contacto, activo) VALUES
('Distribuidora Andina S.A.S', 'contacto@andina.com', '6011234567', TRUE),
('TechImport Ltda', 'ventas@techimport.com', '6012345678', TRUE),
('Moda Express', 'info@modaexpress.com', '6013456789', TRUE),
('Hogar y Deco S.A.S', 'contacto@hogaryDeco.com', '6014567890', TRUE),
('Deportes Nacionales', 'ventas@deportesnal.com', '6015678901', TRUE),
('Bella Piel Cosmeticos', 'contacto@bellapiel.com', '6016789012', TRUE),
('Alimentos del Valle', 'info@alimentosvalle.com', '6017890123', TRUE),
('Juguetes Felices Ltda', 'ventas@juguetesfelices.com', '6018901234', TRUE),
('Editorial Palabra Viva', 'contacto@palabraviva.com', '6019012345', TRUE),
('PetLovers Import', 'info@petlovers.com', '6010123456', TRUE);

INSERT INTO promociones (codigo, descripcion, tipo_descuento, valor_descuento, id_categoria, fecha_inicio, fecha_fin, activa, usos_maximos, usos_actuales) VALUES
('VERANO10', 'Descuento de verano en electronica', 'Porcentaje', 10.00, 1, DATE_SUB(NOW(), INTERVAL 60 DAY), DATE_SUB(NOW(), INTERVAL 30 DAY), FALSE, 200, 87),
('ROPA15', 'Descuento en ropa de temporada', 'Porcentaje', 15.00, 2, DATE_SUB(NOW(), INTERVAL 20 DAY), DATE_ADD(NOW(), INTERVAL 10 DAY), TRUE, 300, 120),
('HOGAR5USD', 'Descuento fijo en hogar', 'Monto_Fijo', 5.00, 3, DATE_SUB(NOW(), INTERVAL 10 DAY), DATE_ADD(NOW(), INTERVAL 20 DAY), TRUE, 150, 40),
('BLACKFRIDAY', 'Descuento general Black Friday', 'Porcentaje', 25.00, NULL, DATE_SUB(NOW(), INTERVAL 200 DAY), DATE_SUB(NOW(), INTERVAL 195 DAY), FALSE, 1000, 430),
('BELLEZA20', 'Descuento en linea de belleza', 'Porcentaje', 20.00, 5, DATE_SUB(NOW(), INTERVAL 5 DAY), DATE_ADD(NOW(), INTERVAL 25 DAY), TRUE, 200, 15),
('JUGUETES10', 'Descuento en juguetes', 'Porcentaje', 10.00, 7, DATE_SUB(NOW(), INTERVAL 100 DAY), DATE_SUB(NOW(), INTERVAL 90 DAY), FALSE, 100, 55),
('LIBROS5USD', 'Descuento fijo en libros', 'Monto_Fijo', 5.00, 8, DATE_SUB(NOW(), INTERVAL 3 DAY), DATE_ADD(NOW(), INTERVAL 40 DAY), TRUE, 250, 8),
('MASCOTAS15', 'Descuento en articulos para mascotas', 'Porcentaje', 15.00, 9, DATE_SUB(NOW(), INTERVAL 150 DAY), DATE_SUB(NOW(), INTERVAL 120 DAY), FALSE, 120, 61);

-- =====================================================================
-- SECCIÓN 11: DATOS DE EJEMPLO — GENERACIÓN MASIVA (procedimiento temporal)
-- =====================================================================
-- Se usa un procedimiento temporal en lugar de cientos de INSERT manuales,
-- para generar volumen suficiente que las 20 consultas analiticas de
-- 02_Consultas_Avanzadas.sql produzcan resultados no triviales. El
-- procedimiento se elimina (DROP) al final de esta seccion.

DELIMITER $$

CREATE PROCEDURE sp_poblar_datos_demo()
BEGIN
  DECLARE i INT DEFAULT 0;
  DECLARE j INT DEFAULT 0;
  DECLARE v_min_cat INT;
  DECLARE v_max_cat INT;
  DECLARE v_min_prov INT;
  DECLARE v_max_prov INT;
  DECLARE v_min_sucursal INT;
  DECLARE v_max_sucursal INT;
  DECLARE v_min_promo INT;
  DECLARE v_max_promo INT;
  DECLARE v_min_prod INT;
  DECLARE v_max_prod INT;
  DECLARE v_min_cli INT;
  DECLARE v_max_cli INT;

  DECLARE v_id_categoria INT;
  DECLARE v_id_proveedor INT;
  DECLARE v_nombre VARCHAR(150);
  DECLARE v_sku VARCHAR(50);
  DECLARE v_precio DECIMAL(10,2);
  DECLARE v_costo DECIMAL(10,2);
  DECLARE v_stock INT;

  DECLARE v_nombre_cli VARCHAR(100);
  DECLARE v_apellido_cli VARCHAR(100);
  DECLARE v_ciudad VARCHAR(100);
  DECLARE v_region VARCHAR(100);
  DECLARE v_fecha_registro DATETIME;
  DECLARE v_fecha_nacimiento DATE;
  DECLARE v_id_cliente_actual INT;

  DECLARE v_num_ventas_cliente INT;
  DECLARE v_rnd_perfil DECIMAL(5,4);
  DECLARE v_id_venta_actual INT;
  DECLARE v_fecha_venta DATETIME;
  DECLARE v_estado VARCHAR(30);
  DECLARE v_id_sucursal INT;
  DECLARE v_id_promocion INT;
  DECLARE v_num_items INT;
  DECLARE v_id_producto_item INT;
  DECLARE v_cantidad_item INT;
  DECLARE v_precio_item DECIMAL(10,2);

  SELECT MIN(id_categoria), MAX(id_categoria) INTO v_min_cat, v_max_cat FROM categorias;
  SELECT MIN(id_proveedor), MAX(id_proveedor) INTO v_min_prov, v_max_prov FROM proveedores;
  SELECT MIN(id_sucursal), MAX(id_sucursal) INTO v_min_sucursal, v_max_sucursal FROM sucursales;
  SELECT MIN(id_promocion), MAX(id_promocion) INTO v_min_promo, v_max_promo FROM promociones;

  -- ---------------------------------------------------------------
  -- PRODUCTOS (80)
  -- ---------------------------------------------------------------
  SET i = 0;
  WHILE i < 80 DO
    SET v_id_categoria = FLOOR(v_min_cat + RAND() * (v_max_cat - v_min_cat + 1));
    SET v_id_proveedor = FLOOR(v_min_prov + RAND() * (v_max_prov - v_min_prov + 1));
    SET v_nombre = CONCAT(
      ELT(FLOOR(1 + RAND() * 10), 'Laptop', 'Camisa', 'Sofa', 'Balon', 'Crema', 'Cereal', 'Muneca', 'Novela', 'Correa', 'Auricular'),
      ' ', ELT(FLOOR(1 + RAND() * 8), 'Pro', 'Max', 'Basico', 'Deluxe', 'Mini', 'Plus', 'Classic', 'Elite'),
      ' #', i
    );
    SET v_precio = ROUND(10 + RAND() * 490, 2);
    SET v_costo = ROUND(v_precio * (0.4 + RAND() * 0.3), 2);
    SET v_stock = 20 + FLOOR(RAND() * 130);
    SET v_sku = CONCAT('SKU-', LPAD(i, 5, '0'));
    INSERT INTO productos (nombre, descripcion, precio, costo, stock, sku, activo, id_categoria, id_proveedor, peso_kg, stock_minimo, ubicacion_almacen)
    VALUES (v_nombre, CONCAT('Descripcion detallada de ', v_nombre), v_precio, v_costo, v_stock, v_sku, TRUE,
            v_id_categoria, v_id_proveedor, ROUND(0.1 + RAND() * 9.9, 3), 5 + FLOOR(RAND() * 10),
            CONCAT('Pasillo-', FLOOR(1 + RAND() * 20)));
    SET i = i + 1;
  END WHILE;

  -- forzar 8 productos con stock por debajo del minimo (para reabastecimiento)
  UPDATE productos
  SET stock = FLOOR(RAND() * 3)
  WHERE id_producto IN (
    SELECT id_producto FROM (
      SELECT id_producto FROM productos ORDER BY RAND() LIMIT 8
    ) AS sub
  );

  SELECT MIN(id_producto), MAX(id_producto) INTO v_min_prod, v_max_prod FROM productos;

  -- ---------------------------------------------------------------
  -- CLIENTES (100)
  -- ---------------------------------------------------------------
  SET i = 0;
  WHILE i < 100 DO
    SET v_nombre_cli = ELT(FLOOR(1 + RAND() * 10), 'Juan', 'Maria', 'Carlos', 'Ana', 'Luis', 'Sofia', 'Pedro', 'Laura', 'Diego', 'Valentina');
    SET v_apellido_cli = ELT(FLOOR(1 + RAND() * 10), 'Garcia', 'Martinez', 'Lopez', 'Hernandez', 'Gonzalez', 'Perez', 'Sanchez', 'Ramirez', 'Torres', 'Flores');
    SET v_ciudad = ELT(FLOOR(1 + RAND() * 5), 'Bogota', 'Medellin', 'Cali', 'Barranquilla', 'Cartagena');
    SET v_region = CASE v_ciudad
      WHEN 'Bogota' THEN 'Centro'
      WHEN 'Medellin' THEN 'Antioquia'
      WHEN 'Cali' THEN 'Valle del Cauca'
      ELSE 'Caribe'
    END;
    SET v_fecha_registro = DATE_SUB(NOW(), INTERVAL FLOOR(RAND() * 540) DAY);
    SET v_fecha_nacimiento = DATE_SUB(CURDATE(), INTERVAL (18 * 365 + FLOOR(RAND() * 40 * 365)) DAY);
    INSERT INTO clientes (nombre, apellido, email, contrasena_hash, direccion_envio, fecha_registro, fecha_nacimiento, ciudad, region)
    VALUES (v_nombre_cli, v_apellido_cli, CONCAT('cliente', i, '@correo.com'), SHA2(CONCAT('Password', i, '!'), 256),
            CONCAT('Calle ', FLOOR(RAND() * 200), ' # ', FLOOR(RAND() * 100), '-', FLOOR(RAND() * 100)),
            v_fecha_registro, v_fecha_nacimiento, v_ciudad, v_region);
    SET i = i + 1;
  END WHILE;

  -- 5 clientes con cumpleanos hoy (mismo mes/dia, distinto anio) para probar el evento de cumpleanos
  UPDATE clientes
  SET fecha_nacimiento = DATE_SUB(CURDATE(), INTERVAL (20 + id_cliente MOD 30) YEAR)
  WHERE id_cliente IN (
    SELECT id_cliente FROM (SELECT id_cliente FROM clientes ORDER BY RAND() LIMIT 5) AS sub
  );

  -- 8 clientes inactivos (ultima actividad hace mas de un anio) via fecha_registro antigua y sin ventas recientes
  UPDATE clientes
  SET fecha_registro = DATE_SUB(NOW(), INTERVAL (400 + FLOOR(RAND() * 300)) DAY)
  WHERE id_cliente IN (
    SELECT id_cliente FROM (SELECT id_cliente FROM clientes ORDER BY RAND() LIMIT 8) AS sub
  );

  SELECT MIN(id_cliente), MAX(id_cliente) INTO v_min_cli, v_max_cli FROM clientes;

  -- ---------------------------------------------------------------
  -- VENTAS + DETALLE_VENTAS (perfil de compra variable por cliente)
  -- ---------------------------------------------------------------
  SET i = v_min_cli;
  WHILE i <= v_max_cli DO
    SET v_id_cliente_actual = i;
    SET v_rnd_perfil = RAND();
    IF v_rnd_perfil < 0.20 THEN
      SET v_num_ventas_cliente = 0;                       -- 20%: nunca compro
    ELSEIF v_rnd_perfil < 0.65 THEN
      SET v_num_ventas_cliente = 1;                       -- 45%: una sola compra
    ELSEIF v_rnd_perfil < 0.90 THEN
      SET v_num_ventas_cliente = 2 + FLOOR(RAND() * 3);   -- 25%: 2 a 4 compras
    ELSE
      SET v_num_ventas_cliente = 5 + FLOOR(RAND() * 6);   -- 10%: 5 a 10 compras (VIP)
    END IF;

    SELECT fecha_registro INTO v_fecha_registro FROM clientes WHERE id_cliente = v_id_cliente_actual;

    SET j = 0;
    WHILE j < v_num_ventas_cliente DO
      SET v_fecha_venta = DATE_ADD(v_fecha_registro, INTERVAL FLOOR(RAND() * GREATEST(DATEDIFF(NOW(), v_fecha_registro), 1)) DAY);
      SET v_fecha_venta = v_fecha_venta + INTERVAL FLOOR(RAND() * 24) HOUR + INTERVAL FLOOR(RAND() * 60) MINUTE;
      SET v_estado = ELT(FLOOR(1 + RAND() * 10), 'Entregado', 'Entregado', 'Entregado', 'Entregado', 'Entregado', 'Enviado', 'Enviado', 'Procesando', 'Pendiente de Pago', 'Cancelado');
      SET v_id_sucursal = FLOOR(v_min_sucursal + RAND() * (v_max_sucursal - v_min_sucursal + 1));
      IF RAND() < 0.3 THEN
        SET v_id_promocion = FLOOR(v_min_promo + RAND() * (v_max_promo - v_min_promo + 1));
      ELSE
        SET v_id_promocion = NULL;
      END IF;

      INSERT INTO ventas (id_cliente, fecha_venta, estado, id_sucursal, id_promocion, fecha_pago, metodo_pago)
      VALUES (v_id_cliente_actual, v_fecha_venta, v_estado, v_id_sucursal, v_id_promocion,
              IF(v_estado IN ('Procesando','Enviado','Entregado'), v_fecha_venta, NULL),
              ELT(FLOOR(1 + RAND() * 3), 'Tarjeta', 'Transferencia', 'Contraentrega'));
      SET v_id_venta_actual = LAST_INSERT_ID();

      SET v_num_items = 1 + FLOOR(RAND() * 4);
      SET j = j + 0; -- no-op, mantiene alcance de variables
      BEGIN
        DECLARE k INT DEFAULT 0;
        WHILE k < v_num_items DO
          SET v_id_producto_item = FLOOR(v_min_prod + RAND() * (v_max_prod - v_min_prod + 1));
          SET v_cantidad_item = 1 + FLOOR(RAND() * 5);
          SELECT precio INTO v_precio_item FROM productos WHERE id_producto = v_id_producto_item;
          INSERT INTO detalle_ventas (id_venta, id_producto, cantidad, precio_unitario_congelado)
          VALUES (v_id_venta_actual, v_id_producto_item, v_cantidad_item, v_precio_item);
          SET k = k + 1;
        END WHILE;
      END;

      SET j = j + 1;
    END WHILE;
    SET i = i + 1;
  END WHILE;

  -- Recalcular totales de venta a partir del detalle (no hay triggers activos aun en este script)
  UPDATE ventas v
  SET v.total = (SELECT COALESCE(SUM(d.subtotal), 0) FROM detalle_ventas d WHERE d.id_venta = v.id_venta);

  -- Actualizar total_gastado y fecha_ultima_compra de clientes (ventas no canceladas)
  UPDATE clientes c
  LEFT JOIN (
    SELECT id_cliente, SUM(total) AS gasto, MAX(fecha_venta) AS ultima
    FROM ventas
    WHERE estado <> 'Cancelado'
    GROUP BY id_cliente
  ) x ON x.id_cliente = c.id_cliente
  SET c.total_gastado = COALESCE(x.gasto, 0),
      c.fecha_ultima_compra = x.ultima;

  -- Nivel de lealtad segun umbrales de configuracion_sistema (mismos umbrales que fn_DeterminarNivelLealtad)
  UPDATE clientes
  SET nivel_lealtad = CASE
    WHEN total_gastado >= 2000 THEN 'Oro'
    WHEN total_gastado >= 500  THEN 'Plata'
    ELSE 'Bronce'
  END;

  -- Suspender clientes sin compras hace mas de 1 anio (fecha_registro antigua y sin ventas)
  UPDATE clientes
  SET activo = FALSE
  WHERE fecha_ultima_compra IS NULL
    AND fecha_registro < DATE_SUB(NOW(), INTERVAL 365 DAY);

  -- ---------------------------------------------------------------
  -- VISITAS_PRODUCTOS (1500)
  -- ---------------------------------------------------------------
  SET i = 0;
  WHILE i < 1500 DO
    INSERT INTO visitas_productos (id_producto, id_cliente, fecha_visita, ip_origen)
    VALUES (
      FLOOR(v_min_prod + RAND() * (v_max_prod - v_min_prod + 1)),
      IF(RAND() < 0.6, FLOOR(v_min_cli + RAND() * (v_max_cli - v_min_cli + 1)), NULL),
      DATE_SUB(NOW(), INTERVAL FLOOR(RAND() * 540) DAY) + INTERVAL FLOOR(RAND() * 86400) SECOND,
      CONCAT(FLOOR(RAND()*255), '.', FLOOR(RAND()*255), '.', FLOOR(RAND()*255), '.', FLOOR(RAND()*255))
    );
    SET i = i + 1;
  END WHILE;

  -- forzar 5 productos "muy vistos, poco comprados"
  UPDATE productos SET id_producto = id_producto WHERE 1 = 0; -- no-op de seguridad
  SET i = 0;
  WHILE i < 5 DO
    INSERT INTO visitas_productos (id_producto, id_cliente, fecha_visita)
    SELECT id_producto, NULL, DATE_SUB(NOW(), INTERVAL FLOOR(RAND()*100) DAY)
    FROM (SELECT id_producto FROM productos ORDER BY RAND() LIMIT 1) AS sub,
         (SELECT 1 FROM information_schema.tables LIMIT 40) AS multiplicador;
    SET i = i + 1;
  END WHILE;

  -- ---------------------------------------------------------------
  -- CARRITOS + CARRITO_ITEMS (150 carritos)
  -- ---------------------------------------------------------------
  SET i = 0;
  WHILE i < 150 DO
    SET v_id_cliente_actual = FLOOR(v_min_cli + RAND() * (v_max_cli - v_min_cli + 1));
    IF RAND() < 0.4 THEN
      SET v_estado = 'Abandonado';
    ELSEIF RAND() < 0.5 THEN
      SET v_estado = 'Convertido';
    ELSE
      SET v_estado = 'Activo';
    END IF;

    INSERT INTO carritos (id_cliente, fecha_creacion, fecha_actualizacion, estado)
    VALUES (
      v_id_cliente_actual,
      DATE_SUB(NOW(), INTERVAL FLOOR(RAND() * 200) DAY),
      IF(v_estado = 'Abandonado', DATE_SUB(NOW(), INTERVAL (73 + FLOOR(RAND() * 400)) HOUR), DATE_SUB(NOW(), INTERVAL FLOOR(RAND()*48) HOUR)),
      v_estado
    );
    SET v_id_venta_actual = LAST_INSERT_ID();

    SET v_num_items = 1 + FLOOR(RAND() * 4);
    BEGIN
      DECLARE k INT DEFAULT 0;
      WHILE k < v_num_items DO
        INSERT IGNORE INTO carrito_items (id_carrito, id_producto, cantidad)
        VALUES (v_id_venta_actual, FLOOR(v_min_prod + RAND() * (v_max_prod - v_min_prod + 1)), 1 + FLOOR(RAND()*3));
        SET k = k + 1;
      END WHILE;
    END;
    SET i = i + 1;
  END WHILE;

  -- ---------------------------------------------------------------
  -- RESENAS_PRODUCTOS (250)
  -- ---------------------------------------------------------------
  SET i = 0;
  WHILE i < 250 DO
    INSERT IGNORE INTO resenas_productos (id_producto, id_cliente, calificacion, comentario, aprobada)
    VALUES (
      FLOOR(v_min_prod + RAND() * (v_max_prod - v_min_prod + 1)),
      FLOOR(v_min_cli + RAND() * (v_max_cli - v_min_cli + 1)),
      1 + FLOOR(RAND() * 5),
      ELT(FLOOR(1 + RAND()*5), 'Excelente producto', 'Cumple lo esperado', 'No lo recomiendo', 'Buena relacion calidad-precio', 'Llego en buen estado'),
      RAND() < 0.85
    );
    SET i = i + 1;
  END WHILE;

  -- ---------------------------------------------------------------
  -- REFERIDOS_CLIENTES (40)
  -- ---------------------------------------------------------------
  SET i = 0;
  WHILE i < 40 DO
    SET v_id_cliente_actual = FLOOR(v_min_cli + RAND() * (v_max_cli - v_min_cli + 1));
    SET v_id_venta_actual = FLOOR(v_min_cli + RAND() * (v_max_cli - v_min_cli + 1));
    IF v_id_cliente_actual <> v_id_venta_actual THEN
      INSERT IGNORE INTO referidos_clientes (id_cliente_referidor, id_cliente_referido, recompensa_aplicada)
      VALUES (v_id_cliente_actual, v_id_venta_actual, RAND() < 0.5);
    END IF;
    SET i = i + 1;
  END WHILE;

  -- ---------------------------------------------------------------
  -- LOG_INTENTOS_LOGIN (300 + rafagas de fallos para deteccion de fraude)
  -- ---------------------------------------------------------------
  SET i = 0;
  WHILE i < 300 DO
    SET v_id_cliente_actual = FLOOR(v_min_cli + RAND() * (v_max_cli - v_min_cli + 1));
    INSERT INTO log_intentos_login (email_intento, id_cliente, exitoso, ip_origen, fecha_intento, motivo_fallo)
    SELECT email, v_id_cliente_actual, RAND() < 0.9,
           CONCAT(FLOOR(RAND()*255),'.',FLOOR(RAND()*255),'.',FLOOR(RAND()*255),'.',FLOOR(RAND()*255)),
           DATE_SUB(NOW(), INTERVAL FLOOR(RAND()*180) DAY) + INTERVAL FLOOR(RAND()*86400) SECOND,
           IF(RAND() < 0.9, NULL, 'Contrasena incorrecta')
    FROM clientes WHERE id_cliente = v_id_cliente_actual;
    SET i = i + 1;
  END WHILE;

  -- rafaga de 6 intentos fallidos seguidos para un cliente (simular actividad sospechosa)
  SELECT email INTO v_nombre FROM clientes WHERE id_cliente = v_min_cli;
  SET i = 0;
  WHILE i < 6 DO
    INSERT INTO log_intentos_login (email_intento, id_cliente, exitoso, ip_origen, fecha_intento, motivo_fallo)
    VALUES (v_nombre, v_min_cli, FALSE, '190.10.20.30', DATE_SUB(NOW(), INTERVAL (10 - i) MINUTE), 'Contrasena incorrecta');
    SET i = i + 1;
  END WHILE;

  -- ---------------------------------------------------------------
  -- DEVOLUCIONES (30, sobre detalle_ventas existentes)
  -- ---------------------------------------------------------------
  SET i = 0;
  WHILE i < 30 DO
    SELECT id_detalle, precio_unitario_congelado, cantidad INTO v_id_venta_actual, v_precio_item, v_cantidad_item
    FROM detalle_ventas ORDER BY RAND() LIMIT 1;
    INSERT INTO devoluciones (id_detalle, cantidad_devuelta, motivo, monto_credito, estado)
    VALUES (v_id_venta_actual, 1, ELT(FLOOR(1+RAND()*3), 'Producto defectuoso', 'No era lo esperado', 'Cambio de opinion'),
            ROUND(v_precio_item, 2), IF(RAND() < 0.85, 'Procesada', 'Rechazada'));
    SET i = i + 1;
  END WHILE;

END$$

DELIMITER ;

CALL sp_poblar_datos_demo();
DROP PROCEDURE sp_poblar_datos_demo;

-- =====================================================================
-- FIN DE 01_Esquema_y_Datos.sql
-- =====================================================================
