// Lista de precios (Productos → Lista de precios, solo dueño): un listado legible para imprimir o para etiquetar.
// Filtros: todos, los que llegaron en una compra (o en las compras desde una fecha), los que cambiaron de precio desde una
// fecha; además categoría, proveedor y búsqueda (lista_precios() en la base). Se puede sacar cualquier producto de la
// lista. Sale en PDF: como lista (con o sin costo, con el precio anterior) o como etiquetas para recortar (sin costo).
// En PDF (y no con imprimir del navegador): en la PC del local Chrome imprime directo en la comandera.
import { llamar } from './base.js';
import { $, $$, esc, plata, cant, dia, hoyDia, sumarDias, correr } from './ui.js';
import { precioPorUnidad } from './catalogo_general.js';

// Lo elegido se mantiene al ir y volver
const f = { modo: 'todos', compra: '', comprasDesde: sumarDias(hoyDia(), -7), precioDesde: sumarDias(hoyDia(), -7),
  categoria: '', proveedor: '', texto: '', formato: 'lista', conCosto: true, conAntes: true, conCodigo: true };

export async function pantallaListaPrecios(vista, ctx, alSalir) {
  const [cata, provs, compras] = await Promise.all([llamar('catalogo'), llamar('proveedores'), llamar('compras')]);
  const recientes = compras.filter(c => !c.anulada).slice(0, 30);
  if (f.modo === 'compras' && !f.compra) f.compra = recientes[0] ? String(recientes[0].id) : 'desde';
  let lista = [], fuera = new Set(), pedido = 0;
  const nombreCompra = c => `${c.fecha_factura ? dia(c.fecha_factura) : dia(String(c.fecha).slice(0, 10))} · ${c.proveedor || 'Sin proveedor'}${c.comprobante ? ' · ' + c.comprobante : ''} (${c.items} prod.)`;

  vista.innerHTML = `<div class="cabecera"><h2>Lista de precios</h2><div class="acciones">
      <button class="btn" id="volver">Volver a Productos</button><button class="btn primario" id="pdf">Descargar PDF</button></div></div>
    <div class="recuadro-blanco form ancho lp-filtros">
      <div class="fila">
        <label class="crece">Qué productos<select class="input" id="lp-modo">
          <option value="todos">Todos</option><option value="compras">Los que llegaron en compras</option><option value="precio">Los que cambiaron de precio</option></select></label>
        <label class="crece" id="lp-compra-l">Compra<select class="input" id="lp-compra"><option value="desde">Todas las compras desde una fecha…</option>
          ${recientes.map(c => `<option value="${c.id}">${esc(nombreCompra(c))}</option>`).join('')}</select></label>
        <label class="crece" id="lp-cdesde-l">Compras desde<input class="input" type="date" id="lp-cdesde"></label>
        <label class="crece" id="lp-pdesde-l">Cambiaron desde<input class="input" type="date" id="lp-pdesde"></label>
      </div>
      <div class="chips" id="lp-dias"><button type="button" class="chip" data-dias="0">Hoy</button><button type="button" class="chip" data-dias="7">Últimos 7 días</button>
        <button type="button" class="chip" data-dias="30">Últimos 30 días</button></div>
      <div class="fila">
        <label class="crece">Categoría<select class="input" id="lp-cat"><option value="">Todas</option>${cata.categorias.map(c => `<option value="${c.id}">${esc(c.nombre)}</option>`).join('')}</select></label>
        <label class="crece">Proveedor<select class="input" id="lp-prov"><option value="">Todos</option>${provs.map(p => `<option value="${p.id}">${esc(p.nombre)}</option>`).join('')}</select></label>
        <label class="crece">Buscar<input class="input" id="lp-texto" placeholder="Nombre o código" autocomplete="off"></label>
      </div>
      <div class="fila lp-formato">
        <label class="check"><input type="radio" name="lp-formato" value="lista"> <b>Lista</b></label>
        <label class="check"><input type="radio" name="lp-formato" value="etiquetas"> <b>Etiquetas para recortar</b> <span class="muted chico">(3 × 8 por hoja, sin costo)</span></label>
        <span class="lp-opc" data-para="lista"><label class="check"><input type="checkbox" id="lp-costo"> Con costo</label>
          <label class="check" id="lp-antes-l"><input type="checkbox" id="lp-antes"> Con el precio anterior</label></span>
        <span class="lp-opc" data-para="etiquetas"><label class="check"><input type="checkbox" id="lp-codigo"> Con el código</label></span>
      </div>
    </div>
    <p class="muted" id="lp-cuenta"></p>
    <div class="tabla-caja"><table class="tabla" id="lp-tabla"></table></div>`;

  // los campos con lo elegido
  $('#lp-modo').value = f.modo; $('#lp-compra').value = f.compra || 'desde'; $('#lp-cdesde').value = f.comprasDesde; $('#lp-pdesde').value = f.precioDesde;
  $('#lp-cat').value = f.categoria; $('#lp-prov').value = f.proveedor; $('#lp-texto').value = f.texto;
  $(`[name=lp-formato][value=${f.formato}]`).checked = true;
  $('#lp-costo').checked = f.conCosto; $('#lp-antes').checked = f.conAntes; $('#lp-codigo').checked = f.conCodigo;

  const mostrarCampos = () => {
    $('#lp-compra-l').hidden = f.modo !== 'compras';
    $('#lp-cdesde-l').hidden = !(f.modo === 'compras' && f.compra === 'desde');
    $('#lp-pdesde-l').hidden = f.modo !== 'precio';
    $('#lp-dias').hidden = !(f.modo === 'precio' || (f.modo === 'compras' && f.compra === 'desde'));
    $('#lp-antes-l').hidden = f.modo !== 'precio';
    $$('.lp-opc').forEach(o => { o.hidden = o.dataset.para !== f.formato; });
  };
  const filtros = () => ({
    categoria_id: f.categoria || null, proveedor_id: f.proveedor || null, texto: f.texto || null,
    ...(f.modo === 'compras' ? (f.compra === 'desde' ? { compras_desde: f.comprasDesde } : { compra_ids: [+f.compra] }) : {}),
    ...(f.modo === 'precio' ? { precio_desde: f.precioDesde } : {}),
  });
  const descripcion = () => [
    f.modo === 'compras' ? (f.compra === 'desde' ? `Llegaron en compras desde el ${dia(f.comprasDesde)}` : `Llegaron en la compra ${nombreCompra(recientes.find(c => String(c.id) === f.compra) || {})}`) : '',
    f.modo === 'precio' ? `Cambiaron de precio desde el ${dia(f.precioDesde)}` : '',
    f.categoria ? `Categoría ${cata.categorias.find(c => String(c.id) === f.categoria)?.nombre || ''}` : '',
    f.proveedor ? `Proveedor ${provs.find(p => String(p.id) === f.proveedor)?.nombre || ''}` : '',
    f.texto ? `"${f.texto}"` : '',
  ].filter(Boolean).join(' · ');

  const cargar = () => correr(async () => {
    const n = ++pedido;
    const r = await llamar('lista_precios', { p: filtros() });
    if (n !== pedido) return;   // llegó una respuesta vieja
    // marca y contenido salen del catálogo del negocio (para el precio por kg o litro)
    const delCat = new Map(cata.productos.map(p => [p.id, p]));
    lista = r.map(x => { const p = delCat.get(x.id); return p ? { ...x, contenido: p.contenido, unidad: p.unidad } : x; });
    fuera = new Set(); pintar();
  });
  const elegidos = () => lista.filter(x => !fuera.has(x.id));
  function pintar() {
    mostrarCampos();
    const conAntes = f.modo === 'precio';
    $('#lp-cuenta').textContent = lista.length ? `${elegidos().length} de ${lista.length} producto${lista.length === 1 ? '' : 's'} en la lista. Destildá los que no quieras imprimir.` : '';
    $('#lp-tabla').innerHTML = lista.length ? `<thead><tr><th><input type="checkbox" id="lp-todos" ${fuera.size ? '' : 'checked'} title="Todos"></th><th>Producto</th><th>Categoría</th>
        <th class="num">Costo</th>${conAntes ? '<th class="num">Antes</th>' : ''}<th class="num">Precio</th>
        ${f.modo === 'compras' ? '<th>Llegó</th>' : ''}${conAntes ? '<th>Cambió</th>' : ''}</tr></thead><tbody>
      ${lista.map(x => `<tr class="${fuera.has(x.id) ? 'lp-fuera' : ''}"><td><input type="checkbox" data-sel="${x.id}" ${fuera.has(x.id) ? '' : 'checked'}></td>
        <td><b>${esc(x.nombre)}</b>${x.codigo ? `<div class="muted chico mono">${esc(x.codigo)}</div>` : ''}</td><td>${esc(x.categoria || '')}</td>
        <td class="num">${plata(x.costo)}</td>${conAntes ? `<td class="num muted">${x.precio_antes != null ? plata(x.precio_antes) : ''}</td>` : ''}
        <td class="num"><b>${plata(x.precio)}</b>${x.por_peso ? '<span class="muted">/kg</span>' : ''}</td>
        ${f.modo === 'compras' ? `<td>${x.llego ? dia(String(x.llego).slice(0, 10)) : ''}</td>` : ''}${conAntes ? `<td>${x.cambio ? dia(String(x.cambio).slice(0, 10)) : ''}</td>` : ''}</tr>`).join('')}</tbody>`
      : '<tbody><tr><td class="muted vacio">No hay productos con estos filtros.</td></tr></tbody>';
    $$('[data-sel]').forEach(c => c.onchange = () => { if (c.checked) fuera.delete(+c.dataset.sel); else fuera.add(+c.dataset.sel); pintar(); });
    if ($('#lp-todos')) $('#lp-todos').onchange = e => { fuera = e.target.checked ? new Set() : new Set(lista.map(x => x.id)); pintar(); };
  }

  $('#volver').onclick = alSalir;
  $('#lp-modo').onchange = e => { f.modo = e.target.value; if (f.modo === 'compras' && !f.compra) f.compra = recientes[0] ? String(recientes[0].id) : 'desde'; cargar(); };
  $('#lp-compra').onchange = e => { f.compra = e.target.value; cargar(); };
  $('#lp-cdesde').onchange = e => { f.comprasDesde = e.target.value || hoyDia(); cargar(); };
  $('#lp-pdesde').onchange = e => { f.precioDesde = e.target.value || hoyDia(); cargar(); };
  $$('[data-dias]').forEach(b => b.onclick = () => {
    const d = sumarDias(hoyDia(), -b.dataset.dias);
    if (f.modo === 'precio') { f.precioDesde = d; $('#lp-pdesde').value = d; } else { f.comprasDesde = d; $('#lp-cdesde').value = d; }
    cargar();
  });
  $('#lp-cat').onchange = e => { f.categoria = e.target.value; cargar(); };
  $('#lp-prov').onchange = e => { f.proveedor = e.target.value; cargar(); };
  let espera;
  $('#lp-texto').oninput = e => { f.texto = e.target.value.trim(); clearTimeout(espera); espera = setTimeout(cargar, 350); };
  $$('[name=lp-formato]').forEach(r => r.onchange = () => { f.formato = r.value; mostrarCampos(); });
  $('#lp-costo').onchange = e => { f.conCosto = e.target.checked; };
  $('#lp-antes').onchange = e => { f.conAntes = e.target.checked; };
  $('#lp-codigo').onchange = e => { f.conCodigo = e.target.checked; };
  $('#pdf').onclick = () => correr(async () => {
    const xs = elegidos();
    if (!xs.length) throw new Error('No hay productos para imprimir');
    if (f.formato === 'etiquetas') await pdfEtiquetas(xs, ctx.negocio.nombre);
    else await pdfLista(xs, ctx.negocio.nombre, descripcion());
  });
  mostrarCampos();
  cargar();
}

