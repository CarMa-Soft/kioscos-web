// Proveedores (solo dueño): lista con lo que se les debe, ficha con la cuenta, pagos, ajustes y datos
import { llamar } from './base.js';
import { $, $$, esc, plata, fecha, dia, hoyDia, sumarDias, textoVence, numero, aviso, correr, modal, confirmar, subpantalla, tarjeta } from './ui.js';
import { verCompra } from './compras.js';

// Lo elegido se mantiene al ir y volver de la sección
let filtro = '', grupo = 'todos';
const textoSaldo = s => +s > 0.004 ? 'Le debés ' + plata(s) : +s < -0.004 ? 'A favor ' + plata(-s) : 'Al día';

// Íconos de las tarjetas (trazos SVG, toman el color del texto). Los estilos son los de Clientes (clases c- en app.css).
const svg = d => `<svg viewBox="0 0 24 24" aria-hidden="true">${d}</svg>`;
const ICO = {
  plata: svg('<rect x="2.5" y="6" width="19" height="12" rx="2"/><circle cx="12" cy="12" r="2.6"/>'),
  alerta: svg('<circle cx="12" cy="12" r="9"/><path d="M12 7.5v5.5M12 16.5v.01"/>'),
  camion: svg('<path d="M2.5 6.5h11v9h-11zM13.5 9.5h4l3 3v3h-7"/><circle cx="6.5" cy="17.5" r="1.8"/><circle cx="17" cy="17.5" r="1.8"/>'),
  lupa: svg('<circle cx="11" cy="11" r="6.5"/><path d="m20 20-4.2-4.2"/>'),
  calendario: svg('<rect x="3.5" y="5" width="17" height="15" rx="2"/><path d="M3.5 10h17M8 3v4M16 3v4"/>'),
  recibo: svg('<path d="M6 3h12v18l-3-2-3 2-3-2-3 2z"/><path d="M9 8h6M9 12h6"/>'),
  lista: svg('<path d="M9 6h11M9 12h11M9 18h11"/><circle cx="4.5" cy="6" r="1"/><circle cx="4.5" cy="12" r="1"/><circle cx="4.5" cy="18" r="1"/>'),
};

