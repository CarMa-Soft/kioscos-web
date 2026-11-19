// Cargar una compra desde la factura (solo dueño), como en la app local: se elige el PDF o las fotos, los lee la IA
// (función de Supabase "leer-factura"), la base reconoce el proveedor y los productos (preparar_factura), se revisa cada
// renglón (qué producto es, cuántas unidades de venta trae, costo y precio) y se guarda (registrar_compra_factura).
// También sirve un archivo .json ya leído (formato "Factura leída" en CLAUDE.md).
import { llamar, funcion } from './base.js';
import * as cat from './catalogo.js';
import { $, $$, esc, plata, cant, dia, hoyDia, sumarDias, numero, aviso, correr, modal, confirmar } from './ui.js';
import { avisarListas } from './entregas.js';

const r2 = n => Math.round((+n || 0) * 100) / 100;
const r3 = n => Math.round((+n || 0) * 1000) / 1000;
const UNIDADES = new Set(['bulto', 'unidad', 'kg']);
let carga = null;   // la factura que se está revisando (sobrevive a cambiar de sección)
export const hayCargaFactura = () => !!carga;

// Unidades de venta que trae cada unidad facturada, según la descripción ("X 36 UNIDADES", "18 UN X 20 GR", "X 6U", "TRIPACK")
function unidadesDeDescripcion(desc) {
  const s = String(desc || '').toUpperCase();
  if (/TRIPACK/.test(s)) return 3;
  const m = s.match(/(?:X|\b)\s*(\d+)\s*(?:UNIDADES|UNID\.?|UN\.?|U)(?![A-Z])/);
  return m && +m[1] > 1 ? +m[1] : null;
}
const nombreLindo = s => String(s || '').toLowerCase().replace(/\s+/g, ' ').trim().replace(/\.$/, '')
  .replace(/(^|[\s(])([a-záéíóúñ])/g, (m, a, b) => a + b.toUpperCase());
// CUIT vacío o con 11 números y el dígito verificador correcto (la base hace la misma cuenta)
function cuitOk(v) {
  const d = String(v ?? '').replace(/\D/g, '');
  if (!d) return true;
  if (d.length !== 11) return false;
  const r = 11 - [5, 4, 3, 2, 7, 6, 5, 4, 3, 2].reduce((s, p, i) => s + p * +d[i], 0) % 11;
  return +d[10] === (r === 11 ? 0 : r === 10 ? 9 : r);
}
function validarFactura(f) {
  if (!f || typeof f !== 'object' || !Array.isArray(f.items) || !f.items.length) throw new Error('La factura no tiene renglones');
  f.items.forEach((it, k) => {
    if (!(+it.cantidad > 0) || !Number.isFinite(+it.importe)) throw new Error(`El renglón ${k + 1} no tiene cantidad o importe`);
    if (!UNIDADES.has(it.unidad)) it.unidad = 'unidad';
  });
  f.proveedor ??= { nombre: '', cuit: null };
  return f;
}
// La cuenta del renglón cierra: cantidad × precio − bonificación = importe (solo si la factura trae el precio)
const lineaCierra = it => !(+it.precio_unitario > 0)
  || Math.abs(+it.cantidad * +it.precio_unitario * (1 - (+it.bonificacion || 0) / 100) - +it.importe) <= Math.max(1, +it.importe * 0.001);
const redondear = (v, m) => +m > 0 ? Math.ceil(r2(v) / m) * m : r2(v);

// Fotos: se achican en el navegador (lado mayor 2000 px, JPEG) para que suban rápido y no pasen el límite de la IA
function achicarFoto(archivo, max = 2000) {
  return new Promise((ok, mal) => {
    const img = new Image(), url = URL.createObjectURL(archivo);
    img.onload = () => {
      const k = Math.min(1, max / Math.max(img.width, img.height));
      const cv = document.createElement('canvas'); cv.width = Math.round(img.width * k); cv.height = Math.round(img.height * k);
      const g = cv.getContext('2d'); g.fillStyle = '#fff'; g.fillRect(0, 0, cv.width, cv.height); g.drawImage(img, 0, 0, cv.width, cv.height);
      URL.revokeObjectURL(url);
      cv.toBlob(b => b ? ok(b) : mal(new Error('No se pudo procesar la foto')), 'image/jpeg', 0.88);
    };
    img.onerror = () => { URL.revokeObjectURL(url); mal(new Error('El archivo no es una imagen válida')); };
    img.src = url;
  });
}
const enBase64 = blob => new Promise((ok, mal) => {
  const r = new FileReader();
  r.onload = () => ok(String(r.result).split(',')[1]);
  r.onerror = () => mal(new Error('No se pudo leer el archivo'));
  r.readAsDataURL(blob);
});

// Arma la revisión: lo que la base reconoce (proveedor, productos, unidades) y lo que se puede cambiar
async function iniciar(f, proveedor_id = null, lectura = null) {
  const [prep, cata, provs, caja] = await Promise.all([llamar('preparar_factura', { p: { factura: f, proveedor_id } }),
    llamar('catalogo'), llamar('proveedores'), llamar('estado_caja')]);
  const prev = carga?.f === f ? carga : null;
  carga = {
    f, prep, lectura: lectura ?? prev?.lectura ?? null,
    prods: new Map(cata.productos.map(p => [p.id, p])), productos: cata.productos, cats: cata.categorias, provs, formas: caja.formas_pago, turno: !!caja.turno,
    proveedor_id: prep.proveedor ? String(prep.proveedor.id) : 'nuevo',
    cuit: prev?.cuit ?? (f.proveedor?.cuit || ''),
    comprobante: prev?.comprobante ?? (f.comprobante || ''),
    fecha_factura: prev?.fecha_factura ?? (/^\d{4}-\d{2}-\d{2}$/.test(f.fecha || '') ? f.fecha : hoyDia()),
    vencimiento: prev?.vencimiento ?? (/^\d{4}-\d{2}-\d{2}$/.test(f.vencimiento || '') ? f.vencimiento : ''),
    sumarIva: prev?.sumarIva ?? preferencia('iva'), sumarPerc: prev?.sumarPerc ?? preferencia('perc'),
    pagar_caja: prev?.pagar_caja ?? false, forma: prev?.forma ?? 'Efectivo',
    lineas: f.items.map((it, i) => {
      const p = prep.lineas[i], ant = prev?.lineas[i];
      if (ant && !p.producto_id) return { ...ant, sugerencias: p.sugerencias };
      const unidades = p.unidades ?? (it.unidad === 'kg' ? 1 : it.unidad === 'bulto' && +it.unidades_por_bulto > 0 ? +it.unidades_por_bulto : unidadesDeDescripcion(it.descripcion) ?? 1);
      return { producto_id: p.producto_id ? String(p.producto_id) : '', recordado: !!p.producto_id, sugerencias: p.sugerencias,
        nuevo: null, unidades: String(+unidades), precio: null, alicuota: it.alicuota_iva != null ? +it.alicuota_iva : 21 };
    }),
  };
}

// Cuentas de un renglón: unidades de venta que entran, costo por unidad y precio propuesto
// Si el IVA y las percepciones van al costo: para un monotributista son costo; un responsable inscripto los descuenta.
// Lo que se elige queda recordado en esta PC.
const preferencia = clave => { try { return localStorage.getItem('kioscos.factura.' + clave) !== 'no'; } catch { return true; } };
const recordar = (clave, si) => { try { localStorage.setItem('kioscos.factura.' + clave, si ? 'si' : 'no'); } catch { /* sin almacenamiento */ } };
const alicuotaDe = (it, l) => l?.alicuota ?? (it.alicuota_iva != null ? +it.alicuota_iva : 21);
const ALICUOTAS = [0, 2.5, 5, 10.5, 21, 27];

function calcular(it, l) {
  const f = carga.f;
  const suma = f.items.reduce((s, x) => s + +x.importe, 0);
  // descuento global y otros cargos (flete, "recupero de gastos") se reparten en proporción al importe
  const ajuste = suma > 0 ? (suma - (+f.descuento_global || 0) + (+f.otros_cargos || 0)) / suma : 1;
  const factor = numero(l.unidades) > 0 ? numero(l.unidades) : 1;
  const ingresan = r3(+it.cantidad * factor);
  const neto = ingresan > 0 ? +it.importe * ajuste / ingresan : 0;
  // percepciones e impuestos internos se reparten en proporción al neto de cada renglón; los internos siempre son costo
  const netoTotal = suma * ajuste;
  const pPerc = netoTotal > 0 && carga.sumarPerc ? (+f.percepciones || 0) / netoTotal : 0;
  const pInt = netoTotal > 0 ? (+f.impuestos_internos || 0) / netoTotal : 0;
  const costo = r2(neto * (1 + (carga.sumarIva ? alicuotaDe(it, l) / 100 : 0) + pPerc + pInt));
  const sugerido = +it.precio_sugerido > 0 ? +it.precio_sugerido : null;
  return { ingresan, costo, propuesto: sugerido ?? redondear(costo * (1 + carga.prep.margen / 100), carga.prep.redondeo), sugerido };
}
const vencePropuesto = () => {
  const plazo = carga.provs.find(p => String(p.id) === carga.proveedor_id)?.plazo;
  return sumarDias(carga.fecha_factura || hoyDia(), plazo || 0);
};

// QR dibujado en un canvas (sin estilos en línea, por la política de seguridad de la página)
async function dibujarQR(canvas, texto) {
  const { default: qrcode } = await import('https://cdn.jsdelivr.net/npm/qrcode-generator@2.0.4/+esm');
  const q = qrcode(0, 'M'); q.addData(texto); q.make();
  const n = q.getModuleCount(), borde = 4, celda = Math.floor(240 / (n + borde * 2));
  canvas.width = canvas.height = celda * (n + borde * 2);
  const g = canvas.getContext('2d');
  g.fillStyle = '#fff'; g.fillRect(0, 0, canvas.width, canvas.height); g.fillStyle = '#000';
  for (let y = 0; y < n; y++) for (let x = 0; x < n; x++) if (q.isDark(y, x)) g.fillRect((x + borde) * celda, (y + borde) * celda, celda, celda);
}

// Factura desde el celular: la base da un código (15 minutos, una factura), se muestra como QR con la dirección de
// celu.html, y acá se consulta cada 2 segundos cómo va. Cuando la IA terminó, se abre la revisión como con un archivo.
async function desdeCelular(alLlegar) {
  const p = await llamar('crear_subida_celular');
  const url = new URL(`celu.html#${p.codigo}`, location.href).href;
  const m = modal('Mandar la factura desde el celular', `<div class="fila celu-qr">
      <canvas id="qr" class="qr" aria-label="Código QR para abrir en el celular"></canvas>
      <div class="crece"><ol><li>Abrí la cámara del celular y apuntá al código.</li>
          <li>Sacá una foto de cada hoja y tocá <b>Mandar a la PC</b>.</li></ol>
        <p class="muted chico">El celular solo necesita internet (no hace falta el mismo WiFi). El código vence en ${p.minutos} minutos y sirve para una factura.</p></div></div>
    <p id="celu-estado"><span class="etiqueta">Esperando la foto…</span></p>
    <div class="fila fin"><button class="btn" data-cerrar>Cancelar</button></div>`, { alCerrar: () => { if (abierto) { abierto = false; llamar('cancelar_subida_celular', { p_id: p.id }).catch(() => {}); } } });
  let abierto = true, t0 = null;
  await dibujarQR($('#qr', m.el), url).catch(() => { $('#qr', m.el).replaceWith(Object.assign(document.createElement('p'), { textContent: url, className: 'mono chico' })); });
  const estado = html => { if ($('#celu-estado', m.el)) $('#celu-estado', m.el).innerHTML = html; };
  while (abierto) {
    await new Promise(ok => setTimeout(ok, 2000));
    if (!abierto) return;
    let e;
    try { e = await llamar('estado_subida_celular', { p_id: p.id }); } catch { continue; }   // un corte momentáneo: se reintenta
    if (e.estado === 'esperando') continue;
    if (e.estado === 'leyendo') {
      t0 ??= Date.now();
      estado(`<span class="etiqueta pendiente">Llegó (${e.paginas} ${e.paginas === 1 ? 'hoja' : 'hojas'}). Leyendo la factura con IA… ${Math.round((Date.now() - t0) / 1000)} s</span>`);
    } else if (e.estado === 'error') {
      t0 = null;
      estado(`<span class="etiqueta alerta">No se pudo leer</span> ${esc(e.error || '')} <span class="muted">· Desde el celular se puede volver a mandar.</span>`);
    } else if (e.estado === 'vencido') {
      abierto = false;
      return estado('<span class="etiqueta alerta">El código venció.</span> <span class="muted">Cerrá esta ventana y pedí otro.</span>');
    } else if (e.estado === 'lista') {
      abierto = false;
      m.cerrar();
      carga = null;
      await correr(async () => {
        await iniciar(validarFactura(e.resultado.factura), null, { uso: e.resultado.uso, segundos: t0 ? Math.round((Date.now() - t0) / 1000) : null });
        alLlegar();
        aviso('Llegó la factura del celular', 'ok');
      });
      return;
    } else { abierto = false; m.cerrar(); return; }   // cancelada o ya entregada
  }
}

export async function pantallaFactura(vista, ctx, alSalir) {
  const c = carga;
  vista.innerHTML = `<div class="cabecera"><h2>Cargar desde factura</h2><div class="acciones">
      ${c ? '<button class="btn" id="descartar">Descartar</button>' : ''}<button class="btn" id="volver">Volver a Compras</button></div></div>
    <div class="recuadro-blanco form ancho"><div class="fila entre">
      <div><b>Factura o remito del proveedor</b><p class="muted chico">Elegí el PDF, el escaneo o las fotos (hasta 5, una por hoja): la lee la IA.
        Tarda entre 10 y 40 segundos y cuesta unos centavos de dólar. También sirve un archivo .json ya leído.</p></div>
      <div class="acciones"><label class="btn">📄 Elegir PDF o fotos<input type="file" id="archivo" accept=".pdf,application/pdf,image/*,.json,application/json" multiple hidden></label>
        <button class="btn primario" id="celu">📱 Desde el celular</button></div></div>
      <p id="leyendo" hidden></p></div>
    ${c?.lectura ? `<div class="recuadro-blanco fila"><span class="etiqueta info">Leída con IA</span>
        <span class="muted chico">${c.lectura.segundos ? c.lectura.segundos + ' s · ' : ''}US$ ${(+c.lectura.uso?.costo_usd || 0).toFixed(3)} · revisá cada renglón antes de guardar</span>
        ${c.lectura.verUrl ? '<button class="btn chico" id="ver">Ver la factura</button>' : ''}
        ${c.f.observaciones ? `<p class="crece"><b>La IA avisa:</b> ${esc(c.f.observaciones)}</p>` : ''}</div>` : ''}
    <div id="cuerpo">${c ? '' : '<p class="muted vacio">Elegí la factura para empezar.</p>'}</div>`;
  $('#volver').onclick = alSalir;
  $('#celu').onclick = () => correr(() => desdeCelular(() => pantallaFactura(vista, ctx, alSalir)));
  if ($('#ver')) $('#ver').onclick = () => window.open(c.lectura.verUrl, '_blank');
  if ($('#descartar')) $('#descartar').onclick = async () => {
    if (await confirmar('Descartar', '¿Descartar esta factura sin guardar la compra?', 'Descartar')) { carga = null; pantallaFactura(vista, ctx, alSalir); }
  };
  $('#archivo').onchange = e => {
    const lista = [...e.target.files], input = e.target, estado = $('#leyendo');
    if (!lista.length) return;
    correr(async () => {
      let f, lectura = null;
      if (lista.length === 1 && (/\.json$/i.test(lista[0].name) || lista[0].type === 'application/json')) {
        try { f = validarFactura(JSON.parse(await lista[0].text())); } catch (err) { throw new Error(`No se pudo leer el archivo: ${err.message}`); }
      } else {
        const pdfs = lista.filter(a => a.type === 'application/pdf' || /\.pdf$/i.test(a.name));
        if (pdfs.length && lista.length > 1) throw new Error('Elegí un solo PDF, o hasta 5 fotos');
        if (!pdfs.length && lista.some(a => !a.type.startsWith('image/'))) throw new Error('Los archivos tienen que ser un PDF o fotos');
        if (lista.length > 5) throw new Error('Hasta 5 fotos (una por hoja)');
        const blobs = pdfs.length ? pdfs : await Promise.all(lista.map(a => achicarFoto(a)));
        input.disabled = true; estado.hidden = false;
        const t0 = Date.now();
        const reloj = setInterval(() => { estado.innerHTML = `<span class="etiqueta pendiente">Leyendo la factura con IA… ${Math.round((Date.now() - t0) / 1000)} s</span> <span class="muted">no cierres esta pantalla</span>`; }, 500);
        try {
          const archivos = await Promise.all(blobs.map(async b => ({ tipo: pdfs.length ? 'application/pdf' : 'image/jpeg', datos: await enBase64(b) })));
          const r = await funcion('leer-factura', { archivos });
          f = validarFactura(r.factura);
          lectura = { uso: r.uso, verUrl: URL.createObjectURL(blobs[0]), segundos: Math.round((Date.now() - t0) / 1000) };
        } finally { clearInterval(reloj); input.disabled = false; estado.hidden = true; }
      }
      carga = null;
      await iniciar(f, null, lectura);
      pantallaFactura(vista, ctx, alSalir);
    }).finally(() => { input.value = ''; });
  };
  if (c) pintar(vista, ctx, alSalir);
}

function pintar(vista, ctx, alSalir) {
  const c = carga, f = c.f, box = $('#cuerpo');
  const suma = r2(f.items.reduce((s, x) => s + +x.importe, 0));
  const neto = r2(suma - (+f.descuento_global || 0) + (+f.otros_cargos || 0));
  const okSubtotal = !(+f.subtotal > 0) || Math.abs(neto - +f.subtotal) <= 1;
  const okTotal = !(+f.total > 0) || !(+f.subtotal > 0) || Math.abs(+f.subtotal + (+f.iva || 0) + (+f.percepciones || 0) + (+f.impuestos_internos || 0) - +f.total) <= 1;
  const ajusteNeto = suma > 0 ? neto / suma : 1;
  const ivaRenglones = r2(f.items.reduce((s, it, i) => s + +it.importe * ajusteNeto * alicuotaDe(it, c.lineas[i]) / 100, 0));
  const okIva = !(+f.iva > 0) || Math.abs(ivaRenglones - +f.iva) <= Math.max(1, +f.iva * 0.005);
  const malas = f.items.filter(it => !lineaCierra(it)).length;
  const sinProducto = c.lineas.filter(l => !l.producto_id && !l.nuevo).length;
  const chip = (b, txt) => `<span class="etiqueta ${b ? 'bien' : 'alerta'}">${b ? '✓' : '✗'} ${txt}</span>`;
  const cuitMal = c.proveedor_id === 'nuevo' && !cuitOk(c.cuit);
  const unidadTxt = it => it.unidad === 'kg' ? 'kg' : it.unidad === 'bulto' ? `bulto${+it.cantidad === 1 ? '' : 's'}` : `unidad${+it.cantidad === 1 ? '' : 'es'}`;
  const plazo = c.provs.find(p => String(p.id) === c.proveedor_id)?.plazo;
  box.innerHTML = `<div class="recuadro-blanco form ancho">
      <div class="fila"><label class="crece">Proveedor<select class="input" id="f-prov">
          <option value="nuevo" ${c.proveedor_id === 'nuevo' ? 'selected' : ''}>＋ Nuevo: ${esc(f.proveedor?.nombre || 'proveedor de la factura')}</option>
          ${c.provs.map(p => `<option value="${p.id}" ${String(p.id) === c.proveedor_id ? 'selected' : ''}>${esc(p.nombre)}${p.cuit ? ' (' + esc(p.cuit) + ')' : ''}</option>`).join('')}</select></label>
        ${c.proveedor_id === 'nuevo' ? `<label class="crece">CUIT ${cuitMal ? '<span class="mal">· no es válido: revisalo en la factura</span>' : ''}
          <input class="input mono" id="f-cuit" value="${esc(c.cuit)}" placeholder="30-12345678-9"></label>` : ''}
        <label class="crece">Factura<input class="input" id="f-comp" value="${esc(c.comprobante)}"></label>
        <label class="crece">Fecha de la factura<input class="input" type="date" id="f-fecha" value="${esc(c.fecha_factura || '')}"></label>
        <label class="crece">Vence ${c.vencimiento ? '' : `<span class="muted">(${plazo ? plazo + ' días de plazo' : 'sin plazo'})</span>`}
          <input class="input" type="date" id="f-vence" value="${esc(c.vencimiento || vencePropuesto())}"></label></div>
      <div class="chips">${chip(!malas, malas ? `${malas} renglón(es) no cierran` : 'Todos los renglones cierran')}
        ${chip(okSubtotal, `Renglones ${plata(neto)} ${okSubtotal ? '=' : '≠'} subtotal ${plata(f.subtotal)}`)}
        ${+f.iva > 0 ? chip(okIva, `IVA de los renglones ${plata(ivaRenglones)} ${okIva ? '=' : '≠'} IVA de la factura ${plata(f.iva)}${okIva ? '' : ': revisá la alícuota de cada renglón'}`) : ''}
        ${chip(okTotal, `Total ${plata(f.total)}`)}
        ${+f.percepciones ? `<span class="etiqueta">Percepciones ${plata(f.percepciones)}${c.sumarPerc ? ' · van al costo' : ''}</span>` : ''}
        ${+f.impuestos_internos ? `<span class="etiqueta">Impuestos internos ${plata(f.impuestos_internos)} · van al costo</span>` : ''}
        ${+f.descuento_global ? `<span class="etiqueta">Descuento global ${plata(f.descuento_global)}</span>` : ''}
        ${+f.otros_cargos ? `<span class="etiqueta">Otros cargos ${plata(f.otros_cargos)}</span>` : ''}
        ${chip(!sinProducto, sinProducto ? `${sinProducto} renglón(es) sin producto` : 'Todos los renglones tienen producto')}</div></div>
    <div class="tabla-caja"><table class="tabla factura"><thead><tr><th>En la factura</th><th>Producto</th><th class="num">Unidades de venta</th><th class="num">Entran</th><th class="num">Costo c/u</th><th class="num">Precio de venta</th></tr></thead>
      <tbody>${f.items.map((it, i) => {
        const l = c.lineas[i], p = l.producto_id && c.prods.get(+l.producto_id), k = calcular(it, l);
        const subio = p && k.costo > +p.costo + 0.5;
        return `<tr class="${l.producto_id || l.nuevo ? '' : 'sin-producto'}"><td><div class="muted chico mono"><span class="nro">${i + 1}</span> ${esc(it.codigo || '')}${it.codigo_barras && it.codigo_barras !== it.codigo ? ` · EAN ${esc(it.codigo_barras)}` : ''}</div><b>${esc(it.descripcion)}</b>
            <div class="muted chico">${cant(it.cantidad)} ${unidadTxt(it)} · ${plata(it.importe)}${+it.bonificacion ? ` · bonif. ${cant(it.bonificacion)}%` : ''}
              ${lineaCierra(it) ? '' : ' <span class="etiqueta alerta">no cierra</span>'}</div></td>
          <td>${l.nuevo ? `<div class="muted chico">Producto nuevo · <button class="link" data-no-nuevo="${i}">elegir otro</button></div>
              <input class="input" data-nn="${i}" value="${esc(l.nuevo.nombre)}">
              <div class="fila"><select class="input crece" data-nc="${i}"><option value="">Sin categoría</option>${c.cats.map(x => `<option value="${x.id}" ${String(x.id) === String(l.nuevo.categoria_id) ? 'selected' : ''}>${esc(x.nombre)}</option>`).join('')}</select>
                <label class="check"><input type="checkbox" data-np="${i}" ${l.nuevo.por_peso ? 'checked' : ''}> por kg</label></div>`
            : p ? `<b>${esc(p.nombre)}</b>${l.recordado ? ' <span class="etiqueta info" title="Se reconoció de la factura anterior">recordado</span>' : ''}
              <div class="muted chico">stock ${cant(p.stock)} · costo ${plata(p.costo)} · <button class="link" data-cambiar="${i}">cambiar</button></div>`
            : `<select class="input" data-elegir="${i}"><option value="">¿Qué producto es?</option>
                ${l.sugerencias.map(s => `<option value="${s.id}">${esc(s.nombre)}</option>`).join('')}
                <option value="buscar">Buscar otro producto…</option><option value="nuevo">＋ Es un producto nuevo</option></select>`}</td>
          <td class="num">${it.unidad === 'kg' ? '<span class="muted chico">por kg</span>'
            : `<input class="input cant" data-u="${i}" value="${esc(l.unidades)}" inputmode="decimal"><div class="muted chico">por ${it.unidad === 'bulto' ? 'bulto' : 'unidad'} facturada</div>`}</td>
          <td class="num">${cant(k.ingresan)}</td>
          <td class="num">${plata(k.costo)}${p && Math.abs(k.costo - p.costo) > 0.5 ? `<div class="muted chico">antes ${plata(p.costo)}</div>` : ''}
            <div><select class="input chico-sel" data-iva="${i}" title="Alícuota de IVA de este renglón">${ALICUOTAS.map(a => `<option value="${a}" ${a === alicuotaDe(it, l) ? 'selected' : ''}>IVA ${String(a).replace('.', ',')}%</option>`).join('')}</select></div></td>
          <td class="num"><input class="input corto" data-pr="${i}" value="${esc(l.precio ?? (l.nuevo ? k.propuesto : ''))}" inputmode="decimal" placeholder="${p ? (p.margen != null ? 'auto' : 'sin cambio') : ''}">
            ${p && p.margen != null ? `<div class="muted chico">margen ${String(+p.margen).replace('.', ',')}% auto: queda en <b>${plata(redondear(k.costo * (1 + p.margen / 100), carga.prep.redondeo))}</b></div>`
            : p ? `<div class="muted chico">hoy ${plata(p.precio)}${(subio || k.sugerido) && l.precio == null ? ` · <button class="link" data-usar="${i}">usar ${plata(k.propuesto)}</button>` : ''}</div>`
              : k.sugerido ? '<div class="muted chico">sugerido por el proveedor</div>' : ''}</td></tr>`;
      }).join('')}</tbody></table></div>
    <div class="recuadro-blanco form ancho"><div class="fila">
      <label class="check" title="En las facturas A los precios vienen sin IVA. Para un monotributista el IVA es costo; un responsable inscripto lo descuenta"><input type="checkbox" id="f-iva" ${c.sumarIva ? 'checked' : ''}> Sumar el IVA al costo</label>
      ${+f.percepciones ? `<label class="check" title="Para un monotributista las percepciones son costo; un responsable inscripto las descuenta"><input type="checkbox" id="f-perc" ${c.sumarPerc ? 'checked' : ''}> Sumar las percepciones al costo (${plata(f.percepciones)})</label>` : ''}
      <label class="check"><input type="checkbox" id="f-caja" ${c.pagar_caja ? 'checked' : ''} ${c.turno ? '' : 'disabled'}> Se pagó con la caja${c.turno ? '' : ' (la caja está cerrada)'}
        <span class="muted chico">(si no, queda en la cuenta del proveedor)</span></label>
      <select class="input" id="f-forma" ${c.pagar_caja ? '' : 'hidden'}>${c.formas.map(x => `<option ${x === c.forma ? 'selected' : ''}>${esc(x)}</option>`).join('')}</select></div>
      <div class="fila entre"><span class="total-etq">Total de la factura</span><span class="total chico-total">${plata(f.total ?? neto)}</span></div>
      <div class="fila fin"><button class="btn primario grande" id="f-guardar">Guardar compra</button></div></div>`;

  const repintar = () => pintar(vista, ctx, alSalir);
  $('#f-prov').onchange = e => correr(async () => { await iniciar(f, e.target.value === 'nuevo' ? null : +e.target.value); if (e.target.value === 'nuevo') carga.proveedor_id = 'nuevo'; repintar(); });
  if ($('#f-cuit')) $('#f-cuit').onchange = e => { c.cuit = e.target.value.trim(); repintar(); };
  $('#f-comp').oninput = e => { c.comprobante = e.target.value; };
  $('#f-fecha').onchange = e => { c.fecha_factura = e.target.value; repintar(); };
  $('#f-vence').onchange = e => { c.vencimiento = e.target.value; };
  $('#f-iva').onchange = e => { c.sumarIva = e.target.checked; recordar('iva', c.sumarIva); repintar(); };
  if ($('#f-perc')) $('#f-perc').onchange = e => { c.sumarPerc = e.target.checked; recordar('perc', c.sumarPerc); repintar(); };
  $$('[data-iva]', box).forEach(s => s.onchange = () => { c.lineas[+s.dataset.iva].alicuota = +s.value; repintar(); });
  $('#f-caja').onchange = e => { c.pagar_caja = e.target.checked; $('#f-forma').hidden = !c.pagar_caja; };
  $('#f-forma').onchange = e => { c.forma = e.target.value; };
  $$('[data-elegir]', box).forEach(s => s.onchange = () => {
    const i = +s.dataset.elegir, l = c.lineas[i];
    if (s.value === 'nuevo') { l.nuevo = { nombre: nombreLindo(f.items[i].descripcion), categoria_id: '', por_peso: f.items[i].unidad === 'kg' }; l.producto_id = ''; return repintar(); }
    if (s.value === 'buscar') { s.value = ''; return elegirProducto(f.items[i].descripcion, p => { l.producto_id = String(p.id); l.recordado = false; repintar(); }); }
    l.producto_id = s.value; l.recordado = false; repintar();
  });
  $$('[data-cambiar]', box).forEach(b => b.onclick = () => { const l = c.lineas[+b.dataset.cambiar]; l.producto_id = ''; l.recordado = false; l.precio = null; repintar(); });
  $$('[data-no-nuevo]', box).forEach(b => b.onclick = () => { c.lineas[+b.dataset.noNuevo].nuevo = null; repintar(); });
  $$('[data-nn]', box).forEach(inp => inp.onchange = () => { c.lineas[+inp.dataset.nn].nuevo.nombre = inp.value.trim(); });
  $$('[data-nc]', box).forEach(s => s.onchange = () => { c.lineas[+s.dataset.nc].nuevo.categoria_id = s.value; });
  $$('[data-np]', box).forEach(x => x.onchange = () => { c.lineas[+x.dataset.np].nuevo.por_peso = x.checked; });
  $$('[data-u]', box).forEach(inp => { inp.onfocus = () => inp.select(); inp.onchange = () => { c.lineas[+inp.dataset.u].unidades = inp.value.trim(); repintar(); }; });
  $$('[data-pr]', box).forEach(inp => { inp.onfocus = () => inp.select(); inp.onchange = () => { c.lineas[+inp.dataset.pr].precio = inp.value.trim(); }; });
  $$('[data-usar]', box).forEach(b => b.onclick = () => { const i = +b.dataset.usar; c.lineas[i].precio = String(calcular(f.items[i], c.lineas[i]).propuesto); repintar(); });
  $('#f-guardar').onclick = () => guardar(ctx, alSalir);

  // Buscador de productos en una ventana, para el renglón que no se reconoció
  function elegirProducto(descripcion, alElegir) {
    const m = modal('¿Qué producto es?', `<p class="muted">En la factura: <b>${esc(descripcion)}</b></p>
      <div class="buscador"><input class="input" id="bp" placeholder="Buscá por nombre o código…" autocomplete="off" autofocus><div class="resultados" id="bp-res"></div></div>
      <div class="fila fin"><button class="btn" data-cerrar>Cancelar</button></div>`);
    const inp = $('#bp', m.el);
    const norm = s => String(s || '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '');
    let lista = [];
    const pintarRes = () => {
      const w = norm(inp.value).split(/\s+/).filter(Boolean);
      lista = w.length ? c.productos.filter(p => w.every(x => norm(p.nombre + ' ' + (p.codigo || '')).includes(x))).slice(0, 12) : [];
      $('#bp-res', m.el).innerHTML = lista.map((p, k) => `<button class="resultado" data-k="${k}"><span>${esc(p.nombre)}</span><span class="muted">costo ${plata(p.costo)}</span><b>${plata(p.precio)}</b></button>`).join('')
        || (w.length ? '<p class="muted sin">No hay productos con ese nombre.</p>' : '');
      $$('[data-k]', m.el).forEach(b => b.onclick = () => { m.cerrar(); alElegir(lista[+b.dataset.k]); });
    };
    inp.oninput = pintarRes;
    inp.onkeydown = e => { if (e.key === 'Enter' && lista[0]) { e.preventDefault(); m.cerrar(); alElegir(lista[0]); } };
  }
}

function guardar(ctx, alSalir) {
  correr(async () => {
    const c = carga, f = c.f;
    const faltan = c.lineas.map((l, i) => !l.producto_id && !l.nuevo ? i + 1 : null).filter(Boolean);
    if (faltan.length) return aviso(`Falta elegir qué producto es en ${faltan.length === 1 ? 'el renglón' : 'los renglones'} ${faltan.join(', ')}`);
    if (c.lineas.some(l => l.nuevo && !l.nuevo.nombre)) return aviso('Falta el nombre de un producto nuevo');
    if (c.lineas.some((l, i) => f.items[i].unidad !== 'kg' && !(numero(l.unidades) > 0))) return aviso('Revisá las unidades de venta: tienen que ser mayores a 0');
    if (c.proveedor_id === 'nuevo' && !cuitOk(c.cuit)) return aviso('El CUIT del proveedor no es válido: corregilo (o dejalo vacío) antes de guardar');
    const lineas = f.items.map((it, i) => {
      const l = c.lineas[i], k = calcular(it, l);
      const precio = l.precio != null && l.precio !== '' ? numero(l.precio) : (l.nuevo ? k.propuesto : '');
      if (precio !== '' && !(precio > 0)) throw new Error(`Revisá el precio de venta del renglón ${i + 1}`);
      return {
        producto_id: l.producto_id ? +l.producto_id : null,
        nuevo: l.nuevo ? { nombre: l.nuevo.nombre, categoria_id: l.nuevo.categoria_id ? +l.nuevo.categoria_id : null, por_peso: l.nuevo.por_peso, precio } : null,
        codigo: it.codigo || '', codigo_barras: it.codigo_barras || null, descripcion: it.descripcion,
        unidades: it.unidad === 'kg' ? 1 : numero(l.unidades), cantidad: k.ingresan, costo: k.costo, precio_nuevo: precio,
      };
    });
    const nuevos = lineas.filter(l => l.nuevo).length;
    if (!await confirmar('Guardar compra', `Se suman al stock ${lineas.length} producto${lineas.length === 1 ? '' : 's'}${nuevos ? `, ${nuevos} nuevo${nuevos === 1 ? '' : 's'}` : ''}, y se recuerda cómo viene cada uno de este proveedor para la próxima factura.`, 'Guardar')) return;
    const r = await llamar('registrar_compra_factura', { p: {
      proveedor_id: c.proveedor_id !== 'nuevo' ? +c.proveedor_id : null,
      proveedor_nuevo: c.proveedor_id === 'nuevo' ? { nombre: f.proveedor?.nombre || 'Proveedor sin nombre', cuit: c.cuit } : null,
      comprobante: c.comprobante, total: f.total ?? null, pagar_caja: c.pagar_caja, forma: c.forma, lineas,
      fecha_factura: c.fecha_factura, vencimiento: c.vencimiento || vencePropuesto(),
      notas: `Cargada desde la factura del ${f.fecha ? dia(f.fecha) : '—'} · neto ${plata(f.subtotal)} + IVA ${plata(f.iva)} + percepciones ${plata(f.percepciones)}${+f.impuestos_internos ? ' + impuestos internos ' + plata(f.impuestos_internos) : ''}${c.sumarIva ? ' · costos con IVA' : ' · costos sin IVA'}${+f.percepciones ? (c.sumarPerc ? ' y con percepciones' : ' y sin percepciones') : ''}`,
    } });
    carga = null;
    aviso(`Compra guardada${r.creados ? ` · ${r.creados} producto${r.creados === 1 ? '' : 's'} nuevo${r.creados === 1 ? '' : 's'}` : ''}`, 'ok');
    await cat.actualizar();
    alSalir();
    avisarListas(r.productos || []).catch(() => {});
  });
}
