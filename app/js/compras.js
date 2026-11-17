// Compras (solo dueño): lista, detalle con anular, y cargar una compra a mano (con escáner o búsqueda).
// Los costos se piden a la base cada vez (catalogo() con costos, solo para el dueño) y no se guardan en el navegador.
import { llamar } from './base.js';
import * as cat from './catalogo.js';
import { $, $$, esc, plata, cant, fecha, numero, aviso, correr, modal, confirmar } from './ui.js';
import { formProveedor } from './proveedores.js';

const r2 = n => Math.round((+n || 0) * 100) / 100;
// La compra que se está cargando sobrevive a cambiar de sección
let borrador = null;
const vacio = () => ({ proveedor_id: '', comprobante: '', notas: '', total: '', pagar_caja: false, forma: 'Efectivo', items: [] });

export async function pantallaCompras(vista, ctx) {
  const lista = await llamar('compras');
  vista.innerHTML = `<div class="cabecera"><h2>Compras</h2><div class="acciones"><a class="btn" href="#/proveedores">Proveedores</a>
      <button class="btn primario" id="nueva">${borrador ? `Seguir cargando la compra (${borrador.items.length})` : '＋ Cargar compra'}</button></div></div>
    <div class="tabla-caja"><table class="tabla">${lista.length ? `<thead><tr><th>Fecha</th><th>Proveedor</th><th>Comprobante</th><th class="num">Productos</th><th class="num">Total</th><th>Pago</th></tr></thead><tbody>
      ${lista.map(c => `<tr class="clic ${c.anulada ? 'anulada' : ''}" data-id="${c.id}"><td>${fecha(c.fecha)}</td><td>${esc(c.proveedor || '—')}</td><td>${esc(c.comprobante)}</td>
        <td class="num">${c.items}</td><td class="num">${plata(c.total)}</td>
        <td>${c.anulada ? '<span class="etiqueta">anulada</span>' : c.pagada_caja ? `De la caja (${esc(c.forma)})` : c.proveedor ? '<span class="muted">A cuenta</span>' : '<span class="muted">Aparte</span>'}</td></tr>`).join('')}</tbody>`
      : '<tbody><tr><td class="muted vacio">Todavía no hay compras cargadas.</td></tr></tbody>'}</table></div>`;
  $('#nueva').onclick = () => { borrador ??= vacio(); correr(() => nuevaCompra(vista, ctx)); };
  $$('tr[data-id]').forEach(tr => tr.onclick = () => verCompra(+tr.dataset.id, ctx));
}

function verCompra(id, ctx) {
  correr(async () => {
    const c = await llamar('compra', { p_id: id });
    const m = modal(`Compra${c.proveedor ? ' a ' + c.proveedor : ''}`, `<p class="muted">${fecha(c.fecha)} · ${esc(c.usuario)}${c.comprobante ? ' · ' + esc(c.comprobante) : ''}
        ${c.anulada ? ` · <b class="mal">Anulada</b> por ${esc(c.anulada_por)}` : ''}</p>
      <div class="tabla-caja"><table class="tabla"><thead><tr><th>Producto</th><th class="num">Cant.</th><th class="num">Costo</th><th class="num">Precio nuevo</th><th class="num">Importe</th></tr></thead><tbody>
        ${c.items.map(i => `<tr><td>${esc(i.nombre)}</td><td class="num">${cant(i.cantidad)}</td>
          <td class="num">${plata(i.costo)}${+i.costo_anterior !== +i.costo ? `<div class="muted chico">antes ${plata(i.costo_anterior)}</div>` : ''}</td>
          <td class="num">${i.precio_nuevo != null ? `${plata(i.precio_nuevo)}<div class="muted chico">antes ${plata(i.precio_anterior)}</div>` : '—'}</td>
          <td class="num">${plata(i.cantidad * i.costo)}</td></tr>`).join('')}</tbody>
        <tfoot><tr><th colspan="4">Total</th><th class="num">${plata(c.total)}</th></tr></tfoot></table></div>
      <p>${c.pagada_caja ? `Pagada con la caja (${esc(c.forma)})` : c.proveedor ? 'A cuenta del proveedor' : 'Pagada aparte'}</p>
      ${c.notas ? `<p class="muted">${esc(c.notas)}</p>` : ''}
      <div class="fila fin">${c.anulada ? '' : '<button class="btn peligro izq" id="anular">Anular compra</button>'}<button class="btn primario" data-cerrar>Cerrar</button></div>`, { ancho: true });
    if ($('#anular', m.el)) $('#anular', m.el).onclick = async () => {
      if (!await confirmar('Anular compra', `Sale del stock lo que entró${c.pagada_caja ? `, vuelven ${plata(c.total)} a la caja del turno abierto` : ''}${c.proveedor && !c.pagada_caja ? ' y se saca de la cuenta del proveedor' : ''}. Los costos y precios de los productos no cambian.`, 'Anular')) return;
      correr(async () => { await llamar('anular_compra', { p_id: c.id }); m.cerrar(); aviso('Compra anulada', 'ok'); await cat.actualizar(); ctx.recargar(); });
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
        <label class="crece">Factura / remito<input class="input" id="comp" value="${esc(d.comprobante)}" placeholder="ej: A 0003-00012345"></label>
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
  $('#prov').onchange = e => { d.proveedor_id = e.target.value; pintar(); };
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
        pagar_caja: d.pagar_caja, forma: d.forma, items } });
      borrador = null; aviso('Compra guardada: stock y costos actualizados', 'ok');
      await cat.actualizar(); ctx.recargar();
    });
  };
  pintar();
}