export async function pantallaProveedores(vista, ctx) {
  const lista = await llamar('proveedores');
  const deben = lista.filter(p => +p.saldo > 0.004);
  vista.innerHTML = `<div class="cabecera"><h2>Proveedores</h2><div class="acciones"><a class="btn" href="#/compras">Compras</a><button class="btn" id="vencimientos">📅 Vencimientos</button><button class="btn primario" id="nuevo">＋ Nuevo proveedor</button></div></div>
    <div class="c-tarjetas">
      <div class="c-tarjeta rojo" id="t-deben" title="Ver a quiénes les debés"><span class="c-ico">${ICO.plata}</span><div><div class="etq">Le debés a proveedores</div><div class="valor">${plata(deben.reduce((s, p) => s + +p.saldo, 0))}</div></div></div>
      <div class="c-tarjeta naranja" id="t-cuantos" title="Ver los vencimientos"><span class="c-ico">${ICO.alerta}</span><div><div class="etq">Proveedores a los que les debés</div><div class="valor">${deben.length}</div></div></div>
      <div class="c-tarjeta verde" id="t-todos" title="Ver todos"><span class="c-ico">${ICO.camion}</span><div><div class="etq">Total de proveedores</div><div class="valor">${lista.length}</div></div></div>
    </div>
    <div class="c-filtros">
      <label class="c-buscar">${ICO.lupa}<input id="filtro" placeholder="Buscar por nombre o CUIT…" value="${esc(filtro)}" autocomplete="off"></label>
      <div class="chips" id="grupos"></div>
    </div>
    <div class="tabla-caja c-tabla"><table class="tabla" id="tabla"></table></div>`;
  const GRUPOS = [['todos', 'Todos', () => true], ['deben', 'Les debés', p => +p.saldo > 0.004]];
  const pintar = () => {
    const f = filtro.trim().toLowerCase();
    const busca = p => !f || p.nombre.toLowerCase().includes(f) || (p.cuit || '').includes(f);
    $('#grupos').innerHTML = GRUPOS.map(([g, nombre, cond]) => `<button class="chip ${g === grupo ? 'elegido' : ''}" data-grupo="${g}">${nombre} <span class="c-cuenta">${lista.filter(p => busca(p) && cond(p)).length}</span></button>`).join('');
    $$('[data-grupo]').forEach(b => b.onclick = () => { grupo = b.dataset.grupo; pintar(); });
    const cond = GRUPOS.find(x => x[0] === grupo)[2];
    const ver = lista.filter(p => busca(p) && cond(p));
    const saldo = s => +s > 0.004 ? `<span class="c-saldo debe">Le debés ${plata(s)}</span>` : +s < -0.004 ? `<span class="c-saldo favor">A favor ${plata(-s)}</span>` : '<span class="c-saldo">Al día</span>';
    $('#tabla').innerHTML = ver.length ? `<thead><tr><th>Proveedor</th><th>Contacto</th><th>Última compra</th><th class="num">Productos</th><th class="num">Cuenta</th></tr></thead><tbody>
      ${ver.map(p => `<tr class="clic" data-id="${p.id}"><td><div class="c-nombre"><span class="c-inicial ${+p.saldo > 0.004 ? 'debe' : ''}">${esc(p.nombre.trim().charAt(0).toUpperCase())}</span>
          <div><b>${esc(p.nombre)}</b>${p.cuit ? `<div class="muted chico">CUIT ${esc(p.cuit)}</div>` : ''}</div></div></td>
        <td>${esc([p.contacto, p.telefono].filter(Boolean).join(' · '))}</td><td>${p.ultima_compra ? `${fecha(p.ultima_compra.fecha)} · ${plata(p.ultima_compra.total)}` : '<span class="muted">—</span>'}</td>
        <td class="num">${p.productos}</td><td class="num">${saldo(p.saldo)}</td></tr>`).join('')}</tbody>`
      : `<tbody><tr><td class="muted vacio">${lista.length ? (grupo === 'deben' && !f ? 'No le debés nada a ningún proveedor.' : 'Ningún proveedor coincide.') : 'Todavía no hay proveedores.'}</td></tr></tbody>`;
    $$('tr[data-id]').forEach(tr => tr.onclick = () => ficha(+tr.dataset.id, ctx, vista));
  };
  $('#filtro').oninput = e => { filtro = e.target.value; pintar(); };
  $('#nuevo').onclick = () => formProveedor(null, () => ctx.recargar());
  $('#vencimientos').onclick = () => vencimientosModal(id => ficha(id, ctx, vista));
  tarjeta($('#t-deben'), () => { grupo = 'deben'; pintar(); });
  tarjeta($('#t-cuantos'), () => vencimientosModal(id => ficha(id, ctx, vista)));
  tarjeta($('#t-todos'), () => { grupo = 'todos'; filtro = ''; $('#filtro').value = ''; pintar(); });
  pintar();
}

