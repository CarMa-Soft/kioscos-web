// Impresión de tickets de 58 mm (venta, devolución, cierre de caja), como en la app local.
// Se arma el ticket en #print-area y se llama a window.print(); app.css esconde todo lo demás al imprimir.
// Con Chrome abierto con --kiosk-printing, imprime directo en la impresora predeterminada, sin preguntar.
import { $, esc, plata, cant } from './ui.js';

const fechaHora = iso => iso ? new Date(iso).toLocaleString('es-AR', { day: '2-digit', month: '2-digit', year: '2-digit', hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }) : '';
const nombreForma = (f, v) => f !== 'Fiado' ? f : v.pagos.some(p => p.forma === 'Fiado') ? 'Descontado de su cuenta' : 'A favor en su cuenta';

export function imprimir(html) {
  $('#print-area').innerHTML = html;
  setTimeout(() => window.print(), 100);
}

// Datos del negocio (Ajustes → Datos del negocio)
function encabezado(cfg) {
  const n = cfg.negocio || {};
  return `<div class="c grande">${esc(n.nombre || '')}</div>
    ${n.direccion ? `<div class="c">${esc(n.direccion)}</div>` : ''}${n.telefono ? `<div class="c">Tel. ${esc(n.telefono)}</div>` : ''}${n.cuit ? `<div class="c">CUIT ${esc(n.cuit)}</div>` : ''}`;
}
const pie = cfg => cfg.negocio?.pie_ticket ? `<hr><div class="c">${esc(cfg.negocio.pie_ticket)}</div>` : '';

export function ticketVenta(v, cfg) {
  const efectivo = v.pagos.find(p => p.forma === 'Efectivo');
  return `<div class="ticket">${encabezado(cfg)}<hr>
    <div>Ticket #${v.numero} · ${fechaHora(v.fecha)}</div>${v.cliente ? `<div>Cliente: ${esc(v.cliente.nombre)}</div>` : ''}
    <div class="c chico">Comprobante no válido como factura</div><hr>
    <table>${v.items.map(i => `<tr><td colspan="2">${esc(i.nombre)}</td></tr>
      <tr><td>&nbsp;${cant(i.cantidad)}${i.por_peso ? ' kg' : ''} x ${plata(i.precio)}</td><td class="n">${plata(i.importe)}</td></tr>`).join('')}</table><hr>
    <table>${+v.descuento || +v.recargo ? `<tr><td>Subtotal</td><td class="n">${plata(v.subtotal)}</td></tr>` : ''}
      ${+v.descuento ? `<tr><td>Descuento</td><td class="n">-${plata(v.descuento)}</td></tr>` : ''}
      ${v.pagos.filter(p => +p.recargo).map(p => `<tr><td>Recargo ${esc(p.forma)} ${+p.pct_recargo}%</td><td class="n">+${plata(p.recargo)}</td></tr>`).join('')}
      <tr class="grande"><td>TOTAL</td><td class="n">${plata(v.total)}</td></tr>
      ${v.pagos.map(p => `<tr><td>${esc(p.forma)}</td><td class="n">${plata(p.monto)}</td></tr>`).join('')}
      ${efectivo && +v.paga_con > +efectivo.monto ? `<tr><td>Paga con</td><td class="n">${plata(v.paga_con)}</td></tr><tr><td>Vuelto</td><td class="n">${plata(v.paga_con - efectivo.monto)}</td></tr>` : ''}</table>
    ${v.pendientes?.length ? `<hr><div class="c">PENDIENTE DE ENTREGA</div>${v.pendientes.map(e => `<div>&nbsp;${cant(e.cantidad)} x ${esc(e.nombre)}</div>`).join('')}
      <div>A nombre de: ${esc(v.pendientes[0].a_nombre)}</div>` : ''}
    ${v.anulada ? '<hr><div class="c grande">ANULADA</div>' : ''}${pie(cfg)}</div>`;
}

