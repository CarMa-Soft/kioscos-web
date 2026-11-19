// Inicio: lo de hoy (el empleado ve solo sus ventas; la ganancia, solo el dueño)
import { llamar } from './base.js';
import { esc, plata, hora, fecha, hoyDia, sumarDias } from './ui.js';
import * as cat from './catalogo.js';
import { verARevisar, verParaReponer } from './productos.js';
import { vencimientosModal } from './proveedores.js';
import { aQuien } from './entregas.js';

// Íconos (trazos SVG, toman el color del texto). Los estilos son los de Clientes y Proveedores (clases c- en app.css).
const svg = d => `<svg viewBox="0 0 24 24" aria-hidden="true">${d}</svg>`;
const ICO = {
  ventas: svg('<path d="M4 4h2l2.2 10.2a1.5 1.5 0 0 0 1.5 1.2h7.6a1.5 1.5 0 0 0 1.5-1.1L20.5 8H6.8"/><circle cx="10" cy="19.5" r="1.3"/><circle cx="17" cy="19.5" r="1.3"/>'),
  ganancia: svg('<path d="M3.5 17.5 9 12l4 4 7.5-8"/><path d="M15 8h5.5v5.5"/>'),
  caja: svg('<rect x="3" y="7" width="18" height="12" rx="2"/><path d="M3 11h18M8 7V5h8v2"/>'),
  fiado: svg('<rect x="5" y="3" width="14" height="18" rx="2"/><path d="M9 8h6M9 12h6M9 16h3"/>'),
  paquete: svg('<path d="m12 3 8 4.5v9L12 21l-8-4.5v-9z"/><path d="m4 7.5 8 4.5 8-4.5M12 12v9"/>'),
  recibo: svg('<path d="M6 3h12v18l-3-2-3 2-3-2-3 2z"/><path d="M9 8h6M9 12h6"/>'),
  calendario: svg('<rect x="3.5" y="5" width="17" height="15" rx="2"/><path d="M3.5 10h17M8 3v4M16 3v4"/>'),
  reponer: svg('<path d="m12 3 8 4.5v9L12 21l-8-4.5v-9z"/><path d="M12 8v6M9 11l3 3 3-3"/>'),
};

