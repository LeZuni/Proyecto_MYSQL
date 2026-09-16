-- =====================================================================
-- 04_Seguridad.sql
-- Proyecto de Base de Datos para un E-commerce — Roles, usuarios, vistas
-- de seguridad y politica de contrasenas.
-- Motor: MySQL 8.x
-- Requiere haber ejecutado antes: 01_Esquema_y_Datos.sql
-- Orden de ejecucion final del proyecto: 01 -> 02 -> 03 -> 04 -> 05 -> 06 -> 07
--
-- Este script es re-ejecutable: al inicio se hace DROP ROLE/DROP USER
-- IF EXISTS de todos los objetos que crea, para poder correrlo varias
-- veces sobre la misma base de datos sin errores.
--
-- =====================================================================
-- DECISIONES DE DISENO IMPORTANTES (leer antes de ejecutar)
-- =====================================================================
--
-- 1) DEPENDENCIAS HACIA ADELANTE (objetos que aun no existen cuando este
--    archivo corre en la secuencia 01->07):
--
--      a) La tabla log_cambios_precio la crea 05_Triggers.sql.
--         El rol Auditor_Financiero necesita SELECT sobre ella.
--      b) Los procedimientos sp_GenerarReporteMensual, sp_DashboardAdmin
--         y sp_AplicarDescuentoCategoria los crea 07_Procedimientos_Almacenados.sql.
--         El rol Gerente_Marketing necesita EXECUTE sobre ellos.
--
--    En MySQL, GRANT sobre una TABLA que no existe falla con error 1146
--    ("Table doesn't exist") y GRANT EXECUTE sobre un PROCEDIMIENTO que
--    no existe falla con error 1305 ("PROCEDURE does not exist") — se
--    verifico este comportamiento contra el servidor real antes de
--    escribir este script. Es decir, un GRANT plano sobre esos objetos
--    rompe la ejecucion de 04 (y de toda la secuencia 01->07, ya que 04
--    corre ANTES que 05 y 07).
--
--    DECISION ADOPTADA: en vez de omitir estos GRANT o de crear tablas
--    y procedimientos "stub" (que habria que recordar borrar y que
--    ensuciarian el esquema), estos GRANT puntuales se ejecutan dentro
--    de procedimientos temporales con un DECLARE ... CONTINUE HANDLER
--    que atrapa el error correspondiente (1146 o 1305), imprime un
--    aviso legible y permite que el resto del script continue sin
--    interrumpirse. El procedimiento temporal se elimina (DROP) justo
--    despues de usarlo, por lo que no queda ningun objeto "de prueba"
--    en el esquema final.
--
--    CONSECUENCIA PRACTICA: si este archivo se ejecuta en el orden
--    01->02->03->04->05->06->07 tal cual, el GRANT hacia log_cambios_precio
--    y los GRANT EXECUTE de Gerente_Marketing se OMITIRAN silenciosamente
--    (se vera el aviso por consola) porque en ese punto los objetos aun
--    no existen. Para que esos privilegios queden efectivamente
--    otorgados en un despliegue real, basta con volver a ejecutar este
--    mismo archivo 04_Seguridad.sql UNA VEZ MAS despues de haber corrido
--    05_Triggers.sql y 07_Procedimientos_Almacenados.sql (el script es
--    idempotente: vuelve a crear roles/usuarios/vistas sin duplicar nada
--    y esta vez los GRANT diferidos si se aplicaran porque los objetos
--    ya existen). No se modifica ningun otro archivo del proyecto para
--    resolver esto, tal como se pidio.
--
-- 2) La politica de contrasenas (component_validate_password) tambien se
--    aisla con el mismo patron de manejador de errores, porque puede
--    fallar si el componente ya esta instalado o si el servidor no lo
--    tiene disponible (no es un caso critico para el resto del script).
--
-- =====================================================================

USE ecommerce_avanzado;

-- =====================================================================
-- LIMPIEZA PREVIA (para que el script sea re-ejecutable)
-- =====================================================================

DROP USER IF EXISTS 'admin_user'@'%';
DROP USER IF EXISTS 'marketing_user'@'%';
DROP USER IF EXISTS 'analista_user'@'%';
DROP USER IF EXISTS 'inventory_user'@'%';
DROP USER IF EXISTS 'support_user'@'%';
DROP USER IF EXISTS 'auditor_user'@'%';
DROP USER IF EXISTS 'visitante_user'@'%';