export function ticketDevolucion(d, v, cfg) {
  return `<div class="ticket">${encabezado(cfg)}<hr>
    <div class="c grande">DEVOLUCIÓN ${esc(d.etiqueta)}</div>
    <div>${fechaHora(d.fecha)} · Ticket #${v.numero} del ${fechaHora(v.fecha)}</div>${v.cliente ? `<div>Cliente: ${esc(v.cliente.nombre)}</div>` : ''}
    <div class="c chico">Comprobante no válido como factura</div><hr>
    <table>${d.items.map(i => `<tr><td colspan="2">${esc(i.nombre)}</td></tr>
      <tr><td>&nbsp;${cant(i.cantidad)}${i.por_peso ? ' kg' : ''}${i.vuelve_stock ? '' : ' (no vuelve al stock)'}</td><td class="n">${plata(i.importe)}</td></tr>`).join('')}</table><hr>
    <table><tr class="grande"><td>REINTEGRO</td><td class="n">${plata(d.total)}</td></tr>
      <tr><td>${esc(nombreForma(d.forma, v))}</td><td class="n">${plata(d.total)}</td></tr></table>
    ${d.motivo ? `<div>Motivo: ${esc(d.motivo)}</div>` : ''}
    <div>Atendió: ${esc(d.usuario)}${d.autorizo ? ` · autorizó ${esc(d.autorizo)}` : ''}</div>
    <br><br><div class="c">______________________</div><div class="c">Firma del cliente</div></div>`;
}

export function ticketCierre(r, cfg) {
  const b = r.billetes, movs = r.movimientos || [];
  return `<div class="ticket">${encabezado(cfg)}<hr><div class="c grande">CIERRE DE CAJA</div>
    <div>Turno de ${esc(r.usuario)}</div><div>Abrió: ${fechaHora(r.apertura)}</div><div>Cerró: ${fechaHora(r.cierre)}</div><hr>
    <table><tr><td>Ventas (${r.ventas})</td><td class="n">${plata(r.total_ventas)}</td></tr>
      ${Object.entries(r.por_forma || {}).map(([f, m]) => `<tr><td>&nbsp;${esc(f)}</td><td class="n">${plata(m)}</td></tr>`).join('')}</table><hr>
    <table><tr><td>Efectivo inicial</td><td class="n">${plata(r.inicial)}</td></tr>
      ${movs.filter(m => !/^(Venta|Anulación venta|Devolución) /.test(m.concepto) && !m.ajuste).map(m => `<tr><td>${m.tipo === 'ingreso' ? '+' : '-'} ${esc(m.concepto)}</td><td class="n">${plata(m.monto)}</td></tr>`).join('')}
      <tr><td>Efectivo esperado</td><td class="n">${plata(r.esperado)}</td></tr><tr><td>Efectivo contado</td><td class="n">${plata(r.contado)}</td></tr>
      <tr class="grande"><td>Diferencia</td><td class="n">${plata(r.diferencia)}</td></tr>
      ${movs.some(m => m.ajuste) ? `<tr><td colspan="2">${+r.diferencia > 0 ? 'Sobrante' : 'Faltante'} registrado en caja</td></tr>` : ''}
      ${+r.retiro ? `<tr><td>Retirado</td><td class="n">${plata(r.retiro)}</td></tr><tr><td>Queda en caja</td><td class="n">${plata(r.contado - r.retiro)}</td></tr>` : ''}</table>
    ${b ? `<hr><div>Conteo de billetes</div><table>${Object.entries(b.detalle || {}).sort((x, y) => +y[0] - +x[0]).map(([val, q]) => `<tr><td>${q} x ${plata(val)}</td><td class="n">${plata(q * val)}</td></tr>`).join('')}
      ${+b.otros ? `<tr><td>Monedas y otros</td><td class="n">${plata(b.otros)}</td></tr>` : ''}</table>` : ''}
    ${r.notas ? `<hr><div>${esc(r.notas)}</div>` : ''}</div>`;
}

// Entrada o salida de mercadería (RI / RE), con lugar para las firmas
export function ticketRemito(r, cfg) {
  const signo = r.tipo === 'ingreso' ? '+' : '-';
  return `<div class="ticket">${encabezado(cfg)}<hr>
    <div class="c grande">${r.tipo === 'ingreso' ? 'ENTRADA' : 'SALIDA'} ${esc(r.etiqueta)}${r.anulado ? ' (ANULADA)' : ''}</div>
    <div>${fechaHora(r.fecha)} · ${esc(r.usuario)}</div><div>Motivo: ${esc(r.motivo)}</div>${r.notas ? `<div>${esc(r.notas)}</div>` : ''}<hr>
    <table>${r.items.map(x => `<tr><td>${esc(x.nombre)}</td><td class="n">${signo}${cant(x.cantidad)}</td></tr>`).join('')}</table>
    <br><br><div class="c">______________________</div><div class="c">Entregó</div>
    <br><br><div class="c">______________________</div><div class="c">Recibió</div></div>`;
}
