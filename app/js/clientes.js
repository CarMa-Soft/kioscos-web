// Clientes y su cuenta (fiado): lista con saldo, ficha con lo pendiente (con vencimiento) y lo pagado, cobrar eligiendo a
// qué compras va el pago, ajustes (solo dueño). Como la cuenta del proveedor.
import { llamar } from './base.js';
import { $, $$, esc, plata, fecha, dia, textoVence, numero, aviso, correr, modal, confirmar } from './ui.js';

const nombreDeuda = d => d.venta_id ? `Compra #${d.numero}` : (d.concepto || 'Deuda');

let filtro = '';

export async function pantallaClientes(vista, ctx) {
  const admin = ctx.yo.rol === 'admin';
  const lista = await llamar('clientes');
  const deben = lista.filter(c => +c.saldo > 0.004);
  vista.innerHTML = `<div class="cabecera"><h2>Clientes</h2><div class="acciones"><button class="btn primario" id="nuevo">＋ Nuevo cliente</button></div></div>
    <div class="tarjetas"><div class="tarjeta"><div class="etq">Te deben (fiado)</div><div class="valor">${plata(deben.reduce((s, c) => s + +c.saldo, 0))}</div></div>
      <div class="tarjeta"><div class="etq">Clientes que deben</div><div class="valor">${deben.length}</div></div></div>
    <input class="input" id="filtro" placeholder="Buscar cliente" value="${esc(filtro)}" autocomplete="off">
    <div class="tabla-caja"><table class="tabla" id="tabla"></table></div>`;
  const pintar = () => {
    const f = filtro.trim().toLowerCase();
    const ver = lista.filter(c => !f || c.nombre.toLowerCase().includes(f) || (c.telefono || '').includes(f));
    $('#tabla').innerHTML = ver.length ? `<thead><tr><th>Cliente</th><th>Teléfono</th><th class="num">Límite</th><th class="num">Saldo</th></tr></thead><tbody>
      ${ver.map(c => `<tr class="clic" data-id="${c.id}"><td>${esc(c.nombre)}${c.activo ? '' : ' <span class="etiqueta">de baja</span>'}</td><td>${esc(c.telefono || '')}</td>
        <td class="num">${+c.limite ? plata(c.limite) : '—'}</td><td class="num ${+c.saldo > 0.004 ? 'mal' : ''}"><b>${textoSaldo(c.saldo)}</b></td></tr>`).join('')}</tbody>`
      : `<tbody><tr><td class="muted vacio">${lista.length ? 'Ningún cliente coincide.' : 'Todavía no hay clientes.'}</td></tr></tbody>`;
    $$('tr[data-id]').forEach(tr => tr.onclick = () => ficha(+tr.dataset.id));
  };
  $('#filtro').oninput = e => { filtro = e.target.value; pintar(); };
  $('#nuevo').onclick = () => formCliente(null, admin, () => ctx.recargar());
  pintar();

  function ficha(id) {
    correr(async () => {
      const c = await llamar('cuenta_cliente', { p_id: id });
      let acum = 0;
      const movs = c.movimientos.map(m => ({ ...m, saldo: (acum = Math.round((acum + +m.monto) * 100) / 100) })).reverse();
      const plazo = c.plazo != null ? `plazo ${c.plazo} días` : `plazo ${c.plazo_general} días (el general)`;
      const m = modal(c.nombre, `<p class="muted">${[c.telefono, c.direccion].filter(Boolean).map(esc).join(' · ') || 'Sin datos de contacto'}${+c.limite ? ' · límite ' + plata(c.limite) : ''} · ${esc(plazo)}</p>
        <div class="tarjeta"><div class="etq">Cuenta</div><div class="valor ${+c.saldo > 0.004 ? 'mal' : ''}">${textoSaldo(c.saldo)}</div></div>
        <div class="fila"><button class="btn primario" id="cobrar">Cobrar</button>
          ${+c.a_favor > 0.004 && c.pendientes.length ? `<button class="btn" id="aplicar">Aplicar lo que está a favor (${plata(c.a_favor)})</button>` : ''}
          ${admin ? '<button class="btn" id="ajuste">Deuda anterior / ajuste</button>' : ''}
          <button class="btn" id="editar">Editar datos</button>${admin ? '<button class="btn peligro" id="eliminar">Eliminar</button>' : ''}</div>
        ${c.pendientes.length ? `<h3>Compras pendientes</h3><div class="tabla-caja"><table class="tabla"><thead><tr><th>Compra</th><th>Fecha</th><th>Vence</th><th class="num">Importe</th><th class="num">Pagado</th><th class="num">Pendiente</th></tr></thead><tbody>
          ${c.pendientes.map(d => `<tr><td>${esc(nombreDeuda(d))}</td><td>${fecha(d.fecha)}</td><td>${dia(d.vencimiento)}<div class="chico">${textoVence(d.vencimiento)}</div></td>
            <td class="num">${plata(d.importe)}</td><td class="num ok">${+d.aplicado ? plata(d.aplicado) : ''}</td><td class="num"><b>${plata(d.pendiente)}</b></td></tr>`).join('')}</tbody></table></div>` : ''}
        ${+c.a_favor > 0.004 ? `<p class="chico">A favor, sin aplicar a ninguna compra: <b class="ok">${plata(c.a_favor)}</b></p>` : ''}
        ${c.pagadas.length ? `<details class="pagadas"><summary><h3>Compras pagadas <span class="muted">(${c.pagadas.length}${c.pagadas.length === 100 ? ', las últimas' : ''})</span></h3></summary>
          <div class="tabla-caja"><table class="tabla"><thead><tr><th>Compra</th><th>Fecha</th><th class="num">Importe</th><th>Pagada el</th></tr></thead><tbody>
          ${c.pagadas.map(d => `<tr><td>${esc(nombreDeuda(d))}</td><td>${fecha(d.fecha)}</td><td class="num">${plata(d.importe)}</td><td>${fecha(d.pagada)}</td></tr>`).join('')}</tbody></table></div></details>` : ''}
        <h3>Movimientos</h3>
        <div class="tabla-caja"><table class="tabla">${movs.length ? `<thead><tr><th>Fecha</th><th>Concepto</th><th class="num">Debe</th><th class="num">Pagó</th><th class="num">Saldo</th></tr></thead><tbody>
          ${movs.map(x => `<tr><td>${fecha(x.fecha)}</td><td>${esc(x.concepto)}${x.forma ? ` <span class="muted">(${esc(x.forma)})</span>` : ''}<div class="muted chico">${esc(x.usuario)}</div></td>
            <td class="num">${+x.monto > 0 ? plata(x.monto) : ''}</td><td class="num ok">${+x.monto < 0 ? plata(-x.monto) : ''}</td><td class="num">${plata(x.saldo)}</td></tr>`).join('')}</tbody>`
          : '<tbody><tr><td class="muted vacio">Sin movimientos.</td></tr></tbody>'}</table></div>
        <div class="fila fin"><button class="btn" data-cerrar>Cerrar</button></div>`, { ancho: true });
      const otraVez = () => { m.cerrar(); ctx.recargar(); ficha(id); };
      $('#cobrar', m.el).onclick = () => cobrar(c, otraVez);
      if ($('#aplicar', m.el)) $('#aplicar', m.el).onclick = () => aplicar(c, otraVez);
      $('#editar', m.el).onclick = () => formCliente(c, admin, otraVez);
      if (admin) {
        $('#ajuste', m.el).onclick = () => ajuste(c, otraVez);
        $('#eliminar', m.el).onclick = async () => {
          if (!await confirmar('Eliminar cliente', `¿Eliminar a ${c.nombre}? Si tiene movimientos, queda dado de baja.`, 'Eliminar')) return;
          correr(async () => { const r = await llamar('eliminar_cliente', { p_id: c.id }); m.cerrar(); aviso(r.desactivado ? 'Cliente dado de baja' : 'Cliente eliminado', 'ok'); ctx.recargar(); });
        };
      }
    });
  }

  function cobrar(c, despues) {
    correr(async () => {
      const caja = await llamar('estado_caja');
      if (!caja.turno) return aviso('La caja está cerrada: abrí tu turno en Caja');
      const m = modal(`Cobrar a ${c.nombre}`, `<form class="form ancho" id="f-cobro"><p>${textoSaldo(c.saldo)}</p>
        <label>Monto<input class="input grande" name="monto" inputmode="decimal" required autofocus value="${+c.saldo > 0 ? c.saldo : ''}"></label>
        <label>Forma<select class="input" name="forma">${caja.formas_pago.map(f => `<option>${esc(f)}</option>`).join('')}</select></label>
        <h3>Qué compras paga</h3><div id="aplicacion"></div>
        <div class="fila fin"><button type="button" class="btn" data-cerrar>Cancelar</button><button class="btn primario">Cobrar</button></div></form>`, { ancho: true });
      const ap = tablaAplicacion($('#aplicacion', m.el), c.pendientes);
      const montoIn = $('[name=monto]', m.el);
      ap.rellenar(numero(montoIn.value) || 0);
      montoIn.oninput = () => ap.rellenar(numero(montoIn.value) || 0);
      $('#f-cobro', m.el).onsubmit = e => {
        e.preventDefault();
        const f = new FormData(e.target), monto = numero(f.get('monto'));
        if (!(monto > 0)) return aviso('Poné el monto');
        if (ap.aplicado() > monto + 0.004) return aviso('Aplicás a las compras más de lo que paga');
        correr(async () => {
          const r = await llamar('cobrar_cliente', { p_cliente_id: c.id, p_monto: monto, p_forma: f.get('forma'), p_aplicaciones: ap.datos() });
          m.cerrar(); aviso(`Cobrado. ${textoSaldo(r.saldo)}`, 'ok'); despues();
        });
      };
    });
  }

  // Lo que está a favor (pagó de más, o quedó sin aplicar), a compras pendientes. No mueve plata.
  function aplicar(c, despues) {
    const m = modal(`Aplicar lo que está a favor — ${c.nombre}`, `<p>Tiene <b>${plata(c.a_favor)}</b> a favor sin aplicar. Elegí a qué compras va. <b>No mueve plata.</b></p>
      <div id="aplicacion"></div><div class="fila fin"><button class="btn" data-cerrar>Cancelar</button><button class="btn primario" id="ok">Aplicar</button></div>`, { ancho: true });
    const ap = tablaAplicacion($('#aplicacion', m.el), c.pendientes);
    ap.rellenar(c.a_favor);
    $('#ok', m.el).onclick = () => {
      if (!ap.datos().length) return aviso('Tildá al menos una compra');
      if (ap.aplicado() > +c.a_favor + 0.004) return aviso('Aplicás más de lo que tiene a favor');
      correr(async () => { await llamar('aplicar_cliente', { p_cliente_id: c.id, p_aplicaciones: ap.datos() }); m.cerrar(); aviso('Aplicado', 'ok'); despues(); });
    };
  }

  function ajuste(c, despues) {
    const m = modal('Deuda anterior / ajuste', `<form class="form" id="f-aj"><p class="muted">No mueve plata de la caja.</p>
      <label>Tipo<select class="input" name="tipo"><option value="1">Suma deuda (debe más)</option><option value="-1">Resta deuda (corrección)</option></select></label>
      <label>Monto<input class="input" name="monto" inputmode="decimal" required autofocus></label>
      <label>Concepto<input class="input" name="concepto" maxlength="120" placeholder="ej: deuda del cuaderno"></label>
      <div class="fila fin"><button type="button" class="btn" data-cerrar>Cancelar</button><button class="btn primario">Guardar</button></div></form>`);
    $('#f-aj', m.el).onsubmit = e => {
      e.preventDefault();
      const f = new FormData(e.target), monto = numero(f.get('monto'));
      if (!(monto > 0)) return aviso('Poné el monto');
      correr(async () => { await llamar('ajuste_cliente', { p_cliente_id: c.id, p_monto: monto * +f.get('tipo'), p_concepto: f.get('concepto') }); m.cerrar(); despues(); });
    };
  }
}