DROP ROLE IF EXISTS 'Administrador_Sistema';
DROP ROLE IF EXISTS 'Gerente_Marketing';
DROP ROLE IF EXISTS 'Analista_Datos';
DROP ROLE IF EXISTS 'Empleado_Inventario';
DROP ROLE IF EXISTS 'Atencion_Cliente';
DROP ROLE IF EXISTS 'Auditor_Financiero';
DROP ROLE IF EXISTS 'Visitante';

DROP VIEW IF EXISTS v_ventas_mi_sucursal;
DROP VIEW IF EXISTS v_info_clientes_basica;

-- =====================================================================
-- SECCION 1: ROLES Y SUS PRIVILEGIOS
-- =====================================================================

CREATE ROLE 'Administrador_Sistema';
CREATE ROLE 'Gerente_Marketing';
CREATE ROLE 'Analista_Datos';
CREATE ROLE 'Empleado_Inventario';
CREATE ROLE 'Atencion_Cliente';
CREATE ROLE 'Auditor_Financiero';
CREATE ROLE 'Visitante';

-- ---------------------------------------------------------------------
-- 1.1 Administrador_Sistema: control total sobre la base de datos,
--     incluyendo la capacidad de otorgar privilegios a otros (WITH GRANT OPTION).
-- ---------------------------------------------------------------------
GRANT ALL PRIVILEGES ON ecommerce_avanzado.* TO 'Administrador_Sistema' WITH GRANT OPTION;

-- ---------------------------------------------------------------------
-- 1.2 Gerente_Marketing: lectura de ventas/clientes para analisis de
--     campanas, y ejecucion de procedimientos de reporte/descuento.
-- ---------------------------------------------------------------------
GRANT SELECT ON ecommerce_avanzado.ventas   TO 'Gerente_Marketing';
GRANT SELECT ON ecommerce_avanzado.clientes TO 'Gerente_Marketing';

-- GRANT EXECUTE diferido (ver DECISION 1.b al inicio del archivo): los
-- procedimientos referenciados los crea 07_Procedimientos_Almacenados.sql.
DELIMITER $$
CREATE PROCEDURE sp_tmp_grant_execute_marketing()
BEGIN
  DECLARE CONTINUE HANDLER FOR 1305 -- ER_SP_DOES_NOT_EXIST
    BEGIN
      SELECT CONCAT(
        'AVISO: no se otorgo EXECUTE sobre uno o mas procedimientos ',
        '(sp_GenerarReporteMensual / sp_DashboardAdmin / sp_AplicarDescuentoCategoria) ',
        'porque aun no existen. Vuelva a ejecutar 04_Seguridad.sql despues de ',
        '07_Procedimientos_Almacenados.sql para que Gerente_Marketing reciba EXECUTE.'
      ) AS aviso;
    END;

  GRANT EXECUTE ON PROCEDURE ecommerce_avanzado.sp_GenerarReporteMensual    TO 'Gerente_Marketing';
  GRANT EXECUTE ON PROCEDURE ecommerce_avanzado.sp_DashboardAdmin           TO 'Gerente_Marketing';
  GRANT EXECUTE ON PROCEDURE ecommerce_avanzado.sp_AplicarDescuentoCategoria TO 'Gerente_Marketing';
END$$
DELIMITER ;

CALL sp_tmp_grant_execute_marketing();
DROP PROCEDURE sp_tmp_grant_execute_marketing;

