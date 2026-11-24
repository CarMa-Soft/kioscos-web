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
| `app/js/app.js` | Arranque: entrar con la cuenta, elegir usuario y PIN, menú de secciones y rutas (`#/inicio`, `#/vender`, `#/caja`…; abre siempre en Hoy). Cada sección es `pantallaX(vista, ctx)`. **Menú** (`menuPorGrupos`): en la PC, barra a la izquierda fija al bajar, que se colapsa a solo íconos con « / » (cada PC lo recuerda en `localStorage` `menu-colapsado`); en el celular (hasta 800 px), barra arriba con ☰. Cada entrada de `SECCIONES` tiene `ico` y `grupo` (`dia`, `mercaderia`, `numeros`, `admin`): bloques sin título separados por una línea, `admin` (Usuarios y Ajustes) a continuación de los demás, los vacíos no se muestran; el bloque del usuario va abajo de todo, en un recuadro aparte; Vender destacado en verde. Abajo, el bloque del usuario: Ayuda, nombre y rol, Cambiar mi PIN (solo el empleado; `cambiarMiPin` de usuarios.js) y Cambiar de usuario. En el celular, el alto de la barra va a `--alto-barra` (`seguirAltoBarra`): lo usan `scroll-padding-top` y los paneles fijos. **Teclado** (`teclasDelMenu`): con el foco en el menú, ↑ ↓ (con vuelta; al pasar por una sección se muestra su pantalla, `mostrarAlPasar`, y el foco sigue en el menú), Inicio/Fin y Ctrl + → (a la pantalla: su primer campo, `enfocarPantalla`); Enter abre la sección y el foco queda en el menú. El atajo para ir al menú (`irAlMenu`) es la config `atajo_menu` del negocio (Ajustes → Teclado, Ctrl + ← de fábrica; se puede elegir Ctrl + ←, no Ctrl + →; `teclado.js`: `atajoDe`, `esAtajo`, `problemaAtajo` controla que no choque con F1–F3, Alt + número, las del navegador ni una tecla sola). Foco visible: `:focus-visible` con anillo verde en toda la app. |
| `app/manifest.webmanifest`, `app/sw.js`, `app/img/` | Para instalar la app (ícono y ventana propia). El service worker **no guarda nada** (todo se pide a internet; sin conexión muestra un aviso); se registra en app.js solo con https. El botón "Instalar la app" del menú aparece con `beforeinstallprompt` (Chrome/Edge). |
| `app/js/ui.js` | Utilidades de pantalla: `$`, `esc`, `plata`, `numero` (acepta coma decimal), `aviso`, `correr`, `modal`, `confirmar`. |
| Bienvenida | Mientras la app arranca, `#bienvenida` (index.html) muestra el logo con el toldo que se enciende raya por raya y, ni bien llega, el nombre del negocio. `quitarBienvenida()` (app.js) la saca con un fundido apenas hay algo para mostrar (cuenta, elegir usuario, error o la primera sección): no agrega espera. Con "entrar sin PIN" sigue hasta que aparece Hoy. |
| Pantallas de entrada | Cuenta, elegir usuario y PIN, y "sin negocio" usan `marcoEntrada` (app.js): fondo verde como la bienvenida, tarjeta al centro con el logo (del negocio o de la app, `img/icon-192.png`) y "Powered by Car-Ma Soft". Usuarios en filas con su inicial; PIN grande con teclado numérico (`[data-tecla]`; se oculta con "entrar sin PIN"). Clase `.entrada` (no `.caja-sola`, que sigue para celu.html). |
| Nombre y logo | La app se llama **Gestión de ventas** (título, manifest, bienvenida, entrada); la pestaña dice "Gestión de ventas · negocio". Logo propio: Ajustes → Logo del negocio (achicado a 256 px, webp, < 60 KB, config `logo` como `data:image/…`); se ve en la barra, al elegir el usuario y en la bienvenida. Cada PC recuerda nombre y logo (localStorage `marca`) y `bienvenida.js` (script común, no módulo) los pone apenas se dibuja la bienvenida. `ctx.cambiarLogo` lo actualiza en la barra sin recargar. |
| Pantallas más vivas | Mientras carga, `mostrarSeccion` (app.js) pone un esqueleto gris (`.esqueleto`) y la pantalla entra con un fundido (`#vista.entrando`). Las tarjetas de resumen que llevan al detalle usan `tarjeta(el, accion)` de ui.js (clic, Enter o espacio). Todo respeta `prefers-reduced-motion`. |
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
- **Pruebas:** `pruebas.yml` corre en cada PR (es obligatoria para unir): aplica las migraciones que la base todavía
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
  **¿Olvidaste tu PIN?** (pantalla del PIN, solo usuarios Dueño): pide el email y la contraseña de la **cuenta del dueño** (`miembros.rol = dueno`,
  no la de la PC), la inicia aparte solo para esa llamada (`llamarComoDueno` de base.js: otro cliente, sin persistir ni token de usuario)
  y llama a `restablecer_pin(p_usuario_id, p_pin)` (desbloquea y cierra las otras sesiones de ese usuario). tests/35.
  Muestra la pista del email del dueño a medias (`pista_cuenta_dueno()`, con la cuenta de la PC; tests/36).
  **¿Olvidaste la contraseña?** (pantalla de la cuenta y "¿Olvidaste tu PIN?"): `mandarRecuperacion(email)` (base.js, cliente aparte, flujo
  implicit) manda el mail de Supabase con un enlace a `recuperar.html` + `recuperar.js`: conexión propia que no se guarda (no toca la
  cuenta de la PC), elige la contraseña nueva (`updateUser`) y cierra. **En Supabase → Authentication → URL Configuration → Redirect URLs
  tiene que estar `https://carma-soft.github.io/kioscos-web/recuperar.html`** (si no, el enlace no vuelve a la app).
  **Un solo usuario:** no se elige el nombre, va directo al PIN. Si además el dueño activó **Entrar sin PIN** (Usuarios; config
  `entrar_sin_pin`), al abrir la app entra solo (`iniciar_usuario` con PIN vacío; la base lo acepta solo si `entra_sin_pin`: la config
  activada, un único usuario activo y que sea dueño; con un segundo usuario se vuelve a pedir). Después de "Cambiar de usuario" no entra
  solo: muestra "Entrar como …" (y "Salir de la cuenta de esta PC"). Pruebas: tests/27.
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
  **Abrir la caja desde Vender:** con la caja cerrada, Vender muestra "Abrir la caja" (y Cobrar también la abre; la venta en curso
  se mantiene). `abrirCaja(estado, alAbrir)` de caja.js. `estado_caja()` con la caja cerrada trae `queda_anterior` (contado − retiro
  del último turno cerrado), que se propone como efectivo inicial (también en Caja). Pruebas: tests/28.
- **Anular** (solo dueño): devuelve el stock y saca la plata de la caja del turno abierto.
- **Productos:** un producto con movimientos (`producto_con_movimientos`: ventas, devoluciones, compras, devoluciones a
  proveedor, entradas y salidas, ajustes de stock; no cuentan "Stock inicial" ni "Corrección desde la ficha") no se borra:
  `eliminar_producto` lo da de baja (`activo = false`). La ficha también tiene "Activo"; los dados de baja no están en el
  catálogo de Vender y se ven en Productos → "Ver dados de baja" (`productos_de_baja`), para volver a activarlos.
