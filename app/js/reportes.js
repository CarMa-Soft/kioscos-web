// Reportes (solo dueño): ventas, ganancia, devoluciones, desgloses, descuentos y recargos, mercadería y fiado.
// Todos los números los calcula la base (reporte): el empleado no puede pedirlos.
import { llamar } from './base.js';
import { $, $$, esc, plata, cant, fecha, correr } from './ui.js';

const dia = d => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
const sumar = (d, n) => { const x = new Date(d); x.setDate(x.getDate() + n); return x; };
const RANGOS = {
  hoy: () => { const h = new Date(); return [h, h]; },
  ayer: () => { const a = sumar(new Date(), -1); return [a, a]; },
  semana: () => [sumar(new Date(), -6), new Date()],
  mes: () => { const h = new Date(); return [new Date(h.getFullYear(), h.getMonth(), 1), h]; },
  mes_pasado: () => { const h = new Date(); return [new Date(h.getFullYear(), h.getMonth() - 1, 1), new Date(h.getFullYear(), h.getMonth(), 0)]; },
};
const NOMBRES = { hoy: 'Hoy', ayer: 'Ayer', semana: '7 días', mes: 'Este mes', mes_pasado: 'Mes pasado', otro: 'Elegir fechas' };
let rango = { tipo: 'hoy', desde: dia(new Date()), hasta: dia(new Date()) };