-- ---------------------------------------------------------------------
-- 1.3 Analista_Datos: SELECT en todas las tablas EXCEPTO las de
--     auditoria/log (informacion sensible de trazabilidad interna).
--     No se otorga DELETE ni TRUNCATE en ningun caso (ver tambien la
--     seccion 5, donde se REVOCA explicitamente por documentacion).
-- ---------------------------------------------------------------------
GRANT SELECT ON ecommerce_avanzado.configuracion_sistema        TO 'Analista_Datos';
GRANT SELECT ON ecommerce_avanzado.sucursales                   TO 'Analista_Datos';
GRANT SELECT ON ecommerce_avanzado.mapeo_usuario_sucursal        TO 'Analista_Datos';
GRANT SELECT ON ecommerce_avanzado.categorias                   TO 'Analista_Datos';
GRANT SELECT ON ecommerce_avanzado.proveedores                  TO 'Analista_Datos';
GRANT SELECT ON ecommerce_avanzado.promociones                  TO 'Analista_Datos';
GRANT SELECT ON ecommerce_avanzado.productos                    TO 'Analista_Datos';
GRANT SELECT ON ecommerce_avanzado.clientes                     TO 'Analista_Datos';
GRANT SELECT ON ecommerce_avanzado.ventas                       TO 'Analista_Datos';
GRANT SELECT ON ecommerce_avanzado.detalle_ventas                TO 'Analista_Datos';
GRANT SELECT ON ecommerce_avanzado.carritos                     TO 'Analista_Datos';
GRANT SELECT ON ecommerce_avanzado.carrito_items                 TO 'Analista_Datos';
GRANT SELECT ON ecommerce_avanzado.resenas_productos             TO 'Analista_Datos';
GRANT SELECT ON ecommerce_avanzado.referidos_clientes            TO 'Analista_Datos';
GRANT SELECT ON ecommerce_avanzado.visitas_productos             TO 'Analista_Datos';
GRANT SELECT ON ecommerce_avanzado.ranking_productos_popular     TO 'Analista_Datos';
GRANT SELECT ON ecommerce_avanzado.productos_relacionados        TO 'Analista_Datos';
GRANT SELECT ON ecommerce_avanzado.alertas_stock                 TO 'Analista_Datos';
GRANT SELECT ON ecommerce_avanzado.ventas_archivadas             TO 'Analista_Datos';
GRANT SELECT ON ecommerce_avanzado.detalle_ventas_archivadas     TO 'Analista_Datos';
GRANT SELECT ON ecommerce_avanzado.respaldo_log                  TO 'Analista_Datos';
GRANT SELECT ON ecommerce_avanzado.respaldo_productos            TO 'Analista_Datos';
GRANT SELECT ON ecommerce_avanzado.respaldo_clientes             TO 'Analista_Datos';
GRANT SELECT ON ecommerce_avanzado.respaldo_ventas               TO 'Analista_Datos';
GRANT SELECT ON ecommerce_avanzado.staging_temporal              TO 'Analista_Datos';
GRANT SELECT ON ecommerce_avanzado.resumen_ventas_diarias        TO 'Analista_Datos';
GRANT SELECT ON ecommerce_avanzado.kpis_mensuales                TO 'Analista_Datos';
GRANT SELECT ON ecommerce_avanzado.snapshot_stock_diario         TO 'Analista_Datos';
GRANT SELECT ON ecommerce_avanzado.segmentacion_rfm              TO 'Analista_Datos';
GRANT SELECT ON ecommerce_avanzado.proyeccion_demanda            TO 'Analista_Datos';
GRANT SELECT ON ecommerce_avanzado.reporte_rendimiento_proveedores TO 'Analista_Datos';
GRANT SELECT ON ecommerce_avanzado.tamano_bd_log                 TO 'Analista_Datos';
GRANT SELECT ON ecommerce_avanzado.notificaciones_cumpleanos     TO 'Analista_Datos';
GRANT SELECT ON ecommerce_avanzado.devoluciones                  TO 'Analista_Datos';
-- Explicitamente EXCLUIDAS de Analista_Datos (tablas de auditoria/log):
--   auditoria_clientes, log_cambios_precio, log_estado_pedido, log_permisos,
--   log_intentos_login, log_actividad_fraudulenta, log_consistencia_datos,
--   log_ajustes_stock

-- ---------------------------------------------------------------------
-- 1.4 Empleado_Inventario: solo puede leer productos y actualizar
--     UNICAMENTE stock y ubicacion_almacen (nunca precio ni costo).
--     El GRANT UPDATE es a nivel de columna, no de tabla completa.
-- ---------------------------------------------------------------------
GRANT SELECT ON ecommerce_avanzado.productos TO 'Empleado_Inventario';
GRANT UPDATE (stock, ubicacion_almacen) ON ecommerce_avanzado.productos TO 'Empleado_Inventario';
-- NO se otorga UPDATE sobre la tabla completa ni sobre las columnas
-- precio/costo: cualquier intento de UPDATE productos SET precio = ...
-- por parte de este rol debe fallar por falta de privilegios.