export async function pantallaInicio(vista, ctx) {
  const admin = ctx.yo.rol === 'admin';
  // entregas pendientes y encargos van en la misma lista; lo de proveedores que vence en los próximos 7 días, solo el dueño
  // (si falla, esa tarjeta no aparece)
  const [r, ent, encs, venc] = await Promise.all([llamar('inicio'), llamar('entregas_pendientes'), llamar('encargos'),
    admin ? llamar('vencimientos', { p_hasta: sumarDias(hoyDia(), 7) }).catch(() => null) : null]);
  const entregas = [...ent, ...encs];
  const aRevisar = admin ? cat.productos().filter(p => p.a_revisar).length : 0;   // creados en la caja con lo mínimo
  // para reponer: del catálogo del navegador (stock mínimo cargado y stock igual o menor)
  const reponer = admin ? cat.productos().filter(p => p.activo !== false && +p.stock_min > 0 && +p.stock <= +p.stock_min).length : 0;
  const aPagar = venc ? venc.proveedores.reduce((s, x) => s + +x.total, 0) : 0;
  const vencido = venc ? venc.proveedores.reduce((s, x) => s + x.deudas.filter(d => d.vencimiento < venc.hoy).reduce((a, d) => a + +d.pendiente, 0), 0) : 0;
  vista.innerHTML = `<div class="cabecera"><div><h2>Hoy</h2><p class="muted">${new Date().toLocaleDateString('es-AR', { weekday: 'long', day: 'numeric', month: 'long' })}</p></div>
      <div class="acciones"><a class="btn primario" href="#/vender">Vender</a>${admin ? '<a class="btn" href="#/reportes">Reportes</a>' : ''}</div></div>
    ${aRevisar ? `<div class="p-aviso fila-aviso"><span>Hay <b>${aRevisar}</b> producto${aRevisar === 1 ? '' : 's'} creado${aRevisar === 1 ? '' : 's'} en la caja para revisar (costo, categoría y stock).</span>
      <button class="btn chico" id="ir-revisar">Revisarlos</button></div>` : ''}
    <div class="c-tarjetas de-a-tres">
      <div class="c-tarjeta verde"><span class="c-ico">${ICO.ventas}</span><div><div class="etq">Ventas de hoy${r.propias ? ' (tuyas)' : ''}</div><div class="valor">${plata(r.total)}</div>
        <div class="c-sub">${r.tickets} venta${r.tickets === 1 ? '' : 's'}${+r.devuelto ? ` · devuelto ${plata(r.devuelto)}` : ''}</div></div></div>
      ${admin ? `<div class="c-tarjeta azul"><span class="c-ico">${ICO.ganancia}</span><div><div class="etq">Ganancia bruta de hoy</div><div class="valor">${plata(r.ganancia)}</div>
        <div class="c-sub">ventas menos el costo de la mercadería</div></div></div>` : ''}
      <div class="c-tarjeta ${r.turno ? 'violeta' : 'gris'}"><span class="c-ico">${ICO.caja}</span><div><div class="etq">Caja</div><div class="valor">${r.turno ? plata(r.turno.esperado) : 'Cerrada'}</div>
        <div class="c-sub">${r.turno ? `efectivo · turno de ${esc(r.turno.usuario)} desde ${hora(r.turno.apertura)}` : '<a href="#/caja">abrir el turno</a>'}</div></div></div>
      <div class="c-tarjeta rojo"><span class="c-ico">${ICO.fiado}</span><div><div class="etq">Fiado pendiente</div><div class="valor">${plata(r.fiado_pendiente)}</div>
        <div class="c-sub"><a href="#/clientes">ver clientes</a></div></div></div>
      ${venc ? `<div class="c-tarjeta ${vencido > 0.004 ? 'rojo' : aPagar > 0.004 ? 'naranja' : 'gris'}"><span class="c-ico">${ICO.calendario}</span><div>
        <div class="etq">A pagar a proveedores (7 días)</div><div class="valor">${plata(aPagar)}</div>
        <div class="c-sub">${vencido > 0.004 ? `<b class="mal">${plata(vencido)} ya vencido</b> · ` : ''}${venc.proveedores.length
          ? `${venc.proveedores.length} proveedor${venc.proveedores.length === 1 ? '' : 'es'} · <button class="link" id="ver-venc">ver vencimientos</button>` : 'nada que pagar esta semana'}</div></div></div>` : ''}
      ${admin ? `<div class="c-tarjeta ${reponer ? 'naranja' : 'gris'}"><span class="c-ico">${ICO.reponer}</span><div>
        <div class="etq">Productos para reponer</div><div class="valor">${reponer}</div>
        <div class="c-sub">${reponer ? '<button class="link" id="ver-reponer">ver cuáles</button>' : 'ninguno debajo del stock mínimo'}</div></div></div>` : ''}
    </div>
    ${entregas.length ? `<div class="c-titulo">${ICO.paquete}<h3>Entregas pendientes y encargos</h3><a class="btn chico" href="#/vender">Entregar desde Vender</a></div>
    <p class="muted chico">Las entregas ya están cobradas; los encargos se cobran al venir a buscarlos (se descuenta la seña).</p>
    <div class="tabla-caja c-tabla"><table class="tabla"><thead><tr><th>Producto</th><th>A quién</th><th>Estado</th></tr></thead><tbody>
      ${entregas.map(e => `<tr><td><b>${esc(e.nombre)}</b></td><td>${aQuien(e)}</td>
        <td>${e.venta == null ? '<span class="etiqueta info">encargo</span> ' : ''}${e.lista ? '<span class="etiqueta bien">lista para entregar</span>' : '<span class="etiqueta pendiente">esperando mercadería</span>'}</td></tr>`).join('')}</tbody></table></div>` : ''}
    <div class="c-titulo">${ICO.recibo}<h3>Últimas ventas${r.propias ? ' tuyas' : ''}</h3></div>
    <div class="tabla-caja c-tabla"><table class="tabla">${r.ultimas.length ? `<thead><tr><th>#</th><th>Hora</th><th>Productos</th><th>Vendió</th><th class="num">Total</th></tr></thead><tbody>
      ${r.ultimas.map(v => `<tr><td>${v.numero}</td><td>${hora(v.fecha)}</td><td class="corto">${esc(v.resumen || '')}</td><td>${esc(v.usuario)}</td>
        <td class="num">${+v.devuelto ? `${plata(v.total - v.devuelto)}<div class="aviso-chico"><s>${plata(v.total)}</s> · devuelto ${plata(v.devuelto)}</div>` : plata(v.total)}</td></tr>`).join('')}</tbody>`
      : '<tbody><tr><td class="muted vacio">Todavía no hay ventas hoy.</td></tr></tbody>'}</table></div>
    <p class="muted chico">Actualizado ${fecha(new Date().toISOString())}</p>`;
  const ir = vista.querySelector('#ir-revisar');
  if (ir) ir.onclick = () => { verARevisar(); ctx.ir('#/productos'); };
  const vr = vista.querySelector('#ver-reponer');
  if (vr) vr.onclick = () => { verParaReponer(); ctx.ir('#/productos'); };
  const vv = vista.querySelector('#ver-venc');
  if (vv) vv.onclick = () => vencimientosModal(() => ctx.ir('#/proveedores'));   // "Pagar" en la ventana lleva a Proveedores
}
