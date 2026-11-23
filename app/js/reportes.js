// Reportes (solo dueño): ventas, ganancia, devoluciones, desgloses, promociones, descuentos y recargos, mercadería y fiado.
// Todos los números los calcula la base (reporte): el empleado no puede pedirlos.
import { llamar } from './base.js';
import { $, $$, esc, plata, cant, fecha, correr } from './ui.js';
import { columnas, activarGraficos } from './graficos.js';

const dia = d => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
const sumar = (d, n) => { const x = new Date(d); x.setDate(x.getDate() + n); return x; };
const RANGOS = {
  hoy: () => { const h = new Date(); return [h, h]; },
  ayer: () => { const a = sumar(new Date(), -1); return [a, a]; },
  semana: () => [sumar(new Date(), -6), new Date()],
  mes: () => { const h = new Date(); return [new Date(h.getFullYear(), h.getMonth(), 1), h]; },
  mes_pasado: () => { const h = new Date(); return [new Date(h.getFullYear(), h.getMonth() - 1, 1), new Date(h.getFullYear(), h.getMonth(), 0)]; },
};
// El período anterior del mismo largo, para comparar (con qué se compara y cómo se dice)
function anterior(tipo, desde, hasta) {
  const d = new Date(desde + 'T12:00'), h = new Date(hasta + 'T12:00'), n = Math.round((h - d) / 864e5) + 1;
  if (tipo === 'mes') { const a = new Date(d.getFullYear(), d.getMonth() - 1, 1), b = new Date(a.getFullYear(), a.getMonth(), Math.min(h.getDate(), new Date(a.getFullYear(), a.getMonth() + 1, 0).getDate()));
    return [dia(a), dia(b), 'los mismos días del mes pasado']; }
  if (tipo === 'mes_pasado') { const a = new Date(d.getFullYear(), d.getMonth() - 1, 1); return [dia(a), dia(new Date(a.getFullYear(), a.getMonth() + 1, 0)), 'el mes anterior']; }
  return [dia(sumar(d, -n)), dia(sumar(d, -1)), { hoy: 'ayer', ayer: 'el día anterior', semana: 'los 7 días anteriores' }[tipo] || (n === 1 ? 'el día anterior' : `los ${n} días anteriores`)];
}
// "↑ 12% vs. ayer" (verde si sube, rojo si baja; nada si antes no hubo)
function comparar(ahora, antes, contra) {
  if (!(+antes > 0)) return '';
  const p = Math.round((ahora - antes) / antes * 100);
  return `<span class="r-cambio ${p > 0 ? 'sube' : p < 0 ? 'baja' : ''}" title="Antes: ${plata(antes)}">${p > 0 ? '↑' : p < 0 ? '↓' : '='} ${Math.abs(p)}% vs. ${contra}</span>`;
}
const NOMBRES = { hoy: 'Hoy', ayer: 'Ayer', semana: '7 días', mes: 'Este mes', mes_pasado: 'Mes pasado', otro: 'Elegir fechas' };