-- ---------------------------------------------------------------------
-- 1.5 Atencion_Cliente: ventas (para dar soporte sobre pedidos) y datos
--     basicos de clientes a traves de una vista que oculta columnas
--     sensibles. No se otorga acceso a productos.precio/productos.costo:
--     se decide NO otorgar SELECT sobre productos en absoluto para este
--     rol, ya que el equipo de soporte no necesita ver costos/margenes
--     para atender pedidos (id_producto/cantidad ya quedan visibles a
--     traves de detalle_ventas si se requiere, sin exponer precio/costo
--     "vivos" de la tabla productos).
--     El GRANT sobre la vista v_info_clientes_basica se hace en la
--     Seccion 3, despues de crear la vista (dependencia de orden).
-- ---------------------------------------------------------------------
GRANT SELECT ON ecommerce_avanzado.ventas TO 'Atencion_Cliente';

-- ---------------------------------------------------------------------
-- 1.6 Auditor_Financiero: ventas, productos y el log de cambios de
--     precio (para conciliar montos y detectar variaciones de precio).
-- ---------------------------------------------------------------------
GRANT SELECT ON ecommerce_avanzado.ventas    TO 'Auditor_Financiero';
GRANT SELECT ON ecommerce_avanzado.productos TO 'Auditor_Financiero';

-- GRANT diferido (ver DECISION 1.a al inicio del archivo): la tabla
-- log_cambios_precio la crea 05_Triggers.sql.
DELIMITER $$
CREATE PROCEDURE sp_tmp_grant_log_cambios_precio()
BEGIN
  DECLARE CONTINUE HANDLER FOR 1146 -- ER_NO_SUCH_TABLE
    BEGIN
      SELECT CONCAT(
        'AVISO: no se otorgo SELECT sobre log_cambios_precio a Auditor_Financiero ',
        'porque la tabla aun no existe. Vuelva a ejecutar 04_Seguridad.sql despues ',
        'de 05_Triggers.sql para que el privilegio quede efectivo.'
      ) AS aviso;
    END;

  GRANT SELECT ON ecommerce_avanzado.log_cambios_precio TO 'Auditor_Financiero';
END$$
DELIMITER ;

CALL sp_tmp_grant_log_cambios_precio();
DROP PROCEDURE sp_tmp_grant_log_cambios_precio;

-- ---------------------------------------------------------------------
-- 1.7 Visitante: solo lectura del catalogo de productos (uso publico,
--     por ejemplo una vitrina sin autenticacion).
-- ---------------------------------------------------------------------
GRANT SELECT ON ecommerce_avanzado.productos TO 'Visitante';

-- =====================================================================
-- SECCION 2: USUARIOS Y ASIGNACION DE ROLES
-- =====================================================================
-- Contrasenas de ejemplo para uso academico/demostrativo unicamente;
-- en un entorno real deben rotarse y gestionarse mediante un vault.

CREATE USER 'admin_user'@'%'      IDENTIFIED BY 'Adm1n_S3guro_2024!';
CREATE USER 'marketing_user'@'%'  IDENTIFIED BY 'Mkt_C4mpana_2024!';
CREATE USER 'analista_user'@'%'   IDENTIFIED BY 'An4lista_D4tos_2024!' WITH MAX_QUERIES_PER_HOUR 100;
CREATE USER 'inventory_user'@'%'  IDENTIFIED BY 'Inv3ntario_Bod3ga_2024!';
CREATE USER 'support_user'@'%'    IDENTIFIED BY 'Sop0rte_Cli3nte_2024!';
CREATE USER 'auditor_user'@'%'    IDENTIFIED BY 'Aud1tor_F1nanzas_2024!';
CREATE USER 'visitante_user'@'%'  IDENTIFIED BY 'V1sitante_Publ1co_2024!';

GRANT 'Administrador_Sistema' TO 'admin_user'@'%';
GRANT 'Gerente_Marketing'     TO 'marketing_user'@'%';
GRANT 'Analista_Datos'        TO 'analista_user'@'%';
GRANT 'Empleado_Inventario'   TO 'inventory_user'@'%';
GRANT 'Atencion_Cliente'      TO 'support_user'@'%';
GRANT 'Auditor_Financiero'    TO 'auditor_user'@'%';
GRANT 'Visitante'             TO 'visitante_user'@'%';

