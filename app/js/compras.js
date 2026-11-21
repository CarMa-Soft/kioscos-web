// Compras (solo dueño): lista, detalle con anular, y cargar una compra a mano (con escáner o búsqueda).
// Los costos se piden a la base cada vez (catalogo() con costos, solo para el dueño) y no se guardan en el navegador.
import { llamar } from './base.js';
import * as cat from './catalogo.js';
import { $, $$, esc, plata, cant, fecha, dia, hoyDia, sumarDias, numero, aviso, correr, modal, confirmar, cargaSinGuardar } from './ui.js';
import { botonCamara, campoEscaner, seguirLector } from './escaner.js';
import { avisarListas } from './entregas.js';
import { productoNoEncontrado } from './alta-producto.js';
import { formProveedor, vencimientosModal } from './proveedores.js';
import { pantallaFactura, hayCargaFactura } from './facturas.js';

const r2 = n => Math.round((+n || 0) * 100) / 100;
// Si el IVA y las percepciones van al costo (lo mismo que en Cargar desde factura, y recordado en la misma PC):
// para un monotributista son costo; un responsable inscripto los descuenta.
const preferencia = clave => { try { return localStorage.getItem('kioscos.factura.' + clave) !== 'no'; } catch { return true; } };
const recordar = (clave, si) => { try { localStorage.setItem('kioscos.factura.' + clave, si ? 'si' : 'no'); } catch { /* sin almacenamiento */ } };
const ALICUOTAS = [0, 2.5, 5, 10.5, 21, 27];
// La compra que se está cargando sobrevive a cambiar de sección
let borrador = null;
cargaSinGuardar(() => borrador?.items.length);
const vacio = () => ({ proveedor_id: '', comprobante: '', notas: '', total: '', pagar_caja: false, forma: 'Efectivo', items: [],
  sin_iva: false, percepciones: '', internos: '',
  sin_factura: false, fecha_factura: hoyDia(), vencimiento: '', vence_a_mano: false });
let soloPendientes = false, buscar = '';   // lo elegido se mantiene al ir y volver de la sección
let enFactura = false;   // cargando una compra desde la factura

