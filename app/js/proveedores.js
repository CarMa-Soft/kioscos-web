// Proveedores (solo dueño): lista con lo que se les debe, ficha con la cuenta, pagos, ajustes y datos
import { llamar } from './base.js';
import { $, $$, esc, plata, fecha, numero, aviso, correr, modal, confirmar } from './ui.js';

let filtro = '';
const textoSaldo = s => +s > 0.004 ? 'Le debés ' + plata(s) : +s < -0.004 ? 'A favor ' + plata(-s) : 'Al día';

export async function pantallaProveedores(vista, ctx) {
  const lista = await llamar('proveedores');
  const deben = lista.filter(p => +p.saldo > 0.004);
  vista.innerHTML = `<div class="cabecera"><h2>Proveedores</h2><div class="acciones"><a class="btn" href="#/compras">Compras</a><button class="btn primario" id="nuevo">＋ Nuevo proveedor</button></div></div>
    <div class="tarjetas"><div class="tarjeta"><div class="etq">Le debés a proveedores</div><div class="valor">${plata(deben.reduce((s, p) => s + +p.saldo, 0))}</div></div>
      <div class="tarjeta"><div class="etq">Proveedores a los que les debés</div><div class="valor">${deben.length}</div></div>
      <div class="tarjeta"><div class="etq">Proveedores</div><div class="valor">${lista.length}</div></div></div>
    <input class="input" id="filtro" placeholder="Buscar proveedor" value="${esc(filtro)}" autocomplete="off">
    <div class="tabla-caja"><table class="tabla" id="tabla"></table></div>`;
  const pintar = () => {
    const f = filtro.trim().toLowerCase();
    const ver = lista.filter(p => !f || p.nombre.toLowerCase().includes(f) || (p.cuit || '').includes(f));
    $('#tabla').innerHTML = ver.length ? `<thead><tr><th>Proveedor</th><th>Contacto</th><th>Última compra</th><th class="num">Productos</th><th class="num">Cuenta</th></tr></thead><tbody>
      ${ver.map(p => `<tr class="clic" data-id="${p.id}"><td>${esc(p.nombre)}${p.cuit ? `<div class="muted chico">CUIT ${esc(p.cuit)}</div>` : ''}</td>
        <td>${esc([p.contacto, p.telefono].filter(Boolean).join(' · '))}</td><td>${p.ultima_compra ? `${fecha(p.ultima_compra.fecha)} · ${plata(p.ultima_compra.total)}` : '—'}</td>
        <td class="num">${p.productos}</td><td class="num ${+p.saldo > 0.004 ? 'mal' : ''}"><b>${textoSaldo(p.saldo)}</b></td></tr>`).join('')}</tbody>`
      : `<tbody><tr><td class="muted vacio">${lista.length ? 'Ningún proveedor coincide.' : 'Todavía no hay proveedores.'}</td></tr></tbody>`;
    $$('tr[data-id]').forEach(tr => tr.onclick = () => ficha(+tr.dataset.id, ctx));
  };
  $('#filtro').oninput = e => { filtro = e.target.value; pintar(); };
  $('#nuevo').onclick = () => formProveedor(null, () => ctx.recargar());
  pintar();
}