SET DEFAULT ROLE 'Administrador_Sistema' TO 'admin_user'@'%';
SET DEFAULT ROLE 'Gerente_Marketing'     TO 'marketing_user'@'%';
SET DEFAULT ROLE 'Analista_Datos'        TO 'analista_user'@'%';
SET DEFAULT ROLE 'Empleado_Inventario'   TO 'inventory_user'@'%';
SET DEFAULT ROLE 'Atencion_Cliente'      TO 'support_user'@'%';
SET DEFAULT ROLE 'Auditor_Financiero'    TO 'auditor_user'@'%';
SET DEFAULT ROLE 'Visitante'             TO 'visitante_user'@'%';

-- =====================================================================
-- SECCION 3: VISTAS DE SEGURIDAD
-- =====================================================================

-- ---------------------------------------------------------------------
-- 3.1 v_info_clientes_basica: expone todas las columnas de clientes
--     EXCEPTO contrasena_hash (credencial), saldo_credito (dato
--     financiero sensible) y anonimizado (bandera interna de
--     cumplimiento/privacidad).
--
--     SQL SECURITY: se deja el valor por defecto, DEFINER (el creador
--     del script, tipicamente una cuenta administradora con acceso
--     completo a clientes). Esto es intencional y es justo lo que hace
--     util a esta vista como mecanismo de seguridad por columnas: con
--     SQL SECURITY DEFINER, quien consulta la vista (por ejemplo
--     support_user) NO necesita ningun privilegio directo sobre la
--     tabla clientes; le basta el GRANT SELECT sobre la vista misma
--     (otorgado mas abajo). Si se usara SQL SECURITY INVOKER aqui, cada
--     usuario tendria que tener ademas SELECT directo sobre clientes
--     completa, lo cual expondria contrasena_hash/saldo_credito/
--     anonimizado y anularia el proposito de la vista.
-- ---------------------------------------------------------------------
CREATE VIEW v_info_clientes_basica AS
SELECT
  id_cliente,
  nombre,
  apellido,
  email,
  direccion_envio,
  fecha_registro,
  fecha_nacimiento,
  ciudad,
  region,
  total_gastado,
  fecha_ultima_compra,
  nivel_lealtad,
  activo
FROM clientes;

GRANT SELECT ON ecommerce_avanzado.v_info_clientes_basica TO 'Atencion_Cliente';

-- ---------------------------------------------------------------------
-- 3.2 v_ventas_mi_sucursal: simula seguridad a nivel de fila (row-level
--     security) por sucursal, algo que MySQL no soporta de forma nativa.
--     La vista filtra ventas usando la sucursal asociada al usuario de
--     base de datos que ejecuta la consulta (CURRENT_USER()), segun el
--     mapeo definido en mapeo_usuario_sucursal.
--
--     El privilegio de SELECT se otorga sobre esta VISTA, nunca sobre
--     la tabla ventas directamente, para los usuarios que deban ver
--     unicamente las ventas de su propia sucursal. SQL SECURITY INVOKER
--     es indispensable aqui: si la vista fuera SQL SECURITY DEFINER,
--     CURRENT_USER() dentro de la vista devolveria el usuario definidor
--     (quien la creo) en vez del usuario que realmente esta consultando,
--     rompiendo el filtrado por sucursal.
--
--     CONTRAPARTIDA de usar INVOKER (a diferencia de v_info_clientes_basica,
--     que usa DEFINER): con SQL SECURITY INVOKER, el usuario que consulta
--     la vista SI necesita privilegio SELECT directo sobre las tablas
--     base referenciadas (ventas y mapeo_usuario_sucursal), ademas del
--     SELECT sobre la vista. Por eso, mas abajo, a quien se le otorgue
--     esta vista tambien se le otorga SELECT sobre mapeo_usuario_sucursal.
-- ---------------------------------------------------------------------
CREATE SQL SECURITY INVOKER VIEW v_ventas_mi_sucursal AS
SELECT v.*
FROM ventas v
WHERE v.id_sucursal = (
  SELECT mus.id_sucursal
  FROM mapeo_usuario_sucursal mus
  WHERE mus.usuario_bd = CURRENT_USER()
);