// La cuenta del proveedor: una pantalla dentro de Proveedores (no una ventana), igual que la ficha del cliente. "← Proveedores",
// "atrás" y Esc vuelven a la lista como estaba. Pagar, ajustar y editar siguen siendo ventanas chicas.
let sub = null;
function ficha(id, ctx, vista) {
  correr(async () => {
    const p = await llamar('cuenta_proveedor', { p_id: id });
    let acum = 0;
    const movs = p.movimientos.map(m => ({ ...m, saldo: (acum = Math.round((acum + +m.monto) * 100) / 100) })).reverse();
    const debe = +p.saldo > 0.004, aFavor = +p.saldo < -0.004;
    const proxima = p.deudas.map(d => d.vencimiento).filter(Boolean).sort()[0];
    const vencido = p.deudas.filter(d => d.vencimiento && d.vencimiento < hoyDia()).reduce((x, d) => x + +d.pendiente, 0);
    vista.innerHTML = `<div class="cabecera"><div><button class="link cf-volver" id="volver">← Proveedores</button><h2>${esc(p.nombre)}</h2>
        <p class="muted">${[p.cuit && 'CUIT ' + p.cuit, p.contacto, p.telefono && 'Tel. ' + p.telefono].filter(Boolean).map(esc).join(' · ') || 'Sin datos de contacto'}</p></div>
      <div class="acciones"><button class="btn primario" id="pagar">Registrar pago</button>
        ${+p.sin_aplicar > 0.004 && p.deudas.length ? `<button class="btn" id="aplicar">Aplicar lo que está a cuenta (${plata(p.sin_aplicar)})</button>` : ''}
        <button class="btn" id="ajuste">Saldo inicial / ajuste</button>
        <button class="btn" id="editar">Editar datos</button><button class="btn peligro" id="eliminar">Eliminar</button></div></div>
    <div class="c-tarjetas">
      <div class="c-tarjeta ${debe ? 'rojo' : 'verde'}"><span class="c-ico">${ICO.plata}</span><div><div class="etq">Cuenta</div>
        <div class="valor">${debe ? plata(p.saldo) : aFavor ? plata(-p.saldo) : 'Al día'}</div>
        <div class="c-sub">${debe ? `le debés · ${p.deudas.length} factura${p.deudas.length === 1 ? '' : 's'} pendiente${p.deudas.length === 1 ? '' : 's'}` : aFavor ? 'a tu favor' : 'no le debés nada'}</div></div></div>
      <div class="c-tarjeta ${vencido > 0.004 ? 'rojo' : proxima ? 'naranja' : 'gris'}"><span class="c-ico">${ICO.calendario}</span><div><div class="etq">${vencido > 0.004 ? 'Vencido desde' : 'Próximo vencimiento'}</div>
        <div class="valor">${proxima ? dia(proxima) : '—'}</div>
        <div class="c-sub">${vencido > 0.004 ? `<b class="mal">${plata(vencido)} ya vencido</b>` : proxima ? textoVence(proxima) : 'nada que pagar'}</div></div></div>
      <div class="c-tarjeta azul"><span class="c-ico">${ICO.camion}</span><div><div class="etq">Plazo y visita</div>
        <div class="valor">${p.plazo != null ? `${p.plazo} días` : 'Sin plazo'}</div>
        <div class="c-sub">${p.dias ? 'visita: ' + esc(p.dias) : 'sin día de visita cargado'}</div></div></div>
    </div>
    <div class="cf-cols"><section>
      <div class="c-titulo">${ICO.recibo}<h3>Facturas pendientes</h3></div>
      <div class="tabla-caja c-tabla"><table class="tabla">${p.deudas.length ? `<thead><tr><th>Factura</th><th>Fecha</th><th>Vence</th><th class="num">Importe</th><th class="num">Pagado</th><th class="num">Pendiente</th></tr></thead><tbody>
        ${p.deudas.map(d => `<tr><td class="nowrap">${linkCompra(d.compra_id, nombreDeuda(d))}</td><td class="nowrap">${dia(d.fecha_factura)}</td><td>${dia(d.vencimiento)}<div class="chico">${textoVence(d.vencimiento)}</div></td>
          <td class="num nowrap">${plata(d.importe)}</td><td class="num ok nowrap">${+d.aplicado ? plata(d.aplicado) : ''}</td><td class="num nowrap"><b>${plata(d.pendiente)}</b></td></tr>`).join('')}</tbody>`
        : '<tbody><tr><td class="muted vacio">No le debés ninguna factura.</td></tr></tbody>'}</table></div>
      ${+p.sin_aplicar > 0.004 ? `<p class="chico">A cuenta, sin aplicar a ninguna factura: <b class="ok">${plata(p.sin_aplicar)}</b></p>` : ''}
      ${p.notas ? `<p class="muted chico">Notas: ${esc(p.notas)}</p>` : ''}
    </section><section>
      <div class="c-titulo">${ICO.lista}<h3>Movimientos</h3></div>
      <div class="tabla-caja c-tabla"><table class="tabla">${movs.length ? `<thead><tr><th>Fecha</th><th>Concepto</th><th class="num">Compra / suma</th><th class="num">Pagado / resta</th><th class="num">Saldo</th><th></th></tr></thead><tbody>
        ${movs.map(x => `<tr class="${x.anulado ? 'anulada' : ''}"><td class="nowrap">${fecha(x.fecha)}</td><td>${linkCompra(x.compra_id, x.concepto)}${x.forma ? ` <span class="muted">(${esc(x.forma)}${x.de_caja ? ', de la caja' : ''})</span>` : ''}<div class="muted chico">${esc(x.usuario)}</div></td>
          <td class="num nowrap">${+x.monto > 0 ? plata(x.monto) : ''}</td><td class="num ok nowrap">${+x.monto < 0 ? plata(-x.monto) : ''}</td><td class="num nowrap">${plata(x.saldo)}</td>
          <td class="num">${['pago', 'ajuste'].includes(x.tipo) && !x.compra_id && !x.anulado ? `<button class="link" data-anular="${x.id}">Anular</button>` : ''}</td></tr>`).join('')}</tbody>`
        : '<tbody><tr><td class="muted vacio">Sin movimientos. Si ya le debías algo, cargalo con "Saldo inicial / ajuste".</td></tr></tbody>'}</table></div>
    </section></div>`;
    window.scrollTo(0, 0);
    if (!sub) sub = subpantalla(() => { sub = null; ctx.recargar(); });
    $('#volver').onclick = () => sub.cerrar();
    const otraVez = () => ficha(id, ctx, vista);
    $('#pagar').onclick = () => pagar(p, otraVez);
    if ($('#aplicar')) $('#aplicar').onclick = () => aplicar(p, otraVez);
    $('#ajuste').onclick = () => ajuste(p, movs.length, otraVez);
    $('#editar').onclick = () => formProveedor(p, otraVez);
    // la factura abre el detalle de la compra (el mismo de Compras); si se anula, devuelve o carga la factura, se vuelve a armar la ficha
    $$('[data-compra]', vista).forEach(b => b.onclick = () => verCompra(+b.dataset.compra, { ...ctx, recargar: otraVez }));
    $('#eliminar').onclick = async () => {
      if (!await confirmar('Eliminar proveedor', `¿Eliminar a ${p.nombre}? Solo se puede si no tiene compras y su cuenta está en cero.`, 'Eliminar')) return;
      correr(async () => { await llamar('eliminar_proveedor', { p_id: p.id }); aviso('Proveedor eliminado', 'ok'); sub.cerrar(); });
    };
    $$('[data-anular]', vista).forEach(b => b.onclick = async () => {
      const x = movs.find(y => y.id === +b.dataset.anular);
      if (!await confirmar('Anular movimiento', `Se anula "${x.concepto}" por ${plata(Math.abs(x.monto))}${x.de_caja ? ' y la plata vuelve a la caja del turno abierto' : ''}.`, 'Anular')) return;
      correr(async () => { await llamar('anular_mov_proveedor', { p_id: x.id }); aviso('Movimiento anulado', 'ok'); otraVez(); });
    });
  });
}

