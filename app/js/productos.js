// Productos y categorías (solo dueño). Los costos se piden a la base cada vez y no se guardan en el navegador.
import { llamar } from './base.js';
import * as cat from './catalogo.js';
import { $, $$, esc, plata, cant, fecha, numero, aviso, correr, modal, confirmar } from './ui.js';
import { botonCamara } from './escaner.js';
import { pantallaListaPrecios } from './listaprecios.js';
import { pantallaPromociones } from './promociones.js';
import { preciosModal } from './precios.js';
import { porProducto, aQuien } from './entregas.js';
import { importarProductos } from './importar.js';
import { UNIDADES, CATEGORIAS, idCategoria, delCatalogoGeneral, pantallaCatalogoGeneral } from './catalogo_general.js';

// Lo que se eligió en la lista se mantiene al ir y volver de la sección
let filtro = '', grupo = 'todos', categoria = '', orden = { col: 'nombre', asc: true };
let enLista = false;   // mostrando la lista de precios para imprimir
let enPromos = false;  // mostrando las promociones
let enGeneral = false; // en Cargar productos (catálogo general y nuevos)
// Desde Inicio: abrir la lista con los productos a revisar
export function verARevisar() { grupo = 'revisar'; filtro = ''; categoria = ''; }
export function verParaReponer() { grupo = 'reponer'; filtro = ''; categoria = ''; }   // desde Inicio

