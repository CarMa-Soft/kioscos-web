// Catálogo general (compartido por todos los negocios): más de 60.000 productos con código de barras de Precios Claros
// (SEPA), con nombre, marca, contenido y un precio de referencia (la mediana en las cadenas). Está en la base
// (catalogo_general_buscar); no se baja entero al navegador.
// - Productos → 📦 Cargar productos (solo dueño): escanear o buscar; los del catálogo general y los que no están, en la misma lista.
// - Al crear un producto con un código (ficha, Vender, Compras): completa nombre, marca y contenido (delCatalogoGeneral).
import { llamar } from './base.js';
import * as cat from './catalogo.js';
import { $, $$, esc, plata, numero, aviso, correr } from './ui.js';
import { botonCamara } from './escaner.js';

// Las categorías sugeridas (las mismas que deduce tools/catalogo-general/categorias.js): Productos → Categorías → Crear las sugeridas
export const CATEGORIAS = ['Almacén', 'Bebidas', 'Bebidas con alcohol', 'Lácteos', 'Fiambres', 'Congelados', 'Panadería', 'Golosinas',
  'Galletitas y snacks', 'Limpieza', 'Perfumería e higiene', 'Bebés', 'Mascotas', 'Cigarrillos', 'Bazar'];
// La categoría del negocio que se llama como la sugerida (sin mayúsculas ni espacios de más), si la tiene
export const idCategoria = nombre => { const n = String(nombre || '').trim().toLowerCase(); return n ? cat.categorias().find(c => c.nombre.trim().toLowerCase() === n)?.id ?? null : null; };

export const UNIDADES = [['g', 'g'], ['kg', 'kg'], ['ml', 'ml'], ['l', 'l'], ['un', 'unid.'], ['m', 'm']];
export const textoContenido = p => p?.contenido != null && p.unidad ? `${String(+p.contenido).replace('.', ',')} ${p.unidad === 'un' ? 'unid.' : p.unidad}` : '';

// Precio por unidad de medida (obligatorio en las góndolas): por kg, por litro, por metro, o c/u si el envase trae varias
// unidades. Con el contenido del producto (500 g → el kg vale precio × 2). null si no tiene contenido o se vende por kilo.
export function precioPorUnidad(p) {
  if (!p || p.por_peso || !(+p.contenido > 0) || !p.unidad || !(+p.precio > 0)) return null;
  const c = +p.contenido, pr = +p.precio;
  const [cuanto, de] = { g: [c / 1000, 'kg'], kg: [c, 'kg'], ml: [c / 1000, 'l'], l: [c, 'l'], m: [c, 'm'], un: [c, 'unidad'] }[p.unidad] || [];
  if (!cuanto || (p.unidad === 'un' && c <= 1)) return null;   // 1 unidad: el precio ya es por unidad
  const valor = Math.round(pr / cuanto * 100) / 100;
  return { valor, de, texto: de === 'unidad' ? `${plata(valor)} c/u` : `${plata(valor)} el ${de === 'l' ? 'litro' : de === 'm' ? 'metro' : 'kg'}` };
}

// Lo del catálogo general para un código (si lo tiene): alEncontrar(g) con { codigo, nombre, marca, contenido, unidad, precio_ref }.
// Sin conexión o sin datos, no hace nada (es solo una ayuda).
export async function delCatalogoGeneral(codigo, alEncontrar) {
  const c = String(codigo || '').trim();
  if (!/^\d{8,14}$/.test(c)) return null;
  try {
    const g = (await llamar('catalogo_general_buscar', { p_texto: c, p_limite: 1 }))?.[0];
    if (g) alEncontrar?.(g);
    return g || null;
  } catch { return null; }
}
// Para mandar con el alta: marca y contenido del catálogo general
export const datosDelGeneral = g => g ? { marca: g.marca || '', contenido: g.contenido, unidad: g.unidad } : {};

