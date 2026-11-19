// Inicio: lo de hoy (el empleado ve solo sus ventas; la ganancia, solo el dueño)
import { llamar } from './base.js';
import { esc, plata, hora, fecha } from './ui.js';
import * as cat from './catalogo.js';
import { verARevisar } from './productos.js';

export async function pantallaInicio(vista, ctx) {
  const r = await llamar('inicio');
  const admin = ctx.yo.rol === 'admin';
  const aRevisar = admin ? cat.productos().filter(p => p.a_revisar).length : 0;   // creados en la caja con lo mínimo
  vista.innerHTML = `<div class="cabecera"><div><h2>Hoy</h2><p class="muted">${new Date().toLocaleDateString('es-AR', { weekday: 'long', day: 'numeric', month: 'long' })}</p></div>
      <div class="acciones"><a class="btn primario" href="#/vender">Vender</a>${admin ? '<a class="btn" href="#/reportes">Reportes</a>' : ''}</div></div>
    ${aRevisar ? `<div class="p-aviso fila-aviso"><span>Hay <b>${aRevisar}</b> producto${aRevisar === 1 ? '' : 's'} creado${aRevisar === 1 ? '' : 's'} en la caja para revisar (costo, categoría y stock).</span>
      <button class="btn chico" id="ir-revisar">Revisarlos</button></div>` : ''}
    <div class="tarjetas">
      <div class="tarjeta"><div class="etq">Ventas de hoy${r.propias ? ' (tuyas)' : ''}</div><div class="valor">${plata(r.total)}</div>
        <div class="muted chico">${r.tickets} venta${r.tickets === 1 ? '' : 's'}${+r.devuelto ? ` · devuelto ${plata(r.devuelto)}` : ''}</div></div>
      ${admin ? `<div class="tarjeta"><div class="etq">Ganancia bruta de hoy</div><div class="valor">${plata(r.ganancia)}</div>
        <div class="muted chico">ventas menos el costo de la mercadería</div></div>` : ''}
      <div class="tarjeta"><div class="etq">Caja</div><div class="valor">${r.turno ? plata(r.turno.esperado) : 'Cerrada'}</div>
        <div class="muted chico">${r.turno ? `efectivo · turno de ${esc(r.turno.usuario)} desde ${hora(r.turno.apertura)}` : '<a href="#/caja">abrir el turno</a>'}</div></div>
      <div class="tarjeta"><div class="etq">Fiado pendiente</div><div class="valor">${plata(r.fiado_pendiente)}</div>
        <div class="muted chico"><a href="#/clientes">ver clientes</a></div></div>
    </div>
    <h3>Últimas ventas${r.propias ? ' tuyas' : ''}</h3>
    <div class="tabla-caja"><table class="tabla">${r.ultimas.length ? `<thead><tr><th>#</th><th>Hora</th><th>Productos</th><th>Vendió</th><th class="num">Total</th></tr></thead><tbody>
      ${r.ultimas.map(v => `<tr><td>${v.numero}</td><td>${hora(v.fecha)}</td><td class="corto">${esc(v.resumen || '')}</td><td>${esc(v.usuario)}</td>
        <td class="num">${+v.devuelto ? `${plata(v.total - v.devuelto)}<div class="aviso-chico"><s>${plata(v.total)}</s> · devuelto ${plata(v.devuelto)}</div>` : plata(v.total)}</td></tr>`).join('')}</tbody>`
      : '<tbody><tr><td class="muted vacio">Todavía no hay ventas hoy.</td></tr></tbody>'}</table></div>
    <p class="muted chico">Actualizado ${fecha(new Date().toISOString())}</p>`;
  const ir = vista.querySelector('#ir-revisar');
  if (ir) ir.onclick = () => { verARevisar(); ctx.ir('#/productos'); };
}