const jspdf = async () => {
  const [{ jsPDF }, { autoTable }] = await Promise.all([import('https://cdn.jsdelivr.net/npm/jspdf@4.2.1/+esm'),
    import('https://cdn.jsdelivr.net/npm/jspdf-autotable@5.0.9/+esm')]);
  return { jsPDF, autoTable };
};
const archivo = (nombre) => `${nombre} ${hoyDia()}.pdf`.replace(/[\\/:*?"<>|]/g, '-');

async function pdfLista(xs, negocio, filtro) {
  const { jsPDF, autoTable } = await jspdf();
  const conAntes = f.modo === 'precio' && f.conAntes;
  const doc = new jsPDF({ unit: 'mm', format: 'a4' });
  doc.setFontSize(16); doc.text('Lista de precios', 14, 17);
  doc.setFontSize(10); doc.text(`${negocio} · ${dia(hoyDia())} · ${xs.length} producto${xs.length === 1 ? '' : 's'}`, 14, 23);
  if (filtro) doc.text(doc.splitTextToSize(filtro, 180), 14, 28);
  const porUnidad = xs.some(x => precioPorUnidad(x));   // la columna, solo si alguno tiene contenido cargado
  const cab = ['Producto', 'Código', 'Categoría', ...(f.conCosto ? ['Costo'] : []), ...(conAntes ? ['Antes'] : []), ...(porUnidad ? ['Por kg / l'] : []), 'Precio'];
  autoTable(doc, {
    startY: filtro ? 33 : 28, head: [cab],
    body: xs.map(x => [x.nombre, x.codigo || '', x.categoria || '', ...(f.conCosto ? [plata(x.costo)] : []),
      ...(conAntes ? [x.precio_antes != null ? plata(x.precio_antes) : ''] : []), ...(porUnidad ? [precioPorUnidad(x)?.texto || ''] : []), plata(x.precio) + (x.por_peso ? ' /kg' : '')]),
    styles: { fontSize: 10, cellPadding: 2 }, headStyles: { fillColor: [31, 41, 51] },
    columnStyles: Object.fromEntries(cab.map((c, k) => [k, ['Costo', 'Antes', 'Precio', 'Por kg / l'].includes(c) ? { halign: 'right' } : {}])
      .concat([[cab.length - 1, { halign: 'right', fontStyle: 'bold', fontSize: 11, minCellWidth: 34 }]])),
  });
  doc.save(archivo('Lista de precios'));
}

// Etiquetas: 3 columnas × 8 filas en A4, con borde para recortar. Nombre (hasta 2 renglones), precio grande, el precio por kg o
// litro (obligatorio en la góndola, si el producto tiene contenido) y el código.
async function pdfEtiquetas(xs, negocio) {
  const { jsPDF } = await jspdf();
  const doc = new jsPDF({ unit: 'mm', format: 'a4' });
  const COL = 3, FIL = 8, MX = 8, MY = 10, G = 2;
  const W = (210 - 2 * MX - (COL - 1) * G) / COL, H = (297 - 2 * MY - (FIL - 1) * G) / FIL;
  xs.forEach((x, k) => {
    const i = k % (COL * FIL);
    if (k > 0 && i === 0) doc.addPage();
    const cx = MX + (i % COL) * (W + G), cy = MY + Math.floor(i / COL) * (H + G);
    doc.setDrawColor(190); doc.setLineWidth(0.2); doc.roundedRect(cx, cy, W, H, 2, 2);
    doc.setFont('helvetica', 'bold'); doc.setFontSize(10); doc.setTextColor(20);
    doc.text(doc.splitTextToSize(x.nombre, W - 6).slice(0, 2), cx + 3, cy + 6);
    doc.setFontSize(22);
    const precio = plata(x.precio);
    doc.text(precio, cx + W - 3, cy + H - 9, { align: 'right' });
    if (x.por_peso) { doc.setFontSize(9); doc.text('por kg', cx + W - 3, cy + H - 4, { align: 'right' }); }
    const pu = precioPorUnidad(x);
    if (pu) { doc.setFont('helvetica', 'normal'); doc.setFontSize(8); doc.text(pu.texto, cx + W - 3, cy + H - 3.5, { align: 'right' }); }
    doc.setFont('helvetica', 'normal'); doc.setFontSize(7); doc.setTextColor(110);
    if (f.conCodigo && x.codigo) doc.text(x.codigo, cx + 3, cy + H - 3);
  });
  doc.save(archivo(`Etiquetas ${negocio}`));
}
