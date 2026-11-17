// Página del celular (celu.html#código): sacar las fotos de la factura y mandarlas a la PC. No inicia sesión: la
// autoriza el código del QR (vence a los 15 minutos, sirve para una factura). Las fotos se achican acá y van a la función
// de Supabase "subir-factura", que las lee con IA y deja el resultado para la PC.
import { SUPABASE_URL, SUPABASE_KEY } from './config.js';

const raiz = document.getElementById('app');
const codigo = location.hash.slice(1).trim().toLowerCase();
const fotos = [];   // [{ blob, url }]
const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

async function llamar(cuerpo) {
  let r;
  try {
    r = await fetch(`${SUPABASE_URL}/functions/v1/subir-factura`, {
      method: 'POST', headers: { 'Content-Type': 'application/json', apikey: SUPABASE_KEY }, body: JSON.stringify({ codigo, ...cuerpo }),
    });
  } catch { throw new Error('Sin conexión a internet: revisá los datos o el WiFi del celular'); }
  const d = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(d.error || `Error ${r.status}`);
  return d;
}

// Lado mayor 2000 px, JPEG: suben rápido y no pasan el límite de la IA
function achicar(archivo, max = 2000) {
  return new Promise((ok, mal) => {
    const img = new Image(), url = URL.createObjectURL(archivo);
    img.onload = () => {
      const k = Math.min(1, max / Math.max(img.width, img.height));
      const cv = document.createElement('canvas'); cv.width = Math.round(img.width * k); cv.height = Math.round(img.height * k);
      const g = cv.getContext('2d'); g.fillStyle = '#fff'; g.fillRect(0, 0, cv.width, cv.height); g.drawImage(img, 0, 0, cv.width, cv.height);
      URL.revokeObjectURL(url);
      cv.toBlob(b => b ? ok(b) : mal(new Error('No se pudo procesar la foto')), 'image/jpeg', 0.85);
    };
    img.onerror = () => { URL.revokeObjectURL(url); mal(new Error('El archivo no es una imagen')); };
    img.src = url;
  });
}
const enBase64 = blob => new Promise((ok, mal) => {
  const r = new FileReader();
  r.onload = () => ok(String(r.result).split(',')[1]);
  r.onerror = () => mal(new Error('No se pudo leer la foto'));
  r.readAsDataURL(blob);
});

function mensaje(titulo, texto) {
  raiz.innerHTML = `<h1>${esc(titulo)}</h1><p>${esc(texto)}</p>`;
}

function pantalla(negocio, error = '') {
  raiz.innerHTML = `<h1>Mandar la factura</h1><p class="muted">${negocio ? `Para <b>${esc(negocio)}</b>. ` : ''}Sacá una foto de cada hoja
      (hasta 5), derecha y con buena luz, y tocá <b>Mandar a la PC</b>.</p>
    <div class="celu-fotos">${fotos.map((f, i) => `<div class="celu-foto"><img src="${f.url}" alt="Hoja ${i + 1}">
      <button class="btn chico" data-quitar="${i}">Quitar</button></div>`).join('')}</div>
    ${fotos.length < 5 ? `<label class="btn grande celu-ancho">📷 ${fotos.length ? 'Sacar otra hoja' : 'Sacar foto'}
      <input type="file" id="foto" accept="image/*" capture="environment" hidden></label>` : ''}
    ${fotos.length ? '<button class="btn primario grande celu-ancho" id="mandar">Mandar a la PC</button>' : ''}
    ${error ? `<p class="mal">${esc(error)}</p>` : ''}`;
  const input = document.getElementById('foto');
  if (input) input.onchange = async () => {
    const a = input.files[0]; if (!a) return;
    try { const blob = await achicar(a); fotos.push({ blob, url: URL.createObjectURL(blob) }); pantalla(negocio); }
    catch (e) { pantalla(negocio, e.message); }
  };
  raiz.querySelectorAll('[data-quitar]').forEach(b => b.onclick = () => {
    const [f] = fotos.splice(+b.dataset.quitar, 1); URL.revokeObjectURL(f.url); pantalla(negocio);
  });
  const mandar = document.getElementById('mandar');
  if (mandar) mandar.onclick = async () => {
    const t0 = Date.now();
    const reloj = setInterval(() => { mensaje('Leyendo la factura…', `La IA la está leyendo (${Math.round((Date.now() - t0) / 1000)} s). No cierres esta página.`); }, 500);
    mensaje('Mandando…', 'Subiendo las fotos.');
    try {
      const archivos = await Promise.all(fotos.map(async f => ({ tipo: 'image/jpeg', datos: await enBase64(f.blob) })));
      const r = await llamar({ archivos });
      clearInterval(reloj);
      mensaje('¡Listo!', `La factura ya está en la PC (${r.renglones} renglones). Revisala y guardala ahí. Ya podés cerrar esta página.`);
    } catch (e) {
      clearInterval(reloj);
      pantalla(negocio, `${e.message}${/venció|no sirve/.test(e.message) ? '' : ' Podés volver a mandarla.'}`);
    }
  };
}

(async () => {
  if (!/^[0-9a-f]{48}$/.test(codigo)) return mensaje('Código incompleto', 'Escaneá de nuevo el QR que muestra la PC en Compras → Cargar desde factura → Desde el celular.');
  try {
    const r = await llamar({ revisar: true });
    if (r.estado === 'lista') return mensaje('¡Listo!', 'Esta factura ya llegó a la PC.');
    pantalla(r.negocio);
  } catch (e) { mensaje('No se puede usar este código', e.message); }
})();
