// Recorrido de bienvenida (solo el dueño): unas pantallas con un dibujo y dos o tres líneas cada una, con "Siguiente".
// Se muestra solo una vez, la primera vez que entra el dueño (config 'recorrido_visto' del negocio; queda anotado al cerrarlo,
// lo haya terminado o no). Después se vuelve a ver desde Ayuda. Cada paso tiene "Ir ahí", que cierra y lleva a esa pantalla.
// Los dibujos son SVG en los colores de la app (sin capturas: no se desactualizan cuando cambia una pantalla).
import { llamar } from './base.js';
import { $, $$, esc, modal } from './ui.js';

const V = '#067647', V2 = '#12b76a', VC = '#d1fadf', G = '#eaecf0', G2 = '#98a2b3', O = '#1f2937', A = '#f79009', B = '#fff';
const dibujo = cuerpo => `<svg viewBox="0 0 240 150" class="rec-dibujo" aria-hidden="true">
  <circle cx="120" cy="78" r="66" fill="#f0fdf4"/>${cuerpo}</svg>`;
const estrella = (x, y, r = 5, c = A) => `<path d="M${x} ${y - r}L${x + r * .3} ${y - r * .3}L${x + r} ${y}L${x + r * .3} ${y + r * .3}L${x} ${y + r}L${x - r * .3} ${y + r * .3}L${x - r} ${y}L${x - r * .3} ${y - r * .3}Z" fill="${c}"/>`;

