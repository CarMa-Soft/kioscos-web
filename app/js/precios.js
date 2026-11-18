// Precios y márgenes (Productos, solo dueño), como en GScom. Dos solapas:
// - Actualizar precios: subir o bajar el precio de venta de los de precio fijo (los de margen siguen al costo), o el costo
//   (los de margen recalculan su precio; los fijos lo mantienen). Con el redondeo que se elija.
// - Asignar margen: calcular el precio con un margen, que queda automático (sigue al costo), o quitarlo (precio fijo).
// A qué productos: los que coinciden con una búsqueda, los que se ven en la lista, todos, una categoría o un proveedor.
// La lista de cómo queda cada uno se ve antes de aplicar (y se pueden destildar). Lo aplica ajustar_precios() en la base,
// que hace la misma cuenta; los cambios anteriores se pueden deshacer.
import { llamar } from './base.js';
import * as cat from './catalogo.js';
import { $, $$, esc, plata, fecha, numero, aviso, correr, modal, confirmar } from './ui.js';

const REDONDEOS = [[1, 'a $1 (sin centavos)'], [10, 'a $10'], [50, 'a $50'], [100, 'a $100'], [500, 'a $500'], [0, 'Sin redondeo']];
const r2 = n => Math.round(n * 100) / 100;
const redondear = (x, m) => +m > 0 ? Math.ceil(r2(x) / m) * m : r2(x);
const norm = s => String(s ?? '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '');
const margenDe = p => +p.costo > 0 ? (p.precio - p.costo) / p.costo * 100 : null;

export async function preciosModal({ productos, categorias, visibles, ctx, alTerminar }) {
  const [provs, previos] = await Promise.all([llamar('proveedores'), llamar('aumentos')]);
  const redAjustes = +(ctx.config.redondeo ?? 10);
  const catNombre = id => categorias.find(c => c.id === id)?.nombre || '';
  let tab = 'precios';
  const excluidos = new Set();
  const m = modal('Precios y márgenes', `<div class="form ancho">
    <div class="chips" id="pm-tabs"><button type="button" class="chip elegido" data-tab="precios">Actualizar precios</button><button type="button" class="chip" data-tab="margen">Asignar margen</button></div>
    <div class="fila">
      <label class="crece">¿A qué productos?<select class="input" id="pm-ambito">
        <option value="buscar">Los que coinciden con una búsqueda (ej: yerba)</option>
        ${visibles ? `<option value="vista">Los que estás viendo en la lista (${visibles.length})</option>` : ''}
        <option value="todos">Todos los productos (${productos.length})</option>
        <optgroup label="Una categoría">${categorias.map(c => `<option value="cat:${c.id}">${esc(c.nombre)} (${productos.filter(p => p.categoria_id === c.id).length})</option>`).join('')}</optgroup>
        <optgroup label="Un proveedor">${provs.map(p => `<option value="prov:${p.id}">${esc(p.nombre)} (${productos.filter(x => x.proveedor_id === p.id).length})</option>`).join('')}</optgroup></select></label>
      <label class="crece" id="pm-q-l">Que contengan<input class="input" id="pm-q" placeholder="ej: yerba · galletitas · coca" autocomplete="off"></label></div>
    <div id="pm-tab-precios">
      <div class="fila">
        <label class="crece">¿Qué se cambia?<select class="input" id="pm-campo"><option value="venta">Precio de venta</option><option value="costo">Costo (lista nueva del proveedor)</option></select></label>
        <label class="crece">¿Cómo?<select class="input" id="pm-modo"><option value="pct">Porcentaje (%)</option><option value="monto">Monto fijo ($)</option></select></label>
        <label class="crece"><span id="pm-val-l">Porcentaje</span><input class="input" id="pm-val" inputmode="decimal" placeholder="ej: 10 (o -5 para bajar)"></label></div>
      <div class="fila" id="pm-red-f"><label class="crece">Redondear el precio nuevo<select class="input" id="pm-red">
          ${REDONDEOS.map(([v, l]) => `<option value="${v}" ${v === redAjustes ? 'selected' : ''}>${v ? 'Hacia arriba ' + l : l}</option>`).join('')}</select></label>
        <p class="muted chico crece" id="pm-red-ej"></p></div></div>
    <div id="pm-tab-margen" hidden>
      <div class="fila">
        <label class="crece">¿Qué hacer?<select class="input" id="pm-accion"><option value="poner">Calcular el precio con un margen</option><option value="quitar">Quitar el margen automático (precio fijo)</option></select></label>
        <label class="crece" id="pm-mg-l">Margen %<input class="input" id="pm-mg" inputmode="decimal" placeholder="ej: 35"></label></div>
      <p class="muted chico" id="pm-mg-ayuda"></p></div>
    <div id="pm-prev"></div>
    <div class="fila fin"><button type="button" class="btn" data-cerrar>Cancelar</button><button type="button" class="btn primario" id="pm-ok" disabled>Aplicar</button></div>
    <details class="pm-hist"><summary>Cambios anteriores (para deshacer)</summary><div id="pm-hist"></div></details></div>`, { ancho: true });
  const v = id => $(id, m.el).value;
  if (visibles) $('#pm-ambito', m.el).value = 'vista';

  const ambito = () => {
    const a = v('#pm-ambito'), t = norm(v('#pm-q')).split(/\s+/).filter(Boolean);
    if (a === 'buscar') return t.length ? productos.filter(p => { const s = norm(p.nombre + ' ' + cat.codigosDe(p).join(' ') + ' ' + catNombre(p.categoria_id)); return t.every(w => s.includes(w)); }) : [];
    if (a === 'vista') return visibles;
    if (a.startsWith('cat:')) return productos.filter(p => p.categoria_id === +a.slice(4));
    if (a.startsWith('prov:')) return productos.filter(p => p.proveedor_id === +a.slice(5));
    return productos;
  };
  // Lo que se hace en la solapa activa: a quiénes afecta y cómo queda cada uno (la misma cuenta que hace la base)
  const plan = () => {
    const l = ambito();
    if (tab === 'margen') {
      const quitar = v('#pm-accion') === 'quitar', crudo = v('#pm-mg').trim(), val = numero(crudo);
      const afectados = l.filter(p => quitar ? p.margen != null : +p.costo > 0);
      const nuevo = p => quitar ? { costo: +p.costo, precio: +p.precio, margen: null } : { costo: +p.costo, precio: redondear(+p.costo * (1 + val / 100), redAjustes), margen: val };
      const valido = quitar || (crudo !== '' && val >= 0 && val <= 1000);
      return { l, afectados, nuevo, valido, quitar, val, texto: quitar ? 'Quitar el margen automático' : `Margen ${String(val).replace('.', ',')}%`, falta: !quitar && crudo === '' ? 'el margen' : '' };
    }
    const campo = v('#pm-campo'), modo = v('#pm-modo'), val = numero(v('#pm-val')), red = +v('#pm-red');
    const cambio = x => modo === 'monto' ? x + val : x * (1 + val / 100);
    const afectados = l.filter(p => campo === 'venta' ? p.margen == null && +p.precio > 0 && cambio(+p.precio) > 0 : +p.costo > 0 && cambio(+p.costo) > 0);
    const nuevo = p => campo === 'venta' ? { costo: +p.costo, precio: redondear(cambio(+p.precio), red), margen: p.margen }
      : { costo: r2(cambio(+p.costo)), precio: p.margen != null ? redondear(r2(cambio(+p.costo)) * (1 + p.margen / 100), redAjustes) : +p.precio, margen: p.margen };
    const valido = Number.isFinite(val) && val !== 0 && (modo === 'monto' || (val >= -90 && val <= 500));
    const texto = (modo === 'monto' ? `${val > 0 ? '+' : '−'}${plata(Math.abs(val))}` : `${val > 0 ? '+' : ''}${String(val).replace('.', ',')}%`) + (campo === 'venta' ? ' al precio de venta' : ' al costo');
    return { l, afectados, nuevo, valido, campo, modo, val, red, cambio, texto, falta: Number.isFinite(val) && val !== 0 ? '' : modo === 'monto' ? 'el monto' : 'el porcentaje' };
  };
  const incluidos = p0 => p0.afectados.filter(p => !excluidos.has(p.id));
  const pintarConteo = () => {
    const p0 = plan(), inc = incluidos(p0), ok = $('#pm-ok', m.el);
    const res = $('#pm-resumen', m.el);
    if (res) res.innerHTML = `Cambian <b>${inc.length}</b> de ${p0.l.length} producto${p0.l.length === 1 ? '' : 's'}${p0.afectados.length - inc.length ? ` <span class="muted">· ${p0.afectados.length - inc.length} destildado${p0.afectados.length - inc.length === 1 ? '' : 's'}</span>` : ''}.`;
    if ($('#pm-todos', m.el)) $('#pm-todos', m.el).checked = inc.length === p0.afectados.length;
    ok.disabled = !p0.valido || !inc.length;
    ok.textContent = p0.valido && inc.length ? `${p0.texto[0].toUpperCase()}${p0.texto.slice(1)} · ${inc.length} producto${inc.length === 1 ? '' : 's'}` : 'Aplicar';
  };
  const pintar = () => {
    const p0 = plan();
    $$('#pm-tabs .chip', m.el).forEach(c => c.classList.toggle('elegido', c.dataset.tab === tab));
    $('#pm-tab-precios', m.el).hidden = tab !== 'precios'; $('#pm-tab-margen', m.el).hidden = tab !== 'margen';
    $('#pm-q-l', m.el).hidden = v('#pm-ambito') !== 'buscar';
    let nota = '';
    if (tab === 'margen') {
      $('#pm-mg-l', m.el).hidden = p0.quitar;
      $('#pm-mg-ayuda', m.el).innerHTML = p0.quitar ? 'Dejan de calcularse solos: quedan con su precio actual, como precio fijo.'
        : `El precio de venta se calcula: costo + margen, redondeado ${redAjustes ? `hacia arriba a múltiplos de ${plata(redAjustes)}` : 'sin redondeo'} (se cambia en Ajustes → Precios).
          Después <b>se actualiza solo cada vez que cambia el costo</b> (por ejemplo, al cargar una compra).`;
      const sinCosto = p0.quitar ? 0 : p0.l.length - p0.afectados.length;
      if (sinCosto) nota = `<p class="muted chico">${sinCosto} producto${sinCosto === 1 ? '' : 's'} sin costo cargado: no se les puede calcular el precio y quedan igual.</p>`;
    } else {
      $('#pm-val-l', m.el).textContent = p0.modo === 'monto' ? 'Monto ($)' : 'Porcentaje';
      $('#pm-val', m.el).placeholder = p0.modo === 'monto' ? 'ej: 500 (o -200 para bajar)' : 'ej: 10 (o -5 para bajar)';
      $('#pm-red-f', m.el).hidden = p0.campo !== 'venta';
      const ej = p0.afectados[0], crudo = ej && !p0.falta ? p0.cambio(+ej.precio) : null;
      $('#pm-red-ej', m.el).innerHTML = crudo == null ? 'Evita precios "sucios" como $13.579,50 después de un aumento.'
        : `Ej.: ${esc(ej.nombre)} quedaría en ${plata(crudo)}${redondear(crudo, p0.red) !== r2(crudo) ? ` → <b>${plata(redondear(crudo, p0.red))}</b>` : ''}`;
      const conMargen = p0.l.filter(p => p.margen != null).length, fijos = p0.afectados.filter(p => p.margen == null).length;
      nota = p0.campo === 'venta'
        ? (conMargen ? `<p class="muted chico">${conMargen} producto${conMargen === 1 ? '' : 's'} con margen automático no cambia${conMargen === 1 ? '' : 'n'} acá: su precio sigue al costo. Si el proveedor aumentó, elegí <b>Costo</b>.</p>` : '')
        : `<p class="muted chico">Los que tienen margen automático (${p0.afectados.length - fijos}) recalculan su precio. Los de precio fijo (${fijos}) mantienen su precio: solo cambia el costo.</p>`;
    }
    const conCosto = tab === 'margen' || p0.campo === 'costo';
    const mgTxt = x => x == null ? '<span class="muted">fijo</span>' : `${Math.round(x)}%`;
    $('#pm-prev', m.el).innerHTML = v('#pm-ambito') === 'buscar' && !v('#pm-q').trim() ? '<p class="muted">Escribí qué productos buscar (por ejemplo: yerba). Vas a ver la lista antes de aplicar.</p>'
      : !p0.l.length ? '<p class="muted">No hay productos con ese criterio.</p>'
      : p0.falta ? `<p class="muted">${p0.l.length} producto${p0.l.length === 1 ? '' : 's'}. Poné ${p0.falta} para ver cómo quedan.</p>`
      : !p0.afectados.length ? `${nota}<p class="muted">Ninguno de estos productos cambia con esto.</p>`
      : `<p id="pm-resumen"></p>${nota}<p class="muted chico">Destildá los que no quieras cambiar.</p>
        <div class="tabla-caja pm-lista"><table class="tabla"><thead><tr><th><input type="checkbox" id="pm-todos" title="Todos"></th><th>Producto</th>
          ${conCosto ? '<th class="num">Costo</th>' : ''}${tab === 'margen' ? '<th class="num">Margen</th>' : ''}<th class="num">Precio de venta</th></tr></thead><tbody>
        ${p0.afectados.map(p => { const n = p0.nuevo(p), fuera = excluidos.has(p.id); return `<tr data-pm="${p.id}" class="${fuera ? 'lp-fuera' : ''}"><td><input type="checkbox" data-inc="${p.id}" ${fuera ? '' : 'checked'}></td>
          <td>${esc(p.nombre)}<div class="muted chico">${esc(catNombre(p.categoria_id))}</div></td>
          ${conCosto ? `<td class="num">${n.costo !== +p.costo ? `${plata(p.costo)} → <b>${plata(n.costo)}</b>` : plata(p.costo)}</td>` : ''}
          ${tab === 'margen' ? `<td class="num">${mgTxt(p.margen != null ? +p.margen : margenDe(p))} → <b>${n.margen == null ? 'fijo' : `${String(n.margen).replace('.', ',')}% auto`}</b></td>` : ''}
          <td class="num">${n.precio !== +p.precio ? `${plata(p.precio)} → <b>${plata(n.precio)}</b>` : `<span class="muted">${plata(p.precio)} (igual)</span>`}</td></tr>`; }).join('')}</tbody></table></div>`;
    const marcar = (id, incluir) => { if (incluir) excluidos.delete(id); else excluidos.add(id); const tr = $(`[data-pm="${id}"]`, m.el); tr.classList.toggle('lp-fuera', !incluir); $('[data-inc]', tr).checked = incluir; };
    $$('[data-inc]', m.el).forEach(c => c.onchange = () => { marcar(+c.dataset.inc, c.checked); pintarConteo(); });
    if ($('#pm-todos', m.el)) $('#pm-todos', m.el).onchange = e => { p0.afectados.forEach(p => marcar(p.id, e.target.checked)); pintarConteo(); };
    pintarConteo();
  };
  $$('#pm-tabs .chip', m.el).forEach(c => c.onclick = () => { tab = c.dataset.tab; pintar(); $(tab === 'margen' ? '#pm-mg' : '#pm-val', m.el).focus(); });
  ['#pm-ambito', '#pm-campo', '#pm-modo', '#pm-red', '#pm-accion'].forEach(s => { $(s, m.el).onchange = pintar; });
  let t; $('#pm-q', m.el).oninput = () => { clearTimeout(t); t = setTimeout(pintar, 150); };
  $('#pm-val', m.el).oninput = pintar; $('#pm-mg', m.el).oninput = pintar;

  $('#pm-ok', m.el).onclick = async () => {
    const p0 = plan(), inc = incluidos(p0);
    const a = $('#pm-ambito', m.el);
    const donde = (a.value === 'buscar' ? `"${v('#pm-q').trim()}"` : a.selectedOptions[0].textContent.replace(/\s*\(\d+\)$/, ''))
      + (inc.length < p0.afectados.length ? ` (menos ${p0.afectados.length - inc.length} destildado${p0.afectados.length - inc.length === 1 ? '' : 's'})` : '');
    const descripcion = `${p0.texto} · ${donde}`;
    if (!await confirmar('Precios y márgenes', `${descripcion}: ${inc.length} producto${inc.length === 1 ? '' : 's'}. Después lo podés deshacer.`, 'Aplicar')) return;
    correr(async () => {
      const ids = inc.map(p => p.id);
      const r = await llamar('ajustar_precios', { p: tab === 'margen' ? { que: 'margen', margen: p0.quitar ? null : p0.val, ids, descripcion }
        : { que: p0.campo, modo: p0.modo, valor: p0.val, redondeo: p0.red, ids, descripcion } });
      m.cerrar(); aviso(`Listo: ${r.cantidad} producto${r.cantidad === 1 ? '' : 's'} actualizado${r.cantidad === 1 ? '' : 's'}`, 'ok');
      await cat.actualizar(); alTerminar();
    });
  };

  // Cambios anteriores: se pueden deshacer (vuelven precio, costo y margen, salvo los que cambiaron después)
  const pintarHist = lista => {
    $('#pm-hist', m.el).innerHTML = lista.length ? `<table class="tabla"><tbody>${lista.map(a => `<tr><td>${fecha(a.fecha)}<div class="muted chico">${esc(a.usuario)}</div></td>
        <td>${esc(a.descripcion)}</td><td class="num">${a.cantidad} prod.</td>
        <td class="num">${a.deshecho ? '<span class="etiqueta">deshecho</span>' : `<button type="button" class="btn chico" data-desh="${a.id}">Deshacer</button>`}</td></tr>`).join('')}</tbody></table>`
      : '<p class="muted">Todavía no hubo cambios.</p>';
    $$('[data-desh]', m.el).forEach(b => b.onclick = async () => {
      if (!await confirmar('Deshacer', 'Los productos vuelven al precio, costo y margen que tenían antes, salvo los que se cambiaron después.', 'Deshacer')) return;
      correr(async () => {
        const r = await llamar('deshacer_aumento', { p_id: +b.dataset.desh });
        aviso(`Volvieron ${r.revertidos} producto${r.revertidos === 1 ? '' : 's'}${r.saltados ? ` · ${r.saltados} no se tocaron porque cambiaron después` : ''}`, 'ok');
        m.cerrar(); await cat.actualizar(); alTerminar();
      });
    });
  };
  pintarHist(previos);
  pintar();
  setTimeout(() => $(visibles ? '#pm-val' : '#pm-q', m.el).focus(), 40);
}
