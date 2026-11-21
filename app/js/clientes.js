// Clientes y su cuenta (fiado): lista con saldo, ficha con lo pendiente (con vencimiento) y lo pagado, cobrar eligiendo a
// qué compras va el pago, ajustes (solo dueño). Como la cuenta del proveedor. La lista se ordena por nombre, saldo, límite o
// antigüedad de la deuda; la ficha saca el estado de cuenta en PDF o lo arma para mandar por WhatsApp.
import { llamar } from './base.js';
import { $, $$, esc, plata, cant, fecha, dia, hoyDia, textoVence, numero, aviso, correr, modal, confirmar, telefonoWhatsApp, subpantalla, tarjeta } from './ui.js';
import { verVenta } from './caja.js';

const nombreDeuda = d => d.venta_id ? `Compra #${d.numero}` : (d.concepto || 'Deuda');
// En la ficha, la compra es un enlace al detalle de la venta (el mismo de Caja)
const linkVenta = (ventaId, texto) => ventaId ? `<button class="link" data-venta="${ventaId}" title="Ver la venta">${esc(texto)}</button>` : esc(texto);

// Lo elegido se mantiene al ir y volver de la sección
let filtro = '', grupo = 'todos', orden = { col: 'nombre', asc: true };
export function verDeudores() { grupo = 'deben'; filtro = ''; orden = { col: 'saldo', asc: false }; }

// Íconos de las tarjetas (trazos SVG, toman el color del texto)
const svg = d => `<svg viewBox="0 0 24 24" aria-hidden="true">${d}</svg>`;
const ICO = {
  plata: svg('<rect x="2.5" y="6" width="19" height="12" rx="2"/><circle cx="12" cy="12" r="2.6"/>'),
  alerta: svg('<circle cx="12" cy="12" r="9"/><path d="M12 7.5v5.5M12 16.5v.01"/>'),
  personas: svg('<circle cx="9" cy="8.5" r="3.2"/><path d="M3 19c.6-3.2 3-5 6-5s5.4 1.8 6 5"/><circle cx="17" cy="9.5" r="2.5"/><path d="M16 14.2c2.6.2 4.4 1.8 5 4.8"/>'),
  lupa: svg('<circle cx="11" cy="11" r="6.5"/><path d="m20 20-4.2-4.2"/>'),
  calendario: svg('<rect x="3.5" y="5" width="17" height="15" rx="2"/><path d="M3.5 10h17M8 3v4M16 3v4"/>'),
  recibo: svg('<path d="M6 3h12v18l-3-2-3 2-3-2-3 2z"/><path d="M9 8h6M9 12h6"/>'),
  lista: svg('<path d="M9 6h11M9 12h11M9 18h11"/><circle cx="4.5" cy="6" r="1"/><circle cx="4.5" cy="12" r="1"/><circle cx="4.5" cy="18" r="1"/>'),
};