- **Botón rápido** (`favorito`): aparece en Vender como acceso rápido, en orden alfabético; los primeros 9 con Alt + número.
- **Impresión** (`impresion.js`): tickets de 58 mm de venta, devolución (con firma del cliente) y cierre de caja, con
  los datos de Ajustes (`config.negocio`: nombre, CUIT, dirección, teléfono, pie) y `config.ticket`
  (`preguntar` | `siempre` | `nunca`). Se arma en `#print-area` y `@media print` esconde el resto. Siempre pasa por la
  ventana de impresión: imprimir directo (Chrome con `--kiosk-printing`, con un instalador para Windows, PR #119) se probó y se sacó
  por engorroso de configurar en cada PC.
  Ancho del papel: `config.papel` (`58` | `76`, por defecto 58). Con 76 el ticket lleva `.p76` (59 mm de ancho, empezando a 9 mm del borde, unos 8 mm al final que terminan en un puntito (el driver borra el blanco final), letra más
  grande, para comanderas de matriz de puntos como la Epson TM-U220) y `#print-area:has(.p76)` usa la página con nombre
  `@page t76` (76 mm). Ojo: el servidor de prueba local saca la CSP; las imágenes elegidas con `blob:` necesitan `img-src blob:`.
- **Versión** (`version.js`): al publicar, `pages.yml` pone el commit en `VERSION`, agrega `?v=<commit>` al CSS y a
  todos los imports de JS (por eso los imports locales tienen que ser `from './archivo.js'`, con comillas simples) y
  escribe `version.json`. Cada 2 minutos la app lo compara y, si cambió, ofrece "Actualizar" (no recarga sola).

## Devoluciones de venta (etapa 4d)
- Desde el detalle de la venta (Caja), `devolver_venta(venta, items [{ id del renglón, cantidad, vuelve_stock }], forma, motivo, autorización)`:
  **DV-0001** (`devoluciones` / `devolucion_items`, numeración propia por negocio). Reintegro = importe del renglón ×
  total / subtotal de la venta (con descuento y recargos); si vuelve todo lo que quedaba, justo lo que falta.
  Forma: una forma de pago (sale de la caja del turno) o `Fiado` (a la cuenta del cliente; no hace falta turno).
  Lo que no vuelve al stock (roto, vencido) queda como pérdida. El empleado necesita la autorización del dueño
  (el mismo permiso de un solo uso de `autorizar_dueno`; la ventana es `pedirAutorizacion` en `ui.js`).
- `venta_json` trae `devuelto` por renglón, `devoluciones` y `devuelto` total. **Anular** una venta con devoluciones
  anula solo lo que quedó: el stock no devuelto y la plata que quedaba, repartida entre los pagos.

## Inicio y Reportes (etapa 4e)
- **Gráficos** (`graficos.js`): `columnas(filas)` arma columnas con cartelito de detalle (mouse, dedo o teclado) y `activarGraficos(raiz, alClic)`
  les pone la altura (desde JS, por la CSP) y la acción al tocar. `contar(el, valor)` hace subir los números de Hoy. Hoy: `inicio().por_hora`
  (`[{hora, total, tickets}]`, tests/32) → "Hoy, hora por hora". Reportes: por día (cada día del período; tocar uno abre ese día) y por hora,
  y las tarjetas comparan con el período anterior del mismo largo (`anterior()`: ayer, los 7 días anteriores, los mismos días del mes pasado…).
- **Recorrido de bienvenida** (`recorrido.js`, solo el dueño): 7 pasos con un dibujo SVG (en los colores de la app, sin capturas) y
  dos o tres líneas, "Siguiente"/"Anterior" (y flechas), puntos, "Ir ahí" (abre esa pantalla y deja abajo a la derecha el cartel "Recorrido N de 7 · Seguir · ✕", que sigue en el paso siguiente) y "Saltear". Sale solo una vez: `recorridoPrimeraVez`
  (app.js, al entrar) si la config `recorrido_visto` no es true, y la guarda al cerrarlo. Después, en Ayuda: "▶ Ver el recorrido".
  (`inicio().arranque` quedó de los "primeros pasos" que se sacaron de Hoy; no se usa.)
- `inicio()`: ventas de hoy, últimas ventas, caja y fiado pendiente. El empleado ve solo sus ventas y no la ganancia.
- Hoy (`inicio.js`) suma, solo para el dueño, "A pagar a proveedores (7 días)" (`vencimientos(hoy + 7)`, roja si hay algo
  vencido; "ver vencimientos" abre `vencimientosModal` de proveedores.js) y "Productos para reponer" (del catálogo del
  navegador; "ver cuáles" usa `verParaReponer()` de productos.js, que deja puesto ese filtro). Tarjetas en filas de tres.
- `reporte(desde, hasta)` (solo dueño, días inclusive, hasta 400): ventas, costo, devoluciones y pérdidas, por día,
  hora, forma, vendedor, categoría y producto, descuentos y recargos, autorizaciones, mercadería valorizada y fiado.
- Mismas cuentas que la app local: las devoluciones se restan **en la fecha de la devolución** (las de ventas anuladas
  no); el costo recupera lo que volvió al stock (lo roto queda como pérdida); el descuento general y los recargos se
  reparten entre los renglones (importe × total / subtotal). Los días son de la hora local del negocio
  (`zona_horaria`, config; por defecto Argentina).

## Proveedores y compras (etapa 5a)
- **Cuenta del proveedor:** pantalla dentro de Proveedores (como la ficha del cliente, `subpantalla`): tarjetas Cuenta, Próximo
  vencimiento (o "Vencido desde") y Plazo y visita; facturas pendientes y movimientos. Pagar, ajustar y editar, en ventanas chicas.
- Todo solo el dueño. `proveedores` (CUIT validado con `cuit_valido`, único por negocio; `plazo` en días),
  `producto_proveedores` (proveedores de cada producto con su último costo), `productos.proveedor_id` (habitual).
- `registrar_compra(p)`: suma stock (movimiento "Compra a …"), actualiza el costo (si es > 0) y el precio si viene
  `precio_nuevo`, deja al proveedor como habitual si no tenía y guarda su último costo. `total` de la factura opcional
  (si no, la suma). Con `pagar_caja` sale de la caja del turno; con proveedor y sin caja, queda a cuenta.
- **Cuenta del proveedor** (`cc_prov`): monto > 0 suma deuda (`compra`, `ajuste`), < 0 la baja (`pago`, `ajuste`).
  Una compra pagada con la caja agrega su pago en el momento. `pagar_proveedor` (de la caja o aparte),
  `ajuste_proveedor` (saldo inicial o corrección, sin plata), `anular_mov_proveedor` (pagos y ajustes; al revés).
- `anular_compra`: saca el stock, devuelve a la caja lo pagado con ella y saca de la cuenta lo que dejó la compra
  (lo pagado aparte queda a favor). No cambia costos ni precios. Un proveedor con compras no se borra.
- Pendiente (5c): devolución a proveedor.

## Factura pendiente, vencimientos y aplicación de pagos (etapa 5b)
- **Factura pendiente** (`registrar_compra` con `factura_pendiente`): suma el stock; el número va a `compras.remito`.
  `cargar_factura_compra` pone número, fechas, costos y precios **sin mover el stock**; el renglón guarda
  `costo_remito`; el costo del producto (y el último costo del proveedor) cambia solo si es su compra más reciente.
  Si el total cambió, la diferencia va a la cuenta del proveedor como `ajuste` con `compra_id` (la caja no se toca).
- **Fechas:** `fecha_factura` (por defecto hoy; sin factura, null) y `vencimiento` (por defecto fecha + `plazo` del
  proveedor; sin factura, se estima desde hoy). `compras.fecha` es cuándo se registró. `cc_prov.vencimiento` para
  un ajuste que suma (saldo inicial).
- **Aplicación** (`aplicaciones_prov`): qué parte de cada crédito (pago, nota de crédito) cubre cada deuda (compra
  o ajuste que suma). `deudas_proveedor` / `creditos_proveedor` calculan pendiente y libre. **Siempre: pendiente − libre
  = saldo** (las pruebas lo controlan con `pruebas.cuadra`). `pagar_proveedor(..., p_aplicaciones)`,
  `aplicar_proveedor` (lo que está a cuenta, sin plata). Pagada con la caja: su pago queda aplicado a esa compra.
  Anular un pago o ajuste borra sus aplicaciones; anular una compra borra las suyas y las de sus créditos; si la factura
  vino por menos, `recortar_aplicaciones` libera lo pagado de más. Al instalar la etapa, los pagos que ya había se
  aplicaron una sola vez (`aplicar_automatico`).
- **Vencimientos** (`vencimientos(hasta)`): qué hay que pagar hasta una fecha, por proveedor, con lo vencido.

## Balanza, cierre por billetes y turnos anteriores (etapa 4c)
- **Etiquetas de balanza** (Ajustes → Balanza: activa, prefijo, tipo `peso` | `importe` | `importe_centavos`):
  EAN-13 = prefijo + PLU (hasta el dígito 7) + 5 dígitos de valor + verificador. Las lee `vender.js` con el catálogo
  (`porCodigoDeBalanza`; el producto tiene que ser por kilo y tener su PLU). Si trae el importe, el renglón lo manda
  (`items[].importe`) y `registrar_venta` lo acepta solo si coincide con kilos × precio dentro del redondeo de medio
  gramo: no sirve para cobrar menos. Cambiar los kilos o el precio del renglón descarta el importe de la etiqueta.
- **Cierre por billetes** (`cerrar_turno` con `p_billetes` = `{ "valor": cantidad }` y `p_otros`): el contado lo calcula
  la base; queda en `turnos.billetes`. Con `p_registrar_ajuste`, el faltante o sobrante queda como movimiento de caja
  (`caja.ajuste = true`); el esperado guardado no cambia. Los valores de billetes se editan en Ajustes (`guardar_ajustes_caja`).
- **Contar billetes con − y +** (botones al lado de cada cantidad) y una barra contra lo esperado (verde justo, amarilla falta, azul sobra).
- **Cierre poniendo el total:** la ventana de cierre tiene "Poner el total" / "Contar billete por billete" (cada PC recuerda en
  localStorage `cierre-modo`; de fábrica, billetes si hay valores cargados). Con el total va `p_contado` (sin `p_billetes`).
- (Ajustes ya no tiene "Descargar mis datos": se sacó a pedido del usuario. Quedó en la base `ventas_periodo` + tests/31, sin uso.)
- **Errores entendibles:** `traducir` (base.js) pasa a castellano los de Postgres sin traducir (timeout, texto largo, número
  inválido, check, clave foránea) y los de programación (TypeError…) a "Algo falló en la app… recargá con ↻" (F5 no recarga en las pantallas de carga) (el detalle, en la
  consola). app.js avisa igual los TypeError/ReferenceError que se escapan (`unhandledrejection`).
- **Turnos anteriores** (`turnos_anteriores`, `turno(id)`): el dueño ve todos; el empleado, los suyos.

## Cobro: descuentos, recargos y autorización (etapa 4b)
- Cuenta (la misma en `vender.js` y en `registrar_venta`; la que vale es la de la base): subtotal = renglones con su
  precio cobrado; base = subtotal − descuento general; cada pago `{ forma, base }` lleva su recargo
  (`pct_recargo`, redondeado a pesos enteros) y su monto = base + recargo; total = base + recargos.
  Con dos medios, lo que se escribe en el primero es lo que paga con ese medio (con recargo) y el resto va al segundo.
- El precio de un renglón se puede cambiar para esa venta (`items[].precio`); si es menor al de lista cuenta como
  descuento (`descuento_renglones`). Efectivo nunca lleva recargo; Fiado puede.
- **Tope del empleado** (`tope_descuento`, por defecto 10%): descuentos manuales en % de lo que valía a precio de lista.
  Por encima, `registrar_venta` corta con `hint = 'autorizacion'`; la pantalla pide el PIN de un dueño con
  `autorizar_dueno` (mismo bloqueo de 5 intentos que el ingreso), que da un permiso de un solo uso (5 minutos, de esa
  cuenta y ese usuario) y la venta lo consume (`p_autorizacion`). Queda `ventas.autorizo_id`. El PIN nunca viaja con la venta.
- Ajustes (solo dueño, `guardar_ajustes_cobro`): formas de pago (Efectivo siempre primero; Fiado no se lista), recargos y tope.
  `estado_caja()` los devuelve (`formas_pago`, `recargos`, `tope_descuento`).

## Clientes y fiado (etapa 4a)
- Cuenta del cliente en `cc`: monto > 0 suma deuda (`cargo` por compra fiada, `ajuste`), < 0 la baja (`pago`, `ajuste`).
  Saldo = suma (positivo = debe). `Fiado` es una forma de pago más en `registrar_venta` (con `p_cliente_id`): va a la
  cuenta, no a la caja. Si el cliente tiene límite y lo pasaría, la base corta con `hint = 'limite'` y no registra nada;
  la pantalla pregunta y reintenta con `p_forzar_limite`.
- Cualquier usuario crea clientes y cobra (`cobrar_cliente`, entra a la caja del turno); el límite, los ajustes
  (`ajuste_cliente`, deuda anterior o corrección, sin plata) y las bajas los hace el dueño. Un cliente con saldo no se borra.
- Anular una venta fiada descuenta lo fiado de la cuenta; el turno hace falta solo si hubo pagos que pasaron por la caja.
- **Aplicación de pagos** (como en proveedores; `aplicaciones_cli`): las deudas son cada venta fiada (su importe = suma de sus
  movimientos en `cc`: el cargo menos lo que restaron su anulación o sus devoluciones a la cuenta) y cada ajuste que suma sin venta;
  los créditos, los pagos y los ajustes que restan (y el exceso de una venta si se devolvió a la cuenta más de lo fiado).
  `deudas_cliente` / `creditos_cliente` calculan pendiente y libre: **siempre pendiente − a favor = saldo** (`pruebas.cuadra_cli`).
  `cobrar_cliente(..., p_aplicaciones)` (`[{venta_id | deuda_id, monto}]`; sin él, a lo que vence primero; lo que sobra queda a favor)
  y `aplicar_cliente` (lo que está a favor, sin plata). El disparador `cc_aplicar` (cada movimiento de `cc` que no es un pago)
  recorta lo aplicado de más y aplica lo que está a favor, así `registrar_venta`, `anular_venta` y `devolver_venta` no saben nada de esto.
- **Vencimiento:** fecha de la venta + `clientes.plazo` (solo el dueño lo cambia, en la ficha del cliente; null = config
  `plazo_clientes`, 30 de fábrica; Ajustes ya no lo muestra). **Por mes:** con `clientes.vence_dia` (1 a 28), lo comprado en cada mes
  vence ese día del mes siguiente (tests/34). Se calcula al mostrarlo. `cuenta_cliente` trae `pendientes`, `pagadas` (con `pagada`, las últimas 100) y `a_favor`.
- **Uso del límite:** con límite de fiado, una barra en la lista y en la ficha (`usoLimite`: verde, amarilla desde 70%, roja al pasarlo).
- **Lista y estado de cuenta:** `clientes()` trae también `deuda_desde` (la compra pendiente más vieja), `vence` (el vencimiento más
  próximo) y `ultimo` (último movimiento); la lista se ordena por nombre, "debe desde", límite o saldo (clic en el título).
  La **ficha** es una pantalla dentro de Clientes (no una ventana): `subpantalla(volver)` de ui.js hace que "← Clientes", "atrás"
  y Esc vuelvan a la lista como estaba; las acciones (cobrar, editar, ajuste) siguen en ventanas chicas.
  La ficha saca el **estado de cuenta** en PDF (jsPDF, con los productos de cada compra, `llamar('venta')`) o arma el texto para
  **WhatsApp** (`telefonoWhatsApp` de ui.js, también lo usa Pedidos: saca el 0 y el 15). Como el Fichero de GSCom.

## Versión de prueba (/prueba/)
- **https://carma-soft.github.io/kioscos-web/prueba/** publica la versión del **PR abierto** (el último que se actualizó; si no hay, la de
  main), con una cinta naranja "VERSIÓN DE PRUEBA". Se prueba ahí, **con el Negocio de prueba**, antes de decir "Unilo": los negocios
  siguen en la raíz con main. `pages.yml` siempre corre en main (el entorno github-pages solo deja main) y trae el PR con git;
  `prueba-pr.yml` lo dispara cuando un PR se abre, cambia o se cierra (`gh workflow run pages.yml -f pr=N`). Con varios PR abiertos,
  se elige cuál con "Run workflow" en "Publicar la app" y el número.
