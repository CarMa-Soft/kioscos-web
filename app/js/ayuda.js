// Ayuda: preguntas frecuentes y cómo hacer cada cosa, con buscador. Sin IA ni base: todo está acá.
// El empleado ve solo lo que puede hacer; los temas con admin: true son del dueño.
import { verRecorrido } from './recorrido.js';
import { $, $$, esc } from './ui.js';

const TEMAS = [
  // ---------- Vender
  { s: 'Vender', t: 'Cómo hago una venta', x: `<ol><li>En <b>Vender</b>, fijate que el buscador diga <b>"Lector listo"</b> (si no, hacé clic en él).</li>
    <li>Escaneá los productos o buscalos por nombre (con <kbd>↑</kbd><kbd>↓</kbd> elegís y <kbd>Enter</kbd> agrega).</li>
    <li>Elegí la forma de pago a la derecha y apretá <b>Cobrar</b> (<kbd>F2</kbd>).</li>
    <li>Elegí <b>Imprimir</b> o <b>No imprimir</b>: ahí se registra la venta.</li></ol>` },
  { s: 'Vender', t: 'Cargar varias unidades de una vez', x: 'Escribí la cantidad y un asterisco antes del código o el nombre: <kbd>3*</kbd> y después escaneá. También podés cambiar la cantidad en el renglón con <b>−</b> y <b>+</b> o escribiéndola.' },
  { s: 'Vender', t: 'El lector de códigos no hace nada', x: `<ul><li>El buscador tiene que decir <b>"Lector listo"</b>: si dice "Clic acá para escanear", hacé clic en él y volvé a escanear.</li>
    <li>Probá el lector en el Bloc de notas: si ahí no escribe nada, el problema es el lector o la conexión (probá otro USB, sin adaptadores).</li>
    <li>Si escribe los números pero no baja de renglón, al lector le falta la configuración "Enter" (se hace escaneando un código del manual del lector).</li></ul>` },
  { s: 'Vender', t: 'Usar la cámara del celular como lector', x: 'En el celular (Chrome en Android), al lado del buscador está el botón 📷. Cada código que lee se agrega a la venta; el mismo código dos veces seguidas no se suma solo: usá el botón <b>+1</b>.' },
  { s: 'Vender', t: 'Un producto no está cargado', x: `Al escanearlo o buscarlo aparece <b>"No está cargado"</b>: poné el precio (y el nombre, si lo sabés) y <b>Crear y agregar</b>.
    Se suma a la venta y queda <b>a revisar</b> en Productos para que el dueño complete el costo, la categoría y el stock. La próxima vez que se escanee, ya lo encuentra.` },
  { s: 'Vender', t: 'Vender algo sin producto (Varios)', x: 'Botón <b>Varios / precio libre</b>: descripción e importe. No pasa por el stock ni por las estadísticas de productos. Si es un producto que no está cargado, mejor tildá <b>"Es un producto que no está cargado: crearlo"</b>. El dueño puede desactivar Varios en Ajustes.' },
  { s: 'Vender', t: 'Cambiar el precio de un renglón o hacer un descuento', x: `<ul><li>Clic en el precio del renglón: poné otro precio o un porcentaje (por ejemplo <kbd>10%</kbd>) solo para esa venta.</li>
    <li>Descuento a toda la venta: en el panel de la derecha, <b>Descuento</b> en $ o en %.</li>
    <li>El empleado tiene un tope de descuento: si lo pasa, la app pide el PIN del dueño para autorizarlo.</li></ul>` },
  { s: 'Vender', t: 'Pagar con dos medios', x: 'En Forma de pago, <b>+ Dos medios</b>: en el primero escribí cuánto paga con ese medio; el resto va solo al segundo. Los recargos (por ejemplo crédito) se calculan sobre cada parte.' },
  { s: 'Vender', t: 'Calcular el vuelto', x: 'En <b>Paga con</b> escribí con cuánto paga en efectivo: la app muestra el vuelto antes de cobrar.' },
  { s: 'Vender', t: 'Productos de balanza (por kilo)', x: 'Si el producto se vende por kilo, al agregarlo pide los kilos. Con la balanza configurada en Ajustes, la etiqueta que imprime la balanza se escanea como cualquier código y trae el peso o el importe.' },
  { s: 'Vender', t: 'Apagar el sonido al escanear', x: 'Cada producto que entra a la venta hace un <b>bip</b> y su renglón destella en verde. Para apagar el bip, tocá <b>🔊</b> en la barra de Vender (queda <b>🔇</b>); cada PC lo recuerda. El sonido de “código que no existe” suena siempre. Al cobrar aparece un ✓ grande con el número de venta y el vuelto: se va solo, con un clic o al seguir escaneando.' },
  { s: 'Vender', t: 'Accesos rápidos', x: 'Los productos marcados como <b>"Botón rápido en Vender"</b> en su ficha aparecen arriba de la venta; los primeros 9 se agregan con <kbd>Alt</kbd> + número. Sirven para lo que no tiene código (pan, fiambre, cigarrillos sueltos…).' },
  { s: 'Vender', t: 'Atajos de teclado', x: '<kbd>F2</kbd> cobrar · <kbd>F1</kbd> efectivo · <kbd>F3</kbd> fiado · <kbd>Esc</kbd> limpiar el buscador · <kbd>Alt</kbd> + número: acceso rápido.' },
  { s: 'Vender', t: '¿Por qué F5 no recarga la página?', x: 'Lo que se está cargando (la venta, una compra, una factura o una entrada o salida) está solo en esta pantalla y se perdería al recargar. Por eso en Vender, Compras y Entradas y salidas, y en cualquier lado mientras haya algo cargado sin guardar, <kbd>F5</kbd> y <kbd>Ctrl</kbd> + <kbd>R</kbd> no hacen nada. Si igual se recarga con el botón del navegador o se cierra la pestaña, el navegador pregunta antes de salir.' },

  // ---------- Fiado, entregas y encargos
  { s: 'Fiado, entregas y encargos', t: 'Fiar una venta', x: 'Elegí el <b>Cliente</b> (o crealo con <b>+</b>) y la forma de pago <b>Fiado</b> (<kbd>F3</kbd>). Va a la cuenta del cliente, no a la caja. Si el cliente tiene límite y lo pasaría, la app pregunta si fiar igual.' },
  { s: 'Fiado, entregas y encargos', t: 'Cobrarle a un cliente lo que debe', x: 'En <b>Clientes</b>, abrí el cliente y <b>Cobrar</b>: el pago entra a la caja del turno y se aplica a lo que vence primero (o elegís qué compras paga). Lo que sobra queda a favor.' },
  { s: 'Fiado, entregas y encargos', t: 'Mandarle a un cliente lo que debe (PDF o WhatsApp)', x: 'En <b>Clientes</b>, abrí el cliente: <b>📄 Estado de cuenta</b> baja un PDF con cada compra que debe (con sus productos), lo pagado y el total; <b>WhatsApp</b> abre WhatsApp con el mensaje armado, al teléfono del cliente (si no tiene, elegís el contacto).' },
  { s: 'Fiado, entregas y encargos', t: 'Ver quién debe más o desde hace más tiempo', x: 'En <b>Clientes</b>, tocá el título de la columna para ordenar: <b>Saldo</b> (los que más deben primero), <b>Debe desde</b> (la deuda más vieja primero, con los días y si ya venció), <b>Límite</b> o <b>Cliente</b>. Otro toque invierte el orden. El filtro <b>Deben</b> deja solo a los que deben.' },
  { s: 'Fiado, entregas y encargos', t: 'Vender más de lo que hay en stock (entrega pendiente)', x: `Si se lleva más de lo que hay, al cobrar la app pregunta: se lleva lo que hay y el resto queda <b>para entregar</b> a su nombre (ya cobrado), o se lleva todo (el stock estaba mal).
    Lo pendiente aparece en Vender, Hoy, Pedidos y Productos. Cuando llega la mercadería: en Vender, el aviso de arriba <b>📦 entregas pendientes → Ver → Entregar</b> (se pone verde cuando ya se puede).` },
  { s: 'Fiado, entregas y encargos', t: 'Un cliente encarga algo sin pagarlo (o con seña)', x: `<ol><li>En Vender, botón <b>📋 Encargo</b>: producto, cantidad, a nombre de quién, teléfono y, si deja, la <b>seña</b> y su forma de pago.</li>
    <li>No es una venta: no toca el stock. La seña entra a la caja en ese momento (Caja → Movimientos, "Seña encargo #N").</li>
    <li>Aparece en Pedidos para pedirlo al proveedor, y en Hoy.</li></ol>` },
  { s: 'Fiado, entregas y encargos', t: 'Entregar un encargo cuando llega', x: `En Vender, el aviso de arriba <b>📋 encargos → Ver → Pasar a la venta</b> (se pone verde cuando llegó). Al cobrar, la seña se descuenta del total.
    Si llegó una parte, el botón dice "Pasar 10 a la venta": se cobran esos y el resto sigue pendiente. Sin mercadería dice "todavía no llegó".` },
  { s: 'Fiado, entregas y encargos', t: 'Cancelar un encargo', x: 'En Vender, aviso de arriba <b>📋 encargos → Ver → Cancelar</b>. Si dejó seña, elegís devolverla (sale de la caja) o que quede para el negocio.' },
  { s: 'Fiado, entregas y encargos', t: 'Dónde veo las señas', x: 'En <b>Caja → Movimientos</b> (al final de la página), como "Seña encargo #N", y en <b>Hoy</b>, al lado de cada encargo. No aparecen en "Ventas del turno" porque no son ventas.' },

  // ---------- Caja
  { s: 'Caja', t: 'Abrir el turno', x: 'En <b>Caja</b>, <b>Abrir turno</b> con el efectivo inicial. Sin turno abierto no se puede vender. Hay un solo turno abierto por negocio: vende quien lo abrió (o el dueño).' },
  { s: 'Caja', t: 'Ingresos y egresos de plata', x: 'En Caja, <b>Ingreso</b> o <b>Egreso</b> (por ejemplo, pago a un repartidor o cambio que se agrega). Quedan en Movimientos y en el efectivo que tiene que haber.' },
  { s: 'Caja', t: 'Cerrar el turno', x: 'En Caja, <b>Cerrar turno</b>: elegí <b>Poner el total</b> (escribís cuánto efectivo hay) o <b>Contar billete por billete</b> (la app suma). Muestra si sobra o falta y podés registrar la diferencia como ajuste. Cada PC recuerda la forma que elegiste. Se puede imprimir el cierre.' },
  { s: 'Reportes, usuarios y ajustes', a: true, t: 'Descargar mis datos (copia en Excel)', x: 'En <b>Ajustes → Descargar mis datos</b>, elegí desde y hasta qué fecha querés las ventas y tocá <b>Descargar Excel</b>: baja una planilla con tus productos, clientes (con lo que deben), proveedores (con lo que les debés) y las ventas de esas fechas (hasta un año por vez). Guardala donde quieras como copia.' },
  { s: 'Caja', t: 'Ver o anular una venta', x: 'En Caja, en Ventas del turno, <b>Ver</b>: muestra el detalle, permite volver a imprimir el ticket (<b>Imprimir ticket</b>), hacer una devolución y (solo el dueño) anularla. Anular devuelve el stock y saca la plata de la caja.' },
  { s: 'Caja', t: 'Abrir la caja para empezar el día', x: 'Si la caja está cerrada, en <b>Vender</b> aparece arriba <b>Abrir la caja</b> (también al tocar Cobrar). Contá el efectivo y confirmá: ya viene puesto lo que quedó al cerrar el turno anterior. También se abre desde <b>Caja</b>.' },
  { s: 'Caja', t: 'Devolver productos de una venta', x: 'Caja → Ver la venta → <b>Devolver productos</b>: elegís qué vuelve, si vuelve al stock (si está roto o vencido, no) y cómo se devuelve la plata. El empleado necesita el PIN del dueño.' },
  { s: 'Caja', t: 'Turnos anteriores', x: 'En Caja, <b>Turnos anteriores</b>: el detalle de cada turno cerrado (totales, billetes y movimientos). El empleado ve solo los suyos.' },

  // ---------- Productos y precios (dueño)
  { s: 'Productos y precios', a: true, t: 'Cargar o editar un producto', x: 'En <b>Productos</b>, <b>＋ Nuevo producto</b> o clic en uno. Nombre, código (también con la cámara), categoría, costo, margen y precio, stock y stock mínimo. En "Otros códigos" agregás los de otros envases del mismo producto.' },
  { s: 'Productos y precios', a: true, t: 'Cargar muchos productos desde una planilla (Excel)', x: 'En <b>Productos → 📥 Importar planilla</b>, elegí un Excel (.xlsx) o un CSV con una fila de títulos y un producto por fila: hace falta el <b>nombre</b> y el <b>precio</b>; puede tener código de barras, costo, stock y categoría. La app adivina qué columna es cada dato (revisalo), muestra cómo van a quedar y los carga. Si un producto ya existe (mismo código, o mismo nombre sin código) le actualiza el precio y el costo: sirve para la lista nueva de un proveedor. Hay una planilla de ejemplo para bajar.' },
  { s: 'Productos y precios', a: true, t: 'Revisar los productos creados en la caja', x: 'En Productos, filtro <b>A revisar</b> (Hoy también avisa cuántos hay). Abrí cada uno, completá el nombre, el costo, la categoría y el stock real (contalo) y guardalo: deja de estar a revisar.' },
  { s: 'Productos y precios', a: true, t: 'Margen automático', x: 'Con <b>Margen automático</b> tildado, el precio se calcula solo (costo + margen, redondeado) y se actualiza cada vez que una compra trae un costo nuevo. Sin tildar, el precio queda fijo. El margen de los productos nuevos se configura en Precios y márgenes → Configuración.' },
  { s: 'Productos y precios', a: true, t: 'Subir precios de muchos productos a la vez', x: 'Productos → <b>Precios y márgenes</b>: en <b>Actualizar precios</b> subís o bajás el precio o el costo de los productos elegidos (por porcentaje o monto), con historial para deshacer. En <b>Asignar margen</b> ponés o quitás el margen automático a varios a la vez.' },
  { s: 'Productos y precios', a: true, t: 'Redondeo de precios', x: 'Productos → Precios y márgenes → <b>Configuración</b>: a qué múltiplo se redondean los precios hacia arriba (por ejemplo, de a $10) y el margen con que arrancan los productos nuevos.' },
  { s: 'Productos y precios', a: true, t: 'Imprimir la lista de precios o etiquetas', x: 'Productos → <b>🏷️ Lista de precios</b>: elegís los productos y sale un PDF con la lista o con etiquetas para las góndolas.' },
  { s: 'Productos y precios', a: true, t: 'Dar de baja un producto', x: 'En la ficha, destildá <b>Activo</b> (o Eliminar: si tuvo movimientos, se da de baja en lugar de borrarse). Los dados de baja no aparecen para vender; se ven en el filtro "Desactivados".' },
  { s: 'Productos y precios', a: true, t: 'Corregir el stock', x: 'En la ficha del producto, cambiá el <b>Stock</b> y guardá: queda registrado como corrección. Para mercadería que entra o sale sin compra ni venta (rotura, consumo, regalo), usá <b>Entradas y salidas</b>.' },

  // ---------- Compras y proveedores (dueño)
  { s: 'Compras y proveedores', a: true, t: 'Cargar una compra a mano', x: `Compras → <b>Cargar compra</b>: proveedor, comprobante, productos con cantidad y costo. Suma el stock y actualiza costos (y precios, si tienen margen automático).
    En <b>Impuestos</b> indicás si los costos son con o sin IVA (con la alícuota de cada producto), las percepciones y los impuestos internos.` },
  { s: 'Compras y proveedores', a: true, t: 'Cargar una compra desde la factura (con IA)', x: 'Compras → <b>Cargar desde factura</b>: subí la foto o el PDF (o sacala con el celular escaneando el QR). La IA lee los renglones; revisás qué producto es cada uno, las unidades por bulto, el IVA de cada renglón, y guardás.' },
  { s: 'Compras y proveedores', a: true, t: 'Mercadería que llegó sin factura', x: 'Al cargar la compra, tildá <b>factura pendiente</b>: suma el stock ahora y la factura se completa después, sin mover el stock otra vez.' },
  { s: 'Compras y proveedores', a: true, t: 'Pagarle a un proveedor', x: 'En <b>Proveedores</b>, abrí el proveedor y <b>Pagar</b> (de la caja o aparte). Ves lo que debés, qué vence y qué compras cubre cada pago.' },
  { s: 'Compras y proveedores', a: true, t: 'Armar un pedido al proveedor', x: '<b>Pedidos</b> junta, por proveedor, lo que está por debajo del mínimo o sin stock, más lo que se debe entregar y lo encargado. Ajustá cantidades y mandalo por <b>WhatsApp</b>, <b>PDF</b> o <b>Excel</b>. Al cargar la compra, lo que llegó sale solo del pedido.' },
  { s: 'Compras y proveedores', a: true, t: 'Devolverle mercadería a un proveedor', x: 'En Compras, abrí la compra y <b>Devolver al proveedor</b> (parte o toda): sale el stock y la plata va a la cuenta del proveedor, o entra a la caja si te la devolvió.' },

  // ---------- Reportes, usuarios y ajustes
  { s: 'Reportes, usuarios y ajustes', a: true, t: 'Ver cuánto vendí y gané', x: '<b>Reportes</b>: elegís las fechas y ves ventas, ganancia, devoluciones, por día, hora, forma de pago, vendedor, categoría y producto, descuentos, lo vendido como Varios, la mercadería valorizada y el fiado.' },
  { s: 'Reportes, usuarios y ajustes', t: 'Hoy', x: '<b>Hoy</b> muestra las ventas del día (el empleado, las suyas), la caja, el fiado pendiente, las entregas pendientes y los encargos, y avisa si hay productos a revisar.' },
  { s: 'Reportes, usuarios y ajustes', t: 'Cambiar de usuario o cambiar mi PIN', x: 'Abajo en el menú de la izquierda (en el celular, dentro del menú ☰), <b>Cambiar de usuario</b>: cada uno entra con su nombre y su PIN. El empleado cambia su PIN con <b>Cambiar mi PIN</b>, abajo junto a su nombre; el dueño, en <b>Usuarios</b>. Cinco PIN incorrectos seguidos bloquean a ese usuario 5 minutos.' },
  { s: 'Reportes, usuarios y ajustes', t: 'Instalar la app (ícono en el escritorio o en el celular)', x: 'En Chrome o Edge, abajo en el menú de la izquierda aparece <b>⬇️ Instalar la app</b>: queda un ícono en el escritorio (o en el celular) y se abre en su propia ventana, sin la barra del navegador. Si no aparece, en el menú del navegador (⋮) elegí <b>Instalar</b> o <b>Agregar a la pantalla de inicio</b>. Necesita internet igual que siempre.' },
  { s: 'Reportes, usuarios y ajustes', t: 'Achicar el menú de la izquierda', x: 'El menú de la izquierda tiene las secciones en bloques, separados por una línea: el <b>día a día</b> (Hoy, Vender, Caja, Clientes), la <b>mercadería</b> (Productos, Entradas y salidas, Pedidos, Compras y Proveedores), los <b>números</b> (Reportes) y, abajo de todo, <b>Usuarios y Ajustes</b>. El empleado ve solo el día a día. Con el botón <b>«</b>, arriba, el menú se achica y quedan solo los íconos (al pasar el mouse se ve el nombre); con <b>»</b> vuelve a abrirse. Cada PC recuerda cómo lo dejaste. En el celular el menú está en el botón <b>☰</b>, arriba.' },
  { s: 'Reportes, usuarios y ajustes', t: 'Usar el menú con el teclado', x: 'Apretá <b>Ctrl + ←</b> (o el atajo que haya elegido el dueño en <b>Ajustes → Teclado</b>) y el cursor va al menú, a la sección en la que estás. Ahí: <b>↑ ↓</b> pasan a la anterior o la siguiente y la van mostrando (al llegar al final vuelve al principio), <b>Inicio</b> y <b>Fin</b> van a la primera y a la última, <b>Enter</b> abre la sección y <b>Ctrl + →</b> pasa a la pantalla (en Vender, al buscador). También se puede recorrer todo con <b>Tab</b>. Donde está el cursor se marca con un borde verde.' },
  { s: 'Reportes, usuarios y ajustes', a: true, t: 'Entrar sin poner el PIN', x: 'Si atendés solo vos (un único usuario, el dueño), en <b>Usuarios → Entrar sin PIN</b> tildá la opción y guardá: al abrir la app entrás directo. Con un solo usuario, aunque no lo actives, no hace falta elegir tu nombre: va directo al PIN. Si agregás un empleado, se vuelve a pedir el PIN a cada uno.' },
  { s: 'Reportes, usuarios y ajustes', a: true, t: 'Agregar un empleado', x: 'En <b>Usuarios</b>, agregá la persona con su nombre, rol (Empleado o Dueño) y PIN. El empleado no ve costos, ganancias ni las secciones del dueño.' },
  { s: 'Reportes, usuarios y ajustes', a: true, t: 'Configurar la impresora de tickets', x: `<ol>
    <li>Conectá la impresora y encendela. Si Windows no la reconoce sola, instalá el programa (driver) de la marca: viene en un CD o en su página web.</li>
    <li>En Windows, <b>Configuración → Dispositivos → Impresoras</b>: clic en la de tickets → <b>Establecer como predeterminada</b>.</li>
    <li>En la app, <b>Ajustes → Imprimir un ticket de prueba</b>. Si sale, ya está.</li>
    <li>Para que imprima <b>directo, sin la ventana de impresión</b>: hacé un acceso directo a Chrome en el escritorio, clic derecho → <b>Propiedades</b>, y en <b>Destino</b> agregá al final, después de un espacio, <span class="mono">--kiosk-printing</span>. Abrí la app siempre desde ese acceso directo.</li>
    <li>En <b>Ajustes → Ticket después de cada venta</b> elegí <b>Imprimir siempre</b>, <b>Preguntar</b> o <b>No imprimir</b>.</li></ol>
    Si la impresora aparece en Windows como "dispositivo no especificado" o como un puerto COM, hay que instalarle el driver y elegir ese puerto: pedí ayuda.` },
  { s: 'Reportes, usuarios y ajustes', a: true, t: 'Datos del ticket e impresión', x: 'En <b>Ajustes</b>: nombre, CUIT, dirección, teléfono y pie del ticket, y si se imprime siempre, nunca o se pregunta. Con <b>Imprimir un ticket de prueba</b> lo probás.' },
  { s: 'Reportes, usuarios y ajustes', a: true, t: 'Formas de pago, recargos y tope de descuento', x: 'En <b>Ajustes → Formas de pago y recargos</b>: qué formas se usan, el recargo de cada una y el tope de descuento de los empleados.' },
];

