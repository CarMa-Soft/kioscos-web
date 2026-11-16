// Clientes y su cuenta (fiado): lista con saldo, ficha, cobrar, ajustes (solo dueño)
import { llamar } from './base.js';
import { $, $$, esc, plata, fecha, numero, aviso, correr, modal, confirmar } from './ui.js';

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
      const m = modal(c.nombre, `<p class="muted">${[c.telefono, c.direccion].filter(Boolean).map(esc).join(' · ') || 'Sin datos de contacto'}${+c.limite ? ' · límite ' + plata(c.limite) : ''}</p>
        <div class="tarjeta"><div class="etq">Saldo</div><div class="valor ${+c.saldo > 0.004 ? 'mal' : ''}">${textoSaldo(c.saldo)}</div></div>
        <div class="fila"><button class="btn primario" id="cobrar">Cobrar</button>${admin ? '<button class="btn" id="ajuste">Deuda anterior / ajuste</button>' : ''}
          <button class="btn" id="editar">Editar datos</button>${admin ? '<button class="btn peligro" id="eliminar">Eliminar</button>' : ''}</div>
        <div class="tabla-caja"><table class="tabla">${movs.length ? `<thead><tr><th>Fecha</th><th>Concepto</th><th class="num">Debe</th><th class="num">Pagó</th><th class="num">Saldo</th></tr></thead><tbody>
          ${movs.map(x => `<tr><td>${fecha(x.fecha)}</td><td>${esc(x.concepto)}${x.forma ? ` <span class="muted">(${esc(x.forma)})</span>` : ''}<div class="muted chico">${esc(x.usuario)}</div></td>
            <td class="num">${+x.monto > 0 ? plata(x.monto) : ''}</td><td class="num ok">${+x.monto < 0 ? plata(-x.monto) : ''}</td><td class="num">${plata(x.saldo)}</td></tr>`).join('')}</tbody>`
          : '<tbody><tr><td class="muted vacio">Sin movimientos.</td></tr></tbody>'}</table></div>
        <div class="fila fin"><button class="btn" data-cerrar>Cerrar</button></div>`, { ancho: true });
      const otraVez = () => { m.cerrar(); ctx.recargar(); ficha(id); };
      $('#cobrar', m.el).onclick = () => cobrar(c, otraVez);
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
      const m = modal(`Cobrar a ${c.nombre}`, `<form class="form" id="f-cobro"><p>Debe <b>${plata(Math.max(0, c.saldo))}</b></p>
        <label>Monto<input class="input grande" name="monto" inputmode="decimal" required autofocus value="${+c.saldo > 0 ? c.saldo : ''}"></label>
        <label>Forma<select class="input" name="forma">${caja.formas_pago.map(f => `<option>${esc(f)}</option>`).join('')}</select></label>
        <div class="fila fin"><button type="button" class="btn" data-cerrar>Cancelar</button><button class="btn primario">Cobrar</button></div></form>`);
      $('#f-cobro', m.el).onsubmit = e => {
        e.preventDefault();
        const f = new FormData(e.target), monto = numero(f.get('monto'));
        if (!(monto > 0)) return aviso('Poné el monto');
        correr(async () => { const r = await llamar('cobrar_cliente', { p_cliente_id: c.id, p_monto: monto, p_forma: f.get('forma') }); m.cerrar(); aviso(`Cobrado. Saldo: ${textoSaldo(r.saldo)}`, 'ok'); despues(); });
      };
    });
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

export const textoSaldo = s => +s > 0.004 ? 'Debe ' + plata(s) : +s < -0.004 ? 'A favor ' + plata(-s) : 'Al día';

// Alta o edición de un cliente; alGuardar recibe el cliente guardado. También la usa Vender.
export function formCliente(c, admin, alGuardar) {
  const m = modal(c ? 'Editar cliente' : 'Nuevo cliente', `<form class="form" id="f-cli">
    <label>Nombre<input class="input" name="nombre" maxlength="80" required value="${esc(c?.nombre || '')}" autofocus></label>
    <label>Teléfono<input class="input" name="telefono" maxlength="40" value="${esc(c?.telefono || '')}"></label>
    <label>Dirección<input class="input" name="direccion" maxlength="120" value="${esc(c?.direccion || '')}"></label>
    ${admin ? `<label>Límite de fiado <span class="muted">(0 = sin límite)</span><input class="input" name="limite" inputmode="decimal" value="${c?.limite ?? 0}"></label>` : ''}
    <label>Notas<input class="input" name="notas" maxlength="500" value="${esc(c?.notas || '')}"></label>
    <div class="fila fin"><button type="button" class="btn" data-cerrar>Cancelar</button><button class="btn primario">Guardar</button></div></form>`);
  $('#f-cli', m.el).onsubmit = e => {
    e.preventDefault();
    const f = new FormData(e.target);
    const datos = { id: c?.id ?? null, nombre: f.get('nombre'), telefono: f.get('telefono'), direccion: f.get('direccion'), notas: f.get('notas') };
    if (admin) { datos.limite = numero(f.get('limite')) || 0; if (datos.limite < 0) return aviso('Revisá el límite'); }
    correr(async () => { const r = await llamar('guardar_cliente', { p: datos }); m.cerrar(); aviso('Cliente guardado', 'ok'); alGuardar(r); });
  };
}