function ficha(id, ctx) {
  correr(async () => {
    const p = await llamar('cuenta_proveedor', { p_id: id });
    let acum = 0;
    const movs = p.movimientos.map(m => ({ ...m, saldo: (acum = Math.round((acum + +m.monto) * 100) / 100) })).reverse();
    const m = modal(p.nombre, `<p class="muted">${[p.cuit && 'CUIT ' + p.cuit, p.contacto, p.telefono && 'Tel. ' + p.telefono, p.dias && 'Visita: ' + p.dias,
        p.plazo != null && `Plazo: ${p.plazo} días`].filter(Boolean).map(esc).join(' · ') || 'Sin datos de contacto'}</p>
      <div class="tarjeta"><div class="etq">Cuenta</div><div class="valor ${+p.saldo > 0.004 ? 'mal' : ''}">${textoSaldo(p.saldo)}</div></div>
      <div class="fila"><button class="btn primario" id="pagar">Registrar pago</button><button class="btn" id="ajuste">Saldo inicial / ajuste</button>
        <button class="btn" id="editar">Editar datos</button><button class="btn peligro" id="eliminar">Eliminar</button></div>
      <div class="tabla-caja"><table class="tabla">${movs.length ? `<thead><tr><th>Fecha</th><th>Concepto</th><th class="num">Compra / suma</th><th class="num">Pagado / resta</th><th class="num">Saldo</th><th></th></tr></thead><tbody>
        ${movs.map(x => `<tr class="${x.anulado ? 'anulada' : ''}"><td>${fecha(x.fecha)}</td><td>${esc(x.concepto)}${x.forma ? ` <span class="muted">(${esc(x.forma)}${x.de_caja ? ', de la caja' : ''})</span>` : ''}<div class="muted chico">${esc(x.usuario)}</div></td>
          <td class="num">${+x.monto > 0 ? plata(x.monto) : ''}</td><td class="num ok">${+x.monto < 0 ? plata(-x.monto) : ''}</td><td class="num">${plata(x.saldo)}</td>
          <td class="num">${['pago', 'ajuste'].includes(x.tipo) && !x.compra_id && !x.anulado ? `<button class="link" data-anular="${x.id}">Anular</button>` : ''}</td></tr>`).join('')}</tbody>`
        : '<tbody><tr><td class="muted vacio">Sin movimientos. Si ya le debías algo, cargalo con "Saldo inicial / ajuste".</td></tr></tbody>'}</table></div>
      <div class="fila fin"><button class="btn" data-cerrar>Cerrar</button></div>`, { ancho: true });
    const otraVez = () => { m.cerrar(); ctx.recargar(); ficha(id, ctx); };
    $('#pagar', m.el).onclick = () => pagar(p, otraVez);
    $('#ajuste', m.el).onclick = () => ajuste(p, movs.length, otraVez);
    $('#editar', m.el).onclick = () => formProveedor(p, otraVez);
    $('#eliminar', m.el).onclick = async () => {
      if (!await confirmar('Eliminar proveedor', `¿Eliminar a ${p.nombre}? Solo se puede si no tiene compras y su cuenta está en cero.`, 'Eliminar')) return;
      correr(async () => { await llamar('eliminar_proveedor', { p_id: p.id }); m.cerrar(); aviso('Proveedor eliminado', 'ok'); ctx.recargar(); });
    };
    $$('[data-anular]', m.el).forEach(b => b.onclick = async () => {
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
      <div class="fila fin"><button type="button" class="btn" data-cerrar>Cancelar</button><button class="btn primario">Registrar pago</button></div></form>`);
    $('[name=origen]', m.el).onchange = e => { $('#como-l', m.el).hidden = e.target.value !== 'aparte'; };
    $('#f-pago', m.el).onsubmit = e => {
      e.preventDefault();
      const f = new FormData(e.target), monto = numero(f.get('monto')), aparte = f.get('origen') === 'aparte';
      if (!(monto > 0)) return aviso('Poné el monto');
      correr(async () => {
        const r = await llamar('pagar_proveedor', { p_proveedor_id: p.id, p_monto: monto, p_de_caja: !aparte, p_forma: aparte ? f.get('como') : f.get('origen').slice(5), p_concepto: f.get('concepto') });
        m.cerrar(); aviso(`Pago registrado. ${textoSaldo(r.saldo)}`, 'ok'); despues();
      });
    };
  });
}

function ajuste(p, hayMovimientos, despues) {
  const m = modal('Saldo inicial / ajuste', `<form class="form" id="f-aj"><p class="muted">Para cargar lo que ya le debías antes de usar la cuenta, o corregir un error. No mueve plata de la caja.</p>
    <label>Tipo<select class="input" name="tipo"><option value="1">Suma deuda (le debés más)</option><option value="-1">Resta deuda (nota de crédito, corrección)</option></select></label>
    <label>Monto<input class="input" name="monto" inputmode="decimal" required autofocus></label>
    <label>Concepto<input class="input" name="concepto" maxlength="120" placeholder="${hayMovimientos ? 'ej: nota de crédito, corrección' : 'Saldo inicial'}"></label>
    <div class="fila fin"><button type="button" class="btn" data-cerrar>Cancelar</button><button class="btn primario">Guardar</button></div></form>`);
  $('#f-aj', m.el).onsubmit = e => {
    e.preventDefault();
    const f = new FormData(e.target), monto = numero(f.get('monto'));
    if (!(monto > 0)) return aviso('Poné el monto');
    correr(async () => { await llamar('ajuste_proveedor', { p_proveedor_id: p.id, p_monto: monto * +f.get('tipo'), p_concepto: f.get('concepto') }); m.cerrar(); despues(); });
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
