// Productos y categorías (solo dueño). Los costos se piden a la base cada vez y no se guardan en el navegador.
import { llamar } from './base.js';
import * as cat from './catalogo.js';
import { $, $$, esc, plata, cant, numero, aviso, correr, modal, confirmar } from './ui.js';

let filtro = '';

export async function pantallaProductos(vista, ctx) {
  const r = await llamar('catalogo');   // con costos (solo el dueño los recibe)
  const lista = r.productos.sort((a, b) => a.nombre.localeCompare(b.nombre));
  const cats = r.categorias, catNombre = id => cats.find(c => c.id === id)?.nombre || '';
  vista.innerHTML = `<div class="cabecera"><h2>Productos <span class="muted">(${lista.length})</span></h2>
      <div class="acciones"><button class="btn" id="categorias">Categorías</button><button class="btn primario" id="nuevo">＋ Nuevo producto</button></div></div>
    <input class="input" id="filtro" placeholder="Buscar por nombre o código" value="${esc(filtro)}" autocomplete="off">
    <div class="tabla-caja"><table class="tabla" id="tabla"></table></div>`;
  const pintar = () => {
    const palabras = filtro.toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').split(/\s+/).filter(Boolean);
    const ver = lista.filter(p => { const t = (p.nombre + ' ' + (p.codigo || '')).toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, ''); return palabras.every(w => t.includes(w)); });
    $('#tabla').innerHTML = ver.length ? `<thead><tr><th>Producto</th><th>Código</th><th>Categoría</th><th class="num">Costo</th><th class="num">Precio</th><th class="num">Stock</th></tr></thead><tbody>
      ${ver.slice(0, 300).map(p => `<tr class="clic" data-id="${p.id}"><td>${esc(p.nombre)}${p.por_peso ? ' <span class="etiqueta">por kg</span>' : ''}</td><td class="mono">${esc(p.codigo || '')}</td>
        <td>${esc(catNombre(p.categoria_id))}</td><td class="num">${plata(p.costo)}</td><td class="num"><b>${plata(p.precio)}</b></td>
        <td class="num ${+p.stock <= +p.stock_min ? 'mal' : ''}">${cant(p.stock)}</td></tr>`).join('')}</tbody>`
      : `<tbody><tr><td class="muted vacio">${lista.length ? 'Ningún producto coincide.' : 'Todavía no hay productos: cargá el primero con "Nuevo producto".'}</td></tr></tbody>`;
    $$('tr[data-id]').forEach(tr => tr.onclick = () => ficha(lista.find(p => p.id === +tr.dataset.id)));
  };
  $('#filtro').oninput = e => { filtro = e.target.value; pintar(); };
  $('#nuevo').onclick = () => ficha(null);
  $('#categorias').onclick = () => categorias(cats);
  pintar();

  function ficha(p) {
    const v = p || { por_peso: false, favorito: false };
    const m = modal(p ? 'Editar producto' : 'Nuevo producto', `<form class="form ancho" id="f-prod">
      <label>Nombre<input class="input" name="nombre" maxlength="120" required value="${esc(v.nombre || '')}" autofocus></label>
      <div class="fila"><label class="crece">Código de barras<input class="input mono" name="codigo" maxlength="40" value="${esc(v.codigo || '')}" autocomplete="off"></label>
        <label class="crece">Categoría<select class="input" name="categoria_id"><option value="">Sin categoría</option>${cats.map(c => `<option value="${c.id}" ${c.id === v.categoria_id ? 'selected' : ''}>${esc(c.nombre)}</option>`).join('')}</select></label></div>
      <div class="fila"><label class="crece">Costo<input class="input" name="costo" inputmode="decimal" value="${v.costo ?? ''}"></label>
        <label class="crece">Precio de venta<input class="input" name="precio" inputmode="decimal" required value="${v.precio ?? ''}"></label></div>
      <div class="fila"><label class="crece">Stock<input class="input" name="stock" inputmode="decimal" value="${v.stock ?? 0}"></label>
        <label class="crece">Stock mínimo<input class="input" name="stock_min" inputmode="decimal" value="${v.stock_min ?? 0}"></label></div>
      <label class="check"><input type="checkbox" name="por_peso" ${v.por_peso ? 'checked' : ''}> Se vende por kilo</label>
      <div class="fila fin">${p ? '<button type="button" class="btn peligro izq" id="eliminar">Eliminar</button>' : ''}
        <button type="button" class="btn" data-cerrar>Cancelar</button><button class="btn primario">Guardar</button></div></form>`, { ancho: true });
    $('#f-prod', m.el).onsubmit = ev => {
      ev.preventDefault();
      const f = new FormData(ev.target);
      const datos = { id: p?.id ?? null, nombre: f.get('nombre'), codigo: f.get('codigo'), categoria_id: f.get('categoria_id') || null,
        costo: numero(f.get('costo')) || 0, precio: numero(f.get('precio')), stock: numero(f.get('stock')) || 0,
        stock_min: numero(f.get('stock_min')) || 0, por_peso: f.get('por_peso') === 'on' };
      if (!(datos.precio >= 0)) return aviso('Revisá el precio');
      if (datos.costo > datos.precio && !confirm('El costo es mayor que el precio de venta. ¿Guardar igual?')) return;
      correr(async () => { await llamar('guardar_producto', { p: datos }); m.cerrar(); aviso('Producto guardado', 'ok'); await cat.actualizar(); ctx.recargar(); });
    };
    if (p) $('#eliminar', m.el).onclick = async () => {
      if (!await confirmar('Eliminar producto', `¿Eliminar "${p.nombre}"? Si ya tiene ventas, queda dado de baja (se conserva el historial).`, 'Eliminar')) return;
      correr(async () => { const r = await llamar('eliminar_producto', { p_id: p.id }); m.cerrar(); aviso(r.desactivado ? 'Producto dado de baja' : 'Producto eliminado', 'ok'); await cat.actualizar(); ctx.recargar(); });
    };
  }

  function categorias(lista) {
    const m = modal('Categorías', `<div id="cats"></div><form class="fila" id="f-cat"><input class="input crece" name="nombre" placeholder="Nueva categoría" maxlength="60" required><button class="btn primario">Agregar</button></form>
      <div class="fila fin"><button class="btn" data-cerrar>Cerrar</button></div>`, { alCerrar: () => ctx.recargar() });
    const pintarCats = () => {
      $('#cats', m.el).innerHTML = lista.length ? `<table class="tabla"><tbody>${lista.map(c => `<tr><td>${esc(c.nombre)}</td><td class="num"><button class="link" data-ren="${c.id}">Renombrar</button> · <button class="link" data-del="${c.id}">Borrar</button></td></tr>`).join('')}</tbody></table>`
        : '<p class="muted">Todavía no hay categorías.</p>';
      $$('[data-ren]', m.el).forEach(b => b.onclick = () => {
        const c = lista.find(x => x.id === +b.dataset.ren), nombre = prompt('Nombre de la categoría', c.nombre);
        if (nombre && nombre.trim() !== c.nombre) correr(async () => { const r = await llamar('guardar_categoria', { p_id: c.id, p_nombre: nombre }); c.nombre = r.nombre; pintarCats(); });
      });
      $$('[data-del]', m.el).forEach(b => b.onclick = () => correr(async () => {
        await llamar('eliminar_categoria', { p_id: +b.dataset.del });
        lista.splice(lista.findIndex(x => x.id === +b.dataset.del), 1); pintarCats();
      }));
    };
    $('#f-cat', m.el).onsubmit = ev => {
      ev.preventDefault();
      correr(async () => { const r = await llamar('guardar_categoria', { p_id: null, p_nombre: new FormData(ev.target).get('nombre') }); lista.push(r); ev.target.reset(); pintarCats(); });
    };
    pintarCats();
  }
}