function pagar(p, despues) {
  correr(async () => {
    const caja = await llamar('estado_caja');
    const m = modal(`Pago a ${p.nombre}`, `<form class="form" id="f-pago"><p>${textoSaldo(p.saldo)}</p>
      <label>Monto<input class="input grande" name="monto" inputmode="decimal" required autofocus value="${+p.saldo > 0 ? p.saldo : ''}"></label>
      <label>De dónde sale<select class="input" name="origen">${caja.turno ? caja.formas_pago.map(f => `<option value="caja:${esc(f)}">De la caja · ${esc(f)}</option>`).join('') : ''}
        <option value="aparte">Aparte (no sale de la caja)</option></select></label>
      <label id="como-l" ${caja.turno ? 'hidden' : ''}>Cómo se pagó<input class="input" name="como" placeholder="ej: transferencia del banco, cheque"></label>
      <label>Nota <span class="muted">(opcional)</span><input class="input" name="concepto" maxlength="120" placeholder="Pago"></label>
      ${caja.turno ? '' : '<p class="muted chico">La caja está cerrada: solo se puede registrar un pago hecho aparte.</p>'}
      <h3>Qué facturas pagás</h3><div id="aplicacion"></div>
      <div class="fila fin"><button type="button" class="btn" data-cerrar>Cancelar</button><button class="btn primario">Registrar pago</button></div></form>`, { ancho: true });
    $('[name=origen]', m.el).onchange = e => { $('#como-l', m.el).hidden = e.target.value !== 'aparte'; };
    const ap = tablaAplicacion($('#aplicacion', m.el), p.deudas || []);
    const montoIn = $('[name=monto]', m.el);
    ap.rellenar(numero(montoIn.value) || 0);
    montoIn.oninput = () => ap.rellenar(numero(montoIn.value) || 0);
    $('#f-pago', m.el).onsubmit = e => {
      e.preventDefault();
      const f = new FormData(e.target), monto = numero(f.get('monto')), aparte = f.get('origen') === 'aparte';
      if (!(monto > 0)) return aviso('Poné el monto');
      if (ap.aplicado() > monto + 0.004) return aviso('Aplicás a las facturas más de lo que pagás');
      correr(async () => {
        const r = await llamar('pagar_proveedor', { p_proveedor_id: p.id, p_monto: monto, p_de_caja: !aparte, p_forma: aparte ? f.get('como') : f.get('origen').slice(5),
          p_concepto: f.get('concepto'), p_aplicaciones: ap.datos() });
        m.cerrar(); aviso(`Pago registrado. ${textoSaldo(r.saldo)}`, 'ok'); despues();
      });
    };
  });
}