- **Ojo:** /prueba/ usa la **misma base**: lo nuevo de una migración recién existe al unir. Las pantallas que dependen de ella se prueban
  con el backend falso (local) y, ya unidas, en el Negocio de prueba. No abrir /prueba/ en la PC de un negocio (comparte la sesión del navegador).

## Copia de seguridad (.github/workflows/copia.yml)
- Todas las noches (4 h de Argentina, y a mano con "Run workflow"): `pg_dump` de `public` (toda la app y los datos de todos los
  negocios) y de los datos de `auth.users`, `auth.identities` y `supabase_migrations.schema_migrations`. Se cifra con **gpg AES-256** con
  la clave del secreto **`BACKUP_CLAVE`** y se guarda 30 días como artifact de la acción. **El repositorio es público: nunca se guarda
  nada sin cifrar.** Sin la clave la copia no sirve: guardarla en un lugar seguro fuera de GitHub (si se pierde, no hay forma de abrirlas).
- **Recuperar:** Actions → "Copia de seguridad" → la corrida del día → bajar el artifact (zip) y descomprimirlo. En Git Bash:
  `gpg --decrypt copia-AAAA-MM-DD.tar.gz.gpg > copia.tar.gz` (pide la clave) y `tar -xzf copia.tar.gz` → `public.dump`, `cuentas.dump`,
  `fecha.txt`. Lo más seguro es restaurar en un **proyecto nuevo** de Supabase: `pg_restore --no-owner --no-privileges -d "<url nueva>" public.dump`
  y `pg_restore --data-only -d "<url nueva>" cuentas.dump`; después se apunta `app/js/config.js` al proyecto nuevo. Para ver un dato puntual
  alcanza con `pg_restore -f datos.sql public.dump` (lo pasa a texto).