// Tabla para elegir qué compras se pagan y cuánto de cada una (como la de proveedores). Se completa sola con las que vencen
// primero hasta cubrir el total, y se puede cambiar (destildar, tildar otras, pago parcial). Lo que no se aplica queda a favor.
function tablaAplicacion(caja, deudas) {
  const filas = deudas.map(d => ({ d, tilde: false, monto: '' }));
  let total = 0;
  const r2 = n => Math.round(n * 100) / 100;
  const aplicado = () => r2(filas.reduce((s, f) => s + (f.tilde ? (numero(f.monto) || 0) : 0), 0));
  function pintar() {
    if (!filas.length) { caja.innerHTML = '<p class="muted chico">No tiene compras pendientes: lo que pague queda a favor.</p>'; return; }
    const libre = r2(total - aplicado());
    caja.innerHTML = `<div class="tabla-caja"><table class="tabla"><thead><tr><th></th><th>Compra</th><th>Vence</th><th class="num">Pendiente</th><th class="num">Aplica</th></tr></thead><tbody>
      ${filas.map((f, k) => `<tr><td><input type="checkbox" data-t="${k}" ${f.tilde ? 'checked' : ''}></td><td>${esc(nombreDeuda(f.d))}</td>
        <td>${dia(f.d.vencimiento)}<div class="chico">${textoVence(f.d.vencimiento)}</div></td><td class="num">${plata(f.d.pendiente)}</td>
        <td class="num"><input class="input corto" data-m="${k}" value="${esc(f.monto)}" inputmode="decimal" ${f.tilde ? '' : 'disabled'}></td></tr>`).join('')}</tbody></table></div>
      <p class="chico">Aplicado <b>${plata(aplicado())}</b> · sin aplicar <b class="${libre < -0.004 ? 'mal' : ''}">${plata(libre)}</b>${libre > 0.004 ? ' <span class="muted">(queda a favor)</span>' : libre < -0.004 ? ' <span class="mal">(aplicás más de lo que hay)</span>' : ''}</p>`;
    $$('[data-t]', caja).forEach(x => x.onchange = () => {
      const f = filas[+x.dataset.t];
      f.tilde = x.checked;
      f.monto = f.tilde ? String(Math.max(0, Math.min(+f.d.pendiente, r2(total - aplicado()))) || +f.d.pendiente) : '';
      pintar();
    });
    $$('[data-m]', caja).forEach(i => i.onchange = () => { const f = filas[+i.dataset.m]; f.monto = String(Math.min(+f.d.pendiente, Math.max(0, numero(i.value) || 0))); pintar(); });
  }
  return {
    rellenar(t) {
      total = Math.max(0, +t || 0);
      let resta = total;
      for (const f of filas) { const m = r2(Math.min(+f.d.pendiente, resta)); f.tilde = m > 0.004; f.monto = f.tilde ? String(m) : ''; resta -= m; }
      pintar();
    },
    aplicado,
    datos: () => filas.filter(f => f.tilde && numero(f.monto) > 0.004).map(f => ({ venta_id: f.d.venta_id, deuda_id: f.d.deuda_id, monto: numero(f.monto) })),
  };
}

