// Escanear códigos de barras con la cámara del celular, sin lector. Usa el lector que trae el navegador (BarcodeDetector:
// Chrome en Android); donde no está (la PC con Windows, Safari en iPhone) el botón 📷 no aparece y todo sigue igual.
// botonCamara(input) agrega 📷 junto a un campo de escanear: cada código leído se pone en el campo y se "aprieta" Enter,
// así la pantalla lo procesa igual que con el lector de la PC (agrega el producto, avisa si no existe, etc.).
import { $, aviso, modal } from './ui.js';

const FORMATOS = ['ean_13', 'ean_8', 'upc_a', 'upc_e', 'code_128', 'code_39', 'code_93', 'itf', 'codabar', 'qr_code'];
export const camaraDisponible = () => 'BarcodeDetector' in window && !!navigator.mediaDevices?.getUserMedia;

// continuo: la cámara queda abierta para el siguiente (compras, ventas); si no, se cierra al primer código (ficha del producto).
// alLeer: qué hacer con el código; si no se pasa, se pone en el campo y se aprieta Enter.
export function botonCamara(input, { continuo = true, alLeer = null, envolver = true } = {}) {
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
  b.onclick = e => { e.preventDefault(); escanearConCamara(leer, { continuo }); };
}

export async function escanearConCamara(alLeer, { continuo = true } = {}) {
  let formatos = FORMATOS;
  try { const s = await window.BarcodeDetector.getSupportedFormats(); formatos = FORMATOS.filter(f => s.includes(f)); } catch { /* se usan todos */ }
  const detector = new window.BarcodeDetector({ formats: formatos });
  let stream = null, activo = true, leidos = 0, ultimo = '', vistoUltimo = 0;
  const m = modal('Escanear con la cámara', `<div class="camara"><video playsinline muted></video><div class="camara-guia"></div></div>
    <p id="cam-estado" class="muted">Apuntá al código de barras, derecho y con buena luz.</p>
    <div class="fila fin"><button class="btn primario" data-cerrar>${continuo ? 'Listo' : 'Cancelar'}</button></div>`,
    { alCerrar: () => { activo = false; stream?.getTracks().forEach(t => t.stop()); } });
  const estado = t => { const e = $('#cam-estado', m.el); if (e) e.textContent = t; };
  const video = $('video', m.el);
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
      const ahora = Date.now();
      // el mismo código sigue a la vista: no se vuelve a contar hasta que salga de cuadro y vuelva
      if (codigo && !(codigo === ultimo && ahora - vistoUltimo < 1200)) {
        ultimo = codigo; vistoUltimo = ahora; leidos++;
        navigator.vibrate?.(60);
        alLeer(codigo);
        if (!continuo) return m.cerrar();
        estado(`✓ ${codigo} · ${leidos} leído${leidos === 1 ? '' : 's'}. Seguí con el próximo o tocá Listo.`);
      } else if (codigo) vistoUltimo = ahora;
    } catch { /* un cuadro que no se pudo leer: se sigue */ }
    setTimeout(ciclo, 120);
  };
  ciclo();
}
