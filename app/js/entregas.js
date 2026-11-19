// Entregas pendientes (lo vendido que el cliente se lleva cuando llega la mercadería): que se vean fuera de Vender.
// Inicio las lista, Pedidos y Productos las muestran en cada producto, y al cargar una compra se avisa si ya se pueden entregar.
import { llamar } from './base.js';
import { esc, cant, modal } from './ui.js';

// "6 a Juan Perez (11 4444-5555) · venta #23"
export const aQuien = e => `${cant(e.cantidad)}${e.por_peso ? ' kg' : ''} a <b>${esc(e.a_nombre)}</b>${e.telefono ? ` (${esc(e.telefono)})` : ''} · venta #${e.venta}`;

// Las pendientes por producto: { producto_id: [entregas] }
export async function porProducto() {
  const m = {};
  for (const e of await llamar('entregas_pendientes')) (m[e.producto_id] ||= []).push(e);
  return m;
}

// Después de cargar una compra: si llegó mercadería para entregas pendientes, avisar a quién hay que entregarle
export async function avisarListas(productoIds) {
  const ids = new Set(productoIds.map(Number));
  const listas = (await llamar('entregas_pendientes')).filter(e => e.lista && ids.has(+e.producto_id));
  if (!listas.length) return;
  modal('Llegó mercadería para entregas pendientes', `<p>Con esta compra ya se puede entregar:</p>
    <ul class="lista-entregas">${listas.map(e => `<li><b>${esc(e.nombre)}</b>: ${aQuien(e)}</li>`).join('')}</ul>
    <p class="muted chico">Ya está cobrado. Entregalo desde Vender → Entregas pendientes (ahí sale del stock).</p>
    <div class="fila fin"><button class="btn primario" data-cerrar>Entendido</button></div>`, { ancho: true });
}