-- Se otorga tambien a Atencion_Cliente como demostracion del mecanismo
-- de seguridad por sucursal (ademas del SELECT amplio sobre ventas ya
-- otorgado en la Seccion 1.5). En un despliegue mas estricto, donde se
-- quisiera limitar a cada agente de soporte a su propia sucursal, bastaria
-- con REVOCAR el SELECT directo sobre ventas y dejar unicamente esta vista.
-- Requiere ademas SELECT directo sobre mapeo_usuario_sucursal (ver nota
-- de SQL SECURITY INVOKER arriba): esta tabla solo expone el mapeo
-- usuario_bd -> id_sucursal, no datos sensibles, por lo que exponerla
-- via SELECT directo a este rol no representa un riesgo relevante.
GRANT SELECT ON ecommerce_avanzado.v_ventas_mi_sucursal    TO 'Atencion_Cliente';
GRANT SELECT ON ecommerce_avanzado.mapeo_usuario_sucursal  TO 'Atencion_Cliente';

-- Filas de ejemplo para mapeo_usuario_sucursal (formato 'usuario@host',
-- tal como lo devuelve CURRENT_USER() para una cuenta creada como
-- 'usuario'@'%'). Se usan sucursales ya existentes (creadas en 01).
INSERT INTO mapeo_usuario_sucursal (usuario_bd, id_sucursal) VALUES
  ('support_user@%', (SELECT id_sucursal FROM sucursales WHERE nombre = 'Sucursal Centro')),
  ('inventory_user@%', (SELECT id_sucursal FROM sucursales WHERE nombre = 'Sucursal Norte')),
  ('auditor_user@%', (SELECT id_sucursal FROM sucursales WHERE nombre = 'Sucursal Medellin'))
ON DUPLICATE KEY UPDATE id_sucursal = VALUES(id_sucursal);

-- =====================================================================
-- SECCION 4: POLITICA DE CONTRASENAS (component_validate_password)
-- =====================================================================
-- Esta seccion puede fallar/omitirse sin afectar el resto del script si
-- el componente ya esta instalado o si el servidor no lo tiene
-- disponible (por ejemplo, algunas imagenes Docker minimizadas de MySQL
-- no incluyen todos los componentes). Se aisla en un procedimiento
-- temporal con manejador de errores generico (SQLEXCEPTION) precisamente
-- porque no es critica para el resto de la seguridad definida arriba.
--
-- NOTA TECNICA: las variables validate_password.* solo existen una vez
-- instalado el componente. Si se escribieran como
-- "SET GLOBAL validate_password.policy = 'MEDIUM';" de forma literal
-- dentro del cuerpo del procedimiento, MySQL fallaria con error 1193
-- ("Unknown system variable") al momento de hacer CREATE PROCEDURE (la
-- validacion del nombre de la variable ocurre al compilar la rutina, no
-- al ejecutarla, sin importar que INSTALL COMPONENT aparezca antes en el
-- mismo cuerpo). Por eso esos dos SET GLOBAL se ejecutan como SQL
-- dinamico (PREPARE/EXECUTE): el texto se analiza en tiempo de
-- ejecucion, ya con el componente instalado, y si de todas formas
-- fallara, el error ahora si ocurre en tiempo de ejecucion y el
-- CONTINUE HANDLER lo atrapa correctamente.

DELIMITER $$
CREATE PROCEDURE sp_tmp_config_password_policy()
BEGIN
  DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
    BEGIN
      SELECT CONCAT(
        'AVISO: no se pudo instalar/configurar component_validate_password ',
        '(posiblemente ya estaba instalado o el servidor no lo tiene disponible). ',
        'Se omite sin afectar el resto de 04_Seguridad.sql.'
      ) AS aviso;
    END;

  INSTALL COMPONENT 'file://component_validate_password';

  SET @ddl_policy = "SET GLOBAL validate_password.policy = 'MEDIUM'";
  PREPARE stmt_policy FROM @ddl_policy;
  EXECUTE stmt_policy;
  DEALLOCATE PREPARE stmt_policy;

  SET @ddl_length = "SET GLOBAL validate_password.length = 8";
  PREPARE stmt_length FROM @ddl_length;
  EXECUTE stmt_length;
  DEALLOCATE PREPARE stmt_length;