function ajuste(p, hayMovimientos, despues) {
  const m = modal('Saldo inicial / ajuste', `<form class="form" id="f-aj"><p class="muted">Para cargar lo que ya le debías antes de usar la cuenta, o corregir un error. No mueve plata de la caja.</p>
    <label>Tipo<select class="input" name="tipo"><option value="1">Suma deuda (le debés más)</option><option value="-1">Resta deuda (nota de crédito, corrección)</option></select></label>
    <label>Monto<input class="input" name="monto" inputmode="decimal" required autofocus></label>
    <label id="vence-l">Vence<input class="input" type="date" name="vencimiento" value="${hoyDia()}"></label>
    <label>Concepto<input class="input" name="concepto" maxlength="120" placeholder="${hayMovimientos ? 'ej: nota de crédito, corrección' : 'Saldo inicial'}"></label>
    <div class="fila fin"><button type="button" class="btn" data-cerrar>Cancelar</button><button class="btn primario">Guardar</button></div></form>`);
  $('[name=tipo]', m.el).onchange = e => { $('#vence-l', m.el).hidden = e.target.value !== '1'; };
  $('#f-aj', m.el).onsubmit = e => {
    e.preventDefault();
    const f = new FormData(e.target), monto = numero(f.get('monto'));
    if (!(monto > 0)) return aviso('Poné el monto');
    correr(async () => {
      await llamar('ajuste_proveedor', { p_proveedor_id: p.id, p_monto: monto * +f.get('tipo'), p_concepto: f.get('concepto'),
        p_vencimiento: f.get('tipo') === '1' ? f.get('vencimiento') || null : null });
      m.cerrar(); despues();
    });
  };
}

// Alta o edición de un proveedor; alGuardar recibe el proveedor guardado. También la usa Compras.
export function formProveedor(p, alGuardar) {
  const v = p || {};
  const m = modal(p ? 'Editar proveedor' : 'Nuevo proveedor', `<form class="form ancho" id="f-prov">
    <div class="fila"><label class="crece">Nombre<input class="input" name="nombre" maxlength="80" required value="${esc(v.nombre || '')}" autofocus></label>
      <label class="crece">CUIT <span class="muted">(opcional)</span><input class="input mono" name="cuit" value="${esc(v.cuit || '')}" placeholder="30-12345678-9"></label></div>
    <div class="fila"><label class="crece">Contacto (preventista)<input class="input" name="contacto" value="${esc(v.contacto || '')}"></label>
      <label class="crece">Teléfono<input class="input" name="telefono" value="${esc(v.telefono || '')}"></label></div>
    <div class="fila"><label class="crece">Días de visita / pedido<input class="input" name="dias" value="${esc(v.dias || '')}" placeholder="ej: martes y viernes"></label>
      <label class="crece">Días de plazo para pagar<input class="input" name="plazo" inputmode="numeric" value="${v.plazo ?? ''}" placeholder="ej: 30"></label></div>
    <label>Notas<input class="input" name="notas" value="${esc(v.notas || '')}"></label>
    <div class="fila fin"><button type="button" class="btn" data-cerrar>Cancelar</button><button class="btn primario">Guardar</button></div></form>`, { ancho: true });
  $('#f-prov', m.el).onsubmit = e => {
    e.preventDefault();
    const f = new FormData(e.target);
    const datos = { id: p?.id ?? null, ...Object.fromEntries(['nombre', 'cuit', 'contacto', 'telefono', 'dias', 'plazo', 'notas'].map(k => [k, f.get(k)])) };
    correr(async () => { const r = await llamar('guardar_proveedor', { p: datos }); m.cerrar(); aviso('Proveedor guardado', 'ok'); alGuardar(r); });
  };
}

