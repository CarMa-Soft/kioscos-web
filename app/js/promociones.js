// Promociones por cantidad (Productos → Promociones, solo dueño): 3x2, "2 por $X", "la 2ª con % menos", "llevando N o más,
// % menos". Con uno o más productos (las unidades se juntan), fechas, días de la semana y formas de pago. Vender las aplica
// solas (promos.js hace la misma cuenta que la base) y sugiere las que están por completarse.
import { llamar } from './base.js';
import * as cat from './catalogo.js';
import { $, $$, esc, plata, dia, numero, aviso, correr, modal, confirmar } from './ui.js';
import { textoPromo, textoDias, DIAS_CORTOS } from './promos.js';

const TIPOS = [
  ['lleva_paga', 'Lleva N, paga M (3x2, 2x1)'],
  ['precio', 'N unidades por un precio (2 por $1.500)'],
  ['unidad_pct', 'La N-ésima con % menos (la 2ª al 50%)'],
  ['desde_pct', 'Llevando N o más, % menos en todas'],
];

// Estado de una promoción hoy: [texto, clase]
function estado(p, hoy) {
  if (!p.activa) return ['Pausada', 'gris'];
  if (p.hasta && p.hasta < hoy) return ['Vencida', 'gris'];
  if (p.desde && p.desde > hoy) return [`Desde el ${dia(p.desde)}`, 'azul'];
  const dow = new Date(hoy + 'T12:00').getDay() || 7;
  if (p.dias?.length && !p.dias.includes(dow)) return ['Hoy no', 'azul'];
  return ['Vigente', 'verde'];
}
const vigencia = p => [
  p.desde || p.hasta ? (p.desde && p.hasta ? `${dia(p.desde)} al ${dia(p.hasta)}` : p.desde ? `desde el ${dia(p.desde)}` : `hasta el ${dia(p.hasta)}`) : '',
  textoDias(p.dias) ? `los ${textoDias(p.dias)}` : '',
  p.formas?.length ? `solo ${p.formas.join(' o ')}` : '',
].filter(Boolean).join(' · ') || 'Siempre';
const num = v => Number.isFinite(v) ? v : null;
const nombresProductos = ids => {
  const ns = ids.map(id => cat.producto(id)?.nombre || '(producto borrado)');
  return ns.length > 3 ? `${ns.slice(0, 3).join(', ')} y ${ns.length - 3} más` : ns.join(', ');
};