// Botones de filtro: cada uno con su condición. "Desactivados" muestra los dados de baja (los demás, solo activos).
const GRUPOS = [
  ['todos', 'Todos', () => true],
  ['revisar', 'A revisar', p => p.a_revisar],   // creados en la caja con lo mínimo, o del catálogo sin costo o categoría
  ['reponer', 'Para reponer', p => +p.stock_min > 0 && +p.stock <= +p.stock_min],
  ['sin-stock', 'Sin stock', p => +p.stock <= 0],
  ['peso', 'Por peso', p => p.por_peso],
  ['favoritos', 'Favoritos', p => p.favorito],
  ['sin-codigo', 'Sin código de barras', p => !p.codigo && !p.por_peso],   // los por kilo no llevan: se leen con la etiqueta de la balanza
  ['desactivados', 'Desactivados', () => true],
];
// Íconos de las tarjetas (trazos SVG, toman el color del texto). Los estilos son los de Hoy, Caja, Clientes y Proveedores (clases c-).
const svg = d => `<svg viewBox="0 0 24 24" aria-hidden="true">${d}</svg>`;
const ICO = {
  productos: svg('<path d="m12 3 8 4.5v9L12 21l-8-4.5v-9z"/><path d="m4 7.5 8 4.5 8-4.5M12 12v9"/>'),
  plata: svg('<rect x="2.5" y="6" width="19" height="12" rx="2"/><circle cx="12" cy="12" r="2.6"/>'),
  reponer: svg('<path d="m12 3 8 4.5v9L12 21l-8-4.5v-9z"/><path d="M12 8v6M9 11l3 3 3-3"/>'),
  sinStock: svg('<circle cx="12" cy="12" r="9"/><path d="M12 7.5v5.5M12 16.5v.01"/>'),
};
// Margen sobre el costo: (precio − costo) / costo. Sin costo no hay margen.
const margen = p => +p.costo > 0 ? (p.precio - p.costo) / p.costo * 100 : null;
const sinAcentos = s => String(s ?? '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '');

export async function pantallaProductos(vista, ctx) {
  if (enLista) return pantallaListaPrecios(vista, ctx, () => { enLista = false; ctx.recargar(); });
  if (enPromos) return pantallaPromociones(vista, ctx, () => { enPromos = false; ctx.recargar(); });
  if (enGeneral) return pantallaCatalogoGeneral(vista, ctx, () => { enGeneral = false; ctx.recargar(); });
  // el catálogo trae solo los activos (con costos: solo el dueño los recibe); los dados de baja vienen aparte
  const [r, bajas, entregas] = await Promise.all([llamar('catalogo'), llamar('productos_de_baja'), porProducto()]);
  const aEntregar = id => (entregas[id] || []).reduce((s, e) => s + +e.cantidad, 0);
  const activos = r.productos;
  const cats = r.categorias, catNombre = id => cats.find(c => c.id === id)?.nombre || '';
  if (categoria && !cats.some(c => String(c.id) === categoria)) categoria = '';
  // tarjetas: de todos los activos (sin filtros). La mercadería se valoriza con el stock positivo.
  const cuenta = g => activos.filter(GRUPOS.find(x => x[0] === g)[2]).length;
  const valorCosto = activos.reduce((s, p) => s + Math.max(0, +p.stock) * +p.costo, 0);
  const valorVenta = activos.reduce((s, p) => s + Math.max(0, +p.stock) * +p.precio, 0);
  const nReponer = cuenta('reponer'), nSinStock = cuenta('sin-stock');
  vista.innerHTML = `<div class="cabecera"><h2>Productos <span class="muted">(${activos.length})</span></h2>
      <div class="acciones p-acciones"><button class="btn" id="lista-precios">🏷️ Lista de precios</button><button class="btn" id="promociones" title="3x2, 2 por $X, la 2ª al 50%…: se aplican solas en Vender">🎁 Promociones</button><button class="btn" id="aumento">Precios y márgenes</button><button class="btn" id="categorias">Categorías</button><button class="btn" id="general" title="Recorré la góndola escaneando: los que están en el catálogo general (más de 60.000) vienen con nombre, marca y contenido; los que no, los cargás ahí mismo">📦 Cargar productos</button><button class="btn" id="importar" title="Cargar o actualizar muchos productos desde una planilla de Excel o CSV">📥 Importar</button><button class="btn primario" id="nuevo">＋ Nuevo producto</button></div></div>
    <div class="c-tarjetas">
      <div class="c-tarjeta verde"><span class="c-ico">${ICO.productos}</span><div><div class="etq">Productos activos</div><div class="valor">${activos.length}</div>
        <div class="c-sub">${bajas.length ? `${bajas.length} desactivado${bajas.length === 1 ? '' : 's'}` : 'ninguno desactivado'}</div></div></div>
      <div class="c-tarjeta azul"><span class="c-ico">${ICO.plata}</span><div><div class="etq">Mercadería valorizada (al costo)</div><div class="valor">${plata(valorCosto)}</div>
        <div class="c-sub">a precio de venta: ${plata(valorVenta)}</div></div></div>
      <div class="c-tarjeta ${nReponer ? 'naranja' : 'gris'}"><span class="c-ico">${ICO.reponer}</span><div><div class="etq">Para reponer</div><div class="valor">${nReponer}</div>
        <div class="c-sub">${nReponer ? '<button class="link" data-ir-grupo="reponer">ver cuáles</button>' : 'ninguno debajo del stock mínimo'}</div></div></div>
      <div class="c-tarjeta ${nSinStock ? 'rojo' : 'gris'}"><span class="c-ico">${ICO.sinStock}</span><div><div class="etq">Sin stock</div><div class="valor">${nSinStock}</div>
        <div class="c-sub">${nSinStock ? '<button class="link" data-ir-grupo="sin-stock">ver cuáles</button>' : 'todos tienen stock'}</div></div></div>
    </div>
    <div class="p-filtros">
      <div class="p-busqueda">
        <label class="p-buscar"><svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="11" cy="11" r="6.5"/><path d="m20 20-4.2-4.2"/></svg>
          <input id="filtro" placeholder="Buscar por nombre o código…" value="${esc(filtro)}" autocomplete="off"></label>
        <select class="input p-select" id="categoria"><option value="">Todas las categorías</option><option value="sin" ${categoria === 'sin' ? 'selected' : ''}>Sin categoría</option>
          ${cats.map(c => `<option value="${c.id}" ${String(c.id) === categoria ? 'selected' : ''}>${esc(c.nombre)}</option>`).join('')}</select>
      </div>
      <div class="chips" id="grupos"></div>
    </div>
    <div class="p-aviso" id="aviso-revisar" hidden>Se crearon en la caja con lo mínimo. Abrí cada uno, completá el nombre, el costo, la categoría y el stock real (contalo), y guardalo: deja de estar a revisar.</div>
    <div class="p-aviso" id="aviso-bajas" hidden>Los desactivados no aparecen para vender. Abrí uno y tildá "Activo" para que vuelva a aparecer.</div>
    <div class="tabla-caja p-tabla"><table class="tabla" id="tabla"></table></div>`;

  // Los productos de un botón que coinciden con la búsqueda y la categoría (de acá salen también las cantidades de los botones)
  const delGrupo = g => {
    const palabras = sinAcentos(filtro).split(/\s+/).filter(Boolean), cond = GRUPOS.find(x => x[0] === g)[2];
    return (g === 'desactivados' ? bajas : activos).filter(p => cond(p)
      && (categoria === 'sin' ? p.categoria_id == null : !categoria || String(p.categoria_id) === categoria)
      && palabras.every(w => sinAcentos(p.nombre + ' ' + (p.marca || '') + ' ' + (p.codigo || '')).includes(w)));
  };
  const contar = g => delGrupo(g).length;
  const visibles = () => {
    const dir = orden.asc ? 1 : -1;
    const valor = {
      nombre: p => sinAcentos(p.nombre), categoria: p => sinAcentos(catNombre(p.categoria_id)) || '￿',
      stock: p => +p.stock, costo: p => +p.costo, precio: p => +p.precio, margen: p => p.margen != null ? +p.margen : margen(p),
    }[orden.col];
    return delGrupo(grupo).sort((a, b) => {
      const x = valor(a), y = valor(b);
      if (x == null || y == null) return x == null && y == null ? 0 : x == null ? 1 : -1;   // sin margen, siempre al final
      return (typeof x === 'string' ? x.localeCompare(y, 'es') : x - y) * dir || a.nombre.localeCompare(b.nombre, 'es');
    });
  };
  const hayFiltros = () => filtro.trim() || categoria || grupo !== 'todos';

  const COLS = [['nombre', 'Producto', ''], ['categoria', 'Categoría', ''], ['stock', 'Stock', 'num'], ['costo', 'Costo', 'num'], ['precio', 'Precio', 'num'], ['margen', 'Margen', 'num']];
  // Precio o stock tocándolos en la tabla: aparece un campo; Enter o salir del campo guarda, Esc deja como estaba
  let guardado = null;   // la fila recién guardada destella
  function enLinea(b) {
    const p = [...activos, ...bajas].find(x => x.id === +b.dataset.pid), campo = b.dataset.editar;
    const antes = +p[campo];
    const inp = Object.assign(document.createElement('input'), { className: 'input p-edit-input', value: String(antes).replace('.', ','), inputmode: 'decimal' });
    inp.setAttribute('aria-label', campo === 'precio' ? 'Precio nuevo' : 'Stock nuevo');
    b.replaceWith(inp); inp.focus(); inp.select();
    inp.onclick = e => e.stopPropagation();
    let listo = false;
    const terminar = guardar => {
      if (listo) return; listo = true;
      const v = numero(inp.value);
      if (!guardar || !Number.isFinite(v) || Math.abs(v - antes) < 0.0005) return pintar();
      if (campo === 'precio' && v < 0) { aviso('El precio no puede ser negativo'); return pintar(); }
      correr(async () => {
        const r = campo === 'precio' ? await llamar('cambiar_precio', { p_id: p.id, p_precio: v })
          : await llamar('ajustar_stock', { p_producto_id: p.id, p_nuevo: v, p_motivo: 'Corrección desde la lista' });
        const teniaMargen = p.margen != null;
        Object.assign(p, { precio: r.precio, stock: r.stock, margen: r.margen });
        aviso(campo === 'precio' ? `Precio de ${p.nombre}: ${plata(r.precio)}${teniaMargen ? ' (queda fijo: ya no sigue al costo)' : ''}` : `Stock de ${p.nombre}: ${cant(r.stock)}`, teniaMargen && campo === 'precio' ? 'info' : 'ok');
        guardado = p.id;
        cat.actualizar().catch(() => {});
      }).finally(pintar);
    };
    inp.onkeydown = e => { if (e.key === 'Enter') { e.preventDefault(); terminar(true); } else if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); terminar(false); } };
    inp.onblur = () => terminar(true);
  }
  const pintar = () => {
    $('#grupos').innerHTML = GRUPOS.map(([g, nombre]) => `<button class="chip ${g === grupo ? 'elegido' : ''}" data-grupo="${g}">${esc(nombre)} <span class="p-cuenta">${contar(g)}</span></button>`).join('');
    $$('[data-grupo]').forEach(b => b.onclick = () => { grupo = b.dataset.grupo; pintar(); });
    $('#aviso-bajas').hidden = grupo !== 'desactivados';
    $('#aviso-revisar').hidden = grupo !== 'revisar';
    const ver = visibles();
    $('#tabla').innerHTML = `<thead><tr>${COLS.map(([c, nombre, cl]) => `<th class="${cl}"><button class="p-orden ${orden.col === c ? 'activo' : ''}" data-orden="${c}">${nombre}
        <span aria-hidden="true">${orden.col === c ? (orden.asc ? '▲' : '▼') : '↕'}</span></button></th>`).join('')}</tr></thead>
      <tbody>${ver.length ? ver.slice(0, 300).map(p => {
        const s = +p.stock, min = +p.stock_min, m = margen(p);
        const claseStock = s < 0 ? 'mal' : (s === 0 || (min > 0 && s <= min)) ? 'p-alerta' : '';
        return `<tr class="clic" data-id="${p.id}">
          <td><div class="p-nombre">${esc(p.nombre)}${p.favorito ? ' <span class="p-estrella" title="Botón rápido en Vender">★</span>' : ''}${p.a_revisar ? ' <span class="etiqueta pendiente" title="Creado en la caja: falta completarlo">a revisar</span>' : ''}</div>
            <div class="p-sub mono">${p.codigo ? esc(p.codigo) : ''}${p.por_peso ? `${p.codigo ? ' ' : ''}· por kilo` : ''}</div></td>
          <td>${esc(catNombre(p.categoria_id))}</td>
          <td class="num"><button class="p-edit ${claseStock}" data-editar="stock" data-pid="${p.id}" title="Cambiar el stock">${cant(s)}${p.por_peso ? ' kg' : ''}</button>${min > 0 ? `<div class="p-sub">mín. ${cant(min)}</div>` : ''}${aEntregar(p.id) ? `<div class="p-entregar" title="${esc(entregas[p.id].map(e => aQuien(e).replace(/<[^>]+>/g, '')).join(' / '))}">📦 ${cant(aEntregar(p.id))} a entregar</div>` : ''}</td>
          <td class="num">${plata(p.costo)}</td>
          <td class="num"><button class="p-edit" data-editar="precio" data-pid="${p.id}" title="Cambiar el precio"><b>${plata(p.precio)}</b>${p.por_peso ? '<span class="muted">/kg</span>' : ''}</button></td>
          <td class="num">${p.margen != null
            // margen automático: el configurado; el real puede dar un poco más por el redondeo del precio
            ? `<span title="Margen automático: el precio sigue al costo${m != null && Math.round(m) !== Math.round(+p.margen) ? `. Real: ${Math.round(m)}%, por el redondeo del precio` : ''}">${String(+p.margen).replace('.', ',')}% <span class="etiqueta info">auto</span></span>`
            : m == null ? '<span class="muted">—</span>' : `${Math.round(m)}%`}</td></tr>`; }).join('')
        : `<tr><td class="muted vacio" colspan="6">${!(grupo === 'desactivados' ? bajas : activos).length
            ? (grupo === 'desactivados' ? 'No hay productos desactivados.' : 'Todavía no hay productos: cargá el primero con "Nuevo producto", o muchos juntos con "Importar" (planilla) o "Cargar productos" (escaneando la góndola).')
            : 'Ningún producto coincide con los filtros.'}</td></tr>`}</tbody>
      ${ver.length > 300 ? `<tfoot><tr><td class="muted" colspan="6">Se muestran 300 de ${ver.length}: usá la búsqueda o los filtros para ver los demás.</td></tr></tfoot>` : ''}`;
    $$('[data-orden]').forEach(b => b.onclick = () => {
      const c = b.dataset.orden;
      orden = orden.col === c ? { col: c, asc: !orden.asc } : { col: c, asc: c === 'nombre' || c === 'categoria' };
      pintar();
    });
    $$('tr[data-id]').forEach(tr => tr.onclick = () => ficha([...activos, ...bajas].find(p => p.id === +tr.dataset.id)));
    $$('[data-editar]').forEach(b => b.onclick = e => { e.stopPropagation(); enLinea(b); });
    if (guardado) { $(`tr[data-id="${guardado}"]`)?.classList.add('p-guardado'); guardado = null; }
  };
  $('#filtro').oninput = e => { filtro = e.target.value; pintar(); };
  $('#categoria').onchange = e => { categoria = e.target.value; pintar(); };
  // "ver cuáles" de las tarjetas: pone ese filtro (sin búsqueda ni categoría, para que se vean todos)
  $$('[data-ir-grupo]').forEach(b => b.onclick = () => {
    grupo = b.dataset.irGrupo; filtro = ''; categoria = '';
    $('#filtro').value = ''; $('#categoria').value = ''; pintar();
  });
  $('#nuevo').onclick = () => ficha(null);
  $('#importar').onclick = () => importarProductos(() => ctx.recargar());
  $('#categorias').onclick = () => categorias(cats);
  $('#aumento').onclick = () => correr(() => preciosModal({ productos: activos, categorias: cats, visibles: hayFiltros() ? visibles().filter(p => p.activo !== false) : null, ctx, alTerminar: () => ctx.recargar() }));
  $('#lista-precios').onclick = () => { enLista = true; ctx.recargar(); };
  $('#promociones').onclick = () => { enPromos = true; ctx.recargar(); };
  $('#general').onclick = () => { enGeneral = true; ctx.recargar(); };
  pintar();

  function ficha(p) {
    const v = p || { por_peso: false, favorito: false, activo: true, margen: +(ctx.config.margen ?? 40) > 0 ? +(ctx.config.margen ?? 40) : null };
    const m = modal(p ? 'Editar producto' : 'Nuevo producto', `<form class="form ancho" id="f-prod">
      ${p && entregas[p.id] ? `<div class="p-aviso">📦 Para entregar (ventas ya cobradas y encargos): ${entregas[p.id].map(aQuien).join('; ')}</div>` : ''}
      ${p?.a_revisar ? '<div class="p-aviso">Se creó con lo mínimo (en la caja, o desde el catálogo general sin costo o sin categoría). Completá lo que falte (costo, categoría, stock real); al guardarlo deja de estar a revisar.</div>' : ''}
      <label>Nombre<input class="input" name="nombre" maxlength="120" required value="${esc(v.nombre || '')}" autofocus></label>
      <div class="fila"><label class="crece">Código de barras<input class="input mono" name="codigo" maxlength="40" value="${esc(v.codigo || '')}" autocomplete="off"></label>
        <label class="crece">Categoría<select class="input" name="categoria_id"><option value="">Sin categoría</option>${cats.map(c => `<option value="${c.id}" ${c.id === v.categoria_id ? 'selected' : ''}>${esc(c.nombre)}</option>`).join('')}</select></label></div>
      <div class="fila"><label class="crece">Marca <span class="muted">(opcional)</span><input class="input" name="marca" maxlength="80" value="${esc(v.marca || '')}" autocomplete="off"></label>
        <label class="p-contenido">Contenido <span class="muted">(opcional)</span><span class="fila"><input class="input" name="contenido" inputmode="decimal" value="${v.contenido != null ? String(+v.contenido).replace('.', ',') : ''}" placeholder="500">
          <select class="input" name="unidad">${UNIDADES.map(([u, t]) => `<option value="${u}" ${(v.unidad || 'g') === u ? 'selected' : ''}>${t}</option>`).join('')}</select></span></label></div>
      <p class="muted chico" id="del-general" hidden></p>
      ${p ? `<div class="otros-codigos"><div><b>Otros códigos</b> <span class="muted chico">(el mismo producto con otro envase: cualquiera lo encuentra)</span></div>
        <div class="chips" id="oc-lista"></div>
        <div class="fila"><input class="input mono crece" id="oc-nuevo" maxlength="40" placeholder="Agregar otro código" autocomplete="off">
          <button type="button" class="btn" id="oc-agregar">Agregar</button></div></div>` : ''}
      <div class="fila"><label class="crece">Costo<input class="input" name="costo" inputmode="decimal" value="${v.costo ?? ''}"></label>
        <label class="crece">Margen % <span class="muted chico" id="margen-ayuda"></span><input class="input" name="margen" inputmode="decimal" value="${v.margen != null ? +v.margen : margen(v) == null ? '' : Math.round(margen(v) * 10) / 10}"></label>
        <label class="crece">Precio de venta<input class="input" name="precio" inputmode="decimal" required value="${v.precio ?? ''}"></label></div>
      <label class="check"><input type="checkbox" name="margen_auto" ${v.margen != null ? 'checked' : ''}> Margen automático <span class="muted">(el precio sigue al costo: se recalcula solo al cargar una compra con costo nuevo)</span></label>
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
    // Costo, margen y precio conectados: el margen calcula el precio (redondeado hacia arriba como en Ajustes → Precios),
    // el precio muestra el margen que queda, y un costo nuevo mantiene el margen y propone el precio.
    const [cCosto, cMargen, cPrecio] = ['costo', 'margen', 'precio'].map(n => $(`[name=${n}]`, m.el));
    const redondeo = +(ctx.config.redondeo ?? 10);
    const precioDesdeMargen = () => {
      const c = numero(cCosto.value), mg = numero(cMargen.value);
      if (!(c > 0) || !Number.isFinite(mg) || cMargen.value.trim() === '') return;
      const x = c * (1 + mg / 100);
      cPrecio.value = String(redondeo > 0 ? Math.ceil(Math.round(x * 100) / 100 / redondeo) * redondeo : Math.round(x * 100) / 100);
      $('#margen-ayuda', m.el).textContent = redondeo > 0 ? `(redondeado a ${plata(redondeo)})` : '';
    };
    const margenDesdePrecio = () => {
      const c = numero(cCosto.value), pr = numero(cPrecio.value);
      cMargen.value = c > 0 && pr >= 0 ? String(Math.round((pr - c) / c * 1000) / 10) : '';
      $('#margen-ayuda', m.el).textContent = '';
    };
    cMargen.oninput = precioDesdeMargen;
    cPrecio.oninput = margenDesdePrecio;
    cCosto.oninput = () => { if (cMargen.value.trim() !== '') precioDesdeMargen(); else margenDesdePrecio(); };
    const campoCodigo = $('[name=codigo]', m.el);
    botonCamara(campoCodigo, { continuo: false, alLeer: c => { campoCodigo.value = c; completarDelGeneral(); } });   // 📷: el código del producto con la cámara
    // Producto nuevo con un código del catálogo general: completa lo que esté vacío (nombre, marca, contenido) y muestra el precio de referencia
    const completarDelGeneral = () => { if (!p) delCatalogoGeneral(campoCodigo.value, g => {
      const f = $('#f-prod', m.el).elements;
      if (!f.nombre.value.trim()) f.nombre.value = g.nombre;
      if (!f.marca.value.trim() && g.marca) f.marca.value = g.marca;
      if (!f.contenido.value.trim() && g.contenido) { f.contenido.value = String(+g.contenido).replace('.', ','); f.unidad.value = g.unidad; }
      if (!f.categoria_id.value && idCategoria(g.categoria)) f.categoria_id.value = idCategoria(g.categoria);   // si ya tiene esa categoría
      const ay = $('#del-general', m.el); ay.hidden = false;
      ay.textContent = `Completado desde el catálogo general${+g.precio_ref ? ` · precio de referencia en las cadenas: ${plata(g.precio_ref)}` : ''}`;
    }); };
    campoCodigo.addEventListener('change', completarDelGeneral);
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
        favorito: f.get('favorito') === 'on', ...(p ? { activo: f.get('activo') === 'on' } : {}),
        marca: f.get('marca').trim(), contenido: numero(f.get('contenido')) > 0 ? numero(f.get('contenido')) : null, unidad: f.get('unidad') };
      if (!(datos.precio >= 0)) return aviso('Revisá el precio');
      if (datos.costo > datos.precio && !confirm('El costo es mayor que el precio de venta. ¿Guardar igual?')) return;
      // margen automático: hace falta el costo; sin costo, se guarda con precio fijo (y se avisa)
      const tilde = f.get('margen_auto') === 'on', mg = numero(f.get('margen'));
      const auto = tilde && mg >= 0 && datos.costo > 0;
      correr(async () => {
        const r = await llamar('guardar_producto', { p: datos });
        if (auto || p?.margen != null) await llamar('margen_producto', { p_id: r.id, p_margen: auto ? mg : null });
        m.cerrar();
        aviso(tilde && !auto ? 'Producto guardado con precio fijo: para el margen automático hacen falta el costo y el margen' : 'Producto guardado', tilde && !auto ? 'info' : 'ok');
        await cat.actualizar(); ctx.recargar();
      });
    };
    if (p) $('#eliminar', m.el).onclick = async () => {
      if (!await confirmar('Eliminar producto', `¿Eliminar "${p.nombre}"? Si ya tiene movimientos (ventas, compras, entradas o ajustes de stock), no se borra: queda dado de baja y se conserva el historial.`, 'Eliminar')) return;
      correr(async () => { const r = await llamar('eliminar_producto', { p_id: p.id }); m.cerrar(); aviso(r.desactivado ? 'Producto dado de baja' : 'Producto eliminado', 'ok'); await cat.actualizar(); ctx.recargar(); });
    };
  }

  function categorias(lista) {
    const m = modal('Categorías', `<div id="cats"></div><form class="fila" id="f-cat"><input class="input crece" name="nombre" placeholder="Nueva categoría" maxlength="60" required><button class="btn primario">Agregar</button></form>
      <p class="muted chico">¿Recién empezás? <button type="button" class="link" id="cat-sugeridas">Crear las categorías sugeridas</button> (${CATEGORIAS.join(', ')}): son las que usa el catálogo general. Las que ya tengas no se repiten.</p>
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
    $('#cat-sugeridas', m.el).onclick = () => correr(async () => {
      const r = await llamar('crear_categorias', { p_nombres: CATEGORIAS });
      const nuevas = r.length - lista.length; lista.splice(0, lista.length, ...r); pintarCats();
      aviso(nuevas > 0 ? `Se crearon ${nuevas} categoría${nuevas === 1 ? '' : 's'}` : 'Ya tenías todas', 'ok');
      cat.actualizar().catch(() => {});
    });
    $('#f-cat', m.el).onsubmit = ev => {
      ev.preventDefault();
      correr(async () => { const r = await llamar('guardar_categoria', { p_id: null, p_nombre: new FormData(ev.target).get('nombre') }); lista.push(r); ev.target.reset(); pintarCats(); });
    };
    pintarCats();
  }
}

