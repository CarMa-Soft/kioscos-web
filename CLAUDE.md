# Kioscos y Almacenes (versión web)

Punto de venta web para kioscos y almacenes, para varios negocios con la misma app. Reemplaza a la app local "Kiosco"
(repo privado `CarMa-Soft/Kiosco`), que sigue siendo la referencia de las reglas del negocio: su `CLAUDE.md` describe
cada función y sus decisiones. Se migra por etapas (el plan está en los issues de ese repo).

**Este repo es público.** Todo lo que se sube (código, historial, issues, PR y comentarios) lo puede ver cualquiera.

## Estructura
| Carpeta | Qué es |
|---|---|
| `app/` | La app: HTML, CSS y módulos JS, sin compilar. Se publica tal cual en GitHub Pages. |
| `app/js/config.js` | Dirección del proyecto de Supabase y su clave pública (publishable). |
| `app/js/base.js` | Conexión con Supabase: `sb` (cliente), `llamar(funcion, args)`, el token del usuario con PIN y la traducción de errores. Toda la app habla con la base desde acá. |
| `app/js/app.js` | Arranque: entrar con la cuenta, elegir usuario y PIN, barra de secciones y rutas (`#/vender`, `#/caja`, `#/productos`, `#/usuarios`). Cada sección es `pantallaX(vista, ctx)`. |
| `app/js/ui.js` | Utilidades de pantalla: `$`, `esc`, `plata`, `numero` (acepta coma decimal), `aviso`, `correr`, `modal`, `confirmar`. |
| `app/js/catalogo.js` | Catálogo de productos en el navegador (ver abajo). |
| `app/js/vender.js`, `caja.js`, `productos.js`, `usuarios.js` | Las secciones. |
| `supabase/migrations/` | Cambios de la base, en orden. Se aplican solos al unirse a `main`. |
| `supabase/config.toml` | Configuración de la CLI de Supabase (solo para uso local). |
| `tests/` | Pruebas de la base en SQL (`NN_tema.sql`), con `pruebas.ok(...)` y `pruebas.falla(sql, patrón, qué)`. |
| `.github/workflows/` | `pages.yml` publica `app/`; `base.yml` aplica las migraciones; `pruebas.yml` corre `tests/` en cada PR. |
| `tools/servidor.js` | Servidor local: `node tools/servidor.js` → http://localhost:5180 |

## Seguridad (no negociable)
- **Claves:** en el código solo pueden ir la dirección del proyecto y la clave *publishable*. La clave secreta,
  la `service_role`, la contraseña de la base, la cadena de conexión y la clave de IA van solo en los secretos de
  GitHub Actions o de Supabase. Nunca en archivos, commits, issues ni en el chat. GitHub frena los push con claves.
- **Datos:** nunca subir datos reales (de un negocio o de la app local), ni exportaciones de la base. Las pruebas usan datos inventados.
- **La seguridad está en la base, no en las pantallas:** cualquiera puede leer el JS. Cada tabla tiene RLS
  (Supabase la activa sola en las tablas nuevas) y sus reglas. Las tablas nuevas **no** se exponen solas a la API:
  hay que dar los permisos (`grant`) a propósito, solo lo necesario.
- **Varios negocios:** cada tabla con datos de un negocio lleva `negocio_id` y reglas que solo dejan ver y tocar lo
  del propio negocio. Cada tabla nueva suma su prueba automática de que un negocio no ve lo de otro.
- **Funciones:** las operaciones que tocan varias tablas son funciones SQL atómicas que controlan el negocio y el rol
  antes de tocar algo. Siempre con `set search_path = ''` y nombres completos (`public.tabla`). Postgres deja
  ejecutar cualquier función a todos: cada función nueva lleva `revoke all ... from public` y `grant execute` solo a
  quien la necesita. `security definer` solo si hace falta, y entonces con controles explícitos.
