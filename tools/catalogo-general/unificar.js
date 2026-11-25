// De juntado.json a una lista única: por código, el mejor nombre, la marca, el contenido y un precio de referencia (mediana).
// Nombre: de la cadena que mejor describe (orden de preferencia de abajo, mirando los datos); se limpian los agregados raros.
const fs = require('fs');
const { categoria } = require('./categorias.js');
const [, , ENTRADA, SALIDA] = process.argv;
const datos = JSON.parse(fs.readFileSync(ENTRADA, 'utf8'));

// cadenas (id_comercio) de la que mejor describe a la que peor: 12 y 10 nombre completo con marca y presentación;
// 2 completo con comas; 11 corto; 9 con agregados ("PAQ-20-gr."); 15 abreviado
const PREFERENCIA = ['12', '10', '2', '11', '9', '15'];
const rango = cadenas => Math.min(...cadenas.map(c => { const i = PREFERENCIA.indexOf(c); return i < 0 ? 99 : i; }));

function limpiar(t) {
  t = t.replace(/\s+[A-Z]{3}-[\d.]+-[a-zA-Z0-9]+\.?$/, '')   // cadena 9: " PAQ-20-gr."
       .replace(/\s*,\s*/g, ' ')                            // cadena 2: "X, MARCA, 20 gr"
       .replace(/\s+/g, ' ').trim();
  if (t === t.toLowerCase()) t = t.toUpperCase();
  return t;
}
// unidades parecidas → una sola
function unidad(u) {
  u = u.replace(/\.$/, '');
  if (/^(gr|grs|grm|g|gramos?)$/.test(u)) return 'g';
  if (/^(kg|kgs|kilo)$/.test(u)) return 'kg';
  if (/^(ml|cc|cm3|cm)$/.test(u)) return 'ml';
  if (/^(lt|lts|ltr|l|litro)$/.test(u)) return 'l';
  if (/^(un|uni|ud|uds|unidad|ea|u)$/.test(u)) return 'un';
  if (/^(mt|mts|m)$/.test(u)) return 'm';
  return u;
}
function contenido(pres) {
  const cuenta = new Map();
  for (const [texto, n] of pres) {
    const [cant, ...u] = texto.split(' '); let c = +cant, un = unidad(u.join(' '));
    if (!(c > 0)) continue;
    if (un === 'kg' && c < 1) { c = Math.round(c * 1000); un = 'g'; }
    if (un === 'l' && c < 1) { c = Math.round(c * 1000); un = 'ml'; }
    if (un === 'g' && c < 1) continue;   // "0.27 gr." = 270 g mal escrito: se descarta
    const k = `${+c.toFixed(3)} ${un}`;
    cuenta.set(k, (cuenta.get(k) || 0) + n);
  }
  const lista = [...cuenta].filter(([k]) => k !== '1 un');   // "1 un" no dice nada si hay otra
  const elegida = (lista.length ? lista : [...cuenta]).sort((a, b) => b[1] - a[1])[0];
  return elegida ? elegida[0] : '';
}
// El contenido escrito en el nombre ("X 930 CC", "750 ML", "1KG", "354 CMQ"): el último que aparece. Más confiable que la
// presentación, que algunas cadenas cargan siempre como "1 UNI".
function delNombre(t) {
  const ms = [...t.matchAll(/(\d+(?:[.,]\d+)?)\s*(KGS?|KILOS?|GRS?|GRM|GRAMOS|G|ML|CC|CM3|CMQ|LTS?|LTR|LITROS?|L)(?![A-Z])/gi)];
  if (!ms.length) return '';
  const [, n, u] = ms[ms.length - 1], c = +n.replace(',', '.');
  return c > 0 ? `${c} ${unidad(u.toLowerCase().replace(/^cmq$/, 'cc').replace(/^kilos?$/, 'kg').replace(/^gramos$/, 'g').replace(/^litros?$/, 'l'))}` : '';
}

function marca(marcas) {
  if (!marcas.length) return '';
  const ord = [...marcas].sort((a, b) => b[1] - a[1]);
  // "KINDE" y "KINDER": la más larga que empieza igual
  const top = ord[0][0];
  return ord.map(m => m[0]).filter(m => m.startsWith(top) || top.startsWith(m)).sort((a, b) => b.length - a.length)[0];
}

// "0000040084107" es el EAN-8 40084107 completado con ceros: el lector lee 8 dígitos
function ean8(c) { const d = c.split('').map(Number), v = d.pop(); let s = 0; d.reverse().forEach((x, i) => { s += x * (i % 2 === 0 ? 3 : 1); }); return (10 - (s % 10)) % 10 === v; }
const codigo = e => /^00000\d{8}$/.test(e) && ean8(e.slice(5)) ? e.slice(5) : e;

const filas = datos.map(p => {
  const desc = [...p.desc].sort((a, b) => rango(a[2]) - rango(b[2]) || b[1] - a[1]);
  return { codigo: codigo(p.ean), nombre: limpiar(desc[0]?.[0] || ''), marca: marca(p.marca),
    contenido: delNombre(limpiar(desc[0]?.[0] || '')) || contenido(p.pres), categoria: categoria(limpiar(desc[0]?.[0] || '')) || '', precio: p.precio, cadenas: new Set(p.desc.flatMap(d => d[2])).size };
}).filter(f => f.nombre).sort((a, b) => a.nombre.localeCompare(b.nombre, 'es'));

const csv = v => { v = String(v ?? ''); return /[;"\n]/.test(v) ? `"${v.replace(/"/g, '""')}"` : v; };
fs.writeFileSync(SALIDA, '﻿' + ['codigo;nombre;marca;contenido;precio_referencia;cadenas;categoria_sugerida',
  ...filas.map(f => [f.codigo, f.nombre, f.marca, f.contenido, f.precio != null ? String(f.precio).replace('.', ',') : '', f.cadenas, f.categoria].map(csv).join(';'))].join('\r\n'));
console.log(filas.length, 'productos');
console.log('en 2+ cadenas:', filas.filter(f => f.cadenas >= 2).length, '· sin marca:', filas.filter(f => !f.marca).length, '· sin contenido:', filas.filter(f => !f.contenido).length);
for (const ean of ['0000040084107', '7791293046914', '7791540999031']) console.log(JSON.stringify(filas.find(f => f.codigo === ean)));
filas.filter((_, i) => i % 6000 === 0).forEach(f => console.log(JSON.stringify(f)));