## Forma de trabajo
- **Nunca commitear ni hacer push directo a `main`** (GitHub lo impide). Todo va en una rama y entra por pull request.
  Cada uno une sus propios PR sin esperar la aprobación del otro (regla "Proteger main": 0 aprobaciones), pero **solo
  con las pruebas de la base en verde**: el control `probar` es obligatorio y nadie lo puede saltear. Como la base es
  desarrollo y producción a la vez, lo que se une se aplica enseguida: si hay dudas, pedirle al otro que revise igual.
- PR en español. Si resuelve un issue, la primera línea es `Closes #N` (o `Closes CarMa-Soft/Kiosco#N` si el issue es del repo privado).
- Las ramas se borran solas al unir el PR.
- Commits con el email privado de GitHub (`…@users.noreply.github.com`), no el personal: `git config user.email` en este repo.
- GitHub CLI en Windows: `"C:\Program Files\GitHub CLI\gh.exe"`.
- Avisarse antes de tocar la misma función de la base o el mismo archivo a la vez.

## Devolución a proveedor (etapa 5c)
- `devoluciones_compra` (DP-0001 por negocio) y `devolucion_compra_items`; se devuelve desde el detalle de la compra,
  hasta lo que queda de cada renglón (`devuelto_compra_item`). Siempre sale el stock (movimiento "Devolución a …").
- `devolver_compra(p)`: `{compra_id, items[{id, cantidad}], total?, forma, motivo}`. Importe = costo × cantidad si no
  viene `total` (el proveedor puede acreditar otro monto). `forma`: `Cuenta` (con proveedor: `cc_prov` tipo
  `devolucion`, < 0, aplicada sola a esa compra), una forma de pago (devolvió la plata: `devolucion` + `reintegro`
  con `par_id` que se compensan, y entra a la caja del turno) o `Sin reintegro` (solo sin proveedor).
- `creditos_proveedor` incluye las devoluciones a cuenta. `compra_json` trae `devuelto` por renglón, el total
  `devuelto` y la lista `devoluciones`.
- `anular_compra` con devoluciones anula solo lo que quedó: stock restante, y a la caja vuelve lo pagado menos lo
  que el proveedor ya devolvió en plata.

## Entradas y salidas de mercadería (etapa 6)
- Pantalla `remitos.js` (menú "Entradas y salidas", solo dueño). Por dentro se llaman "remitos": tablas `remitos`
  (tipo `ingreso`/`egreso`, numeradas por negocio y tipo: RI-0001 / RE-0001) y `remito_items` (con costo y stock antes/después).
- `registrar_remito(p)`: `{tipo, motivo, notas, items[{producto_id, cantidad}]}`; el mismo producto dos veces se suma.
  Mueve el stock (movimiento "Entrada RI-0001 — motivo") y devuelve `stock_negativo` con lo que quedó debajo de cero.