END$$
DELIMITER ;

CALL sp_tmp_config_password_policy();
DROP PROCEDURE sp_tmp_config_password_policy;

-- =====================================================================
-- SECCION 5: RESTRICCIONES ADICIONALES
-- =====================================================================

-- ---------------------------------------------------------------------
-- 5.1 Analista_Datos jamas debe poder borrar datos ni estructuras.
--     Ya es redundante con el hecho de que nunca se le otorgo DELETE ni
--     DROP (Seccion 1.3 solo otorga SELECT), pero se deja el REVOKE de
--     forma EXPLICITA como documentacion/blindaje: si en el futuro
--     alguien agrega por error un GRANT ALL o un GRANT DELETE a este
--     rol, este REVOKE dejaria claro (y revertiria) que esa combinacion
--     no esta permitida para este perfil de solo lectura.
--
--     NOTA TECNICA: como a este rol nunca se le otorgo DELETE/DROP a
--     nivel de esquema completo, MySQL rechaza un REVOKE literal con
--     error 1141 ("There is no such grant defined for user ... ")
--     porque no existe una entrada de privilegio exacta que revocar en
--     ese nivel. Se envuelve en un procedimiento temporal con manejador
--     para el error 1141, de forma que el REVOKE sea un no-operacion
--     segura (documenta la intencion sin romper el script) tanto ahora
--     como si en el futuro cambia el conjunto de privilegios del rol.
-- ---------------------------------------------------------------------
DELIMITER $$
CREATE PROCEDURE sp_tmp_revoke_analista_delete_drop()
BEGIN
  DECLARE CONTINUE HANDLER FOR 1141 -- ER_NONEXISTING_GRANT
    BEGIN
      SELECT CONCAT(
        'AVISO: REVOKE DELETE, DROP sobre Analista_Datos fue un no-op ',
        '(el rol nunca tuvo esos privilegios a nivel de esquema completo). ',
        'Esto es lo esperado: se deja documentado que ese perfil no debe tenerlos.'
      ) AS aviso;
    END;

  REVOKE DELETE, DROP ON ecommerce_avanzado.* FROM 'Analista_Datos';
END$$
DELIMITER ;

CALL sp_tmp_revoke_analista_delete_drop();
DROP PROCEDURE sp_tmp_revoke_analista_delete_drop;

-- ---------------------------------------------------------------------
-- 5.2 Verificacion de que no exista una cuenta root accesible desde
--     cualquier host ('root'@'%'), que es una mala practica de
--     seguridad (el root deberia limitarse a 'root'@'localhost').
--
--     Para verificar manualmente en cualquier momento:
--       SELECT user, host FROM mysql.user WHERE user = 'root';
--
--     Si existe 'root'@'%', se elimina a continuacion. NO se toca
--     'root'@'localhost'. Nota: esto modifica la tabla mysql.user, que
--     es global a la instancia de MySQL (no exclusiva de
--     ecommerce_avanzado); se incluye porque el enunciado lo pide
--     explicitamente como parte del endurecimiento de seguridad.
-- ---------------------------------------------------------------------
DROP USER IF EXISTS 'root'@'%';

-- ---------------------------------------------------------------------
-- 5.3 Auditoria de intentos de login fallidos.
--     MySQL (el motor) no registra intentos de login a nivel de
--     aplicacion; por eso esta auditoria NO se implementa con un
--     mecanismo nativo del servidor, sino a nivel de aplicacion: la
--     tabla log_intentos_login (ya creada en 01_Esquema_y_Datos.sql)
--     se puebla desde el procedimiento sp_LoginCliente, definido en
--     07_Procedimientos_Almacenados.sql, cada vez que un cliente intenta
--     autenticarse (exitosa o fallidamente) desde la capa de aplicacion.
--     No hay nada adicional que crear aqui: este punto es unicamente
--     documentacion de donde vive el mecanismo real.
-- ---------------------------------------------------------------------

FLUSH PRIVILEGES;

-- =====================================================================
-- FIN DE 04_Seguridad.sql
-- =====================================================================