const DIBUJOS = {
  // el localcito del ícono de la app
  bienvenida: dibujo(`
    ${[0, 1, 2, 3].map(i => `<path d="M${76 + i * 22} 40h22v18a11 11 0 0 1-22 0z" fill="${i % 2 ? B : V}" stroke="${V}" stroke-width="3" stroke-linejoin="round"/>`).join('')}
    <rect x="80" y="69" width="80" height="50" rx="3" fill="${B}" stroke="${V}" stroke-width="4"/>
    <rect x="90" y="81" width="22" height="38" fill="${V}"/><rect x="121" y="81" width="29" height="20" rx="2" fill="${VC}" stroke="${V}" stroke-width="3"/>
    <rect x="70" y="117" width="100" height="6" rx="3" fill="${O}"/>
    ${estrella(186, 42, 8)}${estrella(56, 60, 6, V2)}${estrella(196, 92, 5, V2)}`),
  // el ticket con los datos del negocio
  ticket: dibujo(`
    <path d="M88 24h64v100l-8-6-8 6-8-6-8 6-8-6-8 6-8-6-8 6z" fill="${B}" stroke="${G2}" stroke-width="2.5" stroke-linejoin="round"/>
    <rect x="98" y="34" width="44" height="8" rx="2" fill="${V}"/>
    <rect x="102" y="47" width="36" height="4" rx="2" fill="${G2}"/><rect x="106" y="55" width="28" height="4" rx="2" fill="${G2}"/>
    <path d="M96 66h48" stroke="${G}" stroke-width="2" stroke-dasharray="3 3"/>
    ${[74, 83, 92].map(y => `<rect x="96" y="${y}" width="26" height="4" rx="2" fill="${G}"/><rect x="128" y="${y}" width="16" height="4" rx="2" fill="${G}"/>`).join('')}
    <rect x="96" y="103" width="22" height="6" rx="2" fill="${O}"/><rect x="124" y="103" width="20" height="6" rx="2" fill="${V}"/>
    <circle cx="170" cy="46" r="15" fill="${V}"/><path d="M163 46h14M170 39v14" stroke="${B}" stroke-width="3" stroke-linecap="round"/>`),
  // una caja de mercadería y una planilla
  productos: dibujo(`
    <path d="M60 64l32-14 32 14v40l-32 14-32-14z" fill="#fde68a" stroke="${O}" stroke-width="3" stroke-linejoin="round"/>
    <path d="M60 64l32 14 32-14M92 78v40" stroke="${O}" stroke-width="3" fill="none" stroke-linejoin="round"/>
    <path d="M76 57l32 14" stroke="${A}" stroke-width="5"/>
    <rect x="132" y="38" width="64" height="76" rx="5" fill="${B}" stroke="${V}" stroke-width="3"/>
    <rect x="132" y="38" width="64" height="15" rx="5" fill="${V}"/>
    ${[62, 76, 90, 104].map(y => `<path d="M136 ${y}h56" stroke="${G}" stroke-width="2"/>`).join('')}
    <path d="M154 53v57M174 53v57" stroke="${G}" stroke-width="2"/>
    ${[69, 83, 97].map(y => `<rect x="138" y="${y - 4}" width="12" height="4" rx="2" fill="${G2}"/><rect x="178" y="${y - 4}" width="12" height="4" rx="2" fill="${V2}"/>`).join('')}`),
  // la caja registradora y el lector de códigos
  vender: dibujo(`
    <rect x="62" y="40" width="80" height="50" rx="6" fill="${O}"/><rect x="70" y="48" width="64" height="26" rx="3" fill="${VC}"/>
    <text x="102" y="67" text-anchor="middle" font-size="15" font-weight="700" fill="${V}" font-family="system-ui, sans-serif">$ 2.500</text>
    <rect x="54" y="90" width="96" height="30" rx="5" fill="${B}" stroke="${O}" stroke-width="3"/>
    <rect x="88" y="100" width="28" height="6" rx="3" fill="${G2}"/>
    <rect x="156" y="50" width="50" height="40" rx="4" fill="${B}" stroke="${O}" stroke-width="2.5"/>
    ${[0, 1, 2, 3, 4, 5, 6, 7, 8, 9].map(i => `<path d="M${163 + i * 3.7} 56v22" stroke="${O}" stroke-width="${[2.4, 1.2, 1.2, 2.4, 1.2, 2.4, 1.2, 1.2, 2.4, 1.2][i]}"/>`).join('')}
    <text x="181" y="86" text-anchor="middle" font-size="7" fill="${O}" font-family="monospace">7790895</text>
    <path d="M150 67h62" stroke="#f04438" stroke-width="2.5" stroke-linecap="round"/><path d="M150 67h62" stroke="#f04438" stroke-width="8" opacity=".2" stroke-linecap="round"/>`),
  // el cliente y la libreta del fiado
  fiado: dibujo(`
    <circle cx="86" cy="58" r="16" fill="#fecdca"/><path d="M58 120c2-22 14-34 28-34s26 12 28 34z" fill="${V}"/>
    <path d="M70 58a16 16 0 0 1 32 0c-5-7-12-9-16-9s-11 2-16 9z" fill="${O}"/>
    <rect x="124" y="34" width="62" height="82" rx="5" fill="${B}" stroke="${O}" stroke-width="3"/>
    ${[44, 58, 72, 86, 100].map(y => `<circle cx="124" cy="${y}" r="3" fill="${O}"/>`).join('')}
    <text x="134" y="56" font-size="14" font-weight="700" fill="#d92d20" font-family="system-ui, sans-serif">Debe</text>
    ${[66, 76, 86].map(y => `<rect x="134" y="${y}" width="24" height="4" rx="2" fill="${G2}"/><rect x="164" y="${y}" width="14" height="4" rx="2" fill="${G2}"/>`).join('')}
    <rect x="134" y="98" width="44" height="7" rx="2" fill="#d92d20"/>
    <circle cx="190" cy="40" r="13" fill="#25d366"/><path d="M184 46l2-5a7 7 0 1 1 3 3z" fill="${B}"/>`),
  // los billetes contados y el visto
  cerrar: dibujo(`
    ${[0, 1, 2].map(i => `<rect x="${58 + i * 6}" y="${56 + i * 12}" width="92" height="44" rx="5" fill="${i === 2 ? '#a6f4c5' : VC}" stroke="${V}" stroke-width="2.5"/>`).join('')}
    <circle cx="116" cy="102" r="10" fill="none" stroke="${V}" stroke-width="2.5"/><text x="116" y="107" text-anchor="middle" font-size="13" font-weight="700" fill="${V}" font-family="system-ui, sans-serif">$</text>
    <ellipse cx="164" cy="116" rx="14" ry="5" fill="${A}"/><rect x="150" y="104" width="28" height="12" fill="${A}"/><ellipse cx="164" cy="104" rx="14" ry="5" fill="#fec84b"/>
    <circle cx="178" cy="54" r="20" fill="${V2}"/><path d="M168 54l7 7 13-14" stroke="${B}" stroke-width="5" fill="none" stroke-linecap="round" stroke-linejoin="round"/>`),
  // la compu con la app instalada y la ayuda
  ayuda: dibujo(`
    <rect x="58" y="40" width="104" height="66" rx="5" fill="${O}"/><rect x="65" y="47" width="90" height="52" rx="2" fill="#f5f6f8"/>
    <rect x="65" y="47" width="22" height="52" fill="#1f2937" opacity=".85"/>
    ${[56, 66, 76, 86].map(y => `<rect x="70" y="${y}" width="12" height="4" rx="2" fill="${G2}"/>`).join('')}
    <rect x="94" y="56" width="52" height="10" rx="2" fill="${V}"/><rect x="94" y="72" width="24" height="18" rx="2" fill="${B}" stroke="${G}" stroke-width="1.5"/>
    <rect x="122" y="72" width="24" height="18" rx="2" fill="${B}" stroke="${G}" stroke-width="1.5"/>
    <path d="M48 106h124l-8 10H56z" fill="#475467"/>
    <circle cx="184" cy="46" r="18" fill="${V}"/><text x="184" y="53" text-anchor="middle" font-size="22" font-weight="800" fill="${B}" font-family="system-ui, sans-serif">?</text>`),
};