// Íconos (trazos SVG, toman el color del texto). Los estilos son los de Hoy, Caja, Productos y demás (clases c- en app.css).
const svg = d => `<svg viewBox="0 0 24 24" aria-hidden="true">${d}</svg>`;
const ICO = {
  ventas: svg('<path d="M4 4h2l2.2 10.2a1.5 1.5 0 0 0 1.5 1.2h7.6a1.5 1.5 0 0 0 1.5-1.1L20.5 8H6.8"/><circle cx="10" cy="19.5" r="1.3"/><circle cx="17" cy="19.5" r="1.3"/>'),
  recibo: svg('<path d="M6 3h12v18l-3-2-3 2-3-2-3 2z"/><path d="M9 8h6M9 12h6"/>'),
  ganancia: svg('<path d="M3.5 17.5 9 12l4 4 7.5-8"/><path d="M15 8h5.5v5.5"/>'),
  devolucion: svg('<path d="M9 14 4 9l5-5"/><path d="M4 9h10.5a5.5 5.5 0 0 1 0 11H11"/>'),
  varios: svg('<rect x="4" y="4" width="16" height="16" rx="2"/><path d="M12 8v8M8 12h8"/>'),
  calendario: svg('<rect x="3.5" y="5" width="17" height="15" rx="2"/><path d="M3.5 10h17M8 3v4M16 3v4"/>'),
  reloj: svg('<circle cx="12" cy="12" r="8.5"/><path d="M12 7.5V12l3 2"/>'),
  tarjeta: svg('<rect x="2.5" y="5.5" width="19" height="13" rx="2"/><path d="M2.5 10h19M6.5 15h4"/>'),
  persona: svg('<circle cx="12" cy="8" r="3.6"/><path d="M5 20c.8-3.6 3.6-5.5 7-5.5s6.2 1.9 7 5.5"/>'),
  regalo: svg('<rect x="3.5" y="8" width="17" height="4" rx="1"/><path d="M5 12v8h14v-8M12 8v12M12 8c-1.5-3.5-5.5-3.5-5.5-1.2S9.5 8 12 8zM12 8c1.5-3.5 5.5-3.5 5.5-1.2S14.5 8 12 8z"/>'),
  etiqueta: svg('<path d="M3.5 12.5V4.5h8l9 9-8 8z"/><circle cx="8" cy="9" r="1.3"/>'),
  paquete: svg('<path d="m12 3 8 4.5v9L12 21l-8-4.5v-9z"/><path d="m4 7.5 8 4.5 8-4.5M12 12v9"/>'),
  porciento: svg('<path d="M19 5 5 19"/><circle cx="7" cy="7" r="2.2"/><circle cx="17" cy="17" r="2.2"/>'),
  candado: svg('<rect x="5" y="10.5" width="14" height="10" rx="2"/><path d="M8 10.5V7.5a4 4 0 0 1 8 0v3"/>'),
  plata: svg('<rect x="2.5" y="6" width="19" height="12" rx="2"/><circle cx="12" cy="12" r="2.6"/>'),
  fiado: svg('<rect x="5" y="3" width="14" height="18" rx="2"/><path d="M9 8h6M9 12h6M9 16h3"/>'),
  caja: svg('<rect x="3" y="7" width="18" height="12" rx="2"/><path d="M3 11h18M8 7V5h8v2"/>'),
};
// Una tarjeta: color, ícono, título, valor y aclaración (opcional)
const tarjeta = (color, ico, etq, valor, sub = '') => `<div class="c-tarjeta ${color}"><span class="c-ico">${ico}</span><div><div class="etq">${etq}</div><div class="valor">${valor}</div>${sub ? `<div class="c-sub">${sub}</div>` : ''}</div></div>`;
const titulo = (ico, texto) => `<div class="c-titulo">${ico}<h3>${texto}</h3></div>`;
let rango = { tipo: 'hoy', desde: dia(new Date()), hasta: dia(new Date()) };

