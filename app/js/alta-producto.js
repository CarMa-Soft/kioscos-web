// Producto que no está, desde Compras o Entradas y salidas (solo dueño), sin salir de la pantalla:
// - crearlo ahí mismo (nombre, código, categoría, costo y precio), o
// - si es uno que ya está pero cambió el envase, agregarle este código (queda como otro código: los dos lo encuentran).
// alElegir(producto) recibe el producto creado o actualizado (con costo), para que la pantalla lo sume a la lista.
import { llamar } from './base.js';
import * as cat from './catalogo.js';
import { $, $$, esc, plata, numero, aviso, correr, modal, confirmar } from './ui.js';
import { botonCamara } from './escaner.js';

const pareceCodigo = t => /^\S{4,40}$/.test(t) && /\d/.test(t);

export function productoNoEncontrado(texto, { productos, categorias, alElegir }) {
  const t = String(texto || '').trim();
  const esCodigo = pareceCodigo(t);
  const m = modal('No está en tus productos', `<p>No hay ningún producto con ${esCodigo ? 'el código' : ''} <b>${esc(t)}</b>.</p>
    <div class="opciones-alta">
      <button class="btn primario" id="alta-nuevo">＋ Es un producto nuevo: crearlo</button>
      ${esCodigo ? '<button class="btn" id="alta-codigo">Es uno que ya tengo (cambió el envase): agregarle este código</button>' : ''}
      <button class="btn" data-cerrar>Cancelar</button></div>`);
  $('#alta-nuevo', m.el).onclick = () => { m.cerrar(); formNuevo(esCodigo ? { codigo: t } : { nombre: t }, categorias, alElegir); };
  if (esCodigo) $('#alta-codigo', m.el).onclick = () => { m.cerrar(); elegirParaCodigo(t, productos, alElegir); };
}

// Alta rápida: lo justo para cargarlo en la compra; lo demás (stock mínimo, botón rápido…) se completa después en Productos
function formNuevo(v, categorias, alElegir) {
  const m = modal('Producto nuevo', `<form class="form ancho" id="f-alta">
    <label>Nombre<input class="input" name="nombre" maxlength="120" required value="${esc(v.nombre || '')}" ${v.nombre ? '' : 'autofocus'}></label>
    <div class="fila"><label class="crece">Código de barras<input class="input mono" name="codigo" maxlength="40" value="${esc(v.codigo || '')}" autocomplete="off"></label>
      <label class="crece">Categoría<select class="input" name="categoria_id"><option value="">Sin categoría</option>
        ${categorias.map(c => `<option value="${c.id}">${esc(c.nombre)}</option>`).join('')}</select></label></div>
    <div class="fila"><label class="crece">Costo<input class="input" name="costo" inputmode="decimal"></label>
      <label class="crece">Precio de venta<input class="input" name="precio" inputmode="decimal" required></label></div>
    <label class="check"><input type="checkbox" name="por_peso"> Se vende por kilo</label>
    <p class="muted chico">El stock lo suma la compra. El stock mínimo y lo demás se completan después en Productos.</p>
    <div class="fila fin"><button type="button" class="btn" data-cerrar>Cancelar</button><button class="btn primario">Crear y agregar</button></div></form>`, { ancho: true });
  const campo = $('[name=codigo]', m.el);
  botonCamara(campo, { continuo: false, alLeer: c => { campo.value = c; } });
  $('#f-alta', m.el).onsubmit = e => {
    e.preventDefault();
    const f = new FormData(e.target);
    const datos = { nombre: f.get('nombre'), codigo: f.get('codigo'), categoria_id: f.get('categoria_id') || null,
      costo: numero(f.get('costo')) || 0, precio: numero(f.get('precio')), por_peso: f.get('por_peso') === 'on' };
    if (!(datos.precio >= 0)) return aviso('Revisá el precio de venta');
    correr(async () => {
      const p = await llamar('guardar_producto', { p: datos });
      m.cerrar(); aviso(`${p.nombre} creado`, 'ok');
      cat.actualizar().catch(() => {});
      alElegir(p);
    });
  };
}

// Buscar el producto al que se le agrega el código
function elegirParaCodigo(codigo, productos, alElegir) {
  const m = modal('¿A qué producto le agregás el código?', `<p class="muted">Código nuevo: <b class="mono">${esc(codigo)}</b>. El producto va a quedar con los dos códigos.</p>
    <div class="buscador"><input class="input" id="ac-buscar" placeholder="Buscá por nombre o código…" autocomplete="off" autofocus><div class="resultados" id="ac-res"></div></div>
    <div class="fila fin"><button class="btn" data-cerrar>Cancelar</button></div>`);
  const inp = $('#ac-buscar', m.el);
  const norm = s => String(s || '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '');
  let lista = [];
  const elegir = p => correr(async () => {
    if (!await confirmar('Agregar código', `¿Agregar el código ${codigo} a "${p.nombre}"? Desde ahora los dos códigos encuentran ese producto.`, 'Agregar')) return;
    const r = await llamar('agregar_codigo', { p_producto_id: p.id, p_codigo: codigo });
    m.cerrar(); aviso(`Código agregado a ${r.nombre}`, 'ok');
    cat.actualizar().catch(() => {});
    alElegir({ ...p, ...r });
  });
  inp.oninput = () => {
    const w = norm(inp.value).split(/\s+/).filter(Boolean);
    lista = w.length ? productos.filter(p => w.every(x => norm(p.nombre + ' ' + cat.codigosDe(p).join(' ')).includes(x))).slice(0, 12) : [];
    $('#ac-res', m.el).innerHTML = lista.map((p, k) => `<button class="resultado" data-k="${k}"><span>${esc(p.nombre)}</span><span class="muted mono">${esc(p.codigo || '')}</span><b>${plata(p.precio)}</b></button>`).join('')
      || (w.length ? '<p class="muted sin">No hay productos con ese nombre.</p>' : '');
    $$('[data-k]', m.el).forEach(b => b.onclick = () => elegir(lista[+b.dataset.k]));
  };
  inp.onkeydown = e => { if (e.key === 'Enter' && lista[0]) { e.preventDefault(); elegir(lista[0]); } };
}