export async function pantallaReportes(vista) {
  if (rango.tipo !== 'otro') { const [a, b] = RANGOS[rango.tipo](); rango.desde = dia(a); rango.hasta = dia(b); }
  const r = await llamar('reporte', { p_desde: rango.desde, p_hasta: rango.hasta });
  const total = +r.total, costo = +r.costo, ganancia = total - costo;
  const margen = total > 0 ? ganancia / total * 100 : 0;
  const dias = (new Date(rango.hasta) - new Date(rango.desde)) / 864e5 + 1;
  vista.innerHTML = `<div class="cabecera"><h2>Reportes</h2>
      <div class="chips" id="rangos">${Object.entries(NOMBRES).map(([k, n]) => `<button class="chip ${rango.tipo === k ? 'elegido' : ''}" data-r="${k}">${n}</button>`).join('')}</div></div>
    ${rango.tipo === 'otro' ? `<div class="fila"><label>Desde <input class="input" type="date" id="desde" value="${rango.desde}"></label>
      <label>Hasta <input class="input" type="date" id="hasta" value="${rango.hasta}"></label></div>` : ''}
    <div class="tarjetas">
      <div class="tarjeta"><div class="etq">Ventas</div><div class="valor">${plata(total)}</div>
        <div class="muted chico">${r.tickets} venta${r.tickets === 1 ? '' : 's'}${dias > 1 ? ` · ${plata(total / dias)} por día` : ''}</div></div>
      <div class="tarjeta"><div class="etq">Ticket promedio</div><div class="valor">${plata(r.tickets ? +r.vendido / r.tickets : 0)}</div></div>
      <div class="tarjeta"><div class="etq">Ganancia bruta</div><div class="valor">${plata(ganancia)}</div><div class="muted chico">margen ${margen.toFixed(1)}% · costo ${plata(costo)}</div></div>
      <div class="tarjeta"><div class="etq">Devoluciones</div><div class="valor">${plata(r.devoluciones.total)}</div>
        <div class="muted chico">${r.devoluciones.cantidad} devolucion${r.devoluciones.cantidad === 1 ? '' : 'es'}${+r.devoluciones.perdidas ? ` · pérdida ${plata(r.devoluciones.perdidas)} (no volvió al stock)` : ''}</div></div>
    </div>
    ${r.por_dia.length > 1 ? `<h3>Por día</h3>${barras(r.por_dia.map(x => [fechaCorta(x.dia), +x.total]))}` : ''}
    ${r.por_hora.length ? `<h3>Por hora</h3>${barras(r.por_hora.map(x => [`${x.hora} hs`, +x.total]))}` : ''}
    <div class="dos-columnas">
      <div><h3>Por forma de pago</h3>${tabla(['Forma', 'Total'], r.por_forma.map(x => [esc(x.forma), plata(x.total)]))}</div>
      <div><h3>Por vendedor</h3>${tabla(['Vendedor', 'Total'], r.por_usuario.map(x => [esc(x.nombre), plata(x.total)]))}</div>
    </div>
    <h3>Por categoría</h3>${tabla(['Categoría', 'Vendido', 'Costo', 'Ganancia'], r.por_categoria.map(x => [esc(x.categoria), plata(x.importe), plata(x.costo), plata(x.importe - x.costo)]))}
    <h3>Productos más vendidos</h3>${tabla(['Producto', 'Cantidad', 'Vendido', 'Ganancia'], r.productos.slice(0, 50).map(x => [esc(x.nombre), cant(x.cantidad) + (x.por_peso ? ' kg' : ''), plata(x.importe), plata(x.importe - x.costo)]))}
    <h3>Descuentos y recargos</h3>
    <div class="tarjetas">
      <div class="tarjeta"><div class="etq">Descuento general</div><div class="valor">${plata(r.descuentos.general)}</div></div>
      <div class="tarjeta"><div class="etq">Rebajado en renglones</div><div class="valor">${plata(r.descuentos.renglones)}</div></div>
      <div class="tarjeta"><div class="etq">Ventas con descuento</div><div class="valor">${r.descuentos.ventas_con_descuento}</div><div class="muted chico">${r.descuentos.autorizadas} autorizada(s) por un dueño</div></div>
      <div class="tarjeta"><div class="etq">Recargos cobrados</div><div class="valor">${plata(r.descuentos.recargo)}</div>
        <div class="muted chico">${r.recargos_por_forma.map(x => `${esc(x.forma)} ${plata(x.recargo)}`).join(' · ')}</div></div>
    </div>
    ${r.descuentos_por_usuario.length ? `<h3>Descuentos por vendedor</h3>${tabla(['Vendedor', 'Ventas', 'General', 'Renglones'], r.descuentos_por_usuario.map(x => [esc(x.nombre), x.ventas, plata(x.general), plata(x.renglones)]))}` : ''}
    ${r.autorizaciones.length ? `<h3>Descuentos autorizados</h3>${tabla(['Venta', 'Fecha', 'Vendió', 'Autorizó', 'Descuento'], r.autorizaciones.map(x => [`#${x.numero}`, fecha(x.fecha), esc(x.vendio), esc(x.autorizo), plata(x.descuento)]))}` : ''}
    <h3>Hoy</h3>
    <div class="tarjetas">
      <div class="tarjeta"><div class="etq">Mercadería valorizada al costo</div><div class="valor">${plata(r.mercaderia.costo)}</div></div>
      <div class="tarjeta"><div class="etq">Mercadería a precio de venta</div><div class="valor">${plata(r.mercaderia.venta)}</div></div>
      <div class="tarjeta"><div class="etq">Fiado pendiente</div><div class="valor">${plata(r.fiado_pendiente)}</div></div>
    </div>`;
  // el ancho de las barras se pone desde acá (la política de seguridad no deja estilos escritos en el HTML)
  $$('[data-ancho]', vista).forEach(b => { b.style.width = b.dataset.ancho + '%'; });
  $$('[data-r]', vista).forEach(b => b.onclick = () => { rango.tipo = b.dataset.r; correr(() => pantallaReportes(vista)); });
  if ($('#desde', vista)) {
    const cambiar = () => { rango.desde = $('#desde', vista).value; rango.hasta = $('#hasta', vista).value; if (rango.desde && rango.hasta) correr(() => pantallaReportes(vista)); };
    $('#desde', vista).onchange = cambiar; $('#hasta', vista).onchange = cambiar;
  }
}

const fechaCorta = d => new Date(d + 'T12:00').toLocaleDateString('es-AR', { day: '2-digit', month: '2-digit' });
function barras(filas) {
  const max = Math.max(...filas.map(f => f[1]), 1);
  return `<div class="barras">${filas.map(([etq, v]) => `<div class="barra-fila"><span class="barra-etq">${esc(etq)}</span>
    <span class="barra"><span class="barra-llena" data-ancho="${Math.max(0, Math.round(v / max * 100))}"></span></span><span class="barra-valor">${plata(v)}</span></div>`).join('')}</div>`;
}
function tabla(titulos, filas) {
  if (!filas.length) return '<p class="muted">Sin datos en este período.</p>';
  return `<div class="tabla-caja"><table class="tabla"><thead><tr>${titulos.map((t, k) => `<th class="${k ? 'num' : ''}">${t}</th>`).join('')}</tr></thead>
    <tbody>${filas.map(f => `<tr>${f.map((c, k) => `<td class="${k ? 'num' : ''}">${c}</td>`).join('')}</tr>`).join('')}</tbody></table></div>`;
}