export async function pantallaReportes(vista) {
  if (rango.tipo !== 'otro') { const [a, b] = RANGOS[rango.tipo](); rango.desde = dia(a); rango.hasta = dia(b); }
  const [pd, ph, contra] = anterior(rango.tipo, rango.desde, rango.hasta);
  const [r, a, promos] = await Promise.all([llamar('reporte', { p_desde: rango.desde, p_hasta: rango.hasta }),
    llamar('reporte', { p_desde: pd, p_hasta: ph }).catch(() => null),   // si falla la comparación, se muestra igual sin ella
    llamar('reporte_promos', { p_desde: rango.desde, p_hasta: rango.hasta }).catch(() => null)]);   // las promociones (aparte de reporte)
  const gananciaAnt = a ? +a.total - +a.costo : 0;
  const total = +r.total, costo = +r.costo, ganancia = total - costo;
  const margen = total > 0 ? ganancia / total * 100 : 0;
  const dias = (new Date(rango.hasta) - new Date(rango.desde)) / 864e5 + 1;
  const nDev = +r.devoluciones.cantidad;
  vista.innerHTML = `<div class="cabecera"><h2>Reportes</h2></div>
    <div class="c-filtros">
      <div class="chips" id="rangos">${Object.entries(NOMBRES).map(([k, n]) => `<button class="chip ${rango.tipo === k ? 'elegido' : ''}" data-r="${k}">${n}</button>`).join('')}</div>
      ${rango.tipo === 'otro' ? `<div class="fila r-fechas"><label>Desde <input class="input" type="date" id="desde" value="${rango.desde}"></label>
        <label>Hasta <input class="input" type="date" id="hasta" value="${rango.hasta}"></label></div>` : ''}
    </div>
    <div class="c-tarjetas r-tarjetas">
      ${tarjeta('verde', ICO.ventas, 'Ventas', plata(total), `${r.tickets} venta${r.tickets === 1 ? '' : 's'}${dias > 1 ? ` · ${plata(total / dias)} por día` : ''}${a ? '<br>' + comparar(total, +a.total, contra) : ''}`)}
      ${tarjeta('violeta', ICO.recibo, 'Ticket promedio', plata(r.tickets ? +r.vendido / r.tickets : 0), a ? comparar(r.tickets ? +r.vendido / r.tickets : 0, a.tickets ? +a.vendido / a.tickets : 0, contra) : '')}
      ${tarjeta('azul', ICO.ganancia, 'Ganancia bruta', plata(ganancia), `margen ${margen.toFixed(1)}% · costo ${plata(costo)}${a ? '<br>' + comparar(ganancia, gananciaAnt, contra) : ''}`)}
      ${tarjeta(nDev ? 'naranja' : 'gris', ICO.devolucion, 'Devoluciones', plata(r.devoluciones.total),
        `${nDev === 1 ? '1 devolución' : nDev + ' devoluciones'}${+r.devoluciones.perdidas ? ` · pérdida ${plata(r.devoluciones.perdidas)} (no volvió al stock)` : ''}`)}
      ${+r.varios?.importe ? tarjeta('gris', ICO.varios, 'Vendido como Varios', plata(r.varios.importe),
        `${r.varios.renglones} renglón${+r.varios.renglones === 1 ? '' : 'es'} sin producto: no pasan por el stock`) : ''}
    </div>
    ${dias > 1 && dias <= 93 && r.por_dia.length ? `${titulo(ICO.calendario, 'Por día')}<p class="muted chico r-ayuda">Tocá un día para ver solo ese día.</p><div id="r-por-dia">${columnas(diasDe(r))}</div>` : ''}
    ${r.por_hora.length ? `${titulo(ICO.reloj, 'Por hora')}<div id="r-por-hora">${columnas(horasDe(r), { alto: 150 })}</div>` : ''}
    <div class="dos-columnas">
      <div>${titulo(ICO.tarjeta, 'Por forma de pago')}${tabla(['Forma', 'Total'], r.por_forma.map(x => [esc(x.forma), plata(x.total)]))}</div>
      <div>${titulo(ICO.persona, 'Por vendedor')}${tabla(['Vendedor', 'Total'], r.por_usuario.map(x => [esc(x.nombre), plata(x.total)]))}</div>
    </div>
    ${titulo(ICO.etiqueta, 'Por categoría')}${tabla(['Categoría', 'Vendido', 'Costo', 'Ganancia'], r.por_categoria.map(x => [esc(x.categoria), plata(x.importe), plata(x.costo), plata(x.importe - x.costo)]))}
    ${titulo(ICO.paquete, 'Productos más vendidos')}${tabla(['Producto', 'Cantidad', 'Vendido', 'Ganancia'], r.productos.slice(0, 50).map(x => [esc(x.nombre), cant(x.cantidad) + (x.por_peso ? ' kg' : ''), plata(x.importe), plata(x.importe - x.costo)]))}
    ${titulo(ICO.porciento, 'Descuentos y recargos')}
    <div class="c-tarjetas r-tarjetas">
      ${promos ? tarjeta(+promos.total ? 'violeta' : 'gris', ICO.regalo, 'Promociones', plata(promos.total), +promos.ventas ? `en ${promos.ventas} venta${promos.ventas === 1 ? '' : 's'}` : 'ninguna en el período') : ''}
      ${tarjeta(+r.descuentos.general ? 'naranja' : 'gris', ICO.porciento, 'Descuento general', plata(r.descuentos.general))}
      ${tarjeta(+r.descuentos.renglones ? 'naranja' : 'gris', ICO.etiqueta, 'Rebajado en renglones', plata(r.descuentos.renglones))}
      ${tarjeta(+r.descuentos.ventas_con_descuento ? 'naranja' : 'gris', ICO.candado, 'Ventas con descuento', r.descuentos.ventas_con_descuento, `${r.descuentos.autorizadas} autorizada(s) por un dueño`)}
      ${tarjeta(+r.descuentos.recargo ? 'verde' : 'gris', ICO.tarjeta, 'Recargos cobrados', plata(r.descuentos.recargo), r.recargos_por_forma.map(x => `${esc(x.forma)} ${plata(x.recargo)}`).join(' · '))}
    </div>
    ${promos?.por_promo.length ? `${titulo(ICO.regalo, 'Promociones')}${tabla(['Promoción', 'Ventas', 'Unidades con descuento', 'Descontado'], promos.por_promo.map(x => [esc(x.nombre), x.ventas, cant(x.unidades), plata(x.descuento)]))}` : ''}
    ${r.descuentos_por_usuario.length ? `${titulo(ICO.persona, 'Descuentos por vendedor')}${tabla(['Vendedor', 'Ventas', 'General', 'Renglones'], r.descuentos_por_usuario.map(x => [esc(x.nombre), x.ventas, plata(x.general), plata(x.renglones)]))}` : ''}
    ${r.autorizaciones.length ? `${titulo(ICO.candado, 'Descuentos autorizados')}${tabla(['Venta', 'Fecha', 'Vendió', 'Autorizó', 'Descuento'], r.autorizaciones.map(x => [`#${x.numero}`, fecha(x.fecha), esc(x.vendio), esc(x.autorizo), plata(x.descuento)]))}` : ''}
    ${titulo(ICO.caja, 'Hoy')}
    <div class="c-tarjetas r-tarjetas">
      ${tarjeta('azul', ICO.plata, 'Mercadería valorizada al costo', plata(r.mercaderia.costo))}
      ${tarjeta('verde', ICO.paquete, 'Mercadería a precio de venta', plata(r.mercaderia.venta))}
      ${tarjeta(+r.fiado_pendiente > 0.004 ? 'rojo' : 'gris', ICO.fiado, 'Fiado pendiente', plata(r.fiado_pendiente))}
    </div>`;
  // el ancho de las barras se pone desde acá (la política de seguridad no deja estilos escritos en el HTML)
  $$('[data-ancho]', vista).forEach(b => { b.style.width = b.dataset.ancho + '%'; });
  // el gráfico por día: tocar un día lo abre solo (como 'Elegir fechas' con ese día); el por hora solo muestra el detalle
  if ($('#r-por-dia', vista)) activarGraficos($('#r-por-dia', vista), k => { const d = diasDe(r)[k]; rango = { tipo: 'otro', desde: d.dia, hasta: d.dia }; correr(() => pantallaReportes(vista)); });
  if ($('#r-por-hora', vista)) activarGraficos($('#r-por-hora', vista));
  $$('[data-r]', vista).forEach(b => b.onclick = () => { rango.tipo = b.dataset.r; correr(() => pantallaReportes(vista)); });
  if ($('#desde', vista)) {
    const cambiar = () => { rango.desde = $('#desde', vista).value; rango.hasta = $('#hasta', vista).value; if (rango.desde && rango.hasta) correr(() => pantallaReportes(vista)); };
    $('#desde', vista).onchange = cambiar; $('#hasta', vista).onchange = cambiar;
  }
}