export const textoSaldo = s => +s > 0.004 ? 'Debe ' + plata(s) : +s < -0.004 ? 'A favor ' + plata(-s) : 'Al día';

// Alta o edición de un cliente; alGuardar recibe el cliente guardado. También la usa Vender.
export function formCliente(c, admin, alGuardar) {
  const m = modal(c ? 'Editar cliente' : 'Nuevo cliente', `<form class="form" id="f-cli">
    <label>Nombre<input class="input" name="nombre" maxlength="80" required value="${esc(c?.nombre || '')}" autofocus></label>
    <label>Teléfono<input class="input" name="telefono" maxlength="40" value="${esc(c?.telefono || '')}"></label>
    <label>Dirección<input class="input" name="direccion" maxlength="120" value="${esc(c?.direccion || '')}"></label>
    ${admin ? `<div class="fila"><label class="crece">Límite de fiado <span class="muted">(0 = sin límite)</span><input class="input" name="limite" inputmode="decimal" value="${c?.limite ?? 0}"></label>
      <label class="crece">Plazo para pagar (días) <span class="muted">(vacío = el de Ajustes)</span><input class="input" name="plazo" inputmode="numeric" value="${c?.plazo ?? ''}"></label></div>` : ''}
    <label>Notas<input class="input" name="notas" maxlength="500" value="${esc(c?.notas || '')}"></label>
    <div class="fila fin"><button type="button" class="btn" data-cerrar>Cancelar</button><button class="btn primario">Guardar</button></div></form>`);
  $('#f-cli', m.el).onsubmit = e => {
    e.preventDefault();
    const f = new FormData(e.target);
    const datos = { id: c?.id ?? null, nombre: f.get('nombre'), telefono: f.get('telefono'), direccion: f.get('direccion'), notas: f.get('notas') };
    if (admin) {
      datos.limite = numero(f.get('limite')) || 0; if (datos.limite < 0) return aviso('Revisá el límite');
      const plazo = String(f.get('plazo')).trim();
      if (plazo && !(Number.isInteger(numero(plazo)) && numero(plazo) >= 0 && numero(plazo) <= 365)) return aviso('El plazo tiene que ser de 0 a 365 días');
      datos.plazo = plazo;   // vacío = el general de Ajustes
    }
    correr(async () => { const r = await llamar('guardar_cliente', { p: datos }); m.cerrar(); aviso('Cliente guardado', 'ok'); alGuardar(r); });
  };
}