- **Lo que no tiene que ver un empleado** (costos, márgenes, reportes) sale solo por funciones que controlan el rol.
- **Conversaciones sensibles** (precios, clientes, problemas de seguridad sin corregir) van en los issues del repo
  privado `CarMa-Soft/Kiosco`, no acá. Una falla de seguridad se avisa por "Report a vulnerability", no en un issue.
- **Scripts externos:** solo de `cdn.jsdelivr.net` y con la versión exacta (ej. `@supabase/supabase-js@2.118.0`).
  `app/index.html` tiene una Content-Security-Policy: si se agrega otro origen, hay que sumarlo ahí a propósito.

## Base de datos
- **Por ahora hay un solo proyecto** ("Kioscos y Almacenes", plan Free, región São Paulo): es desarrollo y producción
  a la vez. Una migración unida a `main` se aplica ahí enseguida. Antes del primer negocio real: plan Pro y un proyecto
  aparte para pruebas.
- **Migraciones:** un archivo nuevo por cambio en `supabase/migrations/`, con nombre `AAAAMMDDHHMMSS_descripcion.sql`
  (`supabase migration new descripcion` lo crea). **Nunca editar una migración ya unida a `main`**: se agrega otra. Si
  dos ramas agregan migraciones, el segundo en unir revisa que la suya tenga una fecha posterior a las de `main`.
- `base.yml` las aplica al unir a `main` (primero muestra cuáles con `--dry-run`). Usa el secreto `SUPABASE_DB_URL`.
- `estado_app()` devuelve la versión de la base (`base`): subirla cuando la app necesite saber que hay un cambio.
- **Pruebas:** `pruebas.yml` corre en cada PR que toca `supabase/` o `tests/`: aplica las migraciones que la base todavía
  no tiene y corre `tests/*.sql`, todo en una transacción que se deshace (no deja nada). Simulan cuentas y usuarios con
  `pruebas.como(cuenta, token)`. Cada archivo arranca con `set local role authenticated;` y termina con `reset role;`
  (si no, corre como dueño de la base y los controles de permisos no prueban nada). Los archivos corren en orden en la
  misma transacción: cada uno puede usar lo que armaron los anteriores. Un PR no se une si las pruebas fallan. Cada función o tabla nueva suma sus pruebas,
  incluida la de que otro negocio no la ve ni la toca.

## Cuentas, negocios y usuarios (etapa 2)
- **Cuentas** (Supabase Auth, email y contraseña), en `miembros`: la del dueño (`dueno`) y la de la PC del local
  (`local`). Cada cuenta es de un solo negocio. **El registro libre está desactivado**: las cuentas las crea CarMa-Soft.
- **Usuarios** (`usuarios`, como en la app local): personas con PIN de 4 a 8 números, rol `admin` (Dueño) o `empleado`.
  En la PC se entra una vez con la cuenta; después cada uno elige su nombre y pone su PIN (`iniciar_usuario`).
  5 PIN incorrectos seguidos bloquean a ese usuario 5 minutos.
- **Sesión del usuario:** `iniciar_usuario` devuelve un token (vence a las 16 horas) que la app manda en el encabezado
  `x-usuario-kiosco` en cada pedido (`base.js`). Solo vale con la misma cuenta y el mismo negocio.
- **Controles para las funciones:** `requiere_negocio()`, `requiere_usuario()`, `requiere_admin()` (cortan con el error
  para mostrar) y `mi_negocio()`, `usuario_actual_id()`, `es_admin()` (para reglas y condiciones). Un error con
  `hint = 'sesion'` hace que la app vuelva a pedir usuario y PIN.
- **Ninguna tabla se expone directo:** la app lee y escribe solo con funciones (`datos_inicio`, `listar_usuarios`,
  `guardar_usuario`, `cambiar_mi_pin`, `guardar_config`, `cerrar_usuario`).