const fechaCorta = d => new Date(d + 'T12:00').toLocaleDateString('es-AR', { day: '2-digit', month: '2-digit' });
// Cada día del período (los que no vendieron, en cero) y cada hora entre la primera y la última con ventas
function diasDe(r) {
  const de = Object.fromEntries(r.por_dia.map(x => [x.dia, +x.total])), filas = [];
  for (let d = new Date(r.desde + 'T12:00'); dia(d) <= r.hasta; d = sumar(d, 1)) {
    const k = dia(d);
    filas.push({ dia: k, etq: fechaCorta(k), valor: de[k] || 0, detalle: `${d.toLocaleDateString('es-AR', { weekday: 'long' })} ${fechaCorta(k)}` });
  }
  return filas;
}
function horasDe(r) {
  const de = Object.fromEntries(r.por_hora.map(x => [+x.hora, +x.total])), hs = r.por_hora.map(x => +x.hora), filas = [];
  for (let h = Math.min(...hs); h <= Math.max(...hs); h++) filas.push({ etq: h + ' hs', valor: de[h] || 0, detalle: `De ${h} a ${h + 1} hs` });
  return filas;
}
function tabla(titulos, filas) {
  if (!filas.length) return '<p class="muted">Sin datos en este período.</p>';
  return `<div class="tabla-caja c-tabla"><table class="tabla"><thead><tr>${titulos.map((t, k) => `<th class="${k ? 'num' : ''}">${t}</th>`).join('')}</tr></thead>
    <tbody>${filas.map(f => `<tr>${f.map((c, k) => `<td class="${k ? 'num' : ''}">${c}</td>`).join('')}</tr>`).join('')}</tbody></table></div>`;
}
