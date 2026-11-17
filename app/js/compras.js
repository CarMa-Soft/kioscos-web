// Compras (solo dueño): lista, detalle con anular, y cargar una compra a mano (con escáner o búsqueda).
// Los costos se piden a la base cada vez (catalogo() con costos, solo para el dueño) y no se guardan en el navegador.
import { llamar } from './base.js';
import * as cat from './catalogo.js';
import { $, $$, esc, plata, cant, fecha, dia, hoyDia, sumarDias, numero, aviso, correr, modal, confirmar } from './ui.js';
import { formProveedor } from './proveedores.js';

const r2 = n => Math.round((+n || 0) * 100) / 100;
// La compra que se está cargando sobrevive a cambiar de sección
let borrador = null;
const vacio = () => ({ proveedor_id: '', comprobante: '', notas: '', total: '', pagar_caja: false, forma: 'Efectivo', items: [],
  sin_factura: false, fecha_factura: hoyDia(), vencimiento: '', vence_a_mano: false });
let soloPendientes = false;

export async function pantallaCompras(vista, ctx) {
  const todas = await llamar('compras');
  const pendientes = todas.filter(c => c.factura_pendiente && !c.anulada);
  const lista = soloPendientes ? pendientes : todas;
  vista.innerHTML = `<div class="cabecera"><h2>Compras</h2><div class="acciones"><a class="btn" href="#/proveedores">Proveedores</a>
      <button class="btn primario" id="nueva">${borrador ? `Seguir cargando la compra (${borrador.items.length})` : '＋ Cargar compra'}</button></div></div>
    <div class="chips"><button class="chip ${soloPendientes ? '' : 'elegido'}" data-f="">Todas</button>
      <button class="chip ${soloPendientes ? 'elegido' : ''}" data-f="p">Factura pendiente${pendientes.length ? ` (${pendientes.length})` : ''}</button></div>
    <div class="tabla-caja"><table class="tabla">${lista.length ? `<thead><tr><th>Fecha factura</th><th>Proveedor</th><th>Comprobante</th><th class="num">Productos</th><th class="num">Total</th><th>Pago</th></tr></thead><tbody>
      ${lista.map(c => `<tr class="clic ${c.anulada ? 'anulada' : ''}" data-id="${c.id}"><td>${c.fecha_factura ? dia(c.fecha_factura) : `${fecha(c.fecha)}<div class="muted chico">${c.factura_pendiente ? 'sin factura' : 'registrada'}</div>`}</td>
        <td>${esc(c.proveedor || '—')}</td>
        <td>${c.factura_pendiente && !c.anulada ? `<span class="etiqueta pendiente">Factura pendiente</span>${c.remito ? `<div class="muted chico">Remito ${esc(c.remito)}</div>` : ''}` : esc(c.comprobante)}</td>
        <td class="num">${c.items}</td><td class="num">${plata(c.total)}</td>
        <td>${c.anulada ? '<span class="etiqueta">anulada</span>' : c.pagada_caja ? `De la caja (${esc(c.forma)})` : c.proveedor ? `<span class="muted">A cuenta</span>${c.vencimiento ? `<div class="muted chico">vence ${dia(c.vencimiento)}</div>` : ''}` : '<span class="muted">Aparte</span>'}</td></tr>`).join('')}</tbody>`
      : `<tbody><tr><td class="muted vacio">${soloPendientes ? 'No hay compras esperando la factura.' : 'Todavía no hay compras cargadas.'}</td></tr></tbody>`}</table></div>`;
  $$('[data-f]').forEach(b => b.onclick = () => { soloPendientes = b.dataset.f === 'p'; ctx.recargar(); });
  $('#nueva').onclick = () => { borrador ??= vacio(); correr(() => nuevaCompra(vista, ctx)); };
  $$('tr[data-id]').forEach(tr => tr.onclick = () => verCompra(+tr.dataset.id, ctx));
}

