// Instalar en una PC con Windows, con impresión directa de tickets: el instalador (instalar-gestion-de-ventas.bat, en la
// carpeta de la app) crea el acceso directo "Gestión de ventas" que abre la app en su propia ventana de Chrome con un perfil
// aparte y --kiosk-printing (imprime sin la ventana de impresión, aunque haya otro Chrome abierto). La instalación común de
// Chrome ("Instalar la app") no puede imprimir directo: una página no puede saltearse la vista previa.
import { $, modal } from './ui.js';

// La ventana que abre el ícono del instalador: su URL lleva ?pc=1. Como ese ícono usa un perfil de Chrome propio, se anota
// en su localStorage (por si la URL lo pierde) y ahí no se ofrece instalar de nuevo.
export function enVentanaInstalada() {
  if (new URLSearchParams(location.search).get('pc') === '1') { try { localStorage.setItem('ventana-pc', '1'); } catch { /* sin almacenamiento */ } return true; }
  try { return localStorage.getItem('ventana-pc') === '1'; } catch { return false; }
}

export const esWindows = () => /Windows/i.test(navigator.userAgentData?.platform || navigator.userAgent);
export const ARCHIVO = 'instalar-gestion-de-ventas.bat';

const PASOS = `<ol class="inst-pasos">
    <li>Chrome puede avisar que el archivo <i>puede ser peligroso</i>: tocá <b>Conservar</b>.</li>
    <li>Abrilo (en Descargas). Si aparece <i>"Windows protegió su PC"</i>, tocá <b>Más información → Ejecutar de todas formas</b>.</li>
    <li>Queda el ícono <b>Gestión de ventas</b> en el Escritorio y en el menú Inicio: abrí la app siempre con ese ícono.
      La primera vez entrás con la cuenta del negocio.</li>
    <li>Los tickets salen en la <b>impresora predeterminada de Windows</b>: dejá ahí la de tickets.</li>
  </ol>`;

// La ventana de instalar (menú → Instalar la app, en Windows). chrome: la instalación de Chrome, si el navegador la ofrece.
export function ventanaInstalar(chrome) {
  const m = modal('Instalar en esta PC', `
    <div class="inst-opcion recomendada"><b>Con impresión directa de tickets</b> <span class="muted chico">(recomendado en la PC de la caja)</span>
      <p class="muted chico">Los tickets salen solos, sin la ventana de impresión.</p>
      ${PASOS}
      <a class="btn primario" href="${ARCHIVO}" download id="inst-bajar">⬇️ Descargar el instalador</a></div>
    ${chrome ? `<div class="inst-opcion"><b>Como app de Chrome</b> <span class="muted chico">(sin impresión directa: muestra la vista previa)</span>
      <div><button class="btn" id="inst-chrome">Instalar como app de Chrome</button></div></div>` : ''}
    <div class="fila fin"><button class="btn" data-cerrar>Cerrar</button></div>`, { ancho: true });
  if (chrome) $('#inst-chrome', m.el).onclick = () => { m.cerrar(); chrome(); };
  return m;
}

// Para Ajustes → Impresión: el enlace al instalador, con los pasos
export const ayudaInstalador = () => `${enVentanaInstalada() ? '<p class="ok chico">✓ Esta ventana está instalada con impresión directa: los tickets salen en la impresora predeterminada de Windows.</p>' : ''}
  <details class="inst-ajustes"><summary>${enVentanaInstalada() ? 'Instalarla en otra PC' : 'Imprimir directo, sin la ventana de impresión (Windows)'}</summary>
    <p class="muted chico">Instalá la app con este instalador y abrila siempre con su ícono:</p>${PASOS}
    <a class="btn" href="${ARCHIVO}" download>⬇️ Descargar el instalador</a></details>`;
