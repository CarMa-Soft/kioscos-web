// Gráficos de columnas (Hoy y Reportes): al pasar el mouse (o el dedo) muestran el detalle; con alClic, cada columna es un botón.
// columnas(filas, opciones) devuelve el HTML; activarGraficos(raiz) les pone la altura y el detalle (sin estilos en el HTML:
// la política de seguridad no los deja, así que la altura va desde acá).
// filas: [{ etq: 'lun 18', valor: 1234, detalle: 'Lunes 18/11 · 12 ventas' }]
import { $$, esc, plata } from './ui.js';

const acciones = new WeakMap();   // el gráfico → qué hacer al tocar una columna

export function columnas(filas, { alto = 180, cadaEtq = 0 } = {}) {
  const max = Math.max(...filas.map(f => +f.valor), 0) || 1;
  // con muchas columnas, se muestra una etiqueta de cada tantas para que no se encimen
  const salto = cadaEtq || Math.max(1, Math.ceil(filas.length / 14));
  return `<div class="graf" data-graf><div class="graf-cols" data-alto="${alto}">
    ${filas.map((f, k) => `<button type="button" class="graf-col ${+f.valor > 0 ? '' : 'cero'}" data-k="${k}" data-pct="${Math.round(Math.max(0, +f.valor) / max * 100)}"
      aria-label="${esc(f.detalle || f.etq)}: ${esc(plata(f.valor))}" data-tip="${esc(f.detalle || f.etq)}" data-valor="${esc(plata(f.valor))}"><span></span></button>`).join('')}
    </div><div class="graf-etqs">${filas.map((f, k) => `<span>${k % salto === 0 ? esc(f.etq) : ''}</span>`).join('')}</div>
    <div class="graf-tip" hidden></div></div>`;
}

// Altura de cada columna (con una animación al aparecer) y el cartelito con el detalle
export function activarGraficos(raiz, alClic) {
  $$('[data-graf]', raiz).forEach(g => {
    if (alClic) { acciones.set(g, alClic); g.classList.add('graf-clic'); }
    const cols = g.querySelector('.graf-cols');
    cols.style.height = cols.dataset.alto + 'px';
    const barras = $$('.graf-col', g);
    barras.forEach(b => { b.firstElementChild.style.height = '0%'; });
    requestAnimationFrame(() => requestAnimationFrame(() => barras.forEach(b => { b.firstElementChild.style.height = Math.max(b.dataset.pct, +b.dataset.pct > 0 ? 2 : 0) + '%'; })));
    const tip = g.querySelector('.graf-tip');
    const mostrar = b => {
      tip.innerHTML = `${b.dataset.tip}<b>${b.dataset.valor}</b>`;
      tip.hidden = false;
      const rg = g.getBoundingClientRect(), rb = b.getBoundingClientRect();
      const x = Math.min(Math.max(rb.left - rg.left + rb.width / 2, tip.offsetWidth / 2), rg.width - tip.offsetWidth / 2);
      tip.style.left = x + 'px';
      tip.style.top = Math.max(0, rb.top - rg.top + rb.height * (1 - b.dataset.pct / 100) - tip.offsetHeight - 8) + 'px';
      barras.forEach(o => o.classList.toggle('activa', o === b));
    };
    const ocultar = () => { tip.hidden = true; barras.forEach(o => o.classList.remove('activa')); };
    barras.forEach(b => {
      b.onmouseenter = () => mostrar(b); b.onfocus = () => mostrar(b);
      b.onclick = () => { mostrar(b); acciones.get(g)?.(+b.dataset.k); };
    });
    g.onmouseleave = ocultar;
    g.addEventListener('focusout', e => { if (!g.contains(e.relatedTarget)) ocultar(); });
  });
}

// Un número que sube de 0 a su valor al aparecer (formato: plata o número). Sin animación si el sistema pide reducir movimiento.
export function contar(el, valor, formato = plata) {
  if (!el) return;
  const fin = +valor || 0;
  if (matchMedia('(prefers-reduced-motion: reduce)').matches || !fin) { el.textContent = formato(fin); return; }
  const t0 = performance.now(), dura = 650;
  const paso = t => {
    const p = Math.min(1, (t - t0) / dura), suave = 1 - Math.pow(1 - p, 3);
    el.textContent = formato(p < 1 ? fin * suave : fin);
    if (p < 1 && el.isConnected) requestAnimationFrame(paso);
  };
  requestAnimationFrame(paso);
}