export async function pantallaPromociones(vista, ctx, alSalir) {
  const [r, caja] = await Promise.all([llamar('promociones'), llamar('estado_caja')]);
  const formas = [...caja.formas_pago, 'Fiado'];
  const lista = r.promociones;
  vista.innerHTML = `<div class="cabecera"><h2>Promociones <span class="muted">(${lista.length})</span></h2><div class="acciones">
      <button class="btn" id="volver">Volver a Productos</button><button class="btn primario" id="nueva">＋ Nueva promoción</button></div></div>
    <p class="muted">Se aplican solas en Vender cuando la compra las cumple (el cajero puede quitarlas), y Vender sugiere las que están por completarse.
      Son para productos por unidad, a su precio de lista.</p>
    <div class="tabla-caja c-tabla"><table class="tabla">${lista.length ? `<thead><tr><th>Promoción</th><th>Productos</th><th>Cuándo</th><th>Estado</th><th></th></tr></thead><tbody>
      ${lista.map(p => { const [e, c] = estado(p, r.hoy); return `<tr class="clic ${c === 'gris' ? 'pr-apagada' : ''}" data-id="${p.id}">
        <td><b>${esc(p.nombre)}</b><div class="muted chico">${esc(textoPromo(p))}</div></td>
        <td class="corto" title="${esc(p.productos.map(id => cat.producto(id)?.nombre || '').join(', '))}">${esc(nombresProductos(p.productos))}</td>
        <td>${esc(vigencia(p))}</td><td><span class="pr-estado ${c}">${esc(e)}</span></td>
        <td class="num"><button class="btn chico peligro" data-borrar="${p.id}" title="Borrar">×</button></td></tr>`; }).join('')}</tbody>`
      : '<tbody><tr><td class="vacio muted">Todavía no hay promociones. Armá la primera con <b>＋ Nueva promoción</b>.</td></tr></tbody>'}</table></div>`;
  $('#volver').onclick = alSalir;
  $('#nueva').onclick = () => editar(null);
  $$('tr[data-id]').forEach(tr => tr.onclick = e => { if (!e.target.closest('[data-borrar]')) editar(lista.find(p => p.id === +tr.dataset.id)); });
  $$('[data-borrar]').forEach(b => b.onclick = async () => {
    const p = lista.find(x => x.id === +b.dataset.borrar);
    if (!await confirmar('Borrar promoción', `¿Borrar "${p.nombre}"? Las ventas que ya la usaron no cambian.`, 'Borrar')) return;
    correr(async () => { await llamar('borrar_promocion', { p_id: p.id }); aviso('Promoción borrada', 'ok'); ctx.recargar(); });
  });

  function editar(p) {
    const d = p ? { ...p, productos: [...p.productos] } : { nombre: '', tipo: 'lleva_paga', cantidad: 3, paga: 2, pct: '', precio: '', productos: [], desde: '', hasta: '', dias: [], formas: [], activa: true };
    const m = modal(p ? 'Editar promoción' : 'Nueva promoción', `<form class="form ancho" id="f-promo">
      <label>Nombre<input class="input" name="nombre" maxlength="60" value="${esc(d.nombre)}" placeholder="Ej: 3x2 en alfajores" autocomplete="off"></label>
      <div class="fila">
        <label class="crece">Tipo<select class="input" name="tipo">${TIPOS.map(([v, t]) => `<option value="${v}" ${d.tipo === v ? 'selected' : ''}>${t}</option>`).join('')}</select></label>
        <label class="pr-num">N (cantidad)<input class="input" name="cantidad" inputmode="numeric" value="${esc(d.cantidad ?? '')}"></label>
        <label class="pr-num" data-para="lleva_paga">M (paga)<input class="input" name="paga" inputmode="numeric" value="${esc(d.paga ?? '')}"></label>
        <label class="pr-num" data-para="precio">Precio $<input class="input" name="precio" inputmode="decimal" value="${esc(d.precio ?? '')}"></label>
        <label class="pr-num" data-para="unidad_pct desde_pct">% menos<input class="input" name="pct" inputmode="numeric" value="${esc(d.pct ?? '')}"></label>
      </div>
      <p class="pr-ejemplo" id="pr-ejemplo"></p>
      <div><b>Productos</b> <span class="muted chico">(las unidades se juntan: "3 alfajores cualquiera")</span>
        <div class="fila pr-agregar">
          <div class="buscador crece"><input class="input" id="pr-buscar" placeholder="Buscar producto por nombre o código" autocomplete="off">
            <div id="pr-res" class="resultados flotan" hidden></div></div>
          <select class="input" id="pr-cat"><option value="">Agregar una categoría…</option>${cat.categorias().map(c => `<option value="${c.id}">${esc(c.nombre)}</option>`).join('')}</select>
        </div>
        <div class="pr-elegidos" id="pr-elegidos"></div></div>
      <div class="fila">
        <label class="crece">Desde <span class="muted">(opcional)</span><input class="input" type="date" name="desde" value="${esc(d.desde || '')}"></label>
        <label class="crece">Hasta <span class="muted">(opcional)</span><input class="input" type="date" name="hasta" value="${esc(d.hasta || '')}"></label>
      </div>
      <div><b>Días</b> <span class="muted chico">(ninguno marcado = todos)</span>
        <div class="chips">${[1, 2, 3, 4, 5, 6, 7].map(n => `<button type="button" class="chip ${d.dias.includes(n) ? 'elegido' : ''}" data-dia="${n}">${DIAS_CORTOS[n]}</button>`).join('')}</div></div>
      <div><b>Formas de pago</b> <span class="muted chico">(ninguna marcada = todas)</span>
        <div class="chips">${formas.map(f => `<button type="button" class="chip ${d.formas.includes(f) ? 'elegido' : ''}" data-forma="${esc(f)}">${esc(f)}</button>`).join('')}</div></div>
      <label class="check"><input type="checkbox" name="activa" ${d.activa ? 'checked' : ''}> Activa <span class="muted chico">(destildala para pausarla sin borrarla)</span></label>
      <div class="fila fin"><button type="button" class="btn" data-cerrar>Cancelar</button><button class="btn primario">Guardar</button></div></form>`, { ancho: true });
    const f = $('#f-promo', m.el), res = $('#pr-res', m.el), buscar = $('#pr-buscar', m.el);
    let sugeridos = [];

    // los campos que pide cada tipo, y el ejemplo en palabras
    const leer = () => ({ tipo: f.elements.tipo.value, cantidad: numero(f.elements.cantidad.value), paga: numero(f.elements.paga.value),
      precio: numero(f.elements.precio.value), pct: numero(f.elements.pct.value) });
    const pintarTipo = () => {
      const x = leer();
      $$('[data-para]', m.el).forEach(l => { l.hidden = !l.dataset.para.split(' ').includes(x.tipo); });
      const ok = x.cantidad >= 1 && (x.tipo !== 'lleva_paga' || x.paga >= 1) && (x.tipo !== 'precio' || x.precio > 0) && (!x.tipo.endsWith('_pct') || x.pct > 0);
      $('#pr-ejemplo', m.el).innerHTML = ok ? `Queda: <b>${esc(textoPromo(x))}</b>${x.tipo === 'lleva_paga' && x.paga < x.cantidad ? ` — llevando ${x.cantidad} paga ${x.paga}` : ''}` : '';
    };
    f.elements.tipo.onchange = () => {
      const t = f.elements.tipo.value;   // valores de ejemplo al cambiar de tipo, si el campo está vacío
      if (t === 'lleva_paga' && !f.elements.paga.value) { f.elements.cantidad.value = 3; f.elements.paga.value = 2; }
      if (t === 'unidad_pct' && !f.elements.pct.value) { f.elements.cantidad.value = 2; f.elements.pct.value = 50; }
      if (t === 'desde_pct' && !f.elements.pct.value) f.elements.pct.value = 10;
      pintarTipo();
    };
    ['cantidad', 'paga', 'precio', 'pct'].forEach(n => { f.elements[n].oninput = pintarTipo; });
    pintarTipo();

    // productos elegidos
    const pintarElegidos = () => {
      $('#pr-elegidos', m.el).innerHTML = d.productos.length ? d.productos.map(id => { const x = cat.producto(id);
        return `<span class="pr-prod">${esc(x?.nombre || '(producto borrado)')}${x ? ` <small>${plata(x.precio)}</small>` : ''}<button type="button" data-sacar="${id}" title="Sacar">×</button></span>`; }).join('')
        : '<span class="muted chico">Todavía ninguno.</span>';
      $$('[data-sacar]', m.el).forEach(b => b.onclick = () => { d.productos = d.productos.filter(id => id !== +b.dataset.sacar); pintarElegidos(); });
    };
    const sumar = ps => {
      let peso = 0;
      ps.forEach(x => { if (x.por_peso) peso++; else if (!d.productos.includes(x.id)) d.productos.push(x.id); });
      if (peso) aviso(`${peso === 1 ? 'Un producto es' : `${peso} productos son`} por kilo: no entra${peso === 1 ? '' : 'n'} en promociones por cantidad`, 'info');
      pintarElegidos();
    };
    const pintarRes = () => {
      res.hidden = !sugeridos.length;
      res.innerHTML = sugeridos.map((x, k) => `<button type="button" class="resultado" data-k="${k}" tabindex="-1"><span>${esc(x.nombre)}</span>
        <span class="muted">${x.por_peso ? 'por kilo: no entra' : esc(x.codigo || '')}</span><b>${plata(x.precio)}</b></button>`).join('');
      $$('[data-k]', res).forEach(b => b.onmousedown = e => { e.preventDefault(); elegir(sugeridos[+b.dataset.k]); });
    };
    const elegir = x => { if (!x) return; sumar([x]); buscar.value = ''; sugeridos = []; pintarRes(); buscar.focus(); };
    buscar.oninput = () => { const t = buscar.value.trim(); sugeridos = t.length < 2 ? [] : (cat.porCodigoDeBarras(t) ? [cat.porCodigoDeBarras(t)] : cat.buscar(t, 10)); pintarRes(); };
    buscar.onkeydown = e => { if (e.key === 'Enter') { e.preventDefault(); elegir(sugeridos[0]); } };
    buscar.onblur = () => setTimeout(() => { res.hidden = true; }, 150);
    $('#pr-cat', m.el).onchange = e => {
      const id = +e.target.value; e.target.value = '';
      if (id) sumar(cat.productos().filter(x => x.categoria_id === id && x.activo !== false));
    };
    pintarElegidos();

    // días y formas: botones que se marcan
    $$('[data-dia]', m.el).forEach(b => b.onclick = () => b.classList.toggle('elegido'));
    $$('[data-forma]', m.el).forEach(b => b.onclick = () => b.classList.toggle('elegido'));

    f.onsubmit = e => {
      e.preventDefault();
      const x = leer();
      if (!f.elements.nombre.value.trim()) { f.elements.nombre.focus(); return aviso('Poné el nombre de la promoción'); }
      if (!d.productos.length) { buscar.focus(); return aviso('Elegí los productos de la promoción'); }
      const datos = { id: p?.id ?? null, nombre: f.elements.nombre.value.trim(), tipo: x.tipo, cantidad: num(x.cantidad),
        paga: num(x.paga), precio: num(x.precio), pct: num(x.pct), productos: d.productos,
        desde: f.elements.desde.value, hasta: f.elements.hasta.value,
        dias: $$('[data-dia].elegido', m.el).map(b => +b.dataset.dia), formas: $$('[data-forma].elegido', m.el).map(b => b.dataset.forma),
        activa: f.elements.activa.checked };
      correr(async () => {
        await llamar('guardar_promocion', { p: datos });
        m.cerrar(); aviso(p ? 'Promoción guardada' : 'Promoción creada', 'ok'); ctx.recargar();
      });
    };
  }
}
