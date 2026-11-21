// Pedidos a proveedores (solo dueño): los productos con stock bajo o sin stock, reunidos por proveedor (pedidos() en la base).
// Se cambia la cantidad, el proveedor (queda como el habitual del producto) o se quita (pasa a "Pendientes de pedir").
// Cada pedido se exporta a PDF, a Excel o se manda por WhatsApp. No se marca como recibido: al cargar la compra, lo que
// llegó y supera el mínimo sale solo del pedido.
import { llamar } from './base.js';
import { $, $$, esc, plata, cant, dia, hoyDia, numero, aviso, correr, telefonoWhatsApp } from './ui.js';

let conPrecios = false;   // los precios de referencia en el PDF y el Excel (por si se los manda al proveedor)

const referencia = i => i.ultimo_costo != null ? +i.ultimo_costo : +i.costo;
const subtotal = i => Math.round(referencia(i) * +i.cantidad * 100) / 100;
const unidad = i => i.por_peso ? 'kg' : 'u.';
const nombreArchivo = (prov) => `Pedido ${prov} ${hoyDia()}`.replace(/[\\/:*?"<>|]/g, '-');

export async function pantallaPedidos(vista, ctx) {
  const [p, provs] = await Promise.all([llamar('pedidos'), llamar('proveedores')]);
  const grupos = [...p.proveedores.map(g => ({ ...g, items: g.items || [] })),
    ...(p.sin_proveedor.length ? [{ id: null, nombre: 'Sin proveedor', items: p.sin_proveedor }] : [])];
  const total = grupos.reduce((s, g) => s + g.items.length, 0);
  vista.innerHTML = `<div class="cabecera"><h2>Pedidos</h2><div class="acciones">
      <label class="check"><input type="checkbox" id="con-precios" ${conPrecios ? 'checked' : ''}> Precios de referencia en el PDF y el Excel</label></div></div>
    <p class="muted">Los productos con stock bajo o sin stock, por proveedor. Al cargar la compra, lo que llegó sale solo del pedido.</p>
    ${total ? '' : '<div class="recuadro-blanco"><p class="muted vacio">No hay nada para pedir: ningún producto está por debajo de su mínimo ni sin stock.</p></div>'}
    ${grupos.map((g, k) => `<section class="recuadro-blanco pedido ${g.id ? '' : 'sin-prov'}" data-g="${k}">
      <div class="cabecera"><h3>${esc(g.nombre)} <span class="muted">· ${g.items.length} producto${g.items.length === 1 ? '' : 's'} · estimado <b data-total="${k}">${plata(g.items.reduce((s, i) => s + subtotal(i), 0))}</b></span></h3>
        ${g.id ? `<div class="acciones"><button class="btn chico" data-pdf="${k}">PDF</button><button class="btn chico" data-xlsx="${k}">Excel</button>
          <button class="btn chico primario" data-wa="${k}">WhatsApp</button></div>` : '<span class="etiqueta pendiente">Elegí el proveedor de cada uno</span>'}</div>
      ${tabla(g.items, provs, k)}</section>`).join('')}
    ${p.pendientes.length ? `<section class="recuadro-blanco pedido pendientes"><div class="cabecera"><h3>Pendientes de pedir <span class="muted">· los quitaste de su pedido</span></h3></div>
      <div class="tabla-caja"><table class="tabla"><thead><tr><th>Producto</th><th class="num">Stock</th><th>Proveedor</th><th></th></tr></thead><tbody>
        ${p.pendientes.map(i => `<tr><td>${esc(i.nombre)}</td><td class="num">${estadoStock(i)}</td><td>${esc(i.proveedor || 'Sin proveedor')}</td>
          <td class="num"><button class="btn chico" data-volver="${i.producto_id}">Volver al pedido</button></td></tr>`).join('')}</tbody></table></div></section>` : ''}`;

  $('#con-precios').onchange = e => { conPrecios = e.target.checked; };
  // cantidad: se guarda al salir del campo; el subtotal y el total se actualizan sin recargar
  $$('[data-cant]').forEach(inp => {
    inp.onfocus = () => inp.select();
    inp.onchange = () => {
      const [k, n] = inp.dataset.cant.split('-').map(Number), i = grupos[k].items[n];
      const v = inp.value.trim() === '' ? null : numero(inp.value);
      if (v !== null && !(v > 0)) { inp.value = cant(i.cantidad); return aviso('La cantidad tiene que ser mayor a 0'); }
      correr(async () => {
        await llamar('pedido_cantidad', { p_producto_id: i.producto_id, p_cantidad: v });
        i.cantidad = v ?? i.propuesta; inp.value = cant(i.cantidad);
        $(`[data-sub="${k}-${n}"]`).textContent = plata(subtotal(i));
        $(`[data-total="${k}"]`).textContent = plata(grupos[k].items.reduce((s, x) => s + subtotal(x), 0));
      });
    };
    inp.onkeydown = e => { if (e.key === 'Enter') { e.preventDefault(); inp.blur(); } };
  });
  $$('[data-prov]').forEach(s => s.onchange = () => {
    const [k, n] = s.dataset.prov.split('-').map(Number), i = grupos[k].items[n];
    if (!s.value) return;
    correr(async () => {
      await llamar('pedido_proveedor', { p_producto_id: i.producto_id, p_proveedor_id: +s.value });
      aviso(`${i.nombre} pasó al pedido de ${provs.find(x => x.id === +s.value)?.nombre}`, 'ok');
      ctx.recargar();
    });
  });
  $$('[data-quitar]').forEach(b => b.onclick = () => {
    const [k, n] = b.dataset.quitar.split('-').map(Number), i = grupos[k].items[n];
    correr(async () => { await llamar('pedido_pendiente', { p_producto_id: i.producto_id, p_pendiente: true }); ctx.recargar(); });
  });
  $$('[data-volver]').forEach(b => b.onclick = () => correr(async () => {
    await llamar('pedido_pendiente', { p_producto_id: +b.dataset.volver, p_pendiente: false }); ctx.recargar();
  }));
  $$('[data-wa]').forEach(b => b.onclick = () => whatsapp(grupos[+b.dataset.wa], p.negocio));
  $$('[data-pdf]').forEach(b => b.onclick = () => correr(() => pdf(grupos[+b.dataset.pdf], p.negocio)));
  $$('[data-xlsx]').forEach(b => b.onclick = () => correr(() => excel(grupos[+b.dataset.xlsx], p.negocio)));
}

const estadoStock = i => `${cant(i.stock)}${i.por_peso ? ' kg' : ''}${+i.stock_min > 0 ? `<div class="muted chico">mínimo ${cant(i.stock_min)}</div>` : ''}
  ${i.sin_stock ? '<span class="etiqueta alerta">sin stock</span>' : '<span class="etiqueta pendiente">stock bajo</span>'}`;

function tabla(items, provs, k) {
  return `<div class="tabla-caja"><table class="tabla"><thead><tr><th>Producto</th><th class="num">Stock</th><th class="num">A pedir</th>
      <th class="num">Último precio</th><th class="num">Subtotal</th><th>Proveedor</th><th></th></tr></thead><tbody>
    ${items.map((i, n) => `<tr><td><b>${esc(i.nombre)}</b>${i.codigo_proveedor || i.codigo ? `<div class="muted chico mono">${i.codigo_proveedor ? `cód. prov. ${esc(i.codigo_proveedor)}` : esc(i.codigo)}</div>` : ''}
      ${+i.para_entregar > 0 ? `<div class="para-entregar">📦 Para entregar: ${esc(i.entregas || cant(i.para_entregar))}</div>` : ''}</td>
      <td class="num">${estadoStock(i)}</td>
      <td class="num"><input class="input cant" data-cant="${k}-${n}" value="${cant(i.cantidad)}" inputmode="decimal" title="Vacío = la propuesta (${cant(i.propuesta)})">
        <div class="muted chico">${unidad(i)}</div></td>
      <td class="num">${plata(referencia(i))}<div class="muted chico">${i.ultimo_costo != null ? (i.ultima_compra ? dia(String(i.ultima_compra).slice(0, 10)) : 'última compra') : 'costo actual'}</div></td>
      <td class="num" data-sub="${k}-${n}">${plata(subtotal(i))}</td>
      <td><select class="input" data-prov="${k}-${n}">${i.proveedor_id ? '' : '<option value="">Elegí…</option>'}
        ${provs.map(x => `<option value="${x.id}" ${x.id === i.proveedor_id ? 'selected' : ''}>${esc(x.nombre)}</option>`).join('')}</select></td>
      <td class="num"><button class="link" data-quitar="${k}-${n}" title="Pasa a Pendientes de pedir">Quitar</button></td></tr>`).join('')}</tbody></table></div>`;
}

// ---------- Exportar ----------
const lineaTexto = i => `${cant(i.cantidad)}${i.por_peso ? ' kg' : ''} x ${i.nombre}${i.codigo_proveedor ? ` (cód. ${i.codigo_proveedor})` : ''}`;

// WhatsApp: el texto del pedido, al número del proveedor si lo tiene (si no, se elige el contacto en WhatsApp)
function whatsapp(g, negocio) {
  const texto = `Hola${g.nombre ? ' ' + g.nombre : ''}! Te paso el pedido de ${negocio}:\n\n${g.items.map(i => '• ' + lineaTexto(i)).join('\n')}\n\nGracias!`;
  const num = telefonoWhatsApp(g.telefono);
  window.open(`https://wa.me/${num}?text=${encodeURIComponent(texto)}`, '_blank', 'noopener');
  if (!num) aviso('El proveedor no tiene un teléfono cargado: elegí el contacto en WhatsApp', 'info');
}

// Filas del pedido para el PDF y el Excel
function filas(g) {
  const cab = ['Cantidad', 'Unidad', 'Producto', 'Cód. proveedor', ...(conPrecios ? ['Último precio', 'Subtotal'] : [])];
  const cuerpo = g.items.map(i => [+i.cantidad, unidad(i), i.nombre, i.codigo_proveedor || '', ...(conPrecios ? [referencia(i), subtotal(i)] : [])]);
  return { cab, cuerpo, total: g.items.reduce((s, i) => s + subtotal(i), 0) };
}

async function pdf(g, negocio) {
  const [{ jsPDF }, { autoTable }] = await Promise.all([import('https://cdn.jsdelivr.net/npm/jspdf@4.2.1/+esm'),
    import('https://cdn.jsdelivr.net/npm/jspdf-autotable@5.0.9/+esm')]);
  const { cab, cuerpo, total } = filas(g);
  const doc = new jsPDF({ unit: 'mm', format: 'a4' });
  doc.setFontSize(16); doc.text(`Pedido a ${g.nombre}`, 14, 18);
  doc.setFontSize(10); doc.text(`${negocio} · ${dia(hoyDia())}`, 14, 25);
  autoTable(doc, {
    startY: 31, head: [cab],
    body: cuerpo.map(f => f.map((v, c) => c === 0 ? cant(v) : c >= 4 ? plata(v) : v)),
    foot: conPrecios ? [['', '', '', 'Total estimado', '', plata(total)]] : undefined,
    styles: { fontSize: 10 }, headStyles: { fillColor: [31, 41, 51] }, footStyles: { fillColor: [245, 246, 248], textColor: 20 },
    columnStyles: { 0: { halign: 'right' }, 4: { halign: 'right' }, 5: { halign: 'right' } },
  });
  doc.save(nombreArchivo(g.nombre) + '.pdf');
}

// Excel (.xlsx) armado a mano: una hoja con el pedido, comprimida con fflate (sin librerías que usen workers)
async function excel(g, negocio) {
  const { zipSync, strToU8 } = await import('https://cdn.jsdelivr.net/npm/fflate@0.8.3/+esm');
  const { cab, cuerpo, total } = filas(g);
  const x = s => String(s).replace(/[<>&"]/g, c => ({ '<': '&lt;', '>': '&gt;', '&': '&amp;', '"': '&quot;' }[c]));
  const col = n => String.fromCharCode(65 + n);
  const celda = (v, ref, estilo = 0) => typeof v === 'number'
    ? `<c r="${ref}" s="${estilo}"><v>${v}</v></c>` : `<c r="${ref}" t="inlineStr" s="${estilo}"><is><t>${x(v)}</t></is></c>`;
  const filasXml = [[`Pedido a ${g.nombre}`], [`${negocio} · ${dia(hoyDia())}`], [], cab, ...cuerpo,
    ...(conPrecios ? [[], ['', '', '', '', 'Total estimado', total]] : [])]
    .map((f, r) => `<row r="${r + 1}">${f.map((v, c) => v === '' ? '' : celda(v, col(c) + (r + 1), r === 0 || r === 3 ? 1 : 0)).join('')}</row>`).join('');
  const archivos = {
    '[Content_Types].xml': `<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>`,
    '_rels/.rels': `<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>`,
    'xl/workbook.xml': `<?xml version="1.0" encoding="UTF-8" standalone="yes"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Pedido" sheetId="1" r:id="rId1"/></sheets></workbook>`,
    'xl/_rels/workbook.xml.rels': `<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>`,
    'xl/styles.xml': `<?xml version="1.0" encoding="UTF-8" standalone="yes"?><styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts><fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills><borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/></cellXfs></styleSheet>`,
    'xl/worksheets/sheet1.xml': `<?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><cols><col min="1" max="2" width="10" customWidth="1"/><col min="3" max="3" width="40" customWidth="1"/><col min="4" max="6" width="16" customWidth="1"/></cols><sheetData>${filasXml}</sheetData></worksheet>`,
  };
  const zip = zipSync(Object.fromEntries(Object.entries(archivos).map(([k, v]) => [k, strToU8(v)])));
  const url = URL.createObjectURL(new Blob([zip], { type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' }));
  const a = Object.assign(document.createElement('a'), { href: url, download: nombreArchivo(g.nombre) + '.xlsx' });
  document.body.append(a); a.click(); a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 5000);
}