- `anular_remito(id)`: el movimiento al revés. `remitos(p_tipo)` (últimas 300) y `remito(id)`. La pantalla pide
  `remitos(null)` (los dos tipos) y filtra Entradas / Salidas y el buscador ahí mismo; las tarjetas cuentan el mes sin las anuladas.
- Motivos editables en Ajustes: `motivos_remito()` / `guardar_motivos_remito(p)` (config `motivos_remito`, con los de fábrica).
  Las devoluciones no van acá: se hacen desde la venta o la compra.

## Aumentos masivos de precios (etapa 7)
- Botón "Aumento de precios" en Productos. `aumento_masivo(p)`: `{alcance: ids|categoria|proveedor|todos, ids, categoria_id,
  proveedor_id, modo: pct|monto, valor, costo, redondear, descripcion, simular}`. Solo productos activos; por proveedor
  cuenta el habitual y los de `producto_proveedores`. Con `simular` devuelve `{cantidad, ejemplos}` sin cambiar nada
  (la vista previa de la pantalla). Nada baja de cero (`valor_aumentado`).
- Redondeo hacia arriba a múltiplos de config `redondeo` (10 de fábrica, 0 = sin redondeo): `guardar_redondeo` en Ajustes.
- `aumentos` / `aumento_cambios` guardan antes y después. `deshacer_aumento(id)` vuelve al antes solo los productos que no
  cambiaron después (`{revertidos, saltados}`). `aumentos()`: los últimos 15.

## Cargar compra desde la factura, con IA (etapa 8a)
- Compras → "Cargar desde factura" (`facturas.js`): PDF o hasta 5 fotos (se achican en el navegador), o un .json ya leído.
- La lee la **función de Supabase** `supabase/functions/leer-factura` (Deno, SDK `npm:@anthropic-ai/sdk`, modelo
  `claude-opus-5-5`, salida con esquema JSON, igual que la app local). La clave está en Supabase → Edge Functions → Secrets
  (`ANTHROPIC_API_KEY`): nunca en el navegador, el repo ni el chat. `verify_jwt = false` en config.toml: el permiso lo da
  la base con `permiso_lectura_ia()` (llamada con los encabezados del usuario: su sesión y `x-usuario-kiosco`; solo dueño,
  hasta 60 lecturas por día por negocio). El consumo se anota en `lecturas_ia` con `anotar_lectura_ia` (solo `service_role`).
  `uso_ia()` lo muestra en Ajustes. En el navegador: `funcion(nombre, cuerpo)` de base.js.
- Se publica con `.github/workflows/funciones.yml` al cambiar `supabase/functions/**` en main (secreto `SUPABASE_ACCESS_TOKEN`).
  En cada PR, `pruebas.yml` corre `deno check` de las funciones.
- `preparar_factura(p)`: reconoce el proveedor (elegido, por CUIT o por la primera palabra del nombre) y cada renglón (por código
  de barras, por el código del proveedor o por cómo lo describe, en `producto_proveedores`); si no, hasta 5 parecidos (`palabras`).
  Trae `margen` (config, 40 de fábrica; Ajustes → Precios) y `redondeo` para proponer el precio de los nuevos.
- `registrar_compra_factura(p)`: crea el proveedor y los productos nuevos, pone el código de barras al que no tenía, recuerda
  código, descripción y unidades por unidad facturada de cada producto de ese proveedor, y llama a `registrar_compra`.
- **Factura leída** (lo que devuelve la IA y acepta un .json): `{ proveedor: {nombre, cuit}, comprobante, fecha (AAAA-MM-DD),
  vencimiento ("" si no trae), items: [{ codigo, codigo_barras, descripcion, cantidad, unidad: unidad|bulto|kg,
  unidades_por_bulto, precio_unitario, bonificacion, importe (sin IVA), alicuota_iva, precio_sugerido }], descuento_global,
  otros_cargos, subtotal, iva, percepciones, total, observaciones }`.
- La lectura con IA está en `supabase/functions/_shared/lectura.ts` (la usan leer-factura y subir-factura).

## Factura desde el celular (etapa 8b)
- En Cargar desde factura → "Desde el celular": `crear_subida_celular()` da un código (48 hex, vence a los 15 minutos, una
  factura; la base guarda solo su sha256 en `subidas_celular`). La PC lo muestra como QR de `celu.html#código` (QR dibujado
  en canvas con qrcode-generator de jsDelivr) y consulta `estado_subida_celular(id)` cada 2 s; cuando está `lista` entrega
  `{factura, uso}` una sola vez. Cerrar la ventana llama a `cancelar_subida_celular`.
- `celu.html` + `celu.js`: sin sesión ni supabase-js; achica las fotos (hasta 5) y las manda a la función `subir-factura`
  (`verify_jwt = false`), que con la clave de servicio usa `revisar_subida_celular`, `tomar_subida_celular` (pasa a leyendo,
  controla el límite de 60 por día) y `terminar_subida_celular` (lista, o error para volver a mandar). No hace falta el mismo WiFi.
- `funciones.yml` publica todas las funciones; `pages.yml` marca la versión en todas las páginas (`app/*.html`).

## Pedidos a proveedores
- Sección "Pedidos" (después de Compras, solo dueño, `pedidos.js`). `pedidos()` arma un pedido por proveedor con los
  productos activos con `stock <= greatest(stock_min, 0)`: el proveedor es el habitual del producto o, si no tiene, el de su
  última compra (`producto_proveedores`); si no, "Sin proveedor". Trae la cantidad propuesta (`cantidad_propuesta`: hasta el
  doble del mínimo; sin mínimo, lo que falta para tener 1; enteras salvo por kilo), el último costo de ese proveedor y su código.
- `pedido_items` guarda solo lo que se cambió: `cantidad` (`pedido_cantidad`, null = la propuesta) y `pendiente`
  (`pedido_pendiente`: quitado del pedido → "Pendientes de pedir", de donde vuelve con un botón). `pedido_proveedor` deja al
  proveedor elegido como habitual del producto. Al cargar una compra, un trigger en `compra_items` borra lo guardado de esos
  productos; `pedidos()` limpia lo de productos que ya no hace falta pedir. No hay "recibido".
- Exportar cada pedido: PDF (jsPDF + jspdf-autotable de jsDelivr), Excel (.xlsx armado a mano y comprimido con fflate: la
  librería write-excel-file usa workers, que la política de seguridad bloquearía) y WhatsApp (`wa.me` con el teléfono del
  proveedor pasado a 549…; si no tiene, se elige el contacto). Los precios de referencia van en el PDF y el Excel solo si se tilda.
- `pages.yml` marca la versión en todas las hojas de estilo (`css/*.css`), no solo en app.css.

## Escanear con la cámara del celular
- `escaner.js`: `botonCamara(input)` agrega 📷 junto a un campo de escanear, solo donde el navegador trae `BarcodeDetector`
  (Chrome en Android; no en Windows ni en Safari de iPhone, donde el botón no aparece). Cada código leído se pone en el
  campo y se dispara un `keydown` Enter (sin burbujear), así cada pantalla lo procesa con su propio manejo del lector.
  El mismo código dos veces seguidas no se suma solo (con el pulso la cámara lo pierde y lo vuelve a ver): para otra
  unidad de lo mismo está el botón +1; la ventana muestra el nombre del último leído (`describir`). Está en Vender, Cargar compra, Entradas y salidas y la
  ficha del producto (ahí con `continuo: false` y `alLeer`, solo llena el código).

