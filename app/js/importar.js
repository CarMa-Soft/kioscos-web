// Importar productos desde una planilla (Excel .xlsx o CSV): para arrancar sin cargar uno por uno, o para actualizar precios
// con la lista de un proveedor. Se elige el archivo, la pantalla adivina qué columna es cada dato (se puede cambiar), muestra
// cómo va a quedar y manda las filas a importar_productos (de a 1000). Solo el dueño.
// El .xlsx se lee a mano (es un zip con XML; se abre con fflate, como el Excel de Pedidos): sin librerías de planillas.
import { llamar } from './base.js';
import * as cat from './catalogo.js';
import { $, $$, esc, plata, cant, aviso, correr, modal } from './ui.js';

// Los datos que se importan y los títulos de columna que suelen usarse para cada uno (sin tildes ni mayúsculas)
const CAMPOS = [
  ['nombre', 'Nombre', true, ['nombre', 'producto', 'descripcion', 'detalle', 'articulo', 'item']],
  ['codigo', 'Código de barras', false, ['codigo', 'cod', 'codigo de barras', 'barras', 'ean', 'sku', 'cod barra', 'codigo barra']],
  ['precio', 'Precio de venta', true, ['precio', 'precio venta', 'precio de venta', 'venta', 'pvp', 'precio final', 'precio publico', 'p venta']],
  ['costo', 'Costo', false, ['costo', 'precio costo', 'precio de costo', 'compra', 'precio compra', 'costo unitario', 'p costo']],
  ['stock', 'Stock', false, ['stock', 'cantidad', 'existencia', 'cant', 'unidades']],
  ['categoria', 'Categoría', false, ['categoria', 'rubro', 'familia', 'seccion', 'grupo']],
];
const sinTildes = s => String(s ?? '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().replace(/[^a-z0-9 ]+/g, ' ').replace(/\s+/g, ' ').trim();

// Número de una celda: los del Excel ya vienen como número; los escritos, al estilo de acá ($ 1.234,50 → 1234.50)
function aNumero(v) {
  if (typeof v === 'number') return v;
  let s = String(v ?? '').replace(/[\s$]/g, '');
  if (s === '') return null;
  if (s.includes(',')) s = s.replace(/\./g, '').replace(',', '.');
  else if (/^\d{1,3}(\.\d{3})+$/.test(s)) s = s.replace(/\./g, '');   // 1.234 → mil doscientos treinta y cuatro
  return Number.isFinite(+s) ? +s : s;   // si no es número, va como está y la base avisa en qué fila
}

// ---------- Leer el archivo ----------
async function leerPlanilla(archivo) {
  const nombre = archivo.name.toLowerCase();
  if (/\.(csv|txt)$/.test(nombre)) return leerCsv(await archivo.arrayBuffer());
  if (nombre.endsWith('.xlsx')) return leerXlsx(await archivo.arrayBuffer());
  if (nombre.endsWith('.xls') || nombre.endsWith('.ods')) throw new Error('Ese formato no se puede leer: en Excel, "Guardar como" → "Libro de Excel (.xlsx)" o "CSV", y elegí ese archivo');
  throw new Error('Elegí una planilla de Excel (.xlsx) o un archivo CSV');
}

function leerCsv(buf) {
  let texto = new TextDecoder('utf-8').decode(buf);
  if (texto.includes('�')) texto = new TextDecoder('windows-1252').decode(buf);   // CSV guardado por Excel en Windows
  texto = texto.replace(/^﻿/, '');
  const primera = texto.split(/\r?\n/, 1)[0];
  const sep = [';', '\t', ','].sort((a, b) => primera.split(b).length - primera.split(a).length)[0];
  // separador, comillas ("a;b" y "" dentro de un texto) y saltos de línea dentro de comillas
  const filas = []; let fila = [], celda = '', comillas = false;
  for (let i = 0; i < texto.length; i++) {
    const c = texto[i];
    if (comillas) {
      if (c === '"' && texto[i + 1] === '"') { celda += '"'; i++; }
      else if (c === '"') comillas = false;
      else celda += c;
    } else if (c === '"') comillas = true;
    else if (c === sep) { fila.push(celda); celda = ''; }
    else if (c === '\n' || c === '\r') { if (c === '\r' && texto[i + 1] === '\n') i++; fila.push(celda); filas.push(fila); fila = []; celda = ''; }
    else celda += c;
  }
  if (celda !== '' || fila.length) { fila.push(celda); filas.push(fila); }
  return filas;
}

async function leerXlsx(buf) {
  const { unzipSync, strFromU8 } = await import('https://cdn.jsdelivr.net/npm/fflate@0.8.3/+esm');
  let zip;
  try { zip = unzipSync(new Uint8Array(buf)); } catch { throw new Error('No se pudo abrir la planilla: ¿es un archivo de Excel (.xlsx)?'); }
  const xml = ruta => zip[ruta] ? new DOMParser().parseFromString(strFromU8(zip[ruta]), 'application/xml') : null;
  const libro = xml('xl/workbook.xml'), rels = xml('xl/_rels/workbook.xml.rels');
  if (!libro || !rels) throw new Error('No se pudo leer la planilla');
  // la primera hoja
  const rid = libro.getElementsByTagName('sheet')[0]?.getAttribute('r:id');
  const destino = [...rels.getElementsByTagName('Relationship')].find(r => r.getAttribute('Id') === rid)?.getAttribute('Target') || 'worksheets/sheet1.xml';
  const hoja = xml(destino.startsWith('/') ? destino.slice(1) : 'xl/' + destino);
  if (!hoja) throw new Error('No se pudo leer la primera hoja de la planilla');
  const textoDe = el => [...el.getElementsByTagName('t')].map(t => t.textContent).join('');
  const compartidos = [...(xml('xl/sharedStrings.xml')?.getElementsByTagName('si') || [])].map(textoDe);
  const columna = ref => [...ref.replace(/\d+/g, '')].reduce((n, l) => n * 26 + l.charCodeAt(0) - 64, 0) - 1;
  const filas = [];
  for (const r of hoja.getElementsByTagName('row')) {
    const fila = [];
    for (const c of r.getElementsByTagName('c')) {
      const tipo = c.getAttribute('t'), v = c.getElementsByTagName('v')[0]?.textContent ?? '';
      fila[columna(c.getAttribute('r') || '')] = tipo === 's' ? compartidos[+v] ?? '' : tipo === 'inlineStr' ? textoDe(c)
        : tipo === 'str' || tipo === 'b' || tipo === 'e' ? v : v === '' ? '' : +v;
    }
    filas[+r.getAttribute('r') - 1] = Array.from(fila, x => x ?? '');
  }
  return Array.from(filas, x => x ?? []);
}

// ---------- Pantalla ----------
export function importarProductos(alTerminar) {
  const m = modal('Importar productos desde una planilla', `<div id="imp-paso"></div>`, { ancho: true });
  const paso = $('#imp-paso', m.el);
  let filas = [], titulos = [], mapa = {}, inicio = 1;

  function elegir() {
    paso.innerHTML = `<p>Elegí una planilla de <b>Excel (.xlsx)</b> o un <b>CSV</b>, con una fila de títulos y un producto por fila.
        Hace falta al menos el <b>nombre</b> y el <b>precio</b>; también puede tener código de barras, costo, stock y categoría.</p>
      <label class="imp-archivo"><input type="file" id="imp-file" accept=".xlsx,.csv,.txt"><span>📂 Elegir archivo</span></label>
      <p class="muted chico">Si un producto ya existe (mismo código, o mismo nombre si no tiene código), se le actualiza el precio y el costo:
        sirve también para cargar la lista de precios nueva de un proveedor. <button class="link" id="imp-ejemplo">Bajar una planilla de ejemplo</button></p>
      <div class="fila fin"><button class="btn" data-cerrar>Cancelar</button></div>`;
    $('#imp-ejemplo', m.el).onclick = ejemplo;
    $('#imp-file', m.el).onchange = e => {
      const archivo = e.target.files[0];
      if (archivo) correr(async () => {
        filas = (await leerPlanilla(archivo)).map(f => f.map(x => typeof x === 'string' ? x.trim() : x));
        // la fila de títulos: la primera con al menos dos celdas escritas
        const k = filas.findIndex(f => f.filter(x => x !== '' && x != null).length >= 2);
        if (k < 0) throw new Error('La planilla está vacía');
        titulos = filas[k].map((t, i) => String(t || `Columna ${i + 1}`));
        inicio = k + 1;
        filas = filas.slice(inicio).map((f, i) => ({ n: inicio + i + 1, f })).filter(x => x.f.some(c => c !== '' && c != null));
        if (!filas.length) throw new Error('La planilla tiene títulos pero ningún producto');
        // adivinar las columnas por el título (primero coincidencia exacta, después que empiece igual)
        const usados = new Set();
        mapa = {};
        for (const [campo, , , sin] of CAMPOS) {
          const t = titulos.map(sinTildes);
          let i = t.findIndex((x, j) => !usados.has(j) && sin.includes(x));
          if (i < 0) i = t.findIndex((x, j) => !usados.has(j) && sin.some(s => x.startsWith(s + ' ') || x.endsWith(' ' + s)));
          mapa[campo] = i; if (i >= 0) usados.add(i);
        }
        revisar();
      });
    };
  }

  const valor = (x, campo) => mapa[campo] >= 0 ? x.f[mapa[campo]] : '';
  const armar = x => ({ fila: x.n, nombre: String(valor(x, 'nombre') ?? ''), codigo: String(valor(x, 'codigo') ?? '').replace(/\.0+$/, ''),
    precio: aNumero(valor(x, 'precio')), costo: aNumero(valor(x, 'costo')), stock: aNumero(valor(x, 'stock')), categoria: String(valor(x, 'categoria') ?? '') });

  function revisar() {
    const ver = filas.slice(0, 6).map(armar);
    const num = v => v == null || v === '' ? '' : typeof v === 'number' ? v : `<span class="mal">${esc(v)}</span>`;
    paso.innerHTML = `<p><b>${filas.length}</b> fila${filas.length === 1 ? '' : 's'} con datos. Revisá qué columna de la planilla es cada dato:</p>
      <div class="imp-mapa">${CAMPOS.map(([campo, nombre, oblig]) => `<label>${nombre}${oblig ? ' *' : ''}<select class="input" data-campo="${campo}">
        <option value="-1">${oblig ? '— elegí —' : '(no tiene)'}</option>${titulos.map((t, i) => `<option value="${i}" ${mapa[campo] === i ? 'selected' : ''}>${esc(t)}</option>`).join('')}</select></label>`).join('')}</div>
      <h3>Así se van a cargar <span class="muted chico">(las primeras ${ver.length})</span></h3>
      <div class="tabla-caja"><table class="tabla"><thead><tr><th>Fila</th><th>Nombre</th><th>Código</th><th class="num">Precio</th><th class="num">Costo</th><th class="num">Stock</th><th>Categoría</th></tr></thead><tbody>
        ${ver.map(p => `<tr><td class="muted">${p.fila}</td><td>${esc(p.nombre) || '<span class="mal">falta</span>'}</td><td class="mono">${esc(p.codigo)}</td>
          <td class="num">${typeof p.precio === 'number' ? plata(p.precio) : num(p.precio) || '<span class="mal">falta</span>'}</td><td class="num">${typeof p.costo === 'number' ? plata(p.costo) : num(p.costo)}</td>
          <td class="num">${typeof p.stock === 'number' ? cant(p.stock) : num(p.stock)}</td><td>${esc(p.categoria)}</td></tr>`).join('')}</tbody></table></div>
      <label class="check"><input type="checkbox" id="imp-actualizar" checked> Si el producto ya existe, actualizarle el precio y el costo (si no, se saltea)</label>
      <div class="fila fin"><button class="btn" id="imp-otro">Elegir otro archivo</button><button class="btn" data-cerrar>Cancelar</button>
        <button class="btn primario" id="imp-ok">Importar ${filas.length} producto${filas.length === 1 ? '' : 's'}</button></div>`;
    $$('[data-campo]', m.el).forEach(s => s.onchange = () => { mapa[s.dataset.campo] = +s.value; revisar(); });
    $('#imp-otro', m.el).onclick = elegir;
    $('#imp-ok', m.el).onclick = () => {
      if (mapa.nombre < 0 || mapa.precio < 0) return aviso('Elegí qué columna es el nombre y cuál el precio');
      const actualizar = $('#imp-actualizar', m.el).checked;
      correr(async () => {
        const todas = filas.map(armar), total = { creados: 0, actualizados: 0, salteados: 0, errores: [] };
        for (let i = 0; i < todas.length; i += 1000) {
          $('#imp-ok', m.el).textContent = `Importando… ${Math.min(i + 1000, todas.length)} de ${todas.length}`;
          const r = await llamar('importar_productos', { p_filas: todas.slice(i, i + 1000), p_actualizar: actualizar });
          total.creados += r.creados; total.actualizados += r.actualizados; total.salteados += r.salteados; total.errores.push(...r.errores);
        }
        await cat.actualizar().catch(() => {});
        resultado(total);
      });
    };
  }

  function resultado(t) {
    paso.innerHTML = `<div class="c-tarjetas">
        <div class="c-tarjeta verde"><div><div class="etq">Productos nuevos</div><div class="valor">${t.creados}</div></div></div>
        <div class="c-tarjeta"><div><div class="etq">Actualizados</div><div class="valor">${t.actualizados}</div></div></div>
        ${t.salteados ? `<div class="c-tarjeta"><div><div class="etq">Ya existían (salteados)</div><div class="valor">${t.salteados}</div></div></div>` : ''}
        ${t.errores.length ? `<div class="c-tarjeta rojo"><div><div class="etq">Con error (no se cargaron)</div><div class="valor">${t.errores.length}</div></div></div>` : ''}</div>
      ${t.errores.length ? `<h3>Filas que no se cargaron</h3><p class="muted chico">Corregilas en la planilla y volvé a importarla: lo que ya se cargó no se duplica.</p>
        <div class="tabla-caja"><table class="tabla"><thead><tr><th>Fila</th><th>Producto</th><th>Motivo</th></tr></thead><tbody>
        ${t.errores.slice(0, 100).map(e => `<tr><td>${e.fila}</td><td>${esc(e.nombre)}</td><td class="mal">${esc(e.motivo)}</td></tr>`).join('')}</tbody></table></div>
        ${t.errores.length > 100 ? `<p class="muted chico">Y ${t.errores.length - 100} más.</p>` : ''}` : ''}
      <div class="fila fin"><button class="btn primario" data-cerrar>Listo</button></div>`;
    alTerminar();
  }

  elegir();
}

// Planilla de ejemplo (CSV con ; y BOM: Excel la abre bien en castellano)
function ejemplo() {
  const texto = '﻿' + ['Nombre;Código;Precio;Costo;Stock;Categoría', 'Gaseosa cola 2,25 L;7790895000782;2500;1800;12;Bebidas',
    'Yerba mate 1 kg;7790387000307;4200;3100;6;Almacén', 'Pan francés (kg);;1800;1100;;Panadería'].join('\r\n');
  const url = URL.createObjectURL(new Blob([texto], { type: 'text/csv;charset=utf-8' }));
  const a = Object.assign(document.createElement('a'), { href: url, download: 'Productos - ejemplo.csv' });
  document.body.append(a); a.click(); a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 5000);
}
