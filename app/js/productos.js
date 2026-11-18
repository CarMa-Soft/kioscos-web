// Productos y categorías (solo dueño). Los costos se piden a la base cada vez y no se guardan en el navegador.
import { llamar } from './base.js';
import * as cat from './catalogo.js';
import { $, $$, esc, plata, cant, fecha, numero, aviso, correr, modal, confirmar } from './ui.js';
import { botonCamara } from './escaner.js';

// Lo que se eligió en la lista se mantiene al ir y volver de la sección
let filtro = '', grupo = 'todos', categoria = '', orden = { col: 'nombre', asc: true };

// Botones de filtro: cada uno con su condición. "Desactivados" muestra los dados de baja (los demás, solo activos).
const GRUPOS = [
  ['todos', 'Todos', () => true],
  ['reponer', 'Para reponer', p => +p.stock_min > 0 && +p.stock <= +p.stock_min],
  ['sin-stock', 'Sin stock', p => +p.stock <= 0],
  ['peso', 'Por peso', p => p.por_peso],
  ['favoritos', 'Favoritos', p => p.favorito],
  ['sin-codigo', 'Sin código de barras', p => !p.codigo && !p.por_peso],   // los por kilo no llevan: se leen con la etiqueta de la balanza
  ['desactivados', 'Desactivados', () => true],
];
// Margen sobre el costo: (precio − costo) / costo. Sin costo no hay margen.
const margen = p => +p.costo > 0 ? (p.precio - p.costo) / p.costo * 100 : null;
const sinAcentos = s => String(s ?? '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '');

export async function pantallaProductos(vista, ctx) {
  // el catálogo trae solo los activos (con costos: solo el dueño los recibe); los dados de baja vienen aparte
  const [r, bajas] = await Promise.all([llamar('catalogo'), llamar('productos_de_baja')]);
  const activos = r.productos;
  const cats = r.categorias, catNombre = id => cats.find(c => c.id === id)?.nombre || '';
  if (categoria && !cats.some(c => String(c.id) === categoria)) categoria = '';
  vista.innerHTML = `<div class="cabecera"><h2>Productos <span class="muted">(${activos.length})</span></h2>
      <div class="acciones"><button class="btn" id="aumento">Aumento de precios</button><button class="btn" id="categorias">Categorías</button><button class="btn primario" id="nuevo">＋ Nuevo producto</button></div></div>
    <div class="p-filtros">
      <div class="p-busqueda">
        <label class="p-buscar"><svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="11" cy="11" r="6.5"/><path d="m20 20-4.2-4.2"/></svg>
          <input id="filtro" placeholder="Buscar por nombre o código…" value="${esc(filtro)}" autocomplete="off"></label>
        <select class="input p-select" id="categoria"><option value="">Todas las categorías</option><option value="sin" ${categoria === 'sin' ? 'selected' : ''}>Sin categoría</option>
          ${cats.map(c => `<option value="${c.id}" ${String(c.id) === categoria ? 'selected' : ''}>${esc(c.nombre)}</option>`).join('')}</select>
      </div>
      <div class="chips" id="grupos"></div>
    </div>
    <div class="p-aviso" id="aviso-bajas" hidden>Los desactivados no aparecen para vender. Abrí uno y tildá "Activo" para que vuelva a aparecer.</div>
    <div class="tabla-caja p-tabla"><table class="tabla" id="tabla"></table></div>`;

  // Los productos de un botón que coinciden con la búsqueda y la categoría (de acá salen también las cantidades de los botones)
  const delGrupo = g => {
    const palabras = sinAcentos(filtro).split(/\s+/).filter(Boolean), cond = GRUPOS.find(x => x[0] === g)[2];
    return (g === 'desactivados' ? bajas : activos).filter(p => cond(p)
      && (categoria === 'sin' ? p.categoria_id == null : !categoria || String(p.categoria_id) === categoria)
      && palabras.every(w => sinAcentos(p.nombre + ' ' + (p.codigo || '')).includes(w)));
  };
  const contar = g => delGrupo(g).length;
  const visibles = () => {
    const dir = orden.asc ? 1 : -1;
    const valor = {
      nombre: p => sinAcentos(p.nombre), categoria: p => sinAcentos(catNombre(p.categoria_id)) || '￿',
      stock: p => +p.stock, costo: p => +p.costo, precio: p => +p.precio, margen: margen,
    }[orden.col];
    return delGrupo(grupo).sort((a, b) => {
      const x = valor(a), y = valor(b);
      if (x == null || y == null) return x == null && y == null ? 0 : x == null ? 1 : -1;   // sin margen, siempre al final
      return (typeof x === 'string' ? x.localeCompare(y, 'es') : x - y) * dir || a.nombre.localeCompare(b.nombre, 'es');
    });
  };
  const hayFiltros = () => filtro.trim() || categoria || grupo !== 'todos';

  const COLS = [['nombre', 'Producto', ''], ['categoria', 'Categoría', ''], ['stock', 'Stock', 'num'], ['costo', 'Costo', 'num'], ['precio', 'Precio', 'num'], ['margen', 'Margen', 'num']];
  const pintar = () => {
    $('#grupos').innerHTML = GRUPOS.map(([g, nombre]) => `<button class="chip ${g === grupo ? 'elegido' : ''}" data-grupo="${g}">${esc(nombre)} <span class="p-cuenta">${contar(g)}</span></button>`).join('');
    $$('[data-grupo]').forEach(b => b.onclick = () => { grupo = b.dataset.grupo; pintar(); });
    $('#aviso-bajas').hidden = grupo !== 'desactivados';
    const ver = visibles();
    $('#tabla').innerHTML = `<thead><tr>${COLS.map(([c, nombre, cl]) => `<th class="${cl}"><button class="p-orden ${orden.col === c ? 'activo' : ''}" data-orden="${c}">${nombre}
        <span aria-hidden="true">${orden.col === c ? (orden.asc ? '▲' : '▼') : '↕'}</span></button></th>`).join('')}</tr></thead>
      <tbody>${ver.length ? ver.slice(0, 300).map(p => {
        const s = +p.stock, min = +p.stock_min, m = margen(p);
        const claseStock = s < 0 ? 'mal' : (s === 0 || (min > 0 && s <= min)) ? 'p-alerta' : '';
        return `<tr class="clic" data-id="${p.id}">
          <td><div class="p-nombre">${esc(p.nombre)}${p.favorito ? ' <span class="p-estrella" title="Botón rápido en Vender">★</span>' : ''}</div>
            <div class="p-sub mono">${p.codigo ? esc(p.codigo) : ''}${p.por_peso ? `${p.codigo ? ' ' : ''}· por kilo` : ''}</div></td>
          <td>${esc(catNombre(p.categoria_id))}</td>
          <td class="num"><span class="${claseStock}">${cant(s)}${p.por_peso ? ' kg' : ''}</span>${min > 0 ? `<div class="p-sub">mín. ${cant(min)}</div>` : ''}</td>
          <td class="num">${plata(p.costo)}</td>
          <td class="num"><b>${plata(p.precio)}</b>${p.por_peso ? '<span class="muted">/kg</span>' : ''}</td>
          <td class="num">${m == null ? '<span class="muted">—</span>' : `${Math.round(m)}%`}</td></tr>`; }).join('')
        : `<tr><td class="muted vacio" colspan="6">${!(grupo === 'desactivados' ? bajas : activos).length
            ? (grupo === 'desactivados' ? 'No hay productos desactivados.' : 'Todavía no hay productos: cargá el primero con "Nuevo producto".')
            : 'Ningún producto coincide con los filtros.'}</td></tr>`}</tbody>
      ${ver.length > 300 ? `<tfoot><tr><td class="muted" colspan="6">Se muestran 300 de ${ver.length}: usá la búsqueda o los filtros para ver los demás.</td></tr></tfoot>` : ''}`;
    $$('[data-orden]').forEach(b => b.onclick = () => {
      const c = b.dataset.orden;
      orden = orden.col === c ? { col: c, asc: !orden.asc } : { col: c, asc: c === 'nombre' || c === 'categoria' };
      pintar();
    });
    $$('tr[data-id]').forEach(tr => tr.onclick = () => ficha([...activos, ...bajas].find(p => p.id === +tr.dataset.id)));
  };
  $('#filtro').oninput = e => { filtro = e.target.value; pintar(); };
  $('#categoria').onchange = e => { categoria = e.target.value; pintar(); };
  $('#nuevo').onclick = () => ficha(null);
  $('#categorias').onclick = () => categorias(cats);
  $('#aumento').onclick = () => correr(() => aumento(hayFiltros() ? visibles() : null, cats, ctx));
  pintar();

  function ficha(p) {
    const v = p || { por_peso: false, favorito: false, activo: true };
    const m = modal(p ? 'Editar producto' : 'Nuevo producto', `<form class="form ancho" id="f-prod">
      <label>Nombre<input class="input" name="nombre" maxlength="120" required value="${esc(v.nombre || '')}" autofocus></label>
      <div class="fila"><label class="crece">Código de barras<input class="input mono" name="codigo" maxlength="40" value="${esc(v.codigo || '')}" autocomplete="off"></label>
        <label class="crece">Categoría<select class="input" name="categoria_id"><option value="">Sin categoría</option>${cats.map(c => `<option value="${c.id}" ${c.id === v.categoria_id ? 'selected' : ''}>${esc(c.nombre)}</option>`).join('')}</select></label></div>
      ${p ? `<div class="otros-codigos"><div><b>Otros códigos</b> <span class="muted chico">(el mismo producto con otro envase: cualquiera lo encuentra)</span></div>
        <div class="chips" id="oc-lista"></div>
        <div class="fila"><input class="input mono crece" id="oc-nuevo" maxlength="40" placeholder="Agregar otro código" autocomplete="off">
          <button type="button" class="btn" id="oc-agregar">Agregar</button></div></div>` : ''}
      <div class="fila"><label class="crece">Costo<input class="input" name="costo" inputmode="decimal" value="${v.costo ?? ''}"></label>
        <label class="crece">Precio de venta<input class="input" name="precio" inputmode="decimal" required value="${v.precio ?? ''}"></label></div>
      <div class="fila"><label class="crece">Stock<input class="input" name="stock" inputmode="decimal" value="${v.stock ?? 0}"></label>
        <label class="crece">Stock mínimo<input class="input" name="stock_min" inputmode="decimal" value="${v.stock_min ?? 0}"></label></div>
      <label class="check"><input type="checkbox" name="por_peso" ${v.por_peso ? 'checked' : ''}> Se vende por kilo</label>
      <label id="plu-box" ${v.por_peso ? '' : 'hidden'}>Código de balanza (PLU) <span class="muted">(el que tiene en la balanza, para leer sus etiquetas)</span>
        <input class="input mono" name="plu" maxlength="6" inputmode="numeric" value="${esc(v.plu || '')}"></label>
      <label class="check"><input type="checkbox" name="favorito" ${v.favorito ? 'checked' : ''}> Botón rápido en Vender <span class="muted">(para lo que no tiene código: pan, cigarrillos sueltos…)</span></label>
      ${p ? `<label class="check"><input type="checkbox" name="activo" ${v.activo !== false ? 'checked' : ''}> Activo <span class="muted">(si lo destildás no aparece para vender)</span></label>` : ''}
      <div class="fila fin">${p ? '<button type="button" class="btn peligro izq" id="eliminar">Eliminar</button>' : ''}
        <button type="button" class="btn" data-cerrar>Cancelar</button><button class="btn primario">Guardar</button></div></form>`, { ancho: true });
    $('[name=por_peso]', m.el).onchange = ev => { $('#plu-box', m.el).hidden = !ev.target.checked; };
    const campoCodigo = $('[name=codigo]', m.el);
    botonCamara(campoCodigo, { continuo: false, alLeer: c => { campoCodigo.value = c; } });   // 📷: el código del producto con la cámara
    // Otros códigos (producto_codigos): se agregan y se quitan al momento, sin esperar a Guardar
    if (p) {
      const pintarOtros = () => {
        $('#oc-lista', m.el).innerHTML = (p.codigos || []).map(c => `<span class="chip mono">${esc(c)} <button type="button" class="link" data-oc="${esc(c)}" title="Quitar este código">✕</button></span>`).join('')
          || '<span class="muted chico">Ninguno</span>';
        $$('[data-oc]', m.el).forEach(b => b.onclick = () => correr(async () => {
          const r = await llamar('quitar_codigo', { p_producto_id: p.id, p_codigo: b.dataset.oc });
          p.codigos = r.codigos; pintarOtros(); cat.actualizar().catch(() => {});
        }));
      };
      const nuevo = $('#oc-nuevo', m.el);
      const agregarOtro = () => {
        const c = nuevo.value.trim(); if (!c) return;
        correr(async () => {
          const r = await llamar('agregar_codigo', { p_producto_id: p.id, p_codigo: c });
          p.codigos = r.codigos; nuevo.value = '';
          if (!campoCodigo.value.trim() && r.codigo) { campoCodigo.value = r.codigo; p.codigo = r.codigo; }   // no tenía: quedó como el principal
          pintarOtros(); cat.actualizar().catch(() => {});
        });
      };
      $('#oc-agregar', m.el).onclick = agregarOtro;
      nuevo.onkeydown = e => { if (e.key === 'Enter') { e.preventDefault(); agregarOtro(); } };
      botonCamara(nuevo, { continuo: false, alLeer: c => { nuevo.value = c; agregarOtro(); } });
      pintarOtros();
    }
    $('#f-prod', m.el).onsubmit = ev => {
      ev.preventDefault();
      const f = new FormData(ev.target);
      const datos = { id: p?.id ?? null, nombre: f.get('nombre'), codigo: f.get('codigo'), categoria_id: f.get('categoria_id') || null,
        costo: numero(f.get('costo')) || 0, precio: numero(f.get('precio')), stock: numero(f.get('stock')) || 0,
        stock_min: numero(f.get('stock_min')) || 0, por_peso: f.get('por_peso') === 'on', plu: f.get('por_peso') === 'on' ? f.get('plu') : '',
        favorito: f.get('favorito') === 'on', ...(p ? { activo: f.get('activo') === 'on' } : {}) };
      if (!(datos.precio >= 0)) return aviso('Revisá el precio');
      if (datos.costo > datos.precio && !confirm('El costo es mayor que el precio de venta. ¿Guardar igual?')) return;
      correr(async () => { await llamar('guardar_producto', { p: datos }); m.cerrar(); aviso('Producto guardado', 'ok'); await cat.actualizar(); ctx.recargar(); });
    };
    if (p) $('#eliminar', m.el).onclick = async () => {
      if (!await confirmar('Eliminar producto', `¿Eliminar "${p.nombre}"? Si ya tiene movimientos (ventas, compras, entradas o ajustes de stock), no se borra: queda dado de baja y se conserva el historial.`, 'Eliminar')) return;
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

// Aumento masivo de precios: a los productos que se ven (si hay búsqueda), a una categoría, a un proveedor o a todos.
// La vista previa la calcula la base (simular), así cuenta igual que al aplicar. Los aumentos anteriores se pueden deshacer.
async function aumento(visibles, cats, ctx) {
  const [provs, previos] = await Promise.all([llamar('proveedores'), llamar('aumentos')]);
  const redondeo = +(ctx.config.redondeo ?? 10);
  const m = modal('Aumento de precios', `<form class="form ancho" id="f-aum">
    <label>¿A qué productos?<select class="input" name="alcance">
      ${visibles ? `<option value="ids">Los ${visibles.length} que estás viendo (según la búsqueda y los filtros)</option>` : ''}
      <option value="categoria">Una categoría</option><option value="proveedor">Un proveedor</option><option value="todos" ${visibles ? '' : 'selected'}>Todos los productos</option></select></label>
    <label id="a-cat" hidden>Categoría<select class="input" name="categoria_id">${cats.map(c => `<option value="${c.id}">${esc(c.nombre)}</option>`).join('')}</select></label>
    <label id="a-prov" hidden>Proveedor<select class="input" name="proveedor_id">${provs.map(p => `<option value="${p.id}">${esc(p.nombre)}</option>`).join('')}</select></label>
    <div class="fila"><label class="crece">Aumento<input class="input" name="valor" inputmode="decimal" placeholder="ej: 8 (o -5 para rebajar)" autofocus></label>
      <label class="crece">En<select class="input" name="modo"><option value="pct">% (porcentaje)</option><option value="monto">$ (monto fijo)</option></select></label></div>
    <label class="check"><input type="checkbox" name="costo" checked> Aumentar también el costo (si el proveedor subió la lista)</label>
    <label class="check"><input type="checkbox" name="redondear" ${redondeo > 0 ? 'checked' : 'disabled'}> ${redondeo > 0
      ? `Redondear los precios hacia arriba a múltiplos de ${plata(redondeo)}` : 'Redondear los precios (el redondeo está apagado)'} <span class="muted chico">(se cambia en Ajustes)</span></label>
    <p class="muted" id="a-prev"></p>
    <div class="fila fin"><button type="button" class="btn" data-cerrar>Cancelar</button><button class="btn primario">Aplicar aumento</button></div>
    <h3>Aumentos anteriores</h3><div id="a-hist"></div></form>`, { ancho: true });
  const f = $('#f-aum', m.el), campo = n => f.elements[n];
  const datos = () => {
    const alcance = campo('alcance').value, modo = campo('modo').value, valor = numero(campo('valor').value);
    const d = { alcance, modo, valor, costo: campo('costo').checked, redondear: campo('redondear').checked };
    if (alcance === 'ids') d.ids = visibles.map(p => p.id);
    if (alcance === 'categoria') d.categoria_id = +campo('categoria_id').value || null;
    if (alcance === 'proveedor') d.proveedor_id = +campo('proveedor_id').value || null;
    const a = alcance === 'ids' ? `${visibles.length} productos buscados` : alcance === 'categoria' ? `categoría ${cats.find(c => c.id === d.categoria_id)?.nombre || ''}`
      : alcance === 'proveedor' ? `proveedor ${provs.find(p => p.id === d.proveedor_id)?.nombre || ''}` : 'todos los productos';
    d.descripcion = `${valor > 0 ? '+' : ''}${modo === 'pct' ? `${String(valor).replace('.', ',')}%` : plata(valor)} a ${a}${d.costo ? ' (con costo)' : ''}`;
    return d;
  };
  let pedido = 0;
  const previa = async () => {
    $('#a-cat', m.el).hidden = campo('alcance').value !== 'categoria';
    $('#a-prov', m.el).hidden = campo('alcance').value !== 'proveedor';
    const d = datos(), n = ++pedido;
    if (!d.valor || (d.alcance === 'categoria' && !d.categoria_id) || (d.alcance === 'proveedor' && !d.proveedor_id)) { $('#a-prev', m.el).textContent = ''; return; }
    try {
      const r = await llamar('aumento_masivo', { p: { ...d, simular: true } });
      if (n !== pedido) return;   // llegó una respuesta vieja
      $('#a-prev', m.el).innerHTML = `<b>${r.cantidad}</b> producto${r.cantidad === 1 ? '' : 's'}.${r.ejemplos.length ? ' Ejemplos: '
        + r.ejemplos.map(x => `${esc(x.nombre)} ${plata(x.precio)} → <b>${plata(x.precio_nuevo)}</b>`).join(' · ') : ''}`;
    } catch (e) { if (n === pedido) $('#a-prev', m.el).textContent = e.message; }
  };
  f.querySelectorAll('select, input').forEach(i => { i.oninput = previa; i.onchange = previa; });
  previa();
  const pintarHist = lista => {
    $('#a-hist', m.el).innerHTML = lista.length ? `<table class="tabla"><tbody>${lista.map(a => `<tr><td>${fecha(a.fecha)}<div class="muted chico">${esc(a.usuario)}</div></td>
        <td>${esc(a.descripcion)}</td><td class="num">${a.cantidad} prod.</td>
        <td class="num">${a.deshecho ? '<span class="etiqueta">deshecho</span>' : `<button type="button" class="btn chico" data-desh="${a.id}">Deshacer</button>`}</td></tr>`).join('')}</tbody></table>`
      : '<p class="muted">Todavía no hubo aumentos.</p>';
    $$('[data-desh]', m.el).forEach(b => b.onclick = async () => {
      if (!await confirmar('Deshacer aumento', 'Los productos vuelven al precio y costo que tenían antes de ese aumento, salvo los que se cambiaron después.', 'Deshacer')) return;
      correr(async () => {
        const r = await llamar('deshacer_aumento', { p_id: +b.dataset.desh });
        aviso(`Volvieron ${r.revertidos} producto${r.revertidos === 1 ? '' : 's'}${r.saltados ? ` · ${r.saltados} no se tocaron porque cambiaron después` : ''}`, 'ok');
        pintarHist(await llamar('aumentos')); await cat.actualizar(); ctx.recargar();
      });
    });
  };
  pintarHist(previos);
  f.onsubmit = async e => {
    e.preventDefault();
    const d = datos();
    if (!d.valor) return aviso('Poné el aumento');
    if (!await confirmar('Aplicar aumento', `${d.descripcion}. Se puede deshacer después.`, 'Aplicar')) return;
    correr(async () => {
      const r = await llamar('aumento_masivo', { p: d });
      m.cerrar(); aviso(`Precios actualizados: ${r.cantidad} producto${r.cantidad === 1 ? '' : 's'}`, 'ok');
      await cat.actualizar(); ctx.recargar();
    });
  };
}