const PASOS = n => [
  ['bienvenida', `¡Bienvenido a ${esc(n)}!`, 'En un minuto te mostramos lo principal para arrancar. Este recorrido queda en <b>Ayuda</b> para verlo cuando quieras.'],
  ['ticket', 'Los datos del negocio', 'En <b>Ajustes</b> poné el nombre, la dirección, el teléfono y el CUIT: salen en el ticket. Ahí también probás la impresora.', '#/ajustes'],
  ['productos', 'Tus productos', 'En <b>Productos</b> los cargás de a uno o muchos juntos desde una <b>planilla de Excel</b>. Lo que falte, lo podés crear al vender.', '#/productos'],
  ['vender', 'Abrir la caja y vender', 'Al empezar el día abrís la caja con el efectivo que hay. En <b>Vender</b>, escaneá el código o buscá el producto, elegí cómo paga y tocá <b>Cobrar</b>.', '#/vender'],
  ['fiado', 'Fiado y clientes', 'Para fiar, elegí el cliente y la forma de pago <b>Fiado</b>. En <b>Clientes</b> ves quién debe y desde cuándo, cobrás y le mandás el estado de cuenta por WhatsApp.', '#/clientes'],
  ['cerrar', 'Cerrar la caja', 'Al terminar, en <b>Caja → Cerrar turno</b> ponés cuánto efectivo hay: la app te dice si sobra o falta. Lo que quede en la caja se propone al abrir al otro día.', '#/caja'],
  ['ayuda', 'Instalala y consultá la Ayuda', 'Con <b>Instalar la app</b> (abajo en el menú) queda un ícono en el escritorio. Y en <b>Ayuda</b> está cómo hacer cada cosa.', '#/ayuda'],
];

// El recorrido. alTerminar (opcional) corre al cerrarlo, de cualquier forma.
export function verRecorrido(ctx, alTerminar) {
  const pasos = PASOS(ctx.negocio?.nombre || 'tu negocio');
  let k = 0;
  const m = modal('', `<div class="rec" id="rec"></div>`, { alCerrar: () => alTerminar?.() });
  $('.modal', m.el).classList.add('rec-modal');
  $('.modal h2', m.el)?.remove();
  const pintar = () => {
    const [d, titulo, texto, ruta] = pasos[k], ultimo = k === pasos.length - 1;
    $('#rec', m.el).innerHTML = `${DIBUJOS[d]}
      <h2>${titulo}</h2><p>${texto}</p>
      ${ruta && !ultimo ? `<p><button class="link" id="rec-ir">Ir ahí ahora →</button></p>` : ''}
      <div class="rec-puntos">${pasos.map((_, i) => `<button class="${i === k ? 'activo' : ''}" data-paso="${i}" aria-label="Paso ${i + 1}"></button>`).join('')}</div>
      <div class="rec-botones">${k ? '<button class="btn" id="rec-ant">Anterior</button>' : '<button class="link" data-cerrar>Saltear</button>'}
        <span class="muted chico">${k + 1} de ${pasos.length}</span>
        <button class="btn primario" id="rec-sig">${ultimo ? '¡A vender!' : 'Siguiente'}</button></div>`;
    $$('[data-paso]', m.el).forEach(b => b.onclick = () => { k = +b.dataset.paso; pintar(); });
    $$('#rec [data-cerrar]', m.el).forEach(b => b.onclick = () => m.cerrar());   // Saltear (se dibuja después de abrir la ventana)
    if ($('#rec-ant', m.el)) $('#rec-ant', m.el).onclick = () => { k--; pintar(); };
    $('#rec-sig', m.el).onclick = () => { if (ultimo) { m.cerrar(); location.replace('#/vender'); } else { k++; pintar(); } };
    if ($('#rec-ir', m.el)) $('#rec-ir', m.el).onclick = () => { m.cerrar(); location.replace(ruta); };
    $('#rec-sig', m.el).focus();
  };
  // flechas del teclado: anterior y siguiente
  m.el.addEventListener('keydown', e => {
    if (e.key === 'ArrowRight' && k < pasos.length - 1) { k++; pintar(); }
    else if (e.key === 'ArrowLeft' && k > 0) { k--; pintar(); }
  });
  pintar();
}

// La primera vez que entra el dueño: el recorrido, y queda anotado para todo el negocio (aunque lo saltee)
export function recorridoPrimeraVez(ctx) {
  if (ctx.yo?.rol !== 'admin' || ctx.config?.recorrido_visto === true) return;
  ctx.config.recorrido_visto = true;   // no vuelve a salir en esta sesión aunque falle el guardado
  verRecorrido(ctx, () => llamar('guardar_config', { p_clave: 'recorrido_visto', p_valor: true }).catch(() => {}));
}