// ---------- Aplicación de pagos a facturas (5b) ----------
// Nombre de una deuda: la factura (o el remito, si todavía no llegó) o el concepto del saldo inicial
const nombreDeuda = x => x.compra_id
  ? (x.comprobante || (x.remito ? 'Remito ' + x.remito : 'Compra sin número')) + (x.factura_pendiente ? ' · factura pendiente' : '')
  : (x.comprobante || 'Saldo inicial');
// En la ficha, la factura es un enlace al detalle de la compra
const linkCompra = (compraId, texto) => compraId ? `<button class="link" data-compra="${compraId}" title="Ver la compra">${esc(texto)}</button>` : esc(texto);

// Tabla para elegir qué facturas se pagan y cuánto de cada una. Se completa sola con las que vencen primero hasta cubrir
// el total, y se puede cambiar (destildar, tildar otras, aplicación parcial).
function tablaAplicacion(caja, deudas) {
  const filas = deudas.map(d => ({ d, tilde: false, monto: '' }));
  let total = 0;
  const aplicado = () => Math.round(filas.reduce((s, f) => s + (f.tilde ? (numero(f.monto) || 0) : 0), 0) * 100) / 100;
  function pintar() {
    if (!filas.length) { caja.innerHTML = '<p class="muted chico">No hay facturas pendientes: todo queda a cuenta, sin aplicar.</p>'; return; }
    const libre = Math.round((total - aplicado()) * 100) / 100;
    caja.innerHTML = `<div class="tabla-caja"><table class="tabla"><thead><tr><th></th><th>Factura</th><th>Vence</th><th class="num">Pendiente</th><th class="num">Aplica</th></tr></thead><tbody>
      ${filas.map((f, k) => `<tr><td><input type="checkbox" data-t="${k}" ${f.tilde ? 'checked' : ''}></td><td>${esc(nombreDeuda(f.d))}</td>
        <td>${dia(f.d.vencimiento)}<div class="chico">${textoVence(f.d.vencimiento)}</div></td><td class="num">${plata(f.d.pendiente)}</td>
        <td class="num"><input class="input corto" data-m="${k}" value="${esc(f.monto)}" inputmode="decimal" ${f.tilde ? '' : 'disabled'}></td></tr>`).join('')}</tbody></table></div>
      <p class="chico">Aplicado <b>${plata(aplicado())}</b> · sin aplicar <b class="${libre < -0.004 ? 'mal' : ''}">${plata(libre)}</b>${libre > 0.004 ? ' <span class="muted">(queda a cuenta)</span>' : libre < -0.004 ? ' <span class="mal">(aplicás más de lo que hay)</span>' : ''}</p>`;
    $$('[data-t]', caja).forEach(x => x.onchange = () => {
      const f = filas[+x.dataset.t];
      f.tilde = x.checked;
      f.monto = f.tilde ? String(Math.max(0, Math.min(+f.d.pendiente, Math.round((total - aplicado()) * 100) / 100)) || +f.d.pendiente) : '';
      pintar();
    });
    $$('[data-m]', caja).forEach(i => i.onchange = () => { const f = filas[+i.dataset.m]; f.monto = String(Math.min(+f.d.pendiente, Math.max(0, numero(i.value) || 0))); pintar(); });
  }
  return {
    rellenar(t) {
      total = Math.max(0, +t || 0);
      let resta = total;
      for (const f of filas) { const m = Math.round(Math.min(+f.d.pendiente, resta) * 100) / 100; f.tilde = m > 0.004; f.monto = f.tilde ? String(m) : ''; resta -= m; }
      pintar();
    },
    aplicado,
    datos: () => filas.filter(f => f.tilde && numero(f.monto) > 0.004).map(f => ({ compra_id: f.d.compra_id, deuda_id: f.d.deuda_id, monto: numero(f.monto) })),
  };
}