// Cargar productos (solo dueño): una sola pantalla para recorrer la góndola. Se escanea (o se busca) cada producto:
// - si está en el catálogo general, va a la lista con nombre, marca y contenido;
// - si no está, va a la lista como producto nuevo (con el código leído) y se le escribe el nombre ahí mismo;
// - si el negocio ya lo tiene, avisa.
// Todos se agregan juntos (agregar_desde_catalogo, con items { nuevo: true } para los propios).
// Lo elegido se mantiene al ir y volver de la sección (mientras no se recargue la página)
const elegidos = new Map();   // clave -> { g, precio, costo, stock } (del catálogo general) o { nuevo: true, nombre, codigo, categoria_id, precio, costo, stock }
let texto = '', margenTxt = '', categoriaElegida = 'sugerida', numNuevo = 0;   // categoriaElegida: 'sugerida', '' (sin categoría) o el id de una
const esCodigoDeBarras = t => /^\d{6,14}$/.test(t);

export async function pantallaCatalogoGeneral(vista, ctx, alSalir) {
  const cats = cat.categorias();
  const redondeo = +(ctx.config.redondeo ?? 10);
  vista.innerHTML = `<div class="cabecera"><h2>Cargar productos</h2><div class="acciones"><button class="btn" id="volver">Volver a Productos</button></div></div>
    <p class="muted">Recorré la góndola y escaneá (o buscá) cada producto. Si está en el catálogo general (más de 60.000 con código de barras,
      datos públicos de Precios Claros) viene con su nombre, marca y contenido; si no está, lo cargás ahí mismo como producto nuevo.
      Todos van a la misma lista: poné tu precio (y el stock que tenés, si querés) y agregalos juntos. El precio de referencia es el que
      tenían en los supermercados (mediana, noviembre 2026): es solo una guía.</p>
    <div class="recuadro-blanco form ancho cg-buscar">
      <div class="buscador"><label class="v-busca">🔎<input class="input" id="cg-texto" placeholder="Escaneá el código o buscá por nombre, marca…" autocomplete="off" value="${esc(texto)}"></label></div>
    </div>
    <div id="cg-res"></div>
    <div id="cg-elegidos"></div>`;
  $('#volver').onclick = alSalir;
  const inp = $('#cg-texto');
  botonCamara(inp, { continuo: false, alLeer: c => porCodigo(c) });
  let pedido = 0, resultados = [], espera = null;
  const enLista = codigo => [...elegidos.entries()].find(([, x]) => (x.nuevo ? x.codigo : x.g.codigo) === codigo)?.[0];
  const categoriaNuevo = () => (categoriaElegida && categoriaElegida !== 'sugerida' ? categoriaElegida : '');
  const volverAlBuscador = () => { inp.value = ''; texto = ''; resultados = []; pintarResultados(); inp.focus(); };

  // Un código escaneado (o escrito y Enter): directo a la lista
  async function porCodigo(c) {
    c = String(c || '').trim();
    if (!c) return;
    volverAlBuscador();
    const propio = cat.porCodigoDeBarras(c);
    if (propio) return aviso(`Ya tenés "${propio.nombre}" en tus productos`, 'info');
    let k = enLista(c);
    if (k) return pintarElegidos(k);
    let g = null;
    try { g = (await llamar('catalogo_general_buscar', { p_texto: c, p_limite: 1 }))?.[0] || null; } catch { /* sin conexión: se carga como nuevo */ }
    if (g?.ya) return aviso(`Ya tenés "${g.nombre}" en tus productos`, 'info');
    if (g) {
      k = enLista(g.codigo) || g.codigo;
      if (!elegidos.has(k)) elegidos.set(k, { g, precio: '', costo: '', stock: '' });
    } else {
      k = 'n' + (++numNuevo);
      elegidos.set(k, { nuevo: true, nombre: '', codigo: c, categoria_id: categoriaNuevo(), precio: '', costo: '', stock: '' });
      aviso('No está en el catálogo general: escribile el nombre y queda como producto nuevo', 'info');
    }
    pintarElegidos(k);
  }
  function agregarNuevo(nombre = '', codigo = '') {
    const k = 'n' + (++numNuevo);
    elegidos.set(k, { nuevo: true, nombre, codigo, categoria_id: categoriaNuevo(), precio: '', costo: '', stock: '' });
    volverAlBuscador();
    pintarElegidos(k);
  }

  async function buscar() {
    texto = inp.value.trim();
    const n = ++pedido;
    if (texto.length < 2) { resultados = []; return pintarResultados(); }
    $('#cg-res').innerHTML = '<p class="muted">Buscando…</p>';
    try {
      const r = await llamar('catalogo_general_buscar', { p_texto: texto, p_limite: 60 });
      if (n !== pedido) return;   // llegó tarde: ya se escribió otra cosa
      resultados = r; pintarResultados();
    } catch (e) { if (n === pedido) $('#cg-res').innerHTML = `<p class="mal">${esc(e.message)}</p>`; }
  }
  inp.oninput = () => { clearTimeout(espera); espera = setTimeout(buscar, 350); };
  inp.onkeydown = e => {
    if (e.key !== 'Enter') return;
    e.preventDefault(); clearTimeout(espera);
    if (esCodigoDeBarras(inp.value.trim())) porCodigo(inp.value); else buscar();
  };

  function pintarResultados() {
    const cont = $('#cg-res');
    if (!texto || texto.length < 2) { cont.innerHTML = ''; return; }
    const propios = esCodigoDeBarras(texto) ? [] : cat.buscar(texto, 5);   // los que ya tiene el negocio (los propios no están en el catálogo general)
    cont.innerHTML = `${propios.length ? `<p class="muted chico cg-propios">Ya en tus productos: ${propios.map(p => `<b>${esc(p.nombre)}</b>`).join(' · ')}</p>` : ''}
      <div class="tabla-caja c-tabla"><table class="tabla">${resultados.length ? `<thead><tr><th></th><th>Producto</th><th>Código</th><th class="num">Precio de referencia</th></tr></thead><tbody>
      ${resultados.map(g => `<tr class="${g.ya ? 'cg-ya' : 'clic'}" data-cg="${esc(g.codigo)}">
        <td>${g.ya ? '<span class="cg-tengo">Ya lo tenés</span>' : `<input type="checkbox" ${enLista(g.codigo) ? 'checked' : ''} tabindex="-1">`}</td>
        <td><b>${esc(g.nombre)}</b><div class="muted chico">${[g.marca, textoContenido(g), g.categoria && `📁 ${g.categoria}`].filter(Boolean).map(esc).join(' · ')}</div></td>
        <td class="mono chico">${esc(g.codigo)}</td><td class="num">${+g.precio_ref ? plata(g.precio_ref) : '—'}</td></tr>`).join('')}</tbody>`
      : `<tbody><tr><td class="vacio muted">No hay productos con "${esc(texto)}" en el catálogo general.</td></tr></tbody>`}</table></div>
      ${resultados.length >= 60 ? '<p class="muted chico">Se muestran los primeros 60: agregá otra palabra para afinar.</p>' : ''}
      <div class="cg-manual"><button type="button" class="btn" id="cg-manual">＋ No está: cargar "${esc(texto)}" como producto nuevo</button></div>`;
    $$('tr[data-cg].clic', cont).forEach(tr => tr.onclick = () => {
      const g = resultados.find(x => x.codigo === tr.dataset.cg), k = enLista(g.codigo);
      if (k) elegidos.delete(k); else elegidos.set(g.codigo, { g, precio: '', costo: '', stock: '' });
      $('input', tr).checked = !k;
      pintarElegidos();
    });
    $('#cg-manual').onclick = () => esCodigoDeBarras(texto) ? agregarNuevo('', texto) : agregarNuevo(texto);
  }

  // el precio desde el costo con el margen (redondeado como en Ajustes → Precios)
  const conMargen = costo => {
    const c = numero(costo), mg = numero(margenTxt);
    if (!(c > 0) || !Number.isFinite(mg)) return null;
    const x = Math.round(c * (1 + mg / 100) * 100) / 100;
    return redondeo > 0 ? Math.ceil(x / redondeo) * redondeo : x;
  };
  const opcionesCategoria = sel => `<option value="">Sin categoría</option>${cats.map(c => `<option value="${c.id}" ${String(c.id) === String(sel) ? 'selected' : ''}>${esc(c.nombre)}</option>`).join('')}`;
  const filaProducto = x => x.nuevo
    ? `<span class="cg-nuevo-tag">Nuevo</span><input class="input cg-nombre" data-nombre maxlength="120" value="${esc(x.nombre)}" placeholder="Nombre del producto">
       <div class="cg-nuevo-datos"><input class="input mono" data-codigo maxlength="40" value="${esc(x.codigo)}" placeholder="Código (opcional)" autocomplete="off">
         <select class="input" data-cat title="Categoría">${opcionesCategoria(x.categoria_id)}</select></div>`
    : `<b>${esc(x.g.nombre)}</b><div class="muted chico">${[x.g.marca, textoContenido(x.g), x.g.categoria && `📁 ${x.g.categoria}`].filter(Boolean).map(esc).join(' · ')}</div>`;

  // foco: la fila recién agregada (al nombre si es nueva y no lo tiene, si no al precio)
  function pintarElegidos(foco) {
    const cont = $('#cg-elegidos'), lista = [...elegidos.entries()].reverse();   // lo último que se agregó, arriba
    if (!lista.length) { cont.innerHTML = ''; return; }
    const hayDelCatalogo = lista.some(([, x]) => !x.nuevo);
    cont.innerHTML = `<div class="c-titulo"><h3>Para agregar (${lista.length})</h3></div>
      <div class="recuadro-blanco form ancho">
        <div class="fila">
          ${hayDelCatalogo ? `<label class="crece">Categoría de los del catálogo<select class="input" id="cg-cat"><option value="sugerida" ${categoriaElegida === 'sugerida' ? 'selected' : ''}>La sugerida de cada uno (crea las que no tengas)</option><option value="" ${categoriaElegida === '' ? 'selected' : ''}>Sin categoría</option>${cats.map(c => `<option value="${c.id}" ${String(c.id) === categoriaElegida ? 'selected' : ''}>${esc(c.nombre)}</option>`).join('')}</select></label>` : ''}
          <label>Margen % sobre el costo <span class="muted">(opcional)</span><input class="input" id="cg-margen" inputmode="decimal" value="${esc(margenTxt)}" placeholder="Ej: 40"></label>
          ${hayDelCatalogo ? '<button type="button" class="btn" id="cg-ref" title="Pone el precio de referencia en los que no tienen precio">Usar los precios de referencia</button>' : ''}
        </div>
        <div class="tabla-caja"><table class="tabla cg-lista"><thead><tr><th>Producto</th><th class="num">Referencia</th><th>Costo</th><th>Tu precio</th><th title="Lo que hay hoy en el local (queda como stock inicial)">Stock</th><th></th></tr></thead><tbody>
          ${lista.map(([k, x]) => `<tr data-el="${esc(k)}" class="${x.nuevo ? 'cg-fila-nuevo' : ''}"><td>${filaProducto(x)}</td>
            <td class="num muted cg-ref ${!x.nuevo && +x.g.precio_ref ? '' : 'cg-ref-sin'}">${!x.nuevo && +x.g.precio_ref ? plata(x.g.precio_ref) : '—'}</td>
            <td data-t="Costo"><input class="input cg-num" data-costo inputmode="decimal" value="${esc(x.costo)}" placeholder="Costo"></td>
            <td data-t="Tu precio"><input class="input cg-num" data-precio inputmode="decimal" value="${esc(x.precio)}" placeholder="Precio"></td>
            <td data-t="Stock"><input class="input cg-stock" data-stock inputmode="numeric" value="${esc(x.stock)}" placeholder="0"></td>
            <td><button type="button" class="btn chico" data-sacar title="Sacar de la lista">×</button></td></tr>`).join('')}</tbody></table></div>
        <p class="muted chico">Enter pasa al campo siguiente; en el stock, vuelve al buscador para escanear el próximo.</p>
        <div class="fila fin"><button type="button" class="btn" id="cg-limpiar">Vaciar la lista</button><button type="button" class="btn primario" id="cg-agregar">Agregar ${lista.length} producto${lista.length === 1 ? '' : 's'}</button></div>
      </div>`;
    $('#cg-cat') && ($('#cg-cat').onchange = e => { categoriaElegida = e.target.value; });
    $('#cg-margen').oninput = e => {
      margenTxt = e.target.value;
      for (const x of elegidos.values()) { const pr = conMargen(x.costo); if (pr != null) x.precio = String(pr); }
      $$('tr[data-el]', cont).forEach(tr => { $('[data-precio]', tr).value = elegidos.get(tr.dataset.el).precio; });
    };
    $('#cg-ref') && ($('#cg-ref').onclick = () => { for (const x of elegidos.values()) if (!x.nuevo && !x.precio && +x.g.precio_ref) x.precio = String(+x.g.precio_ref); pintarElegidos(); });
    $('#cg-limpiar').onclick = () => { elegidos.clear(); pintarElegidos(); pintarResultados(); };
    $$('tr[data-el]', cont).forEach(tr => {
      const k = tr.dataset.el, x = elegidos.get(k);
      $('[data-costo]', tr).oninput = e => { x.costo = e.target.value; const pr = conMargen(x.costo); if (pr != null) { x.precio = String(pr); $('[data-precio]', tr).value = x.precio; } };
      $('[data-precio]', tr).oninput = e => { x.precio = e.target.value; };
      $('[data-stock]', tr).oninput = e => { x.stock = e.target.value; };
      if (x.nuevo) {
        $('[data-nombre]', tr).oninput = e => { x.nombre = e.target.value; };
        $('[data-codigo]', tr).oninput = e => { x.codigo = e.target.value.trim(); };
        $('[data-cat]', tr).onchange = e => { x.categoria_id = e.target.value; };
      }
      $('[data-sacar]', tr).onclick = () => { elegidos.delete(k); pintarElegidos(); pintarResultados(); };
      // Enter: al campo siguiente de la fila; en el último (stock), de vuelta al buscador
      const campos = $$('input', tr);
      campos.forEach((c, i) => c.addEventListener('keydown', e => {
        if (e.key !== 'Enter') return;
        e.preventDefault();
        if (campos[i + 1]) { campos[i + 1].focus(); campos[i + 1].select?.(); } else inp.focus();
      }));
    });
    if (foco && elegidos.has(foco)) {
      const tr = $$('tr[data-el]', cont).find(t => t.dataset.el === foco), x = elegidos.get(foco);
      const c = x.nuevo && !x.nombre.trim() ? $('[data-nombre]', tr) : $('[data-precio]', tr);
      tr.classList.add('cg-recien'); c.focus();
    }
    $('#cg-agregar').onclick = () => {
      const items = [...elegidos.values()], nom = x => x.nuevo ? x.nombre.trim() || 'el producto nuevo' : x.g.nombre;
      const sinNombre = items.find(x => x.nuevo && !x.nombre.trim());
      if (sinNombre) return aviso(`Falta el nombre de un producto nuevo${sinNombre.codigo ? ` (código ${sinNombre.codigo})` : ''}`);
      const sinPrecio = items.filter(x => !(numero(x.precio) > 0));
      if (sinPrecio.length) return aviso(`Falta el precio de ${sinPrecio.length === 1 ? `"${nom(sinPrecio[0])}"` : `${sinPrecio.length} productos`}`);
      const malStock = items.find(x => x.stock.trim() !== '' && !(numero(x.stock) >= 0 && Number.isInteger(numero(x.stock))));
      if (malStock) return aviso(`El stock de "${nom(malStock)}" tiene que ser un número entero (o vacío)`);
      const comunes = x => ({ precio: numero(x.precio), costo: numero(x.costo) > 0 ? numero(x.costo) : 0, stock: numero(x.stock) > 0 ? numero(x.stock) : 0 });
      correr(async () => {
        const r = await llamar('agregar_desde_catalogo', { p_items: items.map(x => x.nuevo
          ? { nuevo: true, nombre: x.nombre.trim(), codigo: x.codigo || null, categoria_id: x.categoria_id || null, ...comunes(x) }
          : { codigo: x.g.codigo, ...comunes(x), ...(categoriaElegida === 'sugerida' ? { categoria: 'sugerida' } : { categoria_id: categoriaElegida || null }) }) });
        elegidos.clear();
        await cat.actualizar().catch(() => {});   // trae también las categorías que se crearon
        aviso(`Se agregaron ${r.creados} producto${r.creados === 1 ? '' : 's'}${r.ya.length ? ` (${r.ya.length} ya los tenías)` : ''}`, 'ok');
        pintarElegidos(); volverAlBuscador();
      });
    };
  }
  pintarElegidos();
  if (texto) buscar(); else inp.focus();
}
