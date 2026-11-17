// Entradas y salidas de mercadería (solo dueño): suman o restan stock sin compra ni venta (vencidos, rotos, consumo propio,
// transferencias, diferencias de inventario…). Numeradas RI-0001 (entradas) y RE-0001 (salidas); se anulan con el movimiento al revés.
// Por dentro se llaman "remitos" (tablas y funciones de la base).
import { llamar } from './base.js';
import * as cat from './catalogo.js';
import { $, $$, esc, plata, cant, fecha, numero, aviso, correr, modal, confirmar } from './ui.js';
import { imprimir, ticketRemito } from './impresion.js';

const r3 = n => Math.round((+n || 0) * 1000) / 1000;
const nombreTipo = t => t === 'ingreso' ? 'Entrada' : 'Salida';
const etiquetaTipo = r => r.anulado ? '<span class="etiqueta">anulada</span>'
  : `<span class="etiqueta ${r.tipo === 'ingreso' ? 'entra' : 'sale'}">${nombreTipo(r.tipo)}</span>`;
let filtro = '';
// Un borrador por tipo: si se sale de la pantalla, no se pierde lo cargado
const borradores = {};
let cargando = null;   // 'ingreso' | 'egreso' mientras se carga una

export async function pantallaRemitos(vista, ctx) {
  if (cargando) return nuevoRemito(vista, ctx, cargando);
  const lista = await llamar('remitos', { p_tipo: filtro || null });
  const enCurso = t => borradores[t]?.items.length ? ` (${borradores[t].items.length} en curso)` : '';
  vista.innerHTML = `<div class="cabecera"><h2>Entradas y salidas</h2><div class="acciones">
      <button class="btn" id="n-ingreso">＋ Entrada de mercadería${enCurso('ingreso')}</button>
      <button class="btn primario" id="n-egreso">− Salida de mercadería${enCurso('egreso')}</button></div></div>
    <p class="muted">Para sumar o restar mercadería sin pasar por una compra ni una venta: vencidos, rotos, consumo propio, transferencias,
      diferencias de inventario. Cada una queda numerada (RI entradas, RE salidas), con su motivo y quién la hizo.
      Las devoluciones se hacen desde la venta o la compra.</p>
    <div class="chips">${[['', 'Todas'], ['ingreso', 'Entradas'], ['egreso', 'Salidas']].map(([k, l]) => `<button class="chip ${filtro === k ? 'elegido' : ''}" data-f="${k}">${l}</button>`).join('')}</div>
    <div class="tabla-caja"><table class="tabla">${lista.length ? `<thead><tr><th>Nº</th><th>Fecha</th><th>Tipo</th><th>Motivo</th><th>Lo hizo</th><th class="num">Productos</th><th class="num">Valor al costo</th></tr></thead><tbody>
      ${lista.map(r => `<tr class="clic ${r.anulado ? 'anulada' : ''}" data-id="${r.id}"><td><b>${esc(r.etiqueta)}</b></td><td>${fecha(r.fecha)}</td><td>${etiquetaTipo(r)}</td>
        <td>${esc(r.motivo)}${r.notas ? `<div class="muted chico">${esc(r.notas)}</div>` : ''}</td><td>${esc(r.usuario)}</td>
        <td class="num">${r.items}</td><td class="num">${plata(r.valor)}</td></tr>`).join('')}</tbody>`
      : '<tbody><tr><td class="muted vacio">Todavía no hay entradas ni salidas.</td></tr></tbody>'}</table></div>`;
  $('#n-ingreso').onclick = () => { cargando = 'ingreso'; ctx.recargar(); };
  $('#n-egreso').onclick = () => { cargando = 'egreso'; ctx.recargar(); };
  $$('[data-f]').forEach(b => b.onclick = () => { filtro = b.dataset.f; ctx.recargar(); });
  $$('tr[data-id]').forEach(tr => tr.onclick = () => verRemito(+tr.dataset.id, ctx));
}