function aplicar(p, despues) {
  const m = modal(`Aplicar a facturas — ${p.nombre}`, `<p>Tenés <b>${plata(p.sin_aplicar)}</b> a cuenta sin aplicar. Elegí a qué facturas va. <b>No mueve plata.</b></p>
    <div id="aplicacion"></div><div class="fila fin"><button class="btn" data-cerrar>Cancelar</button><button class="btn primario" id="ok">Aplicar</button></div>`, { ancho: true });
  const ap = tablaAplicacion($('#aplicacion', m.el), p.deudas);
  ap.rellenar(p.sin_aplicar);
  $('#ok', m.el).onclick = () => {
    if (!ap.datos().length) return aviso('Tildá al menos una factura');
    if (ap.aplicado() > +p.sin_aplicar + 0.004) return aviso('Aplicás más de lo que hay a cuenta');
    correr(async () => { await llamar('aplicar_proveedor', { p_proveedor_id: p.id, p_aplicaciones: ap.datos() }); m.cerrar(); aviso('Aplicado', 'ok'); despues(); });
  };
}

// Qué hay que pagar hasta una fecha, por proveedor
let vencHasta = null;
export function vencimientosModal(alPagar) {
  vencHasta ??= sumarDias(hoyDia(), 7);
  const m = modal('Vencimientos: qué tenés que pagar', `<div class="fila"><label>Hasta el día <input class="input" type="date" id="v-hasta" value="${vencHasta}"></label>
      <span class="chips">${[['Hoy', 0], ['7 días', 7], ['15 días', 15], ['30 días', 30]].map(([l, n]) => `<button class="chip" data-d="${n}">${l}</button>`).join('')}</span></div>
    <div id="v-lista"><p class="muted">Cargando…</p></div><div class="fila fin"><button class="btn primario" data-cerrar>Cerrar</button></div>`, { ancho: true });
  const cargar = () => correr(async () => {
    const r = await llamar('vencimientos', { p_hasta: vencHasta });
    const total = r.proveedores.reduce((s, x) => s + +x.total, 0);
    const vencido = r.proveedores.reduce((s, x) => s + x.deudas.filter(d => d.vencimiento < r.hoy).reduce((a, d) => a + +d.pendiente, 0), 0);
    $('#v-lista', m.el).innerHTML = !r.proveedores.length ? `<p class="muted">No hay nada que pagar hasta el ${dia(r.hasta)}.</p>` : `
      <div class="tarjetas"><div class="tarjeta"><div class="etq">A pagar hasta el ${dia(r.hasta)}</div><div class="valor mal">${plata(total)}</div></div>
        <div class="tarjeta"><div class="etq">Ya vencido</div><div class="valor ${vencido > 0.004 ? 'mal' : ''}">${plata(vencido)}</div></div></div>
      ${r.proveedores.map(x => `<div class="recuadro-blanco"><div class="fila entre"><h3>${esc(x.nombre)} · ${plata(x.total)}</h3><button class="btn chico" data-pagar="${x.id}">Registrar pago</button></div>
        ${+x.sin_aplicar > 0.004 ? `<p class="ok chico">Tiene ${plata(x.sin_aplicar)} a cuenta sin aplicar</p>` : ''}
        <table class="tabla deudas"><tbody>${x.deudas.map(d => `<tr><td>${esc(nombreDeuda(d))}</td><td>${dia(d.vencimiento)}</td><td>${textoVence(d.vencimiento)}</td><td class="num">${plata(d.pendiente)}</td></tr>`).join('')}</tbody></table></div>`).join('')}`;
    $$('[data-pagar]', m.el).forEach(b => b.onclick = () => { m.cerrar(); alPagar(+b.dataset.pagar); });
  });
  $('#v-hasta', m.el).onchange = e => { vencHasta = e.target.value || hoyDia(); cargar(); };
  $$('[data-d]', m.el).forEach(b => b.onclick = () => { vencHasta = sumarDias(hoyDia(), +b.dataset.d); $('#v-hasta', m.el).value = vencHasta; cargar(); });
  cargar();
}
