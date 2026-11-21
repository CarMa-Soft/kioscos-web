// Escanear códigos de barras con la cámara del celular, sin lector. Usa el lector que trae el navegador (BarcodeDetector:
// Chrome en Android); donde no está (la PC con Windows, Safari en iPhone) el botón 📷 no aparece y todo sigue igual.
// botonCamara(input) agrega 📷 junto a un campo de escanear: cada código leído se pone en el campo y se "aprieta" Enter,
// así la pantalla lo procesa igual que con el lector de la PC (agrega el producto, avisa si no existe, etc.).
// El mismo código dos veces seguidas NUNCA se suma solo (con el pulso la cámara lo pierde y lo vuelve a ver, y antes se
// contaba de nuevo): para otra unidad de lo mismo está el botón "+1"; un código distinto se suma al leerlo.
import { $, esc, aviso, modal } from './ui.js';

const FORMATOS = ['ean_13', 'ean_8', 'upc_a', 'upc_e', 'code_128', 'code_39', 'code_93', 'itf', 'codabar', 'qr_code'];
// Campo de escanear con el aspecto del de Vender (clases v- de vender.css): lupa y "Clic acá para escanear" / "Lector listo".
// Lo usan Cargar compra y Entradas y salidas; después, seguirLector(input) prende "Lector listo" mientras tiene el cursor.
const LUPA = '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="11" cy="11" r="6.5"/><path d="m20 20-4.2-4.2"/></svg>';
export const campoEscaner = placeholder => `<label class="v-busca">${LUPA}<input class="v-busca-input" id="escaner"
  placeholder="${esc(placeholder)}" autocomplete="off" autofocus><span class="v-lector" id="lector"><i></i><span>Clic acá para escanear</span></span></label>`;
export function seguirLector(input) {
  const marca = input.parentElement.querySelector('.v-lector');
  const lector = listo => { marca.classList.toggle('listo', listo); marca.lastElementChild.textContent = listo ? 'Lector listo' : 'Clic acá para escanear'; };
  input.addEventListener('focus', () => lector(true));
  input.addEventListener('blur', () => lector(false));
  lector(document.activeElement === input);
}

export const camaraDisponible = () => 'BarcodeDetector' in window && !!navigator.mediaDevices?.getUserMedia;

// continuo: la cámara queda abierta para el siguiente (compras, ventas); si no, se cierra al primer código (ficha del producto).
// alLeer: qué hacer con el código; si no se pasa, se pone en el campo y se aprieta Enter.
// describir(código): el nombre del producto, para mostrar qué se leyó (null si no existe).
export function botonCamara(input, { continuo = true, alLeer = null, envolver = true, describir = null } = {}) {
  if (!input || !camaraDisponible()) return;
  const b = document.createElement('button');
  b.type = 'button'; b.className = 'btn boton-camara'; b.title = 'Escanear con la cámara'; b.setAttribute('aria-label', 'Escanear con la cámara');
  b.textContent = '📷';
  if (envolver) {
    const caja = document.createElement('span');
    caja.className = 'tiene-camara';
    input.replaceWith(caja); caja.append(input, b);
  } else input.after(b);
  const leer = alLeer || (codigo => {
    input.value = codigo;
    input.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: false, cancelable: true }));
    input.blur();   // la pantalla vuelve a poner el foco en el campo: sin esto, en el celular se abre el teclado sobre la cámara
  });
  b.onclick = e => { e.preventDefault(); escanearConCamara(leer, { continuo, describir }); };
}

export async function escanearConCamara(alLeer, { continuo = true, describir = null } = {}) {
  let formatos = FORMATOS;
  try { const s = await window.BarcodeDetector.getSupportedFormats(); formatos = FORMATOS.filter(f => s.includes(f)); } catch { /* se usan todos */ }
  const detector = new window.BarcodeDetector({ formats: formatos });
  let stream = null, activo = true, leidos = 0, ultimo = '', veces = 0;
  const m = modal('Escanear con la cámara', `<div class="camara"><video playsinline muted></video><div class="camara-guia"></div></div>
    <div id="cam-estado" class="cam-estado"><span class="muted">Apuntá al código de barras, derecho y con buena luz.</span></div>
    <div class="fila fin"><button class="btn primario" data-cerrar>${continuo ? 'Listo' : 'Cancelar'}</button></div>`,
    { alCerrar: () => { activo = false; stream?.getTracks().forEach(t => t.stop()); } });
  const video = $('video', m.el);
  // Lo último leído: el producto, cuántas unidades se sumaron de él y el botón para sumar otra
  const mostrar = () => {
    const nombre = describir?.(ultimo);
    $('#cam-estado', m.el).innerHTML = `<div class="cam-leido"><div><b>${nombre ? esc(nombre) : esc(ultimo)}</b>
        <div class="muted chico">${veces > 1 ? `${veces} unidades · ` : ''}${leidos} lectura${leidos === 1 ? '' : 's'} en total</div></div>
        <button type="button" class="btn" id="cam-otra">+1</button></div>
      <p class="muted chico">El mismo código no se suma dos veces seguidas: para otra unidad de lo mismo tocá +1. Seguí con el próximo o tocá Listo.</p>`;
    $('#cam-otra', m.el).onclick = () => sumar(ultimo);
  };
  const sumar = codigo => {
    veces = codigo === ultimo ? veces + 1 : 1;
    ultimo = codigo; leidos++;
    navigator.vibrate?.(60);
    alLeer(codigo);
    if (!continuo) return m.cerrar();
    mostrar();
  };
  try {
    stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: { ideal: 'environment' }, width: { ideal: 1280 }, height: { ideal: 720 } }, audio: false });
  } catch (e) {
    m.cerrar();
    return aviso(e?.name === 'NotAllowedError' ? 'Sin permiso para usar la cámara: habilitalo en el candado de la barra de direcciones'
      : 'No se pudo abrir la cámara del celular');
  }
  if (!activo) return stream.getTracks().forEach(t => t.stop());   // se cerró mientras pedía permiso
  video.srcObject = stream;
  await video.play().catch(() => {});
  const ciclo = async () => {
    if (!activo) return;
    try {
      const r = video.readyState >= 2 ? await detector.detect(video) : [];
      const codigo = r[0]?.rawValue?.trim();
      if (codigo && codigo !== ultimo) sumar(codigo);   // el mismo de recién se ignora: para otra unidad, +1
    } catch { /* un cuadro que no se pudo leer: se sigue */ }
    if (activo) setTimeout(ciclo, 120);
  };
  ciclo();
}