function verRemito(id, ctx) {
  correr(async () => {
    const r = await llamar('remito', { p_id: id });
    const signo = r.tipo === 'ingreso' ? '+' : '−';
    const m = modal(`${nombreTipo(r.tipo)} ${r.etiqueta}`, `<dl class="kv">
        <dt>Tipo</dt><dd>${nombreTipo(r.tipo)} de mercadería</dd>
        <dt>Fecha</dt><dd>${fecha(r.fecha)} · ${esc(r.usuario)}</dd><dt>Motivo</dt><dd>${esc(r.motivo)}</dd>
        ${r.notas ? `<dt>Notas</dt><dd>${esc(r.notas)}</dd>` : ''}
        ${r.anulado ? `<dt>Anulada</dt><dd class="mal">${fecha(r.anulado_fecha)} · ${esc(r.anulado_por)}</dd>` : ''}</dl>
      <div class="tabla-caja"><table class="tabla"><thead><tr><th>Producto</th><th class="num">Cantidad</th><th class="num">Stock antes</th><th class="num">Stock después</th><th class="num">Valor al costo</th></tr></thead><tbody>
        ${r.items.map(i => `<tr><td>${esc(i.nombre)}</td><td class="num">${signo}${cant(i.cantidad)}</td><td class="num">${cant(i.stock_antes)}</td>
          <td class="num ${+i.stock_despues < 0 ? 'mal' : ''}">${cant(i.stock_despues)}</td><td class="num">${plata(i.cantidad * i.costo)}</td></tr>`).join('')}</tbody>
        <tfoot><tr><th colspan="4">Total</th><th class="num">${plata(r.valor)}</th></tr></tfoot></table></div>
      <div class="fila fin">${r.anulado ? '' : `<button class="btn peligro izq" id="anular">Anular ${nombreTipo(r.tipo).toLowerCase()}</button>`}
        <button class="btn" id="imprimir">Imprimir</button><button class="btn primario" data-cerrar>Cerrar</button></div>`, { ancho: true });
    $('#imprimir', m.el).onclick = () => imprimir(ticketRemito(r, ctx.config));
    if ($('#anular', m.el)) $('#anular', m.el).onclick = async () => {
      if (!await confirmar(`Anular ${nombreTipo(r.tipo).toLowerCase()}`, `Se revierte el stock: ${r.tipo === 'ingreso' ? 'se descuenta lo que había entrado' : 'vuelve lo que había salido'} con la ${r.etiqueta}.`, 'Anular')) return;
      correr(async () => {
        await llamar('anular_remito', { p_id: r.id });
        m.cerrar(); aviso(`${nombreTipo(r.tipo)} ${r.etiqueta} anulada`, 'ok');
        await cat.actualizar(); ctx.recargar();
      });
    };
  });
}