## Varios códigos por producto y alta rápida desde Compras
- `producto_codigos`: otros códigos de un producto (por ejemplo, el envase nuevo), además del principal (`productos.codigo`).
  Un código es de un solo producto (principal u otro, por negocio; lo controlan `agregar_codigo`, el trigger
  `productos_codigo_principal` y `codigo_usado_por`). `producto_json` trae `codigos`; `catalogo.js` los indexa
  (`codigosDe`, `mapaPorCodigo`), así Vender, Compras y Entradas y salidas los encuentran. `producto_por_codigo` los usa al
  leer facturas, y `registrar_compra_factura` guarda como otro código un código de barras nuevo de un producto que ya tenía.
- Ficha del producto: "Otros códigos" se agregan (también con 📷) y se quitan al momento (`agregar_codigo` / `quitar_codigo`;
  si el producto no tenía código, el agregado queda como principal).
- `alta-producto.js` (`productoNoEncontrado`): en Cargar compra y Entradas y salidas, un código o nombre que no está ofrece
  crear el producto ahí mismo (`guardar_producto`) o agregarle el código a uno existente; el producto se suma a la lista.

## Botón "atrás" (celular y navegador)
- `ui.js`: los enlaces a secciones (`#/...`) y `ctx.ir` usan `location.replace`, así cambiar de sección no suma historial.
  Cada ventana (`modal`) hace `pushState`; "atrás" cierra la de arriba. Sin ventanas abiertas, el `popstate` sigue con
  `history.back()` hasta salir de la app (salteando las entradas de ventanas ya cerradas). Un `popstate` con otro `#` es un
  cambio de sección, no el botón atrás.

## Entregas pendientes (vender más de lo que hay)
- Al cobrar, si un producto se vende por más de lo que hay en stock (según el catálogo del navegador), Vender pregunta:
  se lleva todo ahora (el stock estaba mal: sale todo, como antes) o se lleva lo que hay y el resto queda pendiente, a
  nombre del cliente o de un nombre y teléfono. `registrar_venta` tiene `p_entrega {nombre, telefono}` y por renglón
  `pendiente`: se cobra todo, del stock sale solo lo entregado, y lo pendiente va a `entregas_pendientes`.
- `comprometido(producto)`: lo pendiente de entregar. `pedidos()` lo suma (stock − comprometido ≤ mínimo; trae
  `para_entregar` y la nota `entregas`). Vender muestra el aviso (`entregas_pendientes()`) y "Entregar"
  (`entregar_pendiente`, cualquier usuario, con stock suficiente) lo saca del stock sin plata.
- `devolver_venta` descuenta primero de lo pendiente (`descontar_pendiente`: eso no vuelve al stock); `anular_venta` cancela
  lo pendiente y devuelve al stock solo lo entregado. `venta_json` trae `pendientes`, y el ticket los imprime.

## Que nada quede "Cargando…" para siempre
- `base.js`: cada pedido a Supabase se corta a los 30 s (las funciones, a los 2 min) y `llamar`/`funcion` además usan
  `conLimite` (por si la espera es antes del pedido). El error es "La base tardó demasiado en responder" (código `red`).
  Una venta cortada así se puede volver a cobrar: la clave de la venta evita registrarla dos veces.
- `createClient` con `auth.lock` directo (sin `navigator.locks`): con la pestaña un rato sin usar, ese bloqueo podía quedar
  tomado y la app quedaba esperando sin fin.
- `mostrarSeccion`: si la sección no se pudo cargar, muestra "No se pudo cargar" con Reintentar y Recargar la página.

## Lista de precios (para imprimir y etiquetar)
- Productos: **precio y stock en la tabla** (`enLinea`): tocar el valor abre un campo; Enter o salir guarda, Esc cancela. Precio con
  `cambiar_precio(p_id, p_precio)` (dueño; deja el producto sin margen automático; tests/33), stock con `ajustar_stock` ("Corrección desde la lista").
- Productos → "Importar planilla" (`importar.js`, solo dueño): lee .xlsx (a mano: zip con fflate + DOMParser, la primera hoja;
  sin librerías de planillas) o CSV (; , o tab, UTF-8 o Windows-1252). Adivina las columnas por el título (`CAMPOS`, sin tildes), muestra
  las primeras filas y manda de a 1000 a `importar_productos(p_filas, p_actualizar)`: por código (o alternativo; sin código, por
  nombre) actualiza precio/costo/categoría (con precio, deja de tener margen automático; el stock no se toca) o crea con stock
  inicial; la categoría se crea si no existe; cada fila con error vuelve en `errores` (con su número) sin cortar las demás. tests/29.
- Productos → "Lista de precios" (`listaprecios.js`, solo dueño). `lista_precios(p)`: `{categoria_id, proveedor_id,
  compra_ids, compras_desde, precio_desde, texto}`, se combinan; trae costo, precio y, según el filtro, `precio_antes`
  (antes del primer cambio desde la fecha), `cambio` y `llego`. Se puede destildar productos.
- `cambios_precio`: historial de precio y costo de cada producto, cargado por el trigger `productos_cambio_precio` (desde
  la ficha, compras, aumentos o facturas); se completó con las compras y los aumentos de antes.
- Sale en PDF (jsPDF): lista (con o sin costo, con el precio anterior) o etiquetas 3 × 8 por hoja A4 (sin costo). En PDF
  y no con imprimir del navegador, porque en la PC del local Chrome imprime directo en la comandera.

## Precios y márgenes (como en GScom)
- `productos.margen`: con margen, el precio sigue al costo. El trigger `productos_precio_sigue_costo` recalcula
  `precio_por_margen` (costo + margen, redondeo de Ajustes) cuando cambia el costo y el precio no se cambió en el mismo
  momento (compra, factura, ficha). Sin margen, el precio es fijo. En la lista de Productos se marca "auto".
- Productos → "Precios y márgenes" (`precios.js`, reemplaza a "Aumento de precios"): solapa Actualizar precios (precio de
  venta de los fijos, o costo: los de margen recalculan) con el redondeo elegido; solapa Asignar margen (calcular y dejarlo
  automático, o quitarlo). A qué productos: búsqueda, los que se ven en la lista, todos, categoría o proveedor (habitual).
  Vista previa con la misma cuenta que la base y destildar. `ajustar_precios(p)` lo aplica y lo deja en aumentos /
  aumento_cambios (con `margen_antes`/`margen_despues`); `deshacer_aumento` vuelve también el margen.
- Ficha: Margen % y la tilde "Margen automático" (`margen_producto`). `aumento_masivo` queda pero ya no lo usa la pantalla.
- Configuración de precios (antes en Ajustes → Precios): pestaña "Configuración" de Precios y márgenes. `redondeo`
  (`guardar_redondeo`) y `margen` (`guardar_margen`): el margen automático de los productos nuevos (0 = precio fijo).
  `registrar_compra_factura` se lo pone a los nuevos de una factura (después de la compra, para no pisar el precio
  elegido); la pantalla, al alta rápida (`alta-producto.js`) y a "Nuevo producto" (con `margen_producto`; sin costo
  quedan con precio fijo).