function verCompra(id, ctx) {
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
        ${c.items.map(i => `<tr><td>${esc(i.nombre)}</td><td class="num">${cant(i.cantidad)}</td>
          <td class="num">${plata(i.costo)}${+i.costo_anterior !== +i.costo ? `<div class="muted chico">antes ${plata(i.costo_anterior)}</div>` : ''}</td>
          <td class="num">${i.precio_nuevo != null ? `${plata(i.precio_nuevo)}<div class="muted chico">antes ${plata(i.precio_anterior)}</div>` : '—'}</td>
          <td class="num">${plata(i.cantidad * i.costo)}</td></tr>`).join('')}</tbody>
        <tfoot><tr><th colspan="4">Total</th><th class="num">${plata(c.total)}</th></tr></tfoot></table></div>
      <p>${c.pagada_caja ? `Pagada con la caja (${esc(c.forma)})` : c.proveedor ? 'A cuenta del proveedor' : 'Pagada aparte'}</p>
      ${c.notas ? `<p class="muted">${esc(c.notas)}</p>` : ''}
      <div class="fila fin">${c.anulada ? '' : '<button class="btn peligro izq" id="anular">Anular compra</button>'}
        ${pendiente ? '<button class="btn primario" id="factura">Agregar factura</button>' : ''}<button class="btn ${pendiente ? '' : 'primario'}" data-cerrar>Cerrar</button></div>`, { ancho: true });
    if ($('#factura', m.el)) $('#factura', m.el).onclick = () => { m.cerrar(); agregarFactura(c, ctx); };
    if ($('#anular', m.el)) $('#anular', m.el).onclick = async () => {
      if (!await confirmar('Anular compra', `Sale del stock lo que entró${c.pagada_caja ? `, vuelven ${plata(c.total)} a la caja del turno abierto` : ''}${c.proveedor && !c.pagada_caja ? ' y se saca de la cuenta del proveedor' : ''}. Los costos y precios de los productos no cambian.`, 'Anular')) return;
      correr(async () => { await llamar('anular_compra', { p_id: c.id }); m.cerrar(); aviso('Compra anulada', 'ok'); await cat.actualizar(); ctx.recargar(); });
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
  const porCodigo = new Map(cata.productos.filter(p => p.codigo).map(p => [p.codigo.toLowerCase(), p]));
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
    <div class="buscador"><input class="input grande" id="escaner" placeholder="Escaneá o escribí el producto que entra" autocomplete="off" autofocus>
      <div id="resultados" class="resultados flotan" hidden></div></div>
    <div class="tabla-caja"><table class="tabla" id="lineas"></table></div>
    <div class="recuadro-blanco form ancho">
      <div class="fila"><label class="crece">Total de la factura <span class="muted">(vacío = la suma)</span><input class="input" id="total" inputmode="decimal" value="${esc(d.total)}"></label>
        <label class="check"><input type="checkbox" id="caja" ${d.pagar_caja ? 'checked' : ''} ${caja.turno ? '' : 'disabled'}> Pagar con la caja${caja.turno ? '' : ' (la caja está cerrada)'}</label>
        <select class="input crece" id="forma" ${d.pagar_caja ? '' : 'hidden'}>${caja.formas_pago.map(f => `<option ${f === d.forma ? 'selected' : ''}>${esc(f)}</option>`).join('')}</select></div>
      <p class="muted chico" id="nota-pago"></p>
      <div class="fila entre"><span class="total-etq">Total</span><span class="total chico-total" id="tot"></span></div>
      <div class="fila fin"><button class="btn primario grande" id="guardar">Guardar compra</button></div>
    </div>`;
  const escaner = $('#escaner'), res = $('#resultados');
  let sugeridos = [], marcado = 0;
  const buscar = t => { const w = t.toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').split(/\s+/).filter(Boolean);
    return cata.productos.filter(p => { const s = (p.nombre + ' ' + (p.codigo || '')).toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, ''); return w.every(x => s.includes(x)); }).slice(0, 12); };
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
      || '<p class="muted sin">No hay productos con ese nombre. Para uno nuevo, cargalo en Productos.</p>';
    $$('[data-k]', res).forEach(b => b.onmousedown = e => { e.preventDefault(); agregar(sugeridos[+b.dataset.k]); });
  };
  escaner.onkeydown = e => {
    if (['ArrowDown', 'ArrowUp'].includes(e.key) && !res.hidden && sugeridos.length) { e.preventDefault(); marcado = (marcado + (e.key === 'ArrowDown' ? 1 : -1) + sugeridos.length) % sugeridos.length; return pintarSug(); }
    if (e.key !== 'Enter') return;
    e.preventDefault();
    const t = escaner.value.trim();
    const p = porCodigo.get(t.toLowerCase()) || (!res.hidden && sugeridos[marcado]);
    if (p) agregar(p); else if (t) aviso(`No hay ningún producto con "${t}"`);
  };
  escaner.onblur = () => setTimeout(() => { res.hidden = true; }, 150);

  const suma = () => r2(d.items.reduce((s, i) => s + r2(numero(i.cantidad) * (numero(i.costo) || 0)), 0));
  function pintar() {
    $('#lineas').innerHTML = d.items.length ? `<thead><tr><th>Producto</th><th class="num">Cantidad</th><th class="num">Costo unitario</th><th class="num">Precio de venta nuevo</th><th class="num">Importe</th><th></th></tr></thead><tbody>
      ${d.items.map((i, k) => { const p = prods.get(i.producto_id) || {}; const costo = numero(i.costo), pn = numero(i.precio_nuevo), precio = pn > 0 ? pn : +p.precio;
        const margen = costo > 0 && precio > 0 ? Math.round((precio / costo - 1) * 100) : null;
        return `<tr><td>${esc(p.nombre || '?')}<div class="muted chico">stock ${cant(p.stock)} · costo actual ${plata(p.costo)} · precio ${plata(p.precio)}</div></td>
        <td class="num"><input class="input cant" data-c="cantidad" data-k="${k}" value="${esc(i.cantidad)}" inputmode="decimal"></td>
        <td class="num"><input class="input corto" data-c="costo" data-k="${k}" value="${esc(i.costo)}" inputmode="decimal"></td>
        <td class="num"><input class="input corto" data-c="precio_nuevo" data-k="${k}" value="${esc(i.precio_nuevo)}" inputmode="decimal" placeholder="no cambia">
          ${margen != null ? `<div class="muted chico ${margen < 0 ? 'mal' : ''}">margen ${margen}%</div>` : ''}</td>
        <td class="num">${plata(numero(i.cantidad) * (costo || 0))}</td><td><button class="link" data-quitar="${k}">✕</button></td></tr>`; }).join('')}</tbody>`
      : '<tbody><tr><td class="muted vacio">Escaneá o buscá los productos que entran.</td></tr></tbody>';
    $$('[data-c]').forEach(inp => inp.onchange = () => { d.items[+inp.dataset.k][inp.dataset.c] = inp.value; pintar(); });
    $$('[data-quitar]').forEach(b => b.onclick = () => { d.items.splice(+b.dataset.quitar, 1); pintar(); });
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
  $('#caja').onchange = e => { d.pagar_caja = e.target.checked; $('#forma').hidden = !d.pagar_caja; pintar(); };
  $('#forma').onchange = e => { d.forma = e.target.value; };
  // Volver a la lista sin perder lo cargado (el botón ofrece seguir); si no tenía nada, se descarta
  $('#volver').onclick = () => { if (!d.items.length) borrador = null; ctx.recargar(); };
  $('#descartar').onclick = async () => { if (!d.items.length || await confirmar('Descartar', '¿Descartar la compra sin guardarla?', 'Descartar')) { borrador = null; ctx.recargar(); } };
  $('#guardar').onclick = () => {
    if (!d.items.length) return aviso('La compra no tiene productos');
    const items = d.items.map(i => ({ producto_id: i.producto_id, cantidad: numero(i.cantidad), costo: numero(i.costo) || 0, precio_nuevo: numero(i.precio_nuevo) > 0 ? numero(i.precio_nuevo) : null }));
    if (items.some(i => !(i.cantidad > 0))) return aviso('Revisá las cantidades');
    if (d.total !== '' && !(numero(d.total) >= 0)) return aviso('Revisá el total');
    correr(async () => {
      await llamar('registrar_compra', { p: { proveedor_id: d.proveedor_id || null, comprobante: d.comprobante, notas: d.notas, total: d.total === '' ? null : numero(d.total),
        pagar_caja: d.pagar_caja, forma: d.forma, items,
        factura_pendiente: d.sin_factura, fecha_factura: d.sin_factura ? null : d.fecha_factura || null, vencimiento: d.vencimiento || null } });
      borrador = null; aviso(d.sin_factura ? 'Compra guardada con factura pendiente: stock actualizado' : 'Compra guardada: stock y costos actualizados', 'ok');
      await cat.actualizar(); ctx.recargar();
    });
  };
  pintar();
}