const sinAcentos = s => String(s ?? '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '');
const textoPlano = h => h.replace(/<[^>]+>/g, ' ');

export async function pantallaAyuda(vista, ctx) {
  const admin = ctx.yo.rol === 'admin';
  const temas = TEMAS.filter(x => admin || !x.a);
  vista.innerHTML = `<div class="cabecera"><div><h2>Ayuda</h2><p class="muted">Cómo hacer cada cosa en la app. Escribí lo que buscás.</p></div>
      ${admin ? '<div class="acciones"><button class="btn primario" id="ver-recorrido">▶ Ver el recorrido de bienvenida</button></div>' : ''}</div>
    <label class="p-buscar ay-buscar"><svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="11" cy="11" r="6.5"/><path d="m20 20-4.2-4.2"/></svg>
      <input id="ay-filtro" placeholder="Por ejemplo: seña, fiado, cerrar turno, lector…" autocomplete="off" autofocus></label>
    <div id="ay-lista"></div>
    <p class="muted chico">¿No encontrás lo que buscás? Consultá con quien te instaló la app.</p>`;
  const pintar = () => {
    const palabras = sinAcentos($('#ay-filtro').value).split(/\s+/).filter(Boolean);
    const ver = temas.filter(x => palabras.every(w => sinAcentos(x.s + ' ' + x.t + ' ' + textoPlano(x.x)).includes(w)));
    const secciones = [...new Set(ver.map(x => x.s))];
    $('#ay-lista').innerHTML = ver.length ? secciones.map(s => `<section class="recuadro-blanco ay-seccion"><h3>${esc(s)}</h3>
        ${ver.filter(x => x.s === s).map(x => `<details class="ay-tema" ${palabras.length ? 'open' : ''}><summary>${esc(x.t)}</summary><div class="ay-texto">${x.x}</div></details>`).join('')}</section>`).join('')
      : '<div class="recuadro-blanco"><p class="muted vacio">No hay temas con esas palabras. Probá con otra (por ejemplo "caja", "precio", "cliente").</p></div>';
  };
  $('#ay-filtro').oninput = pintar;
  if ($('#ver-recorrido')) $('#ver-recorrido').onclick = () => verRecorrido(ctx);
  pintar();
}