export async function pantallaClientes(vista, ctx) {
  const admin = ctx.yo.rol === 'admin';
  const lista = await llamar('clientes');
  const deben = lista.filter(c => +c.saldo > 0.004);
  vista.innerHTML = `<div class="cabecera"><h2>Clientes</h2><div class="acciones"><button class="btn primario" id="nuevo">＋ Nuevo cliente</button></div></div>
    <div class="c-tarjetas">
      <div class="c-tarjeta rojo" id="t-deben" title="Ver los que deben"><span class="c-ico">${ICO.plata}</span><div><div class="etq">Te deben (fiado)</div><div class="valor">${plata(deben.reduce((s, c) => s + +c.saldo, 0))}</div></div></div>
      <div class="c-tarjeta naranja" id="t-cuantos" title="Ver los que deben, del que debe más al que menos"><span class="c-ico">${ICO.alerta}</span><div><div class="etq">Clientes que deben</div><div class="valor">${deben.length}</div></div></div>
      <div class="c-tarjeta verde" id="t-todos" title="Ver todos"><span class="c-ico">${ICO.personas}</span><div><div class="etq">Total de clientes</div><div class="valor">${lista.length}</div></div></div>
    </div>
    <div class="c-filtros">
      <label class="c-buscar">${ICO.lupa}<input id="filtro" placeholder="Buscar por nombre o teléfono…" value="${esc(filtro)}" autocomplete="off"></label>
      <div class="chips" id="grupos"></div>
    </div>
    <div class="tabla-caja c-tabla"><table class="tabla" id="tabla"></table></div>`;
  const GRUPOS = [['todos', 'Todos', () => true], ['deben', 'Deben', c => +c.saldo > 0.004]];
  const pintar = () => {
    const f = filtro.trim().toLowerCase();
    const busca = c => !f || c.nombre.toLowerCase().includes(f) || (c.telefono || '').includes(f);
    $('#grupos').innerHTML = GRUPOS.map(([g, nombre, cond]) => `<button class="chip ${g === grupo ? 'elegido' : ''}" data-grupo="${g}">${nombre} <span class="c-cuenta">${lista.filter(c => busca(c) && cond(c)).length}</span></button>`).join('');
    $$('[data-grupo]').forEach(b => b.onclick = () => { grupo = b.dataset.grupo; pintar(); });
    const cond = GRUPOS.find(x => x[0] === grupo)[2];
    const ver = ordenar(lista.filter(c => busca(c) && cond(c)));
    const saldo = s => +s > 0.004 ? `<span class="c-saldo debe">Debe ${plata(s)}</span>` : +s < -0.004 ? `<span class="c-saldo favor">A favor ${plata(-s)}</span>` : '<span class="c-saldo">Al día</span>';
    $('#tabla').innerHTML = ver.length ? `<thead><tr>${COLS.map(([col, nombre, cl]) => `<th class="${cl}">${col ? `<button class="p-orden ${orden.col === col ? 'activo' : ''}" data-orden="${col}">${nombre}
        <span aria-hidden="true">${orden.col === col ? (orden.asc ? '▲' : '▼') : '↕'}</span></button>` : nombre}</th>`).join('')}</tr></thead><tbody>
      ${ver.map(c => `<tr class="clic" data-id="${c.id}"><td><div class="c-nombre"><span class="c-inicial ${+c.saldo > 0.004 ? 'debe' : ''}">${esc(c.nombre.trim().charAt(0).toUpperCase())}</span>
          <b>${esc(c.nombre)}</b>${c.activo ? '' : ' <span class="etiqueta">de baja</span>'}</div></td><td>${esc(c.telefono || '')}</td>
        <td>${debeDesde(c)}</td>
        <td class="num">${+c.limite ? plata(c.limite) + usoLimite(c) : '<span class="muted">—</span>'}</td><td class="num">${saldo(c.saldo)}</td></tr>`).join('')}</tbody>`
      : `<tbody><tr><td class="muted vacio">${lista.length ? (grupo === 'deben' && !f ? 'Ningún cliente debe.' : 'Ningún cliente coincide.') : 'Todavía no hay clientes.'}</td></tr></tbody>`;
    anchos($('#tabla'));
    $$('[data-orden]').forEach(b => b.onclick = () => {
      const col = b.dataset.orden;
      // lo que más importa primero: más deuda, más vieja, más límite; el nombre de la A a la Z
      orden = orden.col === col ? { col, asc: !orden.asc } : { col, asc: col === 'nombre' || col === 'desde' };
      pintar();
    });
    $$('tr[data-id]').forEach(tr => tr.onclick = () => ficha(+tr.dataset.id));
  };
  // Columnas (las que tienen clave se ordenan con un clic en el título; otro clic invierte el orden)
  const COLS = [['nombre', 'Cliente', ''], ['', 'Teléfono', ''], ['desde', 'Debe desde', ''], ['limite', 'Límite', 'num'], ['saldo', 'Saldo', 'num']];
  const debe = c => +c.saldo > 0.004 && c.deuda_desde;
  const VALOR = { nombre: c => c.nombre.toLowerCase(), saldo: c => +c.saldo, limite: c => +c.limite || 0, desde: c => debe(c) ? new Date(c.deuda_desde).getTime() : null };
  function ordenar(xs) {
    const v = VALOR[orden.col], dir = orden.asc ? 1 : -1;
    // los que no tienen dato (no deben) van siempre al final
    return xs.slice().sort((a, b) => { const x = v(a), y = v(b); if (x == null || y == null) return (x == null) - (y == null);
      return (x < y ? -1 : x > y ? 1 : 0) * dir || a.nombre.localeCompare(b.nombre); });
  }
  $('#filtro').oninput = e => { filtro = e.target.value; pintar(); };
  $('#nuevo').onclick = () => formCliente(null, admin, () => ctx.recargar());
  // las tarjetas de arriba filtran la lista
  tarjeta($('#t-deben'), () => { grupo = 'deben'; pintar(); });
  tarjeta($('#t-cuantos'), () => { grupo = 'deben'; orden = { col: 'saldo', asc: false }; pintar(); });
  tarjeta($('#t-todos'), () => { grupo = 'todos'; filtro = ''; $('#filtro').value = ''; pintar(); });
  pintar();

  // La ficha del cliente: una pantalla dentro de Clientes (no una ventana), con el estilo de la lista. "← Clientes", "atrás"
  // y Esc vuelven a la lista como estaba (filtro y orden). Cobrar, editar y los ajustes siguen siendo ventanas chicas.
  let sub = null;
  function ficha(id) {
    correr(async () => {
      const c = await llamar('cuenta_cliente', { p_id: id });
      let acum = 0;
      const movs = c.movimientos.map(m => ({ ...m, saldo: (acum = Math.round((acum + +m.monto) * 100) / 100) })).reverse();
      const plazo = c.vence_dia ? `por mes: vence el ${c.vence_dia} del mes siguiente` : c.plazo != null ? `${c.plazo} días` : `${c.plazo_general} días`;
      const masVieja = c.pendientes.slice().sort((a, b) => String(a.fecha).localeCompare(String(b.fecha)))[0];
      const vence = c.pendientes.map(d => d.vencimiento).sort()[0];
      const dias = masVieja ? Math.max(0, Math.floor((Date.now() - new Date(masVieja.fecha)) / 864e5)) : 0;
      const debe = +c.saldo > 0.004, aFavor = +c.saldo < -0.004;
      vista.innerHTML = `<div class="cabecera"><div><button class="link cf-volver" id="volver">← Clientes</button><h2>${esc(c.nombre)}</h2>
          <p class="muted">${[c.telefono, c.direccion].filter(Boolean).map(esc).join(' · ') || 'Sin datos de contacto'}${c.notas ? ' · ' + esc(c.notas) : ''}</p></div>
        <div class="acciones"><button class="btn primario" id="cobrar">Cobrar</button>
          <button class="btn" id="estado-pdf" title="Lo que debe, compra por compra, para imprimir o mandar">📄 Estado de cuenta</button>
          <button class="btn" id="estado-wa" title="${c.telefono ? 'Arma el mensaje con lo que debe y abre WhatsApp' : 'No tiene teléfono: vas a elegir el contacto en WhatsApp'}">WhatsApp</button>
          ${+c.a_favor > 0.004 && c.pendientes.length ? `<button class="btn" id="aplicar">Aplicar lo que está a favor (${plata(c.a_favor)})</button>` : ''}
          ${admin ? '<button class="btn" id="ajuste">Deuda anterior / ajuste</button>' : ''}
          <button class="btn" id="editar">Editar datos</button>${admin ? '<button class="btn peligro" id="eliminar">Eliminar</button>' : ''}</div></div>
      <div class="c-tarjetas">
        <div class="c-tarjeta ${debe ? 'rojo' : 'verde'}"><span class="c-ico">${ICO.plata}</span><div><div class="etq">Cuenta</div>
          <div class="valor">${debe ? plata(c.saldo) : aFavor ? plata(-c.saldo) : 'Al día'}</div>
          <div class="c-sub">${debe ? `debe · ${c.pendientes.length} compra${c.pendientes.length === 1 ? '' : 's'} pendiente${c.pendientes.length === 1 ? '' : 's'}` : aFavor ? 'a favor del cliente' : 'no debe nada'}</div></div></div>
        <div class="c-tarjeta ${masVieja ? 'naranja' : 'gris'}"><span class="c-ico">${ICO.calendario}</span><div><div class="etq">Debe desde</div>
          <div class="valor">${masVieja ? new Date(masVieja.fecha).toLocaleDateString('es-AR', { day: '2-digit', month: '2-digit', year: '2-digit' }) : '—'}</div>
          <div class="c-sub">${masVieja ? `hace ${dias} día${dias === 1 ? '' : 's'} · ${textoVence(vence)}` : 'sin compras pendientes'}</div></div></div>
        <div class="c-tarjeta azul"><span class="c-ico">${ICO.alerta}</span><div><div class="etq">Límite de fiado</div>
          <div class="valor">${+c.limite ? plata(c.limite) : 'Sin límite'}</div>${+c.limite ? usoLimite(c, true) : ''}<div class="c-sub">plazo para pagar: ${esc(plazo)}</div></div></div>
      </div>
      <div class="cf-cols"><section>
        <div class="c-titulo">${ICO.recibo}<h3>Compras pendientes</h3></div>
        <div class="tabla-caja c-tabla"><table class="tabla">${c.pendientes.length ? `<thead><tr><th>Compra</th><th>Fecha</th><th>Vence</th><th class="num">Importe</th><th class="num">Pagado</th><th class="num">Pendiente</th></tr></thead><tbody>
          ${c.pendientes.map(d => `<tr><td class="nowrap">${linkVenta(d.venta_id, nombreDeuda(d))}</td><td class="nowrap">${fecha(d.fecha)}</td><td>${dia(d.vencimiento)}<div class="chico">${textoVence(d.vencimiento)}</div></td>
            <td class="num nowrap">${plata(d.importe)}</td><td class="num ok nowrap">${+d.aplicado ? plata(d.aplicado) : ''}</td><td class="num nowrap"><b>${plata(d.pendiente)}</b></td></tr>`).join('')}</tbody>`
          : '<tbody><tr><td class="muted vacio">No debe ninguna compra.</td></tr></tbody>'}</table></div>
        ${+c.a_favor > 0.004 ? `<p class="chico">A favor, sin aplicar a ninguna compra: <b class="ok">${plata(c.a_favor)}</b></p>` : ''}
        ${c.pagadas.length ? `<details class="pagadas"><summary><h3>Compras pagadas <span class="muted">(${c.pagadas.length}${c.pagadas.length === 100 ? ', las últimas' : ''})</span></h3></summary>
          <div class="tabla-caja c-tabla"><table class="tabla"><thead><tr><th>Compra</th><th>Fecha</th><th class="num">Importe</th><th>Pagada el</th></tr></thead><tbody>
          ${c.pagadas.map(d => `<tr><td class="nowrap">${linkVenta(d.venta_id, nombreDeuda(d))}</td><td class="nowrap">${fecha(d.fecha)}</td><td class="num nowrap">${plata(d.importe)}</td><td class="nowrap">${fecha(d.pagada)}</td></tr>`).join('')}</tbody></table></div></details>` : ''}
      </section><section>
        <div class="c-titulo">${ICO.lista}<h3>Movimientos</h3></div>
        <div class="tabla-caja c-tabla"><table class="tabla">${movs.length ? `<thead><tr><th>Fecha</th><th>Concepto</th><th class="num">Debe</th><th class="num">Pagó</th><th class="num">Saldo</th></tr></thead><tbody>
          ${movs.map(x => `<tr><td class="nowrap">${fecha(x.fecha)}</td><td>${linkVenta(x.venta_id, x.concepto)}${x.forma ? ` <span class="muted">(${esc(x.forma)})</span>` : ''}<div class="muted chico">${esc(x.usuario)}</div></td>
            <td class="num nowrap">${+x.monto > 0 ? plata(x.monto) : ''}</td><td class="num ok nowrap">${+x.monto < 0 ? plata(-x.monto) : ''}</td><td class="num nowrap">${plata(x.saldo)}</td></tr>`).join('')}</tbody>`
          : '<tbody><tr><td class="muted vacio">Sin movimientos.</td></tr></tbody>'}</table></div>
      </section></div>`;
      window.scrollTo(0, 0);
      anchos(vista);
      // "← Clientes", "atrás" o Esc: la lista, como estaba. Al rearmar la ficha (después de cobrar, etc.) no se suma otra entrada.
      if (!sub) sub = subpantalla(() => { sub = null; ctx.recargar(); });
      $('#volver').onclick = () => sub.cerrar();
      const otraVez = () => ficha(id);
      $('#cobrar').onclick = () => cobrar(c, otraVez);
      $('#estado-pdf').onclick = () => correr(() => estadoPdf(c, ctx));
      $('#estado-wa').onclick = () => estadoWhatsApp(c, ctx);
      if ($('#aplicar')) $('#aplicar').onclick = () => aplicar(c, otraVez);
      $('#editar').onclick = () => formCliente(c, admin, otraVez);
      $$('[data-venta]', vista).forEach(b => b.onclick = () => verVenta(+b.dataset.venta, ctx, otraVez));   // si se anula o devuelve, se vuelve a armar la ficha
      if (admin) {
        $('#ajuste').onclick = () => ajuste(c, otraVez);
        $('#eliminar').onclick = async () => {
          if (!await confirmar('Eliminar cliente', `¿Eliminar a ${c.nombre}? Si tiene movimientos, queda dado de baja.`, 'Eliminar')) return;
          correr(async () => { const r = await llamar('eliminar_cliente', { p_id: c.id }); aviso(r.desactivado ? 'Cliente dado de baja' : 'Cliente eliminado', 'ok'); sub.cerrar(); });
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
      <label class="crece">Cómo paga<select class="input" name="tipo_plazo">
        <option value="dias" ${c?.vence_dia ? '' : 'selected'}>Por días</option><option value="mes" ${c?.vence_dia ? 'selected' : ''}>Por mes</option></select></label></div>
      <label class="plazo-dias">Plazo para pagar (días) <span class="muted">(vacío = 30)</span><input class="input" name="plazo" inputmode="numeric" value="${c?.plazo ?? ''}"></label>
      <label class="plazo-mes">Se cierra a fin de mes y vence el día <span class="muted">(del mes siguiente, del 1 al 28)</span><input class="input" name="vence_dia" inputmode="numeric" value="${c?.vence_dia ?? 10}"></label>` : ''}
    <label>Notas<input class="input" name="notas" maxlength="500" value="${esc(c?.notas || '')}"></label>
    <div class="fila fin"><button type="button" class="btn" data-cerrar>Cancelar</button><button class="btn primario">Guardar</button></div></form>`);
  // por días o por mes: se muestra el campo que corresponde
  const tipo = $('[name=tipo_plazo]', m.el);
  const verTipo = () => { if (!tipo) return; $('.plazo-dias', m.el).hidden = tipo.value !== 'dias'; $('.plazo-mes', m.el).hidden = tipo.value !== 'mes'; };
  if (tipo) { tipo.onchange = verTipo; verTipo(); }
  $('#f-cli', m.el).onsubmit = e => {
    e.preventDefault();
    const f = new FormData(e.target);
    const datos = { id: c?.id ?? null, nombre: f.get('nombre'), telefono: f.get('telefono'), direccion: f.get('direccion'), notas: f.get('notas') };
    if (admin) {
      datos.limite = numero(f.get('limite')) || 0; if (datos.limite < 0) return aviso('Revisá el límite');
      if (f.get('tipo_plazo') === 'mes') {
        const d = numero(f.get('vence_dia'));
        if (!(Number.isInteger(d) && d >= 1 && d <= 28)) return aviso('El día de vencimiento tiene que ser del 1 al 28');
        datos.vence_dia = d; datos.plazo = '';
      } else {
        const plazo = String(f.get('plazo')).trim();
        if (plazo && !(Number.isInteger(numero(plazo)) && numero(plazo) >= 0 && numero(plazo) <= 365)) return aviso('El plazo tiene que ser de 0 a 365 días');
        datos.plazo = plazo; datos.vence_dia = null;   // vacío = el general (30 días)
      }
    }
    correr(async () => { const r = await llamar('guardar_cliente', { p: datos }); m.cerrar(); aviso('Cliente guardado', 'ok'); alGuardar(r); });
  };
}

// "Debe desde" en la lista: la compra pendiente más vieja (hace cuántos días) y si ya venció
function debeDesde(c) {
  if (!(+c.saldo > 0.004) || !c.deuda_desde) return '<span class="muted">—</span>';
  const desde = new Date(c.deuda_desde), dias = Math.max(0, Math.floor((Date.now() - desde) / 864e5));
  return `${desde.toLocaleDateString('es-AR', { day: '2-digit', month: '2-digit', year: '2-digit' })} <span class="muted chico">(${dias} día${dias === 1 ? '' : 's'})</span>
    ${c.vence ? `<div class="chico">${textoVence(c.vence)}</div>` : ''}`;
}

// ---------- Estado de cuenta (para el cliente: lo que debe, compra por compra; sin datos internos) ----------
const fechaCorta = iso => new Date(iso).toLocaleDateString('es-AR', { day: '2-digit', month: '2-digit', year: 'numeric' });
const detallePagado = d => +d.aplicado > 0.004 ? ` (de ${plata(d.importe)}, pagó ${plata(d.aplicado)})` : '';
// 'Pérez, Juan' → Juan; 'Juan Pérez' → Juan; una empresa con coma rara, el nombre completo
const primerNombre = n => (n.includes(',') ? n.split(',')[1] : n).trim().split(/\s+/)[0] || n;

function textoEstado(c, negocio) {
  const lineas = c.pendientes.slice().sort((a, b) => String(a.fecha).localeCompare(String(b.fecha)))
    .map(d => `• ${nombreDeuda(d)} del ${fechaCorta(d.fecha)}: ${plata(d.pendiente)}${detallePagado(d)}`);
  const total = c.pendientes.reduce((s, d) => s + +d.pendiente, 0);
  return [`Hola ${primerNombre(c.nombre)}! Te paso el estado de tu cuenta en ${negocio} al ${dia(hoyDia())}:`, '',
    ...(lineas.length ? [...lineas, '', `*Total adeudado: ${plata(total)}*`] : ['No tenés deuda pendiente. ¡Gracias!']),
    ...(+c.a_favor > 0.004 ? ['', `Además tenés ${plata(c.a_favor)} a favor.`] : []),
    '', 'Cualquier consulta, avisanos. ¡Gracias!'].join('\n');
}

function estadoWhatsApp(c, ctx) {
  const num = telefonoWhatsApp(c.telefono);
  window.open(`https://wa.me/${num}?text=${encodeURIComponent(textoEstado(c, ctx.negocio.nombre))}`, '_blank', 'noopener');
  if (!num) aviso('El cliente no tiene un teléfono válido cargado: elegí el contacto en WhatsApp', 'info');
}

async function estadoPdf(c, ctx) {
  const [{ jsPDF }, { autoTable }] = await Promise.all([import('https://cdn.jsdelivr.net/npm/jspdf@4.2.1/+esm'),
    import('https://cdn.jsdelivr.net/npm/jspdf-autotable@5.0.9/+esm')]);
  const n = { nombre: ctx.negocio.nombre, ...(ctx.config.negocio || {}) };
  const pend = c.pendientes.slice().sort((a, b) => String(a.fecha).localeCompare(String(b.fecha)));
  // los productos de cada compra pendiente (la misma consulta que "ver la venta")
  const ventas = new Map(await Promise.all([...new Set(pend.map(d => d.venta_id).filter(Boolean))]
    .map(async id => [id, await llamar('venta', { p_id: id }).catch(() => null)])));
  const productos = d => (ventas.get(d.venta_id)?.items || []).map(i => `${+i.cantidad !== 1 ? cant(i.cantidad) + ' × ' : ''}${i.nombre}`).join(' · ');
  const total = pend.reduce((s, d) => s + +d.pendiente, 0);
  const doc = new jsPDF({ unit: 'mm', format: 'a4' });
  doc.setFontSize(11); doc.text([n.nombre, n.direccion, n.telefono && 'Tel. ' + n.telefono].filter(Boolean).join(' · '), 14, 16);
  doc.setFontSize(18); doc.text('Estado de cuenta', 14, 27);
  doc.setFontSize(11); doc.text(`Cliente: ${c.nombre} · al ${dia(hoyDia())}`, 14, 34);
  if (pend.length) {
    autoTable(doc, {
      startY: 40, head: [['Fecha', 'Compra', 'Vence', 'Importe', 'Pagado', 'Pendiente']],
      body: pend.map(d => [fechaCorta(d.fecha), nombreDeuda(d) + (productos(d) ? '\n' + productos(d) : ''), dia(d.vencimiento),
        plata(d.importe), +d.aplicado > 0.004 ? plata(d.aplicado) : '—', plata(d.pendiente)]),
      foot: [['', 'TOTAL ADEUDADO', '', '', '', plata(total)]],
      styles: { fontSize: 9.5 }, headStyles: { fillColor: [31, 41, 51] }, footStyles: { fillColor: [245, 246, 248], textColor: 20, fontSize: 11 },
      columnStyles: { 1: { cellWidth: 70 }, 3: { halign: 'right' }, 4: { halign: 'right' }, 5: { halign: 'right', fontStyle: 'bold' } },
    });
  } else { doc.setFontSize(13); doc.text('No tiene deuda pendiente.', 14, 46); }
  let y = (doc.lastAutoTable?.finalY || 50) + 8;
  doc.setFontSize(10);
  if (+c.a_favor > 0.004) { doc.text(`Además tiene ${plata(c.a_favor)} a favor.`, 14, y); y += 7; }
  doc.setFontSize(8.5); doc.setTextColor(90);
  doc.text(`Documento no válido como factura. Ante cualquier diferencia, comunicate con nosotros${n.telefono ? ' al ' + n.telefono : ''}.`, 14, y + 4);
  doc.save(`Estado de cuenta ${c.nombre} ${hoyDia()}`.replace(/[\\/:*?"<>|]/g, '-') + '.pdf');
}

// Cuánto del límite de fiado ya usó: una barra (verde, amarilla desde el 70%, roja al pasarlo). Con texto, en la ficha.
function usoLimite(c, conTexto = false) {
  const usado = Math.max(0, +c.saldo), pct = Math.round(usado / +c.limite * 100);
  const color = pct >= 100 ? 'pasado' : pct >= 70 ? 'cerca' : '';
  return `<div class="c-uso ${color}" title="Usó ${pct}% del límite (${plata(usado)} de ${plata(c.limite)})"><i data-ancho="${Math.min(100, pct)}"></i></div>${conTexto
    ? `<div class="c-sub">${pct >= 100 ? `<b class="mal">pasó el límite (${pct}%)</b>` : `usó el ${pct}% · le quedan ${plata(+c.limite - usado)}`}</div>` : ''}`;
}
// el ancho de las barras va desde acá (sin estilos en el HTML: CSP)
const anchos = raiz => $$('[data-ancho]', raiz).forEach(i => { i.style.width = i.dataset.ancho + '%'; });
