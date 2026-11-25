// Catálogo general (compartido por todos los negocios): más de 60.000 productos con código de barras de Precios Claros
// (SEPA), con nombre, marca, contenido y un precio de referencia (la mediana en las cadenas). Está en la base
// (catalogo_general_buscar); no se baja entero al navegador.
// - Productos → 📚 Agregar desde el catálogo general (solo dueño): buscar, elegir, poner precio y agregarlos.
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

// Lo elegido se mantiene al ir y volver de la sección (mientras no se recargue la página)
const elegidos = new Map();   // codigo -> { g, precio, costo }
let texto = '', margenTxt = '', categoriaElegida = 'sugerida';   // 'sugerida', '' (sin categoría) o el id de una

export async function pantallaCatalogoGeneral(vista, ctx, alSalir) {
  const cats = cat.categorias();
  const redondeo = +(ctx.config.redondeo ?? 10);
  vista.innerHTML = `<div class="cabecera"><h2>Catálogo general</h2><div class="acciones"><button class="btn" id="volver">Volver a Productos</button></div></div>
    <p class="muted">Más de 60.000 productos con código de barras (datos públicos de Precios Claros). Buscá los que vendés, tildalos,
      poné tu precio y agregalos: quedan en tus productos con su código, nombre, marca y contenido. El precio de referencia es el que
      tenían en los supermercados (mediana, noviembre 2026): es solo una guía.</p>
    <div class="recuadro-blanco form ancho cg-buscar">
      <div class="buscador"><label class="v-busca">🔎<input class="input" id="cg-texto" placeholder="Buscá por nombre, marca o código: yerba taragui, coca 2,25…" autocomplete="off" value="${esc(texto)}"></label></div>
    </div>
    <div id="cg-res"></div>
    <div id="cg-elegidos"></div>`;
  $('#volver').onclick = alSalir;
  const inp = $('#cg-texto');
  botonCamara(inp, { continuo: false, alLeer: c => { inp.value = c; buscar(); } });
  let pedido = 0, resultados = [], espera = null;

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
  inp.onkeydown = e => { if (e.key === 'Enter') { e.preventDefault(); clearTimeout(espera); buscar(); } };

  function pintarResultados() {
    const cont = $('#cg-res');
    if (!texto || texto.length < 2) { cont.innerHTML = ''; return; }
    cont.innerHTML = `<div class="tabla-caja c-tabla"><table class="tabla">${resultados.length ? `<thead><tr><th></th><th>Producto</th><th>Código</th><th class="num">Precio de referencia</th></tr></thead><tbody>
      ${resultados.map(g => `<tr class="${g.ya ? 'cg-ya' : 'clic'}" data-cg="${esc(g.codigo)}">
        <td>${g.ya ? '<span class="cg-tengo">Ya lo tenés</span>' : `<input type="checkbox" ${elegidos.has(g.codigo) ? 'checked' : ''} tabindex="-1">`}</td>
        <td><b>${esc(g.nombre)}</b><div class="muted chico">${[g.marca, textoContenido(g), g.categoria && `📁 ${g.categoria}`].filter(Boolean).map(esc).join(' · ')}</div></td>
        <td class="mono chico">${esc(g.codigo)}</td><td class="num">${+g.precio_ref ? plata(g.precio_ref) : '—'}</td></tr>`).join('')}</tbody>`
      : `<tbody><tr><td class="vacio muted">No hay productos con "${esc(texto)}" en el catálogo general.</td></tr></tbody>`}</table></div>
      ${resultados.length >= 60 ? '<p class="muted chico">Se muestran los primeros 60: agregá otra palabra para afinar.</p>' : ''}`;
    $$('tr[data-cg].clic', cont).forEach(tr => tr.onclick = () => {
      const g = resultados.find(x => x.codigo === tr.dataset.cg);
      if (elegidos.has(g.codigo)) elegidos.delete(g.codigo); else elegidos.set(g.codigo, { g, precio: '', costo: '' });
      $('input', tr).checked = elegidos.has(g.codigo);
      pintarElegidos();
    });
  }

  // el precio desde el costo con el margen (redondeado como en Ajustes → Precios)
  const conMargen = costo => {
    const c = numero(costo), mg = numero(margenTxt);
    if (!(c > 0) || !Number.isFinite(mg)) return null;
    const x = Math.round(c * (1 + mg / 100) * 100) / 100;
    return redondeo > 0 ? Math.ceil(x / redondeo) * redondeo : x;
  };
  function pintarElegidos() {
    const cont = $('#cg-elegidos'), lista = [...elegidos.values()];
    if (!lista.length) { cont.innerHTML = ''; return; }
    cont.innerHTML = `<div class="c-titulo"><h3>Para agregar (${lista.length})</h3></div>
      <div class="recuadro-blanco form ancho">
        <div class="fila">
          <label class="crece">Categoría<select class="input" id="cg-cat"><option value="sugerida" ${categoriaElegida === 'sugerida' ? 'selected' : ''}>La sugerida de cada uno (crea las que no tengas)</option><option value="" ${categoriaElegida === '' ? 'selected' : ''}>Sin categoría</option>${cats.map(c => `<option value="${c.id}" ${String(c.id) === categoriaElegida ? 'selected' : ''}>${esc(c.nombre)}</option>`).join('')}</select></label>
          <label>Margen % sobre el costo <span class="muted">(opcional)</span><input class="input" id="cg-margen" inputmode="decimal" value="${esc(margenTxt)}" placeholder="Ej: 40"></label>
          <button type="button" class="btn" id="cg-ref" title="Pone el precio de referencia en los que no tienen precio">Usar los precios de referencia</button>
        </div>
        <div class="tabla-caja"><table class="tabla"><thead><tr><th>Producto</th><th class="num">Referencia</th><th>Costo</th><th>Tu precio</th><th></th></tr></thead><tbody>
          ${lista.map(x => `<tr data-el="${esc(x.g.codigo)}"><td><b>${esc(x.g.nombre)}</b><div class="muted chico">${[x.g.marca, textoContenido(x.g), x.g.categoria && `📁 ${x.g.categoria}`].filter(Boolean).map(esc).join(' · ')}</div></td>
            <td class="num muted">${+x.g.precio_ref ? plata(x.g.precio_ref) : '—'}</td>
            <td><input class="input cg-num" data-costo inputmode="decimal" value="${esc(x.costo)}" placeholder="Costo"></td>
            <td><input class="input cg-num" data-precio inputmode="decimal" value="${esc(x.precio)}" placeholder="Precio"></td>
            <td><button type="button" class="btn chico" data-sacar title="Sacar de la lista">×</button></td></tr>`).join('')}</tbody></table></div>
        <div class="fila fin"><button type="button" class="btn" id="cg-limpiar">Vaciar la lista</button><button type="button" class="btn primario" id="cg-agregar">Agregar ${lista.length} producto${lista.length === 1 ? '' : 's'}</button></div>
      </div>`;
    $('#cg-cat').onchange = e => { categoriaElegida = e.target.value; };
    $('#cg-margen').oninput = e => {
      margenTxt = e.target.value;
      for (const x of elegidos.values()) { const pr = conMargen(x.costo); if (pr != null) x.precio = String(pr); }
      $$('tr[data-el]', cont).forEach(tr => { $('[data-precio]', tr).value = elegidos.get(tr.dataset.el).precio; });
    };
    $('#cg-ref').onclick = () => { for (const x of elegidos.values()) if (!x.precio && +x.g.precio_ref) x.precio = String(+x.g.precio_ref); pintarElegidos(); };
    $('#cg-limpiar').onclick = () => { elegidos.clear(); pintarElegidos(); pintarResultados(); };
    $$('tr[data-el]', cont).forEach(tr => {
      const x = elegidos.get(tr.dataset.el);
      $('[data-costo]', tr).oninput = e => { x.costo = e.target.value; const pr = conMargen(x.costo); if (pr != null) { x.precio = String(pr); $('[data-precio]', tr).value = x.precio; } };
      $('[data-precio]', tr).oninput = e => { x.precio = e.target.value; };
      $('[data-sacar]', tr).onclick = () => { elegidos.delete(x.g.codigo); pintarElegidos(); pintarResultados(); };
    });
    $('#cg-agregar').onclick = () => {
      const items = [...elegidos.values()];
      const sinPrecio = items.filter(x => !(numero(x.precio) > 0));
      if (sinPrecio.length) return aviso(`Falta el precio de ${sinPrecio.length === 1 ? `"${sinPrecio[0].g.nombre}"` : `${sinPrecio.length} productos`}`);
      correr(async () => {
        const r = await llamar('agregar_desde_catalogo', { p_items: items.map(x => ({ codigo: x.g.codigo, precio: numero(x.precio),
          costo: numero(x.costo) > 0 ? numero(x.costo) : 0, ...(categoriaElegida === 'sugerida' ? { categoria: 'sugerida' } : { categoria_id: categoriaElegida || null }) })) });
        elegidos.clear();
        await cat.actualizar().catch(() => {});   // trae también las categorías que se crearon
        aviso(`Se agregaron ${r.creados} producto${r.creados === 1 ? '' : 's'}${r.ya.length ? ` (${r.ya.length} ya los tenías)` : ''}`, 'ok');
        pintarElegidos(); buscar();
      });
    };
  }
  pintarElegidos();
  if (texto) buscar(); else inp.focus();
}