// Íconos (trazos SVG, toman el color del texto). Los estilos son los de Hoy, Caja, Productos, Clientes y Proveedores (clases c-).
const svg = d => `<svg viewBox="0 0 24 24" aria-hidden="true">${d}</svg>`;
const ICO = {
  carrito: svg('<path d="M4 4h2l2.2 10.2a1.5 1.5 0 0 0 1.5 1.2h7.6a1.5 1.5 0 0 0 1.5-1.1L20.5 8H6.8"/><circle cx="10" cy="19.5" r="1.3"/><circle cx="17" cy="19.5" r="1.3"/>'),
  factura: svg('<path d="M6 3h9l3 3v15H6z"/><path d="M15 3v3h3M9 11h6M9 15h4"/>'),
  calendario: svg('<rect x="3.5" y="5" width="17" height="15" rx="2"/><path d="M3.5 10h17M8 3v4M16 3v4"/>'),
  lupa: svg('<circle cx="11" cy="11" r="6.5"/><path d="m20 20-4.2-4.2"/>'),
};
const sinAcentos = s => String(s ?? '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '');

export async function pantallaCompras(vista, ctx) {
  if (enFactura) return pantallaFactura(vista, ctx, () => { enFactura = false; ctx.recargar(); });
  // las compras (las últimas 300 y todas las de factura pendiente) y lo que vence en los próximos 7 días (si falla, esa tarjeta no aparece)
  const [todas, venc] = await Promise.all([llamar('compras'), llamar('vencimientos', { p_hasta: sumarDias(hoyDia(), 7) }).catch(() => null)]);
  const pendientes = todas.filter(c => c.factura_pendiente && !c.anulada);
  // compras de este mes: por la fecha de la factura (o cuándo se registró), sin las anuladas y descontando lo devuelto
  const mes = hoyDia().slice(0, 7), diaDe = c => c.fecha_factura || hoyDiaDe(c.fecha);
  const delMes = todas.filter(c => !c.anulada && diaDe(c).startsWith(mes));
  const totalMes = delMes.reduce((s, c) => s + +c.total - +c.devuelto, 0);
  const aPagar = venc ? venc.proveedores.reduce((s, x) => s + +x.total, 0) : 0;
  const vencido = venc ? venc.proveedores.reduce((s, x) => s + x.deudas.filter(d => d.vencimiento < venc.hoy).reduce((a, d) => a + +d.pendiente, 0), 0) : 0;
  vista.innerHTML = `<div class="cabecera"><h2>Compras</h2><div class="acciones"><a class="btn" href="#/proveedores">Proveedores</a>
      <button class="btn" id="factura-ia">📄 ${hayCargaFactura() ? 'Seguir con la factura' : 'Cargar desde factura'}</button>
      <button class="btn primario" id="nueva">${borrador ? `Seguir cargando la compra (${borrador.items.length})` : '＋ Cargar compra'}</button></div></div>
    <div class="c-tarjetas de-a-tres">
      <div class="c-tarjeta verde"><span class="c-ico">${ICO.carrito}</span><div><div class="etq">Compras de este mes</div><div class="valor">${plata(totalMes)}</div>
        <div class="c-sub">${delMes.length} compra${delMes.length === 1 ? '' : 's'}</div></div></div>
      <div class="c-tarjeta ${pendientes.length ? 'naranja' : 'gris'}"><span class="c-ico">${ICO.factura}</span><div><div class="etq">Factura pendiente</div><div class="valor">${pendientes.length}</div>
        <div class="c-sub">${pendientes.length ? `${plata(pendientes.reduce((s, c) => s + +c.total, 0))} · <button class="link" id="ver-pendientes">ver cuáles</button>` : 'todas tienen su factura'}</div></div></div>
      ${venc ? `<div class="c-tarjeta ${vencido > 0.004 ? 'rojo' : aPagar > 0.004 ? 'azul' : 'gris'}"><span class="c-ico">${ICO.calendario}</span><div>
        <div class="etq">A pagar a proveedores (7 días)</div><div class="valor">${plata(aPagar)}</div>
        <div class="c-sub">${vencido > 0.004 ? `<b class="mal">${plata(vencido)} ya vencido</b> · ` : ''}${venc.proveedores.length ? '<button class="link" id="ver-venc">ver vencimientos</button>' : 'nada que pagar esta semana'}</div></div></div>` : ''}
    </div>
    <div class="c-filtros">
      <label class="c-buscar">${ICO.lupa}<input id="buscar" placeholder="Buscar por proveedor o comprobante…" value="${esc(buscar)}" autocomplete="off"></label>
      <div class="chips" id="grupos"></div>
    </div>
    <div class="tabla-caja c-tabla"><table class="tabla" id="tabla"></table></div>`;
  const coincide = c => { const w = sinAcentos(buscar).split(/\s+/).filter(Boolean), t = sinAcentos(`${c.proveedor || ''} ${c.comprobante || ''} ${c.remito || ''}`); return w.every(x => t.includes(x)); };
  const pintar = () => {
    const lista = (soloPendientes ? pendientes : todas).filter(coincide);
    $('#grupos').innerHTML = `<button class="chip ${soloPendientes ? '' : 'elegido'}" data-f="">Todas <span class="c-cuenta">${todas.filter(coincide).length}</span></button>
      <button class="chip ${soloPendientes ? 'elegido' : ''}" data-f="p">Factura pendiente <span class="c-cuenta">${pendientes.filter(coincide).length}</span></button>`;
    $$('[data-f]').forEach(b => b.onclick = () => { soloPendientes = b.dataset.f === 'p'; pintar(); });
    $('#tabla').innerHTML = `${lista.length ? `<thead><tr><th>Fecha factura</th><th>Proveedor</th><th>Comprobante</th><th class="num">Productos</th><th class="num">Total</th><th>Pago</th></tr></thead><tbody>
      ${lista.map(c => `<tr class="clic ${c.anulada ? 'anulada' : ''}" data-id="${c.id}"><td>${c.fecha_factura ? dia(c.fecha_factura) : `${fecha(c.fecha)}<div class="muted chico">${c.factura_pendiente ? 'sin factura' : 'registrada'}</div>`}</td>
        <td>${esc(c.proveedor || '—')}</td>
        <td>${c.factura_pendiente && !c.anulada ? `<span class="etiqueta pendiente">Factura pendiente</span>${c.remito ? `<div class="muted chico">Remito ${esc(c.remito)}</div>` : ''}` : esc(c.comprobante)}</td>
        <td class="num">${c.items}</td><td class="num">${+c.devuelto && !c.anulada ? `${plata(c.total - c.devuelto)}<div class="aviso-chico"><s>${plata(c.total)}</s> · devuelto ${plata(c.devuelto)}</div>` : plata(c.total)}</td>
        <td>${c.anulada ? '<span class="etiqueta">anulada</span>' : c.pagada_caja ? `De la caja (${esc(c.forma)})` : c.proveedor ? `<span class="muted">A cuenta</span>${c.vencimiento ? `<div class="muted chico">vence ${dia(c.vencimiento)}</div>` : ''}` : '<span class="muted">Aparte</span>'}</td></tr>`).join('')}</tbody>`
      : `<tbody><tr><td class="muted vacio">${buscar.trim() ? 'Ninguna compra coincide con la búsqueda.' : soloPendientes ? 'No hay compras esperando la factura.' : 'Todavía no hay compras cargadas.'}</td></tr></tbody>`}`;
    $$('tr[data-id]').forEach(tr => tr.onclick = () => verCompra(+tr.dataset.id, ctx));
  };
  $('#buscar').oninput = e => { buscar = e.target.value; pintar(); };
  $('#nueva').onclick = () => { borrador ??= vacio(); correr(() => nuevaCompra(vista, ctx)); };
  $('#factura-ia').onclick = () => { enFactura = true; ctx.recargar(); };
  if ($('#ver-pendientes')) $('#ver-pendientes').onclick = () => { soloPendientes = true; buscar = ''; $('#buscar').value = ''; pintar(); };
  if ($('#ver-venc')) $('#ver-venc').onclick = () => vencimientosModal(() => ctx.ir('#/proveedores'));   // "Pagar" lleva a Proveedores
  pintar();
}
// Día local (AAAA-MM-DD) de una fecha con hora
const hoyDiaDe = iso => { const d = new Date(iso); return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`; };

// Detalle de una compra. Lo usan Compras y la ficha del proveedor (que pasa un ctx cuyo recargar vuelve a armar la ficha).
export function verCompra(id, ctx) {
  correr(async () => {
    const c = await llamar('compra', { p_id: id });
    const pendiente = c.factura_pendiente && !c.anulada;
    const m = modal(`Compra${c.proveedor ? ' a ' + c.proveedor : ''}`, `<dl class="kv">
        ${c.fecha_factura ? `<dt>Fecha de la factura</dt><dd>${dia(c.fecha_factura)}</dd>` : ''}
        ${c.vencimiento && !c.pagada_caja ? `<dt>Vence</dt><dd>${dia(c.vencimiento)}${pendiente ? ' <span class="muted chico">(estimado con el plazo)</span>' : ''}</dd>` : ''}
        <dt>Registrada</dt><dd>${fecha(c.fecha)} · ${esc(c.usuario)}</dd>
        ${pendiente ? '<dt>Factura</dt><dd><span class="etiqueta pendiente">Factura pendiente</span></dd>' : ''}
        ${c.comprobante ? `<dt>Comprobante</dt><dd>${esc(c.comprobante)}</dd>` : ''}${c.remito ? `<dt>Remito</dt><dd>${esc(c.remito)}</dd>` : ''}
        ${c.factura_fecha ? `<dt>Factura cargada</dt><dd>${fecha(c.factura_fecha)} · ${esc(c.factura_por)}</dd>` : ''}
        ${c.anulada ? `<dt>Anulada</dt><dd class="mal">${fecha(c.anulada_fecha)} · ${esc(c.anulada_por)}</dd>` : ''}</dl>
      <div class="tabla-caja"><table class="tabla"><thead><tr><th>Producto</th><th class="num">Cant.</th><th class="num">Costo</th><th class="num">Precio nuevo</th><th class="num">Importe</th></tr></thead><tbody>
        ${c.items.map(i => `<tr><td>${esc(i.nombre)}</td><td class="num">${cant(i.cantidad)}${+i.devuelto ? `<div class="aviso-chico">devuelto ${cant(i.devuelto)}</div>` : ''}</td>
          <td class="num">${plata(i.costo)}${+i.costo_anterior !== +i.costo ? `<div class="muted chico">antes ${plata(i.costo_anterior)}</div>` : ''}</td>
          <td class="num">${i.precio_nuevo != null ? `${plata(i.precio_nuevo)}<div class="muted chico">antes ${plata(i.precio_anterior)}</div>` : '—'}</td>
          <td class="num">${plata(i.cantidad * i.costo)}</td></tr>`).join('')}</tbody>
        <tfoot><tr><th colspan="4">Total</th><th class="num">${plata(c.total)}</th></tr>
          ${+c.devuelto ? `<tr><td colspan="4" class="aviso-chico">Devuelto al proveedor</td><td class="num aviso-chico">−${plata(c.devuelto)}</td></tr>` : ''}</tfoot></table></div>
      <p>${c.pagada_caja ? `Pagada con la caja (${esc(c.forma)})` : c.proveedor ? 'A cuenta del proveedor' : 'Pagada aparte'}</p>
      ${c.notas ? `<p class="muted">${esc(c.notas)}</p>` : ''}
      ${c.devoluciones.length ? `<h3>Devoluciones al proveedor</h3><table class="tabla"><tbody>${c.devoluciones.map(d => `<tr><td><b>${esc(d.etiqueta)}</b> · ${fecha(d.fecha)} · ${esc(d.usuario)}
          <div class="muted chico">${d.items.map(x => `${cant(x.cantidad)} ${esc(x.nombre)}`).join(', ')}${d.motivo ? ' · ' + esc(d.motivo) : ''}</div></td>
        <td>${d.forma === 'Cuenta' ? 'a su cuenta' : d.forma === 'Sin reintegro' ? 'sin reintegro' : 'devolvió ' + esc(d.forma)}</td><td class="num">${plata(d.total)}</td></tr>`).join('')}</tbody></table>` : ''}
      <div class="fila fin">${c.anulada ? '' : '<button class="btn peligro izq" id="anular">Anular compra</button>'}
        ${!c.anulada && c.items.some(i => +i.cantidad - +i.devuelto > 0.0005) ? '<button class="btn" id="devolver">Devolver al proveedor</button>' : ''}
        ${pendiente ? '<button class="btn primario" id="factura">Agregar factura</button>' : ''}<button class="btn ${pendiente ? '' : 'primario'}" data-cerrar>Cerrar</button></div>`, { ancho: true });
    if ($('#factura', m.el)) $('#factura', m.el).onclick = () => { m.cerrar(); agregarFactura(c, ctx); };
    if ($('#devolver', m.el)) $('#devolver', m.el).onclick = () => { m.cerrar(); devolverAlProveedor(c, ctx); };
    if ($('#anular', m.el)) $('#anular', m.el).onclick = async () => {
      if (!await confirmar('Anular compra', `${+c.devuelto ? 'Ya tuvo devoluciones: se anula solo lo que quedó. ' : ''}Sale del stock lo que entró${c.pagada_caja ? ' y vuelve a la caja del turno abierto lo que se pagó con ella' : ''}${c.proveedor && !c.pagada_caja ? ' y se saca de la cuenta del proveedor' : ''}. Los costos y precios de los productos no cambian.`, 'Anular')) return;
      correr(async () => { await llamar('anular_compra', { p_id: c.id }); m.cerrar(); aviso('Compra anulada', 'ok'); await cat.actualizar(); ctx.recargar(); });
    };
  });
}

// Devolver al proveedor parte o toda la compra. Sale el stock; la plata va a su cuenta, entra a la caja si la devolvió,
// o sin reintegro (solo sin proveedor). El importe es costo × cantidad, y se puede cambiar.
function devolverAlProveedor(c, ctx) {
  correr(async () => {
    const caja = await llamar('estado_caja');
    const filas = c.items.map(i => ({ i, queda: Math.round((+i.cantidad - +i.devuelto) * 1000) / 1000, cantidad: '' })).filter(f => f.queda > 0.0005);
    const formas = c.proveedor ? [['Cuenta', `A la cuenta de ${c.proveedor} (baja lo que le debés)`], ...caja.formas_pago.map(f => [f, `Devolvió la plata · ${f} (entra a la caja)`])]
      : [...caja.formas_pago.map(f => [f, `Devolvió la plata · ${f} (entra a la caja)`]), ['Sin reintegro', 'Sin reintegro']];
    const m = modal(`Devolver al proveedor · compra${c.proveedor ? ' a ' + c.proveedor : ''}`, `<form class="form ancho" id="f-dp">
      <p class="muted">Elegí qué devolvés y cuántos. Sale del stock.</p>
      <div class="tabla-caja"><table class="tabla" id="dp-tabla"></table></div>
      <div class="fila"><label class="crece">Qué pasa con la plata<select class="input" name="forma">${formas.map(([v, t]) => `<option value="${esc(v)}">${esc(t)}</option>`).join('')}</select></label>
        <label class="crece">Importe <span class="muted">(vacío = costo × cantidad)</span><input class="input" name="total" inputmode="decimal"></label></div>
      <label>Motivo<input class="input" name="motivo" maxlength="200" placeholder="ej: vencido, roto, mal enviado"></label>
      ${caja.turno ? '' : '<p class="muted chico">La caja está cerrada: si el proveedor devolvió la plata, primero abrí el turno.</p>'}
      <div class="fila entre"><span>Importe de la devolución</span><span class="total chico-total" id="dp-total">${plata(0)}</span></div>
      <div class="fila fin"><button type="button" class="btn" data-cerrar>Cancelar</button><button class="btn primario">Devolver</button></div></form>`, { ancho: true });
    const suma = () => filas.reduce((s, f) => s + Math.round(+f.i.costo * (numero(f.cantidad) || 0) * 100) / 100, 0);
    const totales = () => { const t = numero($('[name=total]', m.el).value); $('#dp-total', m.el).textContent = plata(t >= 0 ? t : suma()); };
    const pintar = () => {
      $('#dp-tabla', m.el).innerHTML = `<thead><tr><th>Producto</th><th class="num">Puede devolver</th><th class="num">Costo</th><th class="num">Devuelve</th></tr></thead><tbody>
        ${filas.map((f, k) => `<tr><td>${esc(f.i.nombre)}</td><td class="num">${cant(f.queda)} <button type="button" class="link" data-todo="${k}">Todo</button></td><td class="num">${plata(f.i.costo)}</td>
          <td class="num"><input class="input cant" data-cant="${k}" value="${esc(f.cantidad)}" inputmode="decimal" placeholder="0"></td></tr>`).join('')}</tbody>`;
      $$('[data-cant]', m.el).forEach(inp => inp.oninput = () => { filas[+inp.dataset.cant].cantidad = inp.value; totales(); });
      $$('[data-todo]', m.el).forEach(b => b.onclick = () => { filas[+b.dataset.todo].cantidad = String(filas[+b.dataset.todo].queda); pintar(); });
      totales();
    };
    $('[name=total]', m.el).oninput = totales;
    pintar();
    $('#f-dp', m.el).onsubmit = e => {
      e.preventDefault();
      const f = new FormData(e.target);
      const items = filas.filter(x => numero(x.cantidad) > 0).map(x => ({ id: x.i.id, cantidad: numero(x.cantidad) }));
      if (!items.length) return aviso('Elegí qué productos devolvés');
      if (filas.some(x => numero(x.cantidad) > x.queda + 0.0005)) return aviso('Hay más cantidad de la que se puede devolver');
      correr(async () => {
        const r = await llamar('devolver_compra', { p: { compra_id: c.id, items, forma: f.get('forma'), motivo: f.get('motivo'),
          total: f.get('total') === '' ? null : numero(f.get('total')) } });
        m.cerrar();
        aviso(`${r.devolucion.etiqueta}: ${plata(r.devolucion.total)}${r.devolucion.stock_negativo.length ? ` · ojo: quedó stock negativo en ${r.devolucion.stock_negativo.join(', ')}` : ''}`,
          r.devolucion.stock_negativo.length ? 'info' : 'ok');
        await cat.actualizar(); ctx.recargar();
      });
    };
  });
}

// La factura de una compra que llegó sin ella: número, fechas, costos y precios. El stock no cambia.
function agregarFactura(c, ctx) {
  correr(async () => {
    const provs = c.proveedor_id ? await llamar('proveedores') : [];
    const plazo = provs.find(p => p.id === c.proveedor_id)?.plazo || 0;
    const m = modal(`Agregar factura · compra a ${c.proveedor || 'sin proveedor'}`, `<form class="form ancho" id="f-fac">
      <p class="muted">La mercadería ya sumó al stock cuando se cargó la compra: acá va el número de la factura y, si vino con otros precios, los costos. <b>El stock no cambia.</b></p>
      <div class="fila"><label class="crece">Número de factura<input class="input" name="comprobante" required autofocus placeholder="ej: A 0003-00012345"></label>
        <label class="crece">Fecha de la factura<input class="input" type="date" name="fecha_factura" value="${hoyDia()}"></label>
        <label class="crece">Vence<input class="input" type="date" name="vencimiento" value="${sumarDias(hoyDia(), plazo)}"></label></div>
      <div class="tabla-caja"><table class="tabla"><thead><tr><th>Producto</th><th class="num">Cant.</th><th class="num">Costo del remito</th><th class="num">Costo de la factura</th><th class="num">Precio nuevo</th></tr></thead><tbody>
        ${c.items.map((i, k) => `<tr><td>${esc(i.nombre)}</td><td class="num">${cant(i.cantidad)}</td><td class="num">${plata(i.costo)}</td>
          <td class="num"><input class="input corto" data-costo="${k}" value="${i.costo}" inputmode="decimal"></td>
          <td class="num"><input class="input corto" data-precio="${k}" inputmode="decimal" placeholder="no cambia"></td></tr>`).join('')}</tbody></table></div>
      <label>Total de la factura <span class="muted">(vacío = la suma)</span><input class="input" name="total" inputmode="decimal"></label>
      <div class="fila fin"><button type="button" class="btn" data-cerrar>Cancelar</button><button class="btn primario">Guardar factura</button></div></form>`, { ancho: true });
    let venceAMano = false;
    $('[name=vencimiento]', m.el).onchange = () => { venceAMano = true; };
    $('[name=fecha_factura]', m.el).onchange = e => { if (!venceAMano && e.target.value) $('[name=vencimiento]', m.el).value = sumarDias(e.target.value, plazo); };
    $('#f-fac', m.el).onsubmit = e => {
      e.preventDefault();
      const f = new FormData(e.target);
      const items = c.items.map((i, k) => ({ id: i.id, costo: numero($(`[data-costo="${k}"]`, m.el).value), precio_nuevo: numero($(`[data-precio="${k}"]`, m.el).value) > 0 ? numero($(`[data-precio="${k}"]`, m.el).value) : null }));
      if (items.some(i => !(i.costo >= 0))) return aviso('Revisá los costos');
      correr(async () => {
        const r = await llamar('cargar_factura_compra', { p: { id: c.id, comprobante: f.get('comprobante'), fecha_factura: f.get('fecha_factura'), vencimiento: f.get('vencimiento'),
          total: f.get('total') === '' ? null : numero(f.get('total')), items } });
        m.cerrar();
        aviso(Math.abs(+r.diferencia) > 0.004 ? `Factura cargada. El total cambió en ${plata(r.diferencia)}${c.pagada_caja ? ': la caja no se toca sola, registralo en Caja si corresponde' : c.proveedor ? ' y quedó en la cuenta del proveedor' : ''}` : 'Factura cargada', 'ok');
        await cat.actualizar(); ctx.recargar();
      });
    };
  });
}

async function nuevaCompra(vista, ctx) {
  const d = borrador;
  const [cata, provs, caja] = await Promise.all([llamar('catalogo'), llamar('proveedores'), llamar('estado_caja')]);
  const prods = new Map(cata.productos.map(p => [p.id, p]));
  const porCodigo = cat.mapaPorCodigo(cata.productos);
  vista.innerHTML = `<div class="cabecera"><h2>Cargar compra</h2><div class="acciones"><button class="btn" id="descartar">Descartar</button><button class="btn" id="volver">Volver</button></div></div>
    <div class="recuadro-blanco form ancho">
      <div class="fila"><label class="crece">Proveedor<span class="fila"><select class="input crece" id="prov"><option value="">Sin proveedor</option>
          ${provs.map(p => `<option value="${p.id}" ${String(p.id) === String(d.proveedor_id) ? 'selected' : ''}>${esc(p.nombre)}</option>`).join('')}</select>
          <button type="button" class="btn" id="nuevo-prov" title="Nuevo proveedor">＋</button></span></label>
        <label class="crece"><span id="comp-l">${d.sin_factura ? 'Remito <span class="muted">(si vino)</span>' : 'Factura / remito'}</span><input class="input" id="comp" value="${esc(d.comprobante)}" placeholder="ej: A 0003-00012345"></label>
        <label class="crece" id="ff-l" ${d.sin_factura ? 'hidden' : ''}>Fecha de la factura<input class="input" type="date" id="ff" value="${esc(d.fecha_factura || '')}"></label>
        <label class="crece">Vence <span class="muted" id="vence-txt"></span><input class="input" type="date" id="vence" value="${esc(d.vencimiento || '')}"></label></div>
      <div class="fila"><label class="check"><input type="checkbox" id="sin-factura" ${d.sin_factura ? 'checked' : ''}> <b>Llegó sin factura</b>
          <span class="muted">(el stock se suma ahora y la compra queda como "Factura pendiente")</span></label>
        <label class="crece">Notas<input class="input" id="notas" value="${esc(d.notas)}"></label></div>
    </div>
    <div class="buscador escanear">${campoEscaner('Escaneá o escribí el producto que entra')}
      <div id="resultados" class="resultados flotan" hidden></div></div>
    <div class="tabla-caja"><table class="tabla" id="lineas"></table></div>
    <div class="recuadro-blanco form ancho" id="impuestos">
      <h3>Impuestos</h3>
      <div class="fila">
        <label class="crece">Los costos que cargás<select class="input" id="modo-iva">
          <option value="con" ${d.sin_iva ? '' : 'selected'}>Ya incluyen el IVA (costo final)</option>
          <option value="sin" ${d.sin_iva ? 'selected' : ''}>Son sin IVA (como en la factura A): se suma el IVA de cada producto</option></select></label>
        <label class="crece">Percepciones $ <span class="muted">(IVA, IIBB…)</span><input class="input" id="perc" inputmode="decimal" value="${esc(d.percepciones)}" placeholder="0"></label>
        <label class="crece">Impuestos internos $<input class="input" id="internos" inputmode="decimal" value="${esc(d.internos)}" placeholder="0"></label></div>
      <div class="fila">
        <label class="check" id="sumar-iva-l"><input type="checkbox" id="sumar-iva"> Sumar el IVA al costo</label>
        <label class="check" id="sumar-perc-l"><input type="checkbox" id="sumar-perc"> Sumar las percepciones al costo</label></div>
      <p class="muted chico">Para un monotributista el IVA y las percepciones son costo; un responsable inscripto los descuenta y no van al costo.
        Las percepciones y los impuestos internos se reparten entre los productos según el importe de cada uno; los internos siempre van al costo.</p></div>
    <div class="recuadro-blanco form ancho">
      <div class="fila"><label class="crece">Total de la factura <span class="muted">(vacío = la suma)</span><input class="input" id="total" inputmode="decimal" value="${esc(d.total)}"></label>
        <label class="check"><input type="checkbox" id="caja" ${d.pagar_caja ? 'checked' : ''} ${caja.turno ? '' : 'disabled'}> Pagar con la caja${caja.turno ? '' : ' (la caja está cerrada)'}</label>
        <select class="input crece" id="forma" ${d.pagar_caja ? '' : 'hidden'}>${caja.formas_pago.map(f => `<option ${f === d.forma ? 'selected' : ''}>${esc(f)}</option>`).join('')}</select></div>
      <p class="muted chico" id="nota-pago"></p>
      <div class="fila entre"><span class="total-etq">Total</span><span class="total chico-total" id="tot"></span></div>
      <div class="fila fin"><button class="btn primario grande" id="guardar">Guardar compra</button></div>
    </div>`;
  const escaner = $('#escaner'), res = $('#resultados');
  seguirLector(escaner);
  botonCamara(escaner, { envolver: false, describir: c => porCodigo.get(c.toLowerCase())?.nombre });   // 📷 en el celular: cada código leído se agrega como con el lector
  let sugeridos = [], marcado = 0;
  const buscar = t => { const w = t.toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').split(/\s+/).filter(Boolean);
    return cata.productos.filter(p => { const s = (p.nombre + ' ' + cat.codigosDe(p).join(' ')).toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, ''); return w.every(x => s.includes(x)); }).slice(0, 12); };
  const agregar = p => {
    escaner.value = ''; res.hidden = true;
    const ya = d.items.find(i => i.producto_id === p.id);
    if (ya) ya.cantidad = String(numero(ya.cantidad) + 1); else d.items.push({ producto_id: p.id, cantidad: '1', costo: String(p.costo ?? ''), precio_nuevo: '' });
    pintar(); escaner.focus();
  };
  escaner.oninput = () => {
    const t = escaner.value.trim();
    if (t.length < 2 || /^\d{6,}$/.test(t)) { res.hidden = true; return; }
    sugeridos = buscar(t); marcado = 0; pintarSug();
  };
  const pintarSug = () => {
    res.hidden = false;
    res.innerHTML = sugeridos.map((p, k) => `<button class="resultado ${k === marcado ? 'marcado' : ''}" data-k="${k}" tabindex="-1"><span>${esc(p.nombre)}</span><span class="muted">costo ${plata(p.costo)}</span><b>${plata(p.precio)}</b></button>`).join('')
      || '<p class="muted sin">No hay productos con ese nombre: apretá Enter para crearlo.</p>';
    $$('[data-k]', res).forEach(b => b.onmousedown = e => { e.preventDefault(); agregar(sugeridos[+b.dataset.k]); });
  };
  escaner.onkeydown = e => {
    if (['ArrowDown', 'ArrowUp'].includes(e.key) && !res.hidden && sugeridos.length) { e.preventDefault(); marcado = (marcado + (e.key === 'ArrowDown' ? 1 : -1) + sugeridos.length) % sugeridos.length; return pintarSug(); }
    if (e.key !== 'Enter') return;
    e.preventDefault();
    const t = escaner.value.trim();
    const p = porCodigo.get(t.toLowerCase()) || (!res.hidden && sugeridos[marcado]);
    if (p) agregar(p);
    else if (t) productoNoEncontrado(t, { productos: cata.productos, categorias: cata.categorias, alElegir: incorporar, config: ctx.config });   // crearlo o agregarle el código a uno
  };
  escaner.onblur = () => setTimeout(() => { res.hidden = true; }, 150);
  // Un producto recién creado (o al que se le agregó un código): entra a la lista de esta pantalla y se suma
  function incorporar(p) {
    const k = cata.productos.findIndex(x => x.id === p.id);
    if (k >= 0) cata.productos[k] = { ...cata.productos[k], ...p }; else cata.productos.push(p);
    const q = k >= 0 ? cata.productos[k] : p;
    prods.set(q.id, q);
    for (const c of cat.codigosDe(q)) porCodigo.set(c.toLowerCase(), q);
    agregar(q);
  }

  // Impuestos: el costo final de cada unidad = costo cargado × (1 + IVA si se suma + parte de percepciones + parte de internos)
  let sumarIva = preferencia('iva'), sumarPerc = preferencia('perc');
  const neto = i => r2(numero(i.cantidad) * (numero(i.costo) || 0));
  const netoTotal = () => d.items.reduce((s, i) => s + neto(i), 0);
  const ivaDe = i => i.iva != null ? +i.iva : 21;
  const costoFinal = i => {
    const nt = netoTotal(), perc = numero(d.percepciones) || 0, internos = numero(d.internos) || 0;
    return r2((numero(i.costo) || 0) * (1 + (d.sin_iva && sumarIva ? ivaDe(i) / 100 : 0)
      + (nt > 0 && sumarPerc ? perc / nt : 0) + (nt > 0 ? internos / nt : 0)));
  };
  // la suma de la factura: neto + IVA (si los costos son sin IVA) + percepciones + internos
  const suma = () => r2(netoTotal() + (d.sin_iva ? d.items.reduce((s, i) => s + neto(i) * ivaDe(i) / 100, 0) : 0)
    + (numero(d.percepciones) || 0) + (numero(d.internos) || 0));
  function pintar() {
    $('#lineas').innerHTML = d.items.length ? `<thead><tr><th>Producto</th><th class="num">Cantidad</th><th class="num">Costo unitario</th><th class="num">Precio de venta nuevo</th><th class="num">Importe</th><th></th></tr></thead><tbody>
      ${d.items.map((i, k) => { const p = prods.get(i.producto_id) || {}; const base = numero(i.costo), costo = costoFinal(i), pn = numero(i.precio_nuevo);
        // con margen automático y sin precio escrito, el precio sigue al costo: se muestra en cuánto queda
        const auto = p.margen != null && !(pn > 0) && costo > 0, red = +(ctx.config.redondeo ?? 10);
        const precioAuto = auto ? (x => red > 0 ? Math.ceil(r2(x) / red) * red : r2(x))(costo * (1 + p.margen / 100)) : null;
        const precio = pn > 0 ? pn : auto ? precioAuto : +p.precio;
        const margen = costo > 0 && precio > 0 ? Math.round((precio / costo - 1) * 100) : null;
        return `<tr><td>${esc(p.nombre || '?')}<div class="muted chico">stock ${cant(p.stock)} · costo actual ${plata(p.costo)} · precio ${plata(p.precio)}</div></td>
        <td class="num"><input class="input cant" data-c="cantidad" data-k="${k}" value="${esc(i.cantidad)}" inputmode="decimal"></td>
        <td class="num"><input class="input corto" data-c="costo" data-k="${k}" value="${esc(i.costo)}" inputmode="decimal">
          ${d.sin_iva ? `<div><select class="input chico-sel" data-iva="${k}" title="Alícuota de IVA de este producto">${ALICUOTAS.map(a => `<option value="${a}" ${a === ivaDe(i) ? 'selected' : ''}>IVA ${String(a).replace('.', ',')}%</option>`).join('')}</select></div>` : ''}
          ${base > 0 && Math.abs(costo - base) > 0.004 ? `<div class="muted chico">final <b>${plata(costo)}</b> c/u</div>` : ''}</td>
        <td class="num"><input class="input corto" data-c="precio_nuevo" data-k="${k}" value="${esc(i.precio_nuevo)}" inputmode="decimal" placeholder="${auto ? 'auto' : 'no cambia'}" title="${auto ? 'Con margen automático el precio se calcula solo; escribí uno solo si querés otro' : 'Vacío: el precio no cambia'}">
          ${auto ? `<div class="muted chico">margen ${String(+p.margen).replace('.', ',')}% auto: queda en <b>${plata(precioAuto)}</b></div>`
            : margen != null ? `<div class="muted chico ${margen < 0 ? 'mal' : ''}">margen ${margen}%</div>` : ''}</td>
        <td class="num">${plata(neto(i))}</td><td><button class="link" data-quitar="${k}">✕</button></td></tr>`; }).reverse().join('')}</tbody>`   // el último cargado, arriba (d.items queda en el orden de carga)
      : '<tbody><tr><td class="muted vacio">Escaneá o buscá los productos que entran.</td></tr></tbody>';
    $$('[data-c]').forEach(inp => inp.onchange = () => { d.items[+inp.dataset.k][inp.dataset.c] = inp.value; pintar(); });
    $$('[data-quitar]').forEach(b => b.onclick = () => { d.items.splice(+b.dataset.quitar, 1); pintar(); });
    $$('[data-iva]').forEach(sel => sel.onchange = () => { d.items[+sel.dataset.iva].iva = +sel.value; pintar(); });
    $('#sumar-iva-l').hidden = !d.sin_iva; $('#sumar-iva').checked = sumarIva;
    $('#sumar-perc-l').hidden = !(numero(d.percepciones) > 0); $('#sumar-perc').checked = sumarPerc;
    const t = numero(d.total) >= 0 ? numero(d.total) : suma();
    $('#tot').textContent = plata(t);
    const prov = provs.find(p => String(p.id) === String(d.proveedor_id));
    $('#nota-pago').textContent = d.pagar_caja ? 'Sale de la caja del turno.' : prov ? `Queda a cuenta de ${prov.nombre}.` : 'Sin proveedor y sin caja: se registra como pagada aparte.';
  }
  // El vencimiento se completa solo (fecha de la factura + plazo del proveedor) hasta que se lo cambia a mano
  const pintarVence = () => {
    const plazo = provs.find(p => String(p.id) === String(d.proveedor_id))?.plazo;
    if (!d.vence_a_mano) { d.vencimiento = sumarDias(d.sin_factura ? hoyDia() : (d.fecha_factura || hoyDia()), plazo || 0); $('#vence').value = d.vencimiento; }
    $('#vence-txt').textContent = d.vence_a_mano ? '' : plazo ? `(${plazo} días de plazo)` : '';
  };
  $('#ff').onchange = e => { d.fecha_factura = e.target.value; pintarVence(); };
  $('#vence').onchange = e => { d.vencimiento = e.target.value; d.vence_a_mano = !!e.target.value; pintarVence(); };
  $('#sin-factura').onchange = e => {
    d.sin_factura = e.target.checked;
    $('#comp-l').innerHTML = d.sin_factura ? 'Remito <span class="muted">(si vino)</span>' : 'Factura / remito';
    $('#ff-l').hidden = d.sin_factura; pintarVence();
  };
  $('#prov').onchange = e => { d.proveedor_id = e.target.value; pintarVence(); pintar(); };
  pintarVence();
  $('#nuevo-prov').onclick = () => formProveedor(null, p => { d.proveedor_id = String(p.id); nuevaCompra(vista, ctx); });
  $('#comp').oninput = e => { d.comprobante = e.target.value; };
  $('#notas').oninput = e => { d.notas = e.target.value; };
  $('#total').oninput = e => { d.total = e.target.value; pintar(); };
  $('#modo-iva').onchange = e => { d.sin_iva = e.target.value === 'sin'; pintar(); };
  $('#perc').onchange = e => { d.percepciones = e.target.value; pintar(); };
  $('#internos').onchange = e => { d.internos = e.target.value; pintar(); };
  $('#sumar-iva').onchange = e => { sumarIva = e.target.checked; recordar('iva', sumarIva); pintar(); };
  $('#sumar-perc').onchange = e => { sumarPerc = e.target.checked; recordar('perc', sumarPerc); pintar(); };
  $('#caja').onchange = e => { d.pagar_caja = e.target.checked; $('#forma').hidden = !d.pagar_caja; pintar(); };
  $('#forma').onchange = e => { d.forma = e.target.value; };
  // Volver a la lista sin perder lo cargado (el botón ofrece seguir); si no tenía nada, se descarta
  $('#volver').onclick = () => { if (!d.items.length) borrador = null; ctx.recargar(); };
  $('#descartar').onclick = async () => { if (!d.items.length || await confirmar('Descartar', '¿Descartar la compra sin guardarla?', 'Descartar')) { borrador = null; ctx.recargar(); } };
  $('#guardar').onclick = () => {
    if (!d.items.length) return aviso('La compra no tiene productos');
    const items = d.items.map(i => ({ producto_id: i.producto_id, cantidad: numero(i.cantidad), costo: costoFinal(i), precio_nuevo: numero(i.precio_nuevo) > 0 ? numero(i.precio_nuevo) : null }));
    const perc = numero(d.percepciones) || 0, internos = numero(d.internos) || 0;
    if (perc < 0 || internos < 0) return aviso('Revisá las percepciones y los impuestos internos');
    const detalle = [d.sin_iva ? (sumarIva ? 'costos sin IVA + IVA de cada producto' : 'costos sin IVA (el IVA no va al costo)') : '',
      perc ? `percepciones ${plata(perc)}${sumarPerc ? ' en el costo' : ' fuera del costo'}` : '', internos ? `impuestos internos ${plata(internos)} en el costo` : ''].filter(Boolean).join(' · ');
    if (items.some(i => !(i.cantidad > 0))) return aviso('Revisá las cantidades');
    if (d.total !== '' && !(numero(d.total) >= 0)) return aviso('Revisá el total');
    correr(async () => {
      await llamar('registrar_compra', { p: { proveedor_id: d.proveedor_id || null, comprobante: d.comprobante, notas: [d.notas, detalle].filter(Boolean).join(' · '), total: d.total === '' ? suma() : numero(d.total),
        pagar_caja: d.pagar_caja, forma: d.forma, items,
        factura_pendiente: d.sin_factura, fecha_factura: d.sin_factura ? null : d.fecha_factura || null, vencimiento: d.vencimiento || null } });
      borrador = null; aviso(d.sin_factura ? 'Compra guardada con factura pendiente: stock actualizado' : 'Compra guardada: stock y costos actualizados', 'ok');
      await cat.actualizar(); ctx.recargar();
      avisarListas(items.map(i => i.producto_id)).catch(() => {});
    });
  };
  pintar();
}