- Cargar compra y Cargar desde factura muestran, en los productos con margen automático, el precio en que van a quedar.

## Impuestos en la factura (IVA por renglón, percepciones, impuestos internos)
- La IA lee la alícuota de IVA de cada renglón (aunque la factura mezcle 10,5% y 21%) e `impuestos_internos` aparte
  (número, 0 si no hay: el esquema ya usa los 16 campos que pueden ser null).
- En la revisión, cada renglón tiene su IVA editable (`alicuota` en la línea) y un control compara el IVA de los renglones
  con el de la factura. El costo = neto × (1 + IVA si se tilda + percepciones si se tilda + impuestos internos); percepciones
  e internos se reparten en proporción al neto. Las tildes "Sumar el IVA / las percepciones al costo" se recuerdan en la PC
  (para un monotributista son costo; un responsable inscripto los descuenta).
- Cargar compra (a mano) tiene lo mismo: "Los costos que cargás" ya incluyen el IVA o son sin IVA (alícuota por renglón y
  tilde "Sumar el IVA al costo"), percepciones (con su tilde) e impuestos internos como importes de la factura, repartidos
  según el importe de cada renglón. Se guarda el costo final de cada producto, el total propuesto suma todo y las notas
  dicen cómo se calculó. Las tildes se comparten con Cargar desde factura.

## Alta rápida desde caja (productos "a revisar") y Varios desactivable
- En Vender, un código o nombre que no está ofrece crearlo ahí (`alta_desde_caja`, también el empleado): nombre opcional
  (vacío = "Producto <código>"), código y precio. Queda `productos.a_revisar` con costo 0 y precio fijo, y se agrega a la venta.
  Hasta 500 sin revisar por negocio. Varios con la tilde "Es un producto que no está cargado" lleva al mismo alta.
- Mientras está a revisar, su stock no cuenta: Pedidos no lo propone y Vender no pregunta por faltantes (queda en negativo).
- Productos tiene el filtro "A revisar" (con aviso) y la etiqueta en la lista y en la ficha; al guardarlo desde la ficha
  (`guardar_producto`) deja de estar a revisar. Inicio le avisa al dueño cuántos hay, con botón a ese filtro.
- Ajustes → "Vender como Varios": config `varios` (false = sin el botón, y un trigger en `venta_items` rechaza la venta sin
  producto). Reportes muestra lo vendido como Varios (`reporte().varios`).

## Entregas pendientes visibles fuera de Vender
- `entregas.js`: `aQuien(e)`, `porProducto()` y `avisarListas(ids)` (sobre `entregas_pendientes()`).
- Inicio lista las entregas pendientes (todos los usuarios), con estado "lista para entregar" / "esperando mercadería".
- Pedidos muestra en el renglón "📦 Para entregar: 6 a Juan Perez (venta #23)"; Productos, "📦 N a entregar" en el stock
  (detalle al pasar el mouse) y un aviso en la ficha.
- Al guardar una compra (a mano o desde la factura), si llegó mercadería para entregas pendientes, avisa a quién entregar.

## Encargos (sin pagar o con seña)
- Tabla `encargos` (numero por negocio): producto, cantidad, cliente o nombre/teléfono, notas, seña y su forma. No es una
  venta y no toca el stock; cuenta en `comprometido()` y Pedidos lo muestra en la nota "(encargo #N)".
- `registrar_encargo(p)` (cualquier usuario): la seña entra a la caja del turno ("Seña encargo #N"). `encargos()` lista los
  pendientes (`lista` = hay stock). `cancelar_encargo(id, p_devolver, motivo)`: con seña hay que elegir devolverla (egreso
  de la caja con su forma) o que quede para el negocio.
- Vender: botón "📋 Encargo" (alta, `encargos.js`), aviso "📋 N encargos" → "Pasar a la venta". `registrar_venta` recibe
  `p_encargos` y acepta la forma de pago "Seña" hasta la suma de las señas (no entra a la caja otra vez); los encargos
  quedan entregados. Anular esa venta los vuelve a pendiente (trigger) y la parte "Seña" no sale de la caja.
- Inicio, Productos y el aviso al cargar una compra muestran también los encargos.
- Encargos en partes (`20261210120000_encargos_parciales`): `encargos.entregado` y `sena_usada`, y `encargo_entregas` (cada
  entrega con su venta). `p_encargos` acepta `{ id, cantidad }`; no se entrega más de lo que hay en stock ni de lo que falta.
  La seña se descuenta hasta el importe de lo entregado y el resto queda para la próxima entrega. `encargo_json`: `cantidad`
  y `sena` son lo que falta entregar y la seña que queda (`encargado`, `entregado`, `sena_dejada` aparte). Vender pasa solo
  lo que llegó ("Pasar 10 a la venta") y sin stock no deja pasarlo. Anular la venta devuelve al encargo lo de esa venta.

## Promociones por cantidad (Productos → 🎁 Promociones)
- Tabla `promociones` (solo por funciones). `tipo`:
  - `lleva_paga`: lleva N, paga M.
  - `precio`: N por $X.
  - `unidad_pct`: la N-ésima con % menos.
  - `desde_pct`: llevando N o más, % menos; con N = 1 es una oferta simple.
- Otras columnas:
  - `productos` (bigint[]): las unidades se juntan; no entran productos por kilo.
  - `desde` / `hasta`: fecha del negocio.
  - `dias`: 1 = lunes … 7; vacío = todos.
  - `formas`: vacío = todas; si no, todos los pagos de la venta (sin la seña) tienen que ser de esas.
  - `activa`.
  - El % es entero, para redondear igual en la base y en el navegador.
- Funciones:
  - Dueño: `promociones()` (con `hoy`), `guardar_promocion(p)` y `borrar_promocion(id)`. Al borrar, las ventas guardan el nombre.
  - Todos: `promociones_vigentes()`, las de hoy; Vender las pide al entrar.
- **La cuenta está dos veces y tiene que dar igual:** `promo_descuentos` / `promos_venta` en la base (la que vale) y `calcularPromos` de `promos.js`.
  - Entran los renglones de productos por unidad a precio de lista. Un precio cambiado a mano o un producto por kilo no entran.
  - Las unidades van de la más cara a la más barata; a igual precio, en el orden de los renglones. Los grupos de N se arman desde la más cara.
  - Todo se calcula en centavos.
  - En "N por $X", lo descontado se reparte en proporción al precio; la última unidad del grupo se lleva el redondeo.
  - Con varias promociones, primero va la que más descuenta, y sus renglones ya no entran en otra.
- **En la venta:**
  - El descuento queda en cada renglón (`venta_items.promo`, `promocion_id`, `promo_nombre`; el `importe` ya rebajado) y en
    `ventas.descuento_promos`. El `subtotal` es después de promociones. Así devoluciones, reportes por producto y ganancia lo toman solos.
  - No cuenta para el tope de descuento del empleado.
  - `registrar_venta(..., p_sin_promos, p_promos)` recibe las que quitó el cajero y lo que calculó Vender. Si la base calcula otra cosa,
    corta con hint `promos` y Vender vuelve a pedir las vigentes.
