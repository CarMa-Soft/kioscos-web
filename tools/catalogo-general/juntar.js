// Junta los CSV de SEPA (Precios Claros) por código de barras: por cada EAN, sus descripciones (con cuántas filas y de
// cuántas cadenas), marca, presentación y los precios de lista (para la mediana). Guarda un JSON intermedio.
const fs = require('fs'), path = require('path'), readline = require('readline');
const DIR = process.argv[2], SALIDA = process.argv[3];

// EAN-13 / EAN-8 / UPC-A con dígito verificador válido
function eanValido(c) {
  if (!/^\d{8}$|^\d{12,14}$/.test(c)) return false;
  const d = c.split('').map(Number), v = d.pop();
  let s = 0; d.reverse().forEach((x, i) => { s += x * (i % 2 === 0 ? 3 : 1); });
  return (10 - (s % 10)) % 10 === v;
}
const normalizarEAN = c => { c = String(c || '').trim().replace(/^0+(?=\d{13}$)/, ''); if (c.length === 12) c = '0' + c; return c; };

const productos = new Map();   // ean -> { desc: Map(texto -> {filas, cadenas:Set}), marca: Map, pres: Map, precios: [] }
const stats = { filas: 0, sinEan: 0, eanInvalido: 0, internos: 0 };

async function leer(archivo) {
  const rl = readline.createInterface({ input: fs.createReadStream(archivo, { encoding: 'utf8' }), crlfDelay: Infinity });
  let cab = null;
  for await (let linea of rl) {
    if (!cab) { cab = linea.replace(/^﻿/, '').split('|'); continue; }
    const c = linea.split('|');
    if (c.length < 10) continue;   // pie ("Última actualización…") o renglón cortado
    stats.filas++;
    const r = Object.fromEntries(cab.map((k, i) => [k, c[i]]));
    if (r.productos_ean !== '1') { stats.sinEan++; continue; }
    const ean = normalizarEAN(r.id_producto);
    if (!eanValido(ean)) { stats.eanInvalido++; continue; }
    if (/^2/.test(ean) && ean.length === 13) { stats.internos++; continue; }   // prefijo 2: códigos internos o de balanza
    let p = productos.get(ean);
    if (!p) { p = { desc: new Map(), marca: new Map(), pres: new Map(), precios: [] }; productos.set(ean, p); }
    const desc = (r.productos_descripcion || '').replace(/\s+/g, ' ').trim();
    if (desc) {
      let d = p.desc.get(desc); if (!d) { d = { filas: 0, cadenas: new Set() }; p.desc.set(desc, d); }
      d.filas++; d.cadenas.add(r.id_comercio);
    }
    const marca = (r.productos_marca || '').trim().toUpperCase();
    if (marca && !/^SIN MARCA$|^GENERICO$|^VARIOS$/.test(marca)) p.marca.set(marca, (p.marca.get(marca) || 0) + 1);
    const pres = `${(+r.productos_cantidad_presentacion || 0)} ${(r.productos_unidad_medida_presentacion || '').trim().toLowerCase()}`;
    p.pres.set(pres, (p.pres.get(pres) || 0) + 1);
    const pr = +r.productos_precio_lista;
    if (pr > 0 && p.precios.length < 400) p.precios.push(pr);
  }
}

(async () => {
  const archivos = fs.readdirSync(DIR).filter(f => /\.csv$/i.test(f)).sort();
  for (const f of archivos) { const t0 = Date.now(); await leer(path.join(DIR, f)); console.error(`${f}: ${productos.size} códigos hasta acá (${Math.round((Date.now() - t0) / 1000)} s)`); }
  const out = [];
  for (const [ean, p] of productos) {
    out.push({ ean, desc: [...p.desc].map(([t, d]) => [t, d.filas, [...d.cadenas]]), marca: [...p.marca], pres: [...p.pres],
      precio: p.precios.length ? p.precios.sort((a, b) => a - b)[Math.floor(p.precios.length / 2)] : null });
  }
  fs.writeFileSync(SALIDA, JSON.stringify(out));
  console.error(JSON.stringify({ ...stats, codigos: productos.size }));
})();