- **Negocio suspendido:** `negocios.activo = false` corta el acceso a todas sus cuentas sin borrar nada.
- **Alta de un negocio** (la hace CarMa-Soft, nunca la app):
  1. Supabase → Authentication → Users → Add user, con **Auto Confirm User**: la cuenta del dueño y la de la PC del local.
     Las contraseñas las elige quien crea la cuenta y se las da al cliente; no se escriben en ningún otro lado.
  2. SQL Editor: `select public.admin_alta_negocio('Nombre', 'email.dueno', 'email.local', 'Nombre del dueño', 'PIN');`
     (el email del local puede ser `null`). Crea el negocio, sus cuentas y el primer usuario Dueño.

## Productos, caja y ventas (etapa 3)
- **Referencias compuestas:** las tablas con datos de un negocio tienen `unique (id, negocio_id)` y se referencian con
  `foreign key (x_id, negocio_id)`: la base no deja apuntar a un registro de otro negocio.
- **Catálogo en el navegador** (`catalogo.js`): se guarda en `localStorage` por negocio, **sin costos** (la PC la usan
  los empleados), y se actualiza con `catalogo(p_desde)`, que trae solo lo que cambió (también los dados de baja, para
  sacarlos). Cada cambio de un producto toca `productos.actualizado` (trigger). Así cada escaneo responde sin ir a internet.
  Los costos los ve solo el dueño, en Productos, pedidos a la base cada vez.
- **Venta** (`registrar_venta`): el precio sale de la base, nunca de la pantalla. Cada intento de cobro lleva una
  `clave` (uuid) que genera la pantalla: si se corta la conexión y se reintenta, la base devuelve la venta ya
  registrada (`repetida: true`) en lugar de registrarla otra vez. Las ventas se numeran por negocio.
  Los pagos (varias formas) tienen que sumar el total y van a la caja del turno.
- **Turnos:** uno abierto por negocio. Vende y carga movimientos quien lo abrió (o el dueño); lo cierra quien lo abrió
  (o el dueño). Las funciones que mueven plata o stock bloquean la fila del negocio (`for update`) para no cruzarse.
- **Anular** (solo dueño): devuelve el stock y saca la plata de la caja del turno abierto.
- **Productos:** un producto con ventas no se borra, se da de baja (`activo = false`).
- **Pendiente (etapa 4):** descuentos y recargos, balanza, cierre por billetes, devoluciones, reportes.

## Clientes y fiado (etapa 4a)
- Cuenta del cliente en `cc`: monto > 0 suma deuda (`cargo` por compra fiada, `ajuste`), < 0 la baja (`pago`, `ajuste`).
  Saldo = suma (positivo = debe). `Fiado` es una forma de pago más en `registrar_venta` (con `p_cliente_id`): va a la
  cuenta, no a la caja. Si el cliente tiene límite y lo pasaría, la base corta con `hint = 'limite'` y no registra nada;
  la pantalla pregunta y reintenta con `p_forzar_limite`.
- Cualquier usuario crea clientes y cobra (`cobrar_cliente`, entra a la caja del turno); el límite, los ajustes
  (`ajuste_cliente`, deuda anterior o corrección, sin plata) y las bajas los hace el dueño. Un cliente con saldo no se borra.
- Anular una venta fiada descuenta lo fiado de la cuenta; el turno hace falta solo si hubo pagos que pasaron por la caja.

## Forma de trabajo
- **Nunca commitear ni hacer push directo a `main`** (GitHub lo impide). Todo va en una rama y entra por pull request
  aprobado por el otro; el dueño de la organización puede unir un PR propio sin aprobación, pero siempre por PR.
- PR en español. Si resuelve un issue, la primera línea es `Closes #N` (o `Closes CarMa-Soft/Kiosco#N` si el issue es del repo privado).
- Las ramas se borran solas al unir el PR.
- Commits con el email privado de GitHub (`…@users.noreply.github.com`), no el personal: `git config user.email` en este repo.
- GitHub CLI en Windows: `"C:\Program Files\GitHub CLI\gh.exe"`.
- Avisarse antes de tocar la misma función de la base o el mismo archivo a la vez.