- **Vender:**
  - Como dependen de la forma de pago, `totales()` calcula con las formas elegidas; con dos medios, si uno queda en 0, recalcula sin ese.
  - En el renglón aparece 🎁 con lo descontado y una × para quitarla.
  - Arriba de la venta, `#sugerencias` muestra las que se completan con hasta 3 unidades más, las que valen con otra forma de pago y las
    quitadas ("Volver a aplicarla").
  - El ticket muestra cada promo debajo de su renglón y "Ahorraste $X en promociones".
- **Combos** (`tipo = 'combo'`, migración 20261223120000_combos.sql):
  - `componentes`: [{ productos: [id], cantidad }], de 2 a 10. Cada parte es un producto o varios que valen igual; un producto va en una sola parte.
  - `precio` fijo o `pct` (uno de los dos). `productos` tiene todos los productos de las partes y `cantidad` las unidades del combo.
  - La cuenta está en `promo_combo` (base) y `descuentosCombo` (promos.js). De cada parte, sus unidades de la más cara a la más barata.
    Se arman tantos combos como alcance la parte que menos tiene. Dentro de cada combo, las unidades van en el orden de las partes.
    Con precio fijo se reparte en proporción y la última unidad se lleva el redondeo; con %, se redondea por unidad.
  - Sugerencia en Vender: si ya hay algo del próximo combo y faltan hasta 3 unidades ("Con 1 Coca más: …").
- **Reportes:** `reporte_promos(desde, hasta)` (aparte de `reporte()`, que no se tocó) da lo descontado, en cuántas ventas y por promoción
  (agrupado por `promo_nombre`: sigue aunque se borre). Tarjeta "Promociones" en Descuentos y recargos y la tabla "Promociones".

## Ayuda
- `ayuda.js`: preguntas frecuentes y cómo hacer cada cosa (array `TEMAS`, por sección; `a: true` = solo el dueño), con
  buscador sin acentos. Sin IA ni base. Se abre con "? Ayuda" del bloque del usuario, abajo del menú (sección `#/ayuda`,
  `aparte`: no está en los bloques de secciones). **Al agregar o cambiar una función, actualizar su tema acá.**

## Vender: pantalla, cobro y teclas
- **Destello, bip y ✓:** el renglón agregado (o sumado) destella (`nuevo` en `pintar`), `bip()` suena al agregar (botón 🔊/🔇,
  localStorage `vender-sonido` por PC; `sonidoError` suena siempre) y al cobrar `ventaLista` muestra un ✓ con el número, el total y
  el vuelto (se va solo, con un clic o con la próxima tecla).
- Estilos en `vender.css` (clases `v-`). `--v-oscuro` (verde oscuro) es el fondo de "Total a cobrar" y del encabezado de la
  lista de la venta; el botón elegido ($ / %, forma de pago) usa `--primario`. Arriba, las entregas pendientes y los encargos
  en una fila fina; la columna de la venta termina a la altura del panel de cobro.
- **Renglones:** el último agregado se **muestra** arriba (y resaltado), pero `venta.items` sigue en el orden en que se
  cargaron: la venta y el ticket salen en ese orden, y las entregas pendientes (`preguntarFaltantes`) usan la posición de
  cada renglón. "Stock en sistema: N" avisa cuando se lleva más de lo que hay.
- **Cobrar** (F2 o el botón): primero `preguntarFaltantes` y después `confirmarCobro`, **antes de grabar**: Imprimir (P) y
  No imprimir (N) graban; Seguir cargando (Esc) vuelve sin grabar. Enter es Imprimir si `config.ticket` es `siempre` y No
  imprimir en los demás casos (la ventana sale siempre).
- **Teclas** (`ctx.alTeclear`): F1 Efectivo, F2 cobrar, F3 Fiado (sin cliente, primero lo pide; en Vender no abre el buscar
  del navegador), Alt + 1…9 los accesos rápidos, Esc limpia el buscador. Con una ventana abierta, F3 y Alt + número no actúan.
- Un código que no existe (lector, teclado, cámara o etiqueta de balanza) suena (`sonidoError`, dos tonos con Web Audio, sin
  archivos) y queda seleccionado para que el próximo escaneo lo reemplace.
- El descuento arranca en % (`descPct: true` en `vacia()`). Los botones de billetes de "Paga con" están ocultos con CSS
  (`.v-paga .billetes`); el código sigue.

## Estilo común de las pantallas
- Hoy, Caja, Productos, Compras, Reportes, Clientes, Proveedores y Entradas y salidas usan las clases `c-` de `app.css`
  (Productos además las `p-` de `productos.css`). **Una pantalla nueva usa las mismas:**
  - `c-tarjetas` / `c-tarjeta` + color (`verde`, `azul`, `violeta`, `rojo`, `naranja`, `gris`) con `c-ico` (un SVG de trazo),
    `.etq`, `.valor` (el monto en un renglón) y `c-sub`. `de-a-tres` (filas de tres) y `r-tarjetas` (Reportes: cada grupo
    ocupa todo el ancho). Gris cuando no hay nada que mostrar.
  - `c-filtros` con `c-buscar` (buscador con lupa) y `.chips` (el elegido en verde) con su cantidad (`c-cuenta`).
  - `c-tabla` (encabezado verde grisáceo, un tono más oscuro) y `c-titulo` (título de sección con ícono).
  - `c-nombre` / `c-inicial` (círculo con la inicial) y `c-saldo` (`debe`, `favor`) en las listas de clientes y proveedores.
- Los íconos son SVG de trazo escritos en cada pantalla (`const ICO = { … }`), que toman el color del texto.
- Detalles compartidos: `verVenta(id, ctx, alCambiar)` de caja.js (ver, devolver, anular) se abre también desde la cuenta del
  cliente; `verCompra(id, ctx)` de compras.js, desde la del proveedor (con un `ctx` cuyo `recargar` vuelve a armar la ficha).
- **Campo de escanear** de Cargar compra y Entradas y salidas: `campoEscaner(texto)` + `seguirLector(input)` de `escaner.js`
  arman el mismo campo que Vender (clases `v-busca`, lupa y "Clic acá para escanear" / "Lector listo"), dentro de
  `.buscador.escanear` (recuadro blanco aparte); el 📷 va adentro (`botonCamara(..., { envolver: false })`). Un buscador
  común con ese tono: `.input.como-vender` (el de elegir producto en Cargar desde factura).
- En Cargar compra y Entradas y salidas, como en Vender, el último producto cargado se **muestra** arriba (`.reverse()` al
  pintar, `data-k` con la posición real) y `d.items` sigue en el orden de carga.

## F5 no recarga con algo cargado
- La venta, la compra a mano, la factura y la entrada o salida viven solo en memoria. Cada pantalla anota cuándo tiene algo
  sin guardar con `cargaSinGuardar(fn)` (`ui.js`); `hayCargaSinGuardar()` las consulta. **Una pantalla nueva de carga se suma.**
- `app.js` (`sinRecargar`): F5, Ctrl + F5 y Ctrl + R no recargan en Vender, Compras y Entradas y salidas
  (`PANTALLAS_DE_CARGA`), ni en ningún lado con algo sin guardar, y avisa por qué. Con algo sin guardar, `beforeunload` hace
  que el navegador pregunte "¿Salir del sitio?" (botón recargar, cerrar la pestaña, "Actualizar").
