// Del CSV unificado (unificar.js) a la migración con los datos del catálogo general.
// Uso (ver LEEME.md): node tools/catalogo-general/sql.js "<catalogo-general.csv>" supabase/migrations/<fecha>_catalogo_general_datos.sql
const fs = require('fs');
const [, , ENTRADA, SALIDA] = process.argv;
const lineas = fs.readFileSync(ENTRADA, 'utf8').replace(/^\uFEFF/, '').split(/\r?\n/).filter(Boolean);
const cab = lineas.shift().split(';');
// CSV con ; y comillas dobles
function partir(l) {
  const r = []; let v = '', q = false;
  for (let i = 0; i < l.length; i++) {
    const ch = l[i];
    if (q) { if (ch === '"') { if (l[i + 1] === '"') { v += '"'; i++; } else q = false; } else v += ch; }
    else if (ch === '"') q = true; else if (ch === ';') { r.push(v); v = ''; } else v += ch;
  }
  r.push(v); return r;
}
const s = v => v == null || v === '' ? 'null' : `'${String(v).replace(/'/g, "''")}'`;
const UNIDADES = new Set(['g', 'kg', 'ml', 'l', 'un', 'm']);
const filas = lineas.map(l => Object.fromEntries(partir(l).map((v, i) => [cab[i], v]))).filter(f => /^\d{8,14}$/.test(f.codigo));
const valores = filas.map(f => {
  const [c, u] = (f.contenido || '').split(' ');
  const ok = +c > 0 && UNIDADES.has(u);
  const precio = f.precio_referencia ? (+f.precio_referencia.replace(',', '.')).toFixed(2) : null;
  return `(${s(f.codigo)},${s(f.nombre.slice(0, 160))},${s(f.marca ? f.marca.slice(0, 80) : '')},${ok ? (+c).toFixed(3) : 'null'},${ok ? s(u) : 'null'},${precio ?? 'null'},${+f.cadenas || 1},${s(f.categoria_sugerida)})`;
});
let sql = `-- Datos del catálogo general: ${filas.length} productos de Precios Claros (SEPA, datos abiertos de la Secretaría de Comercio),
-- unificados por código de barras con tools/catalogo-general (ver LEEME.md). Generado: no editar a mano.
-- Para actualizarlo: una migración nueva que borra y vuelve a cargar (truncate + insert), generada igual.
`;
for (let i = 0; i < valores.length; i += 1000) {
  sql += `insert into public.catalogo_general (codigo, nombre, marca, contenido, unidad, precio_ref, cadenas, categoria) values\n${valores.slice(i, i + 1000).join(',\n')}\non conflict (codigo) do nothing;\n`;
}
fs.writeFileSync(SALIDA, sql);
console.log(filas.length, 'productos ·', Math.round(sql.length / 1024), 'KB');
