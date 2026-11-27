// Servidor local contra la BASE DE PRUEBAS: node tools/servidor-pruebas.js  →  http://localhost:5181
// Sirve la carpeta app/ igual que servidor.js, pero:
//   - /js/config.js sale armado con la dirección y la clave publishable del proyecto de pruebas;
//   - en las páginas (.html) cambia la dirección de producción por la de pruebas (Content-Security-Policy), suma
//     "PRUEBAS · " al título y una cinta naranja abajo.
// Los datos salen de .env.pruebas, en la raíz del repo (nunca se sube: .gitignore tiene .env.*):
//   SUPABASE_URL=https://<ref de pruebas>.supabase.co
//   SUPABASE_KEY=sb_publishable_...
// No arranca si falta algo, si es el proyecto de producción o si la clave no es la publishable.
const http = require('http'), fs = require('fs'), path = require('path');
const raiz = path.join(__dirname, '..'), root = path.join(raiz, 'app'), port = process.env.PORT || 5181;
const PROD = 'jmktvtbyeifrminlrhpa';

function salir(msg) { console.error('No arranca: ' + msg); process.exit(1); }

const archivoEnv = path.join(raiz, '.env.pruebas');
if (!fs.existsSync(archivoEnv)) salir('falta .env.pruebas en la raíz del repo (ver el comienzo de este archivo).');
const env = {};
for (const linea of fs.readFileSync(archivoEnv, 'utf8').split(/\r?\n/)) {
  const m = linea.match(/^\s*([A-Z_]+)\s*=\s*(.*?)\s*$/);
  if (m) env[m[1]] = m[2].replace(/^["']|["']$/g, '');
}
const URL_PRUEBAS = env.SUPABASE_URL || '', KEY_PRUEBAS = env.SUPABASE_KEY || '';
const m = URL_PRUEBAS.match(/^https:\/\/([a-z0-9]{20})\.supabase\.co$/);
if (!m) salir('SUPABASE_URL tiene que ser https://<ref>.supabase.co');
const REF = m[1];
if (REF === PROD) salir('SUPABASE_URL es el proyecto de PRODUCCIÓN.');
if (!/^sb_publishable_[A-Za-z0-9_-]+$/.test(KEY_PRUEBAS)) salir('SUPABASE_KEY tiene que ser la clave publishable (sb_publishable_…), nunca la secreta.');

const configJs = `// Generado por tools/servidor-pruebas.js: BASE DE PRUEBAS.
export const SUPABASE_URL = '${URL_PRUEBAS}';
export const SUPABASE_KEY = '${KEY_PRUEBAS}';
`;
const CINTA = '<div class="cinta-prueba">BASE DE PRUEBAS · ' + REF + '</div>';
const CSS_CINTA = '\n.cinta-prueba { position: fixed; left: 0; right: 0; bottom: 0; z-index: 200; background: #f79009; color: #fff; text-align: center; font: 600 .78rem system-ui, sans-serif; padding: .25rem .5rem; letter-spacing: .03em; pointer-events: none; }\n';

const tipos = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8', '.png': 'image/png', '.svg': 'image/svg+xml', '.json': 'application/json', '.webmanifest': 'application/manifest+json', '.ico': 'image/x-icon' };

function enviar(res, tipo, data) {
  res.writeHead(200, { 'Content-Type': tipo, 'Cache-Control': 'no-store' });
  res.end(data);
}

http.createServer((req, res) => {
  let p = decodeURIComponent(req.url.split('?')[0]);
  if (p.endsWith('/')) p += 'index.html';
  const f = path.join(root, p);
  if (f !== root && !f.startsWith(root + path.sep)) { res.writeHead(403); return res.end(); }
  const ext = path.extname(f), tipo = tipos[ext] || 'application/octet-stream';
  if (f === path.join(root, 'js', 'config.js')) return enviar(res, tipo, configJs);
  fs.readFile(f, (err, data) => {
    if (err) { res.writeHead(404); return res.end('No encontrado'); }
    if (ext === '.html') {
      const html = data.toString('utf8')
        .split(`${PROD}.supabase.co`).join(`${REF}.supabase.co`)
        .replace('<title>', '<title>PRUEBAS · ')
        .replace('<body>', '<body>' + CINTA);
      return enviar(res, tipo, html);
    }
    if (f === path.join(root, 'css', 'app.css')) return enviar(res, tipo, data.toString('utf8') + CSS_CINTA);
    enviar(res, tipo, data);
  });
}).listen(port, '127.0.0.1', () => console.log(`Kioscos y Almacenes (BASE DE PRUEBAS ${REF}) en http://localhost:${port}`));