async function nuevoRemito(vista, ctx, tipo) {
  const d = borradores[tipo] ??= { motivo: '', notas: '', items: [] };
  const ing = tipo === 'ingreso';
  const [cata, motivos] = await Promise.all([llamar('catalogo'), llamar('motivos_remito')]);
  const prods = new Map(cata.productos.map(p => [p.id, p]));
  const porCodigo = new Map(cata.productos.filter(p => p.codigo).map(p => [p.codigo.toLowerCase(), p]));
  d.items = d.items.filter(i => prods.has(i.producto_id));
  const lista = motivos[tipo] || [];
  vista.innerHTML = `<div class="cabecera"><h2>${nombreTipo(tipo)} de mercadería</h2><div class="acciones"><button class="btn" id="descartar">Descartar</button><button class="btn" id="volver">Volver</button></div></div>
    <p class="muted">${ing ? 'Suma' : 'Resta'} mercadería del stock. El número se asigna al guardar y queda registrado quién lo hizo.</p>
    <div class="recuadro-blanco form ancho"><div class="fila">
      <label class="crece">Motivo<select class="input" id="motivo"><option value="">Elegí el motivo…</option>
        ${lista.map(x => `<option ${x === d.motivo ? 'selected' : ''}>${esc(x)}</option>`).join('')}</select></label>
      <label class="crece">Notas <span class="muted">(opcional: detalle, quién retiró, a qué local…)</span><input class="input" id="notas" maxlength="300" value="${esc(d.notas)}"></label></div>
      <p class="muted chico">Los motivos se cambian en Ajustes.</p></div>
    <div class="buscador"><input class="input grande" id="escaner" placeholder="Escaneá o escribí el producto que ${ing ? 'entra' : 'sale'}" autocomplete="off" autofocus>
      <div id="resultados" class="resultados flotan" hidden></div></div>
    <div class="tabla-caja"><table class="tabla" id="lineas"></table></div>
    <div class="recuadro-blanco form ancho">
      <div class="fila entre"><span class="total-etq">Valor al costo</span><span class="total chico-total" id="tot"></span></div>
      <div class="fila fin"><button class="btn primario grande" id="guardar">Guardar ${nombreTipo(tipo).toLowerCase()}</button></div></div>`;
  const escaner = $('#escaner'), res = $('#resultados');
  let sugeridos = [], marcado = 0;
  const buscar = t => { const w = t.toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').split(/\s+/).filter(Boolean);
    return cata.productos.filter(p => { const s = (p.nombre + ' ' + (p.codigo || '')).toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, ''); return w.every(x => s.includes(x)); }).slice(0, 12); };
  const agregar = p => {
    escaner.value = ''; res.hidden = true;
    const ya = d.items.find(i => i.producto_id === p.id);
    if (ya) ya.cantidad = String(r3(numero(ya.cantidad) + 1)); else d.items.push({ producto_id: p.id, cantidad: '1' });
    pintar();
    setTimeout(() => $(`[data-k="${d.items.findIndex(i => i.producto_id === p.id)}"]`)?.select(), 20);
  };
  const pintarSug = () => {
    res.hidden = false;
    res.innerHTML = sugeridos.map((p, k) => `<button class="resultado ${k === marcado ? 'marcado' : ''}" data-s="${k}" tabindex="-1"><span>${esc(p.nombre)}</span><span class="muted">stock ${cant(p.stock)}</span><b>${plata(p.costo)}</b></button>`).join('')
      || '<p class="muted sin">No hay productos con ese nombre.</p>';
    $$('[data-s]', res).forEach(b => b.onmousedown = e => { e.preventDefault(); agregar(sugeridos[+b.dataset.s]); });
  };
  escaner.oninput = () => {
    const t = escaner.value.trim();
    if (t.length < 2 || /^\d{6,}$/.test(t)) { res.hidden = true; return; }
    sugeridos = buscar(t); marcado = 0; pintarSug();
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

  function pintar() {
    $('#lineas').innerHTML = d.items.length ? `<thead><tr><th>Producto</th><th class="num">Stock actual</th><th class="num">Cantidad</th><th class="num">Quedaría</th><th class="num">Valor al costo</th><th></th></tr></thead><tbody>
      ${d.items.map((i, k) => { const p = prods.get(i.producto_id), c = numero(i.cantidad) || 0, queda = r3(+p.stock + (ing ? c : -c));
        return `<tr><td>${esc(p.nombre)}${p.codigo ? `<div class="muted chico">${esc(p.codigo)}</div>` : ''}</td><td class="num">${cant(p.stock)}</td>
          <td class="num"><input class="input cant" data-k="${k}" value="${esc(i.cantidad)}" inputmode="decimal"></td>
          <td class="num ${queda < 0 ? 'mal' : ''}">${cant(queda)}</td><td class="num">${plata(c * (+p.costo || 0))}</td>
          <td><button class="link" data-quitar="${k}">✕</button></td></tr>`; }).join('')}</tbody>`
      : `<tbody><tr><td class="muted vacio">Escaneá o buscá los productos que ${ing ? 'entran' : 'salen'}.</td></tr></tbody>`;
    $$('[data-k]', $('#lineas')).forEach(inp => {
      inp.onfocus = () => inp.select();
      inp.onchange = () => { d.items[+inp.dataset.k].cantidad = inp.value.trim(); pintar(); };
      inp.onkeydown = e => { if (e.key === 'Enter') { e.preventDefault(); inp.blur(); escaner.focus(); } };
    });
    $$('[data-quitar]').forEach(b => b.onclick = () => { d.items.splice(+b.dataset.quitar, 1); pintar(); });
    $('#tot').textContent = plata(d.items.reduce((s, i) => s + (numero(i.cantidad) || 0) * (+prods.get(i.producto_id).costo || 0), 0));
  }
  pintar();

  $('#motivo').onchange = e => { d.motivo = e.target.value; };
  $('#notas').oninput = e => { d.notas = e.target.value; };
  // Volver a la lista sin perder lo cargado (el botón ofrece seguir); si no tenía nada, se descarta
  $('#volver').onclick = () => { if (!d.items.length) delete borradores[tipo]; cargando = null; ctx.recargar(); };
  $('#descartar').onclick = async () => {
    if (!d.items.length || await confirmar('Descartar', `¿Descartar la ${nombreTipo(tipo).toLowerCase()} sin guardarla?`, 'Descartar')) { delete borradores[tipo]; cargando = null; ctx.recargar(); }
  };
  $('#guardar').onclick = async () => {
    if (!d.motivo) { $('#motivo').focus(); return aviso('Elegí el motivo'); }
    if (!d.items.length) return aviso('Agregá al menos un producto');
    const items = d.items.map(i => ({ producto_id: i.producto_id, cantidad: numero(i.cantidad) }));
    if (items.some(i => !(i.cantidad > 0))) return aviso('Revisá las cantidades');
    if (!ing) {
      const negativos = items.filter(i => +prods.get(i.producto_id).stock - i.cantidad < 0).length;
      if (negativos && !await confirmar('Stock negativo', `${negativos} producto${negativos === 1 ? '' : 's'} quedaría${negativos === 1 ? '' : 'n'} con stock negativo: en el sistema hay menos de lo que sacás. ¿Registrar la salida igual?`, 'Registrar')) return;
    }
    correr(async () => {
      const r = await llamar('registrar_remito', { p: { tipo, motivo: d.motivo, notas: d.notas, items } });
      delete borradores[tipo]; cargando = null;
      aviso(`${nombreTipo(tipo)} ${r.etiqueta} guardada${r.stock_negativo.length ? ` · quedó stock negativo en ${r.stock_negativo.join(', ')}` : ''}`, r.stock_negativo.length ? 'info' : 'ok');
      await cat.actualizar(); ctx.recargar();
    });
  };
}
