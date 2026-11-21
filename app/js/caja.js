// Caja: abrir y cerrar el turno, ingresos y egresos, ventas del turno (ver y anular)
import { llamar } from './base.js';
import * as cat from './catalogo.js';
import { $, $$, esc, plata, cant, hora, fecha, numero, aviso, correr, modal, confirmar, pedirAutorizacion } from './ui.js';
import { imprimir, ticketVenta, ticketDevolucion, ticketCierre } from './impresion.js';

// Íconos (trazos SVG, toman el color del texto). Los estilos son los de Hoy, Clientes y Proveedores (clases c- en app.css).
const svg = d => `<svg viewBox="0 0 24 24" aria-hidden="true">${d}</svg>`;
const ICO = {
  billete: svg('<rect x="2.5" y="6" width="19" height="12" rx="2"/><circle cx="12" cy="12" r="2.6"/><path d="M6 9.5v5M18 9.5v5"/>'),
  tarjeta: svg('<rect x="2.5" y="5.5" width="19" height="13" rx="2"/><path d="M2.5 10h19M6.5 15h4"/>'),
  transfer: svg('<path d="M4 8h14l-3.5-3.5M20 16H6l3.5 3.5"/>'),
  celu: svg('<rect x="6.5" y="2.5" width="11" height="19" rx="2.2"/><path d="M11 18.5h2"/>'),
  fiado: svg('<rect x="5" y="3" width="14" height="18" rx="2"/><path d="M9 8h6M9 12h6M9 16h3"/>'),
  recibo: svg('<path d="M6 3h12v18l-3-2-3 2-3-2-3 2z"/><path d="M9 8h6M9 12h6"/>'),
  flechas: svg('<path d="M7 4v16M7 4 3.5 7.5M7 4l3.5 3.5M17 20V4M17 20l-3.5-3.5M17 20l3.5-3.5"/>'),
  caja: svg('<rect x="3" y="7" width="18" height="12" rx="2"/><path d="M3 11h18M8 7V5h8v2"/>'),
};
const icoForma = f => /d[eé]bito|cr[eé]dito|tarjeta/i.test(f) ? ICO.tarjeta : /transf/i.test(f) ? ICO.transfer : /mercado|qr|billetera|modo|ual[aá]/i.test(f) ? ICO.celu : ICO.tarjeta;

// Abrir la caja desde otra pantalla (Vender): pide el efectivo inicial, con lo que quedó del cierre anterior ya puesto
export function abrirCaja(estado, alAbrir) {
  const m = modal('Abrir la caja', `<form class="form" id="f-abrir-caja">
    <p class="muted">Para cobrar hay que abrir la caja. Contá el efectivo que hay.</p>
    <label>Efectivo inicial en la caja<input class="input grande" name="inicial" inputmode="decimal" value="${+estado.queda_anterior || 0}" autofocus></label>
    ${estado.queda_anterior != null ? `<p class="muted chico">Al cerrar el turno anterior quedaron ${plata(estado.queda_anterior)}.</p>` : ''}
    <div class="fila fin"><button type="button" class="btn" data-cerrar>Cancelar</button><button class="btn primario">Abrir la caja</button></div></form>`);
  $('#f-abrir-caja', m.el).onsubmit = ev => {
    ev.preventDefault();
    const inicial = numero(new FormData(ev.target).get('inicial'));
    if (!(inicial >= 0)) return aviso('Revisá el efectivo inicial');
    correr(async () => { await llamar('abrir_turno', { p_inicial: inicial }); m.cerrar(); aviso('Caja abierta', 'ok'); alAbrir(); });
  };
}

export async function pantallaCaja(vista, ctx) {
  const e = await llamar('estado_caja');
  const admin = ctx.yo.rol === 'admin';
  if (!e.turno) {
    vista.innerHTML = `<div class="cabecera"><h2>Caja cerrada</h2><button class="btn" id="anteriores">Turnos anteriores</button></div>
      <div class="recuadro-blanco c-abrir"><div class="c-titulo">${ICO.caja}<h3>Abrir el turno</h3></div>
      <p class="muted">Para vender hay que abrir el turno. Contá el efectivo que hay en la caja.</p>
      <form class="form" id="f-abrir"><label>Efectivo inicial en la caja<input class="input grande" name="inicial" inputmode="decimal" value="${+e.queda_anterior || 0}" autofocus></label>
      ${e.queda_anterior != null ? `<p class="muted chico">Al cerrar el turno anterior quedaron ${plata(e.queda_anterior)} en la caja.</p>` : ''}
      <div class="fila"><button class="btn primario">Abrir turno</button></div></form></div>`;
    $('#anteriores').onclick = () => turnosAnteriores();
    $('#f-abrir').onsubmit = ev => {
      ev.preventDefault();
      const inicial = numero(new FormData(ev.target).get('inicial'));
      if (!(inicial >= 0)) return aviso('Revisá el efectivo inicial');
      correr(async () => { await llamar('abrir_turno', { p_inicial: inicial }); aviso('Turno abierto', 'ok'); ctx.ir('#/vender'); });
    };
    return;
  }
  const t = e.turno, propio = t.usuario_id === ctx.yo.id;
  const formas = Object.entries(e.por_forma).filter(([f]) => f !== 'Efectivo');
  vista.innerHTML = `<div class="cabecera"><div><h2>Turno de ${esc(t.usuario)}</h2><p class="muted">Abierto ${fecha(t.apertura)} · inicial ${plata(t.inicial)}</p></div>
      <div class="acciones"><button class="btn" id="anteriores">Turnos anteriores</button><button class="btn" id="ingreso">Ingreso</button><button class="btn" id="egreso">Egreso</button>
      ${propio || admin ? '<button class="btn primario" id="cerrar">Cerrar turno</button>' : ''}</div></div>
    <div class="c-tarjetas">
      <div class="c-tarjeta verde"><span class="c-ico">${ICO.billete}</span><div><div class="etq">Efectivo que tiene que haber</div><div class="valor">${plata(t.esperado)}</div></div></div>
      ${formas.map(([f, v]) => `<div class="c-tarjeta azul"><span class="c-ico">${icoForma(f)}</span><div><div class="etq">${esc(f)}</div><div class="valor">${plata(v)}</div></div></div>`).join('')}
      ${+e.fiado ? `<div class="c-tarjeta rojo"><span class="c-ico">${ICO.fiado}</span><div><div class="etq">Fiado</div><div class="valor">${plata(e.fiado)}</div><div class="c-sub">no entra a la caja</div></div></div>` : ''}
      <div class="c-tarjeta violeta"><span class="c-ico">${ICO.recibo}</span><div><div class="etq">Ventas</div><div class="valor">${e.ventas.filter(v => !v.anulada).length}</div></div></div></div>
    <div class="c-titulo">${ICO.recibo}<h3>Ventas del turno</h3></div>
    <div class="tabla-caja c-tabla"><table class="tabla">${e.ventas.length ? `<thead><tr><th>#</th><th>Hora</th><th>Productos</th><th>Vendió</th><th class="num">Total</th><th></th></tr></thead><tbody>
      ${e.ventas.map(v => `<tr class="${v.anulada ? 'anulada' : ''}"><td>${v.numero}</td><td>${hora(v.fecha)}</td><td class="corto">${esc(v.resumen || '')}${v.cliente ? `<div class="muted chico">${esc(v.cliente)}${v.fiado ? ' · fiado' : ''}</div>` : ''}</td><td>${esc(v.usuario)}</td>
        <td class="num">${+v.devuelto && !v.anulada ? `${plata(v.total - v.devuelto)}<div class="aviso-chico"><s>${plata(v.total)}</s> · devuelto ${plata(v.devuelto)}</div>` : plata(v.total)}${v.anulada ? ' <span class="etiqueta">anulada</span>' : ''}</td><td><button class="link" data-venta="${v.id}">Ver</button></td></tr>`).join('')}</tbody>`
      : '<tbody><tr><td class="muted vacio">Todavía no hay ventas en este turno.</td></tr></tbody>'}</table></div>
    <div class="c-titulo">${ICO.flechas}<h3>Ingresos y egresos</h3></div>
    <div class="tabla-caja c-tabla"><table class="tabla">${e.movimientos.length ? '<thead><tr><th>Hora</th><th>Concepto</th><th>Forma</th><th class="num">Monto</th></tr></thead>' : ''}
      <tbody>${e.movimientos.map(m => `<tr><td>${hora(m.fecha)}</td><td>${esc(m.concepto)}<div class="muted chico">${esc(m.usuario)}</div></td>
      <td>${esc(m.forma)}</td><td class="num ${m.tipo === 'egreso' ? 'mal' : 'ok'}">${m.tipo === 'egreso' ? '−' : '+'}${plata(m.monto)}</td></tr>`).join('') || '<tr><td class="muted vacio">Sin movimientos.</td></tr>'}</tbody></table></div>`;

  $('#anteriores').onclick = () => turnosAnteriores();
  $('#ingreso').onclick = () => movimiento('ingreso');
  $('#egreso').onclick = () => movimiento('egreso');
  if ($('#cerrar')) $('#cerrar').onclick = () => cerrar();
  $$('[data-venta]').forEach(b => b.onclick = () => verVenta(+b.dataset.venta, ctx));

  function movimiento(tipo) {
    const m = modal(tipo === 'ingreso' ? 'Ingreso de plata' : 'Egreso de plata', `<form class="form" id="f-mov">
      <label>Motivo<input class="input" name="concepto" maxlength="120" required autofocus placeholder="${tipo === 'ingreso' ? 'ej: cambio' : 'ej: pago al proveedor'}"></label>
      <label>Monto<input class="input" name="monto" inputmode="decimal" required></label>
      <label>Forma<select class="input" name="forma">${e.formas_pago.map(f => `<option>${esc(f)}</option>`).join('')}</select></label>
      <div class="fila fin"><button type="button" class="btn" data-cerrar>Cancelar</button><button class="btn primario">Guardar</button></div></form>`);
    $('#f-mov', m.el).onsubmit = ev => {
      ev.preventDefault();
      const f = new FormData(ev.target), monto = numero(f.get('monto'));
      if (!(monto > 0)) return aviso('Poné el monto');
      correr(async () => { await llamar('movimiento_caja', { p_tipo: tipo, p_concepto: f.get('concepto'), p_monto: monto, p_forma: f.get('forma') }); m.cerrar(); ctx.recargar(); });
    };
  }

  // Cierre: poniendo solo el total que hay, o contando los billetes de cada valor (Ajustes; el total lo suma la pantalla y lo
  // vuelve a calcular la base). Cada PC recuerda la forma elegida; de fábrica, billetes si hay valores cargados.
  function cerrar() {
    const billetes = (e.billetes || []).map(Number);
    let modo = (() => { try { return localStorage.getItem('cierre-modo'); } catch { return null; } })() || (billetes.length ? 'billetes' : 'total');
    if (!billetes.length) modo = 'total';
    const m = modal('Cerrar turno', `<form class="form ancho" id="f-cerrar">
      <p>Tiene que haber <b>${plata(t.esperado)}</b> en efectivo.</p>
      ${billetes.length ? `<div class="chips" id="modo-cierre"><button type="button" class="chip" data-modo="total">Poner el total</button><button type="button" class="chip" data-modo="billetes">Contar billete por billete</button></div>` : ''}
      <label id="caja-total">¿Cuánto efectivo hay en la caja?<input class="input grande" name="total" inputmode="decimal" placeholder="0"></label>
      <p class="muted chico" id="ayuda-billetes">Contá cuántos billetes hay de cada valor: el total se suma solo.</p>
      <table class="tabla" id="tabla-billetes"><thead><tr><th>Billete</th><th>Cantidad</th><th class="num">Subtotal</th></tr></thead><tbody>
        ${billetes.map(b => `<tr><td><b>${plata(b).replace(/,00$/, '')}</b></td><td><input class="input corto" data-bill="${b}" inputmode="numeric" placeholder="0"></td><td class="num" data-sub="${b}">—</td></tr>`).join('')}
        <tr><td colspan="2">Monedas y otros <span class="muted chico">(si no contás por billetes, poné acá el total)</span></td><td class="num"><input class="input corto" name="otros" inputmode="decimal" placeholder="0"></td></tr></tbody></table>
      <div class="fila entre"><span>Total contado</span><span class="total chico-total" id="contado">${plata(0)}</span></div>
      <p class="diferencia" id="dif"></p>
      <label class="check" id="ajuste-box" hidden><input type="checkbox" name="ajuste" checked> <span id="ajuste-txt"></span></label>
      <label>Retiro <span class="muted">(lo que te llevás; el resto queda para el próximo turno)</span><input class="input" name="retiro" inputmode="decimal" placeholder="0"></label>
      <label>Notas<input class="input" name="notas" maxlength="500" placeholder="opcional"></label>
      <div class="fila fin"><button type="button" class="btn" data-cerrar>Cancelar</button><button class="btn primario" id="ok">Cerrar turno</button></div></form>`, { ancho: true });
    const leer = () => {
      if (modo === 'total') {
        const txt = $('[name=total]', m.el).value.trim(), o = txt === '' ? 0 : numero(txt);
        return { det: {}, otros: o >= 0 ? o : 0, contado: o >= 0 ? Math.round(o * 100) / 100 : 0, invalido: !(o >= 0), hay: txt !== '' };
      }
      const det = {}; let suma = 0, invalido = false, hay = false;
      $$('[data-bill]', m.el).forEach(i => {
        const txt = i.value.trim(), q = numero(txt);
        if (txt !== '') hay = true;
        if (txt !== '' && !(Number.isInteger(q) && q >= 0)) invalido = true;
        else if (q > 0) { det[i.dataset.bill] = q; suma += q * +i.dataset.bill; }
      });
      const txtO = $('[name=otros]', m.el).value.trim(), o = txtO === '' ? 0 : numero(txtO);
      if (txtO !== '') hay = true;
      if (!(o >= 0)) invalido = true;
      return { det, otros: o >= 0 ? o : 0, contado: Math.round((suma + (o >= 0 ? o : 0)) * 100) / 100, invalido, hay };
    };
    const actualizar = () => {
      const { det, contado, hay } = leer();
      $$('[data-bill]', m.el).forEach(i => { const q = det[i.dataset.bill] || 0; $(`[data-sub="${i.dataset.bill}"]`, m.el).textContent = q ? plata(q * +i.dataset.bill) : '—'; });
      $('#contado', m.el).textContent = plata(contado);
      const d = Math.round((contado - t.esperado) * 100) / 100, hayDif = hay && Math.abs(d) >= 0.01;
      $('#dif', m.el).innerHTML = !hay ? '' : !hayDif ? '<span class="ok">Cierra justo ✓</span>' : d > 0 ? `<span class="ok">Sobran ${plata(d)}</span>` : `<span class="mal">Faltan ${plata(-d)}</span>`;
      $('#ajuste-box', m.el).hidden = !hayDif;
      $('#ajuste-txt', m.el).textContent = `Registrar el ${d > 0 ? 'sobrante' : 'faltante'} de ${plata(Math.abs(d))} en los movimientos de caja`;
    };
    m.el.addEventListener('input', actualizar);
    // Enter pasa al campo siguiente; en el último, cierra
    const campos = () => $$('input:not([type=checkbox])', m.el);
    campos().forEach(c => c.addEventListener('focus', () => c.select()));
    m.el.addEventListener('keydown', ev => {
      if (ev.key !== 'Enter' || !ev.target.matches('input:not([type=checkbox])')) return;
      ev.preventDefault();
      const cs = campos(), i = cs.indexOf(ev.target);
      if (i < cs.length - 1) cs[i + 1].focus(); else $('#ok', m.el).click();
    });
    const ponerModo = nuevo => {
      modo = nuevo;
      try { localStorage.setItem('cierre-modo', modo); } catch { /* sin almacenamiento */ }
      $$('[data-modo]', m.el).forEach(b => b.classList.toggle('elegido', b.dataset.modo === modo));
      $('#caja-total', m.el).hidden = modo !== 'total';
      $('#tabla-billetes', m.el).hidden = $('#ayuda-billetes', m.el).hidden = $('#contado', m.el).parentElement.hidden = modo === 'total';
      actualizar();
      setTimeout(() => (modo === 'total' ? $('[name=total]', m.el) : $('[data-bill]', m.el))?.focus(), 40);
    };
    $$('[data-modo]', m.el).forEach(b => b.onclick = () => ponerModo(b.dataset.modo));
    ponerModo(modo);
    $('#f-cerrar', m.el).onsubmit = ev => {
      ev.preventDefault();
      const f = new FormData(ev.target), { det, otros, contado, invalido, hay } = leer(), retiro = numero(f.get('retiro')) || 0;
      if (invalido) return aviso('Revisá el conteo: las cantidades de billetes son números enteros');
      if (invalido && modo === 'total') return aviso('Revisá el efectivo: tiene que ser un número');
      if (!hay) return aviso(modo === 'total' ? 'Poné cuánto efectivo hay (si no hay nada, poné 0)' : 'Contá el efectivo (si no hay nada, poné 0 en "Monedas y otros")');
      if (!(retiro >= 0) || retiro > contado) return aviso('El retiro no puede ser mayor a lo contado');
      correr(async () => {
        const r = await llamar('cerrar_turno', { p_retiro: retiro, p_notas: f.get('notas'),
          ...(modo === 'total' ? { p_contado: contado, p_billetes: null, p_otros: 0 } : { p_contado: null, p_billetes: det, p_otros: otros }), p_registrar_ajuste: f.get('ajuste') === 'on' });
        m.cerrar();
        resumenTurno(r, () => ctx.recargar());
      });
    };
  }

  // Detalle de un turno cerrado: totales, conteo de billetes y movimientos
  function resumenTurno(r, alCerrar) {
    const d = +r.diferencia, b = r.billetes;
    const m = modal(`Turno de ${r.usuario}`, `<p class="muted">${fecha(r.apertura)} a ${fecha(r.cierre)}${r.cerrado_por && r.cerrado_por !== r.usuario ? ' · cerró ' + esc(r.cerrado_por) : ''}</p>
      <dl class="kv"><dt>Inicial</dt><dd>${plata(r.inicial)}</dd><dt>Tenía que haber</dt><dd>${plata(r.esperado)}</dd><dt>Contado</dt><dd>${plata(r.contado)}</dd>
        <dt>Diferencia</dt><dd class="${Math.abs(d) >= 0.01 ? (d > 0 ? 'ok' : 'mal') : 'ok'}">${Math.abs(d) < 0.01 ? 'Justo' : (d > 0 ? 'Sobraron ' : 'Faltaron ') + plata(Math.abs(d))}</dd>
        <dt>Retiro</dt><dd>${plata(r.retiro)}</dd><dt>Ventas</dt><dd>${r.ventas} · ${plata(r.total_ventas)}</dd></dl>
      ${b ? `<h3>Conteo</h3><table class="tabla"><tbody>${Object.entries(b.detalle || {}).sort((x, y) => +y[0] - +x[0]).map(([v, q]) => `<tr><td>${q} × ${plata(v)}</td><td class="num">${plata(q * v)}</td></tr>`).join('')}
        ${+b.otros ? `<tr><td>Monedas y otros</td><td class="num">${plata(b.otros)}</td></tr>` : ''}</tbody></table>` : ''}
      ${r.notas ? `<p><b>Notas:</b> ${esc(r.notas)}</p>` : ''}
      <h3>Movimientos</h3><div class="tabla-caja"><table class="tabla"><tbody>${(r.movimientos || []).map(x => `<tr><td>${hora(x.fecha)}</td><td>${esc(x.concepto)}${x.ajuste ? ' <span class="etiqueta">ajuste</span>' : ''}</td>
        <td>${esc(x.forma)}</td><td class="num ${x.tipo === 'egreso' ? 'mal' : ''}">${x.tipo === 'egreso' ? '−' : ''}${plata(x.monto)}</td></tr>`).join('') || '<tr><td class="muted vacio">Sin movimientos.</td></tr>'}</tbody></table></div>
      <div class="fila fin"><button class="btn" id="imp-cierre">Imprimir cierre</button><button class="btn primario" data-cerrar>Listo</button></div>`, { ancho: true, alCerrar });
    $('#imp-cierre', m.el).onclick = () => imprimir(ticketCierre(r, ctx.config));
  }

  function turnosAnteriores() {
    correr(async () => {
      const lista = await llamar('turnos_anteriores');
      const m = modal('Turnos anteriores', `<div class="tabla-caja"><table class="tabla">${lista.length ? `<thead><tr><th>Cierre</th><th>Usuario</th><th class="num">Ventas</th><th class="num">Diferencia</th></tr></thead><tbody>
        ${lista.map(x => `<tr class="clic" data-turno="${x.id}"><td>${fecha(x.cierre)}</td><td>${esc(x.usuario)}</td><td class="num">${plata(x.total_ventas)}</td>
          <td class="num ${Math.abs(+x.diferencia) >= 0.01 ? (+x.diferencia > 0 ? 'ok' : 'mal') : ''}">${Math.abs(+x.diferencia) < 0.01 ? 'Justo' : plata(x.diferencia)}</td></tr>`).join('')}</tbody>`
        : '<tbody><tr><td class="muted vacio">Todavía no hay turnos cerrados.</td></tr></tbody>'}</table></div>
        <div class="fila fin"><button class="btn" data-cerrar>Cerrar</button></div>`, { ancho: true });
      $$('[data-turno]', m.el).forEach(tr => tr.onclick = () => correr(async () => resumenTurno(await llamar('turno', { p_id: +tr.dataset.turno }))));
    });
  }
}

// Detalle de una venta: ver, reimprimir, devolver y anular. Lo usan Caja y la cuenta del cliente.
// alCambiar: qué hacer después de anular o devolver (si no se pasa, recargar la sección).
export function verVenta(id, ctx, alCambiar = () => ctx.recargar()) {
  const admin = ctx.yo.rol === 'admin';
  correr(async () => {
    const v = await llamar('venta', { p_id: id });
    const queda = i => Math.round((+i.cantidad - +i.devuelto) * 1000) / 1000;
    const puedeDevolver = !v.anulada && v.items.some(i => queda(i) > 0.0005);
    const m = modal(`Venta #${v.numero}`, `<p class="muted">${fecha(v.fecha)} · ${esc(v.usuario)}${v.cliente ? ' · cliente ' + esc(v.cliente.nombre) : ''}${v.anulada ? ` · <b class="mal">Anulada</b> por ${esc(v.anulada_por)}${v.motivo_anulacion ? ': ' + esc(v.motivo_anulacion) : ''}` : ''}</p>
      <table class="tabla"><tbody>${v.items.map(i => `<tr><td>${esc(i.nombre)}</td><td class="num">${cant(i.cantidad)}${i.por_peso ? ' kg' : ''}${+i.devuelto ? `<div class="aviso-chico">devuelto ${cant(i.devuelto)}</div>` : ''}</td><td class="num">${plata(i.importe)}</td></tr>`).join('')}</tbody>
      <tfoot>${+v.descuento || +v.recargo ? `<tr><td colspan="2">Subtotal</td><td class="num">${plata(v.subtotal)}</td></tr>` : ''}
        ${+v.descuento ? `<tr><td colspan="2">Descuento</td><td class="num">−${plata(v.descuento)}</td></tr>` : ''}
        ${+v.recargo ? `<tr><td colspan="2">Recargo</td><td class="num">+${plata(v.recargo)}</td></tr>` : ''}
        <tr><th colspan="2">Total</th><th class="num">${plata(v.total)}</th></tr>
        ${+v.devuelto ? `<tr><td colspan="2" class="aviso-chico">Devuelto</td><td class="num aviso-chico">−${plata(v.devuelto)}</td></tr>` : ''}</tfoot></table>
      ${+v.descuento_renglones ? `<p class="muted chico">Precios rebajados en los renglones: ${plata(v.descuento_renglones)} menos que la lista.</p>` : ''}
      ${v.autorizo ? `<p class="muted chico">Descuento autorizado por ${esc(v.autorizo)}.</p>` : ''}
      <p>${v.pagos.map(p => `${esc(p.forma)} ${plata(p.monto)}`).join(' · ')}${v.paga_con ? ` · pagó con ${plata(v.paga_con)}` : ''}</p>
      ${v.devoluciones.length ? `<h3>Devoluciones</h3><table class="tabla"><tbody>${v.devoluciones.map(d => `<tr><td><b>${esc(d.etiqueta)}</b> · ${fecha(d.fecha)} · ${esc(d.usuario)}${d.autorizo ? ` (autorizó ${esc(d.autorizo)})` : ''}
          <div class="muted chico">${d.items.map(x => `${cant(x.cantidad)} ${esc(x.nombre)}${x.vuelve_stock ? '' : ' (no volvió al stock)'}`).join(', ')}${d.motivo ? ' · ' + esc(d.motivo) : ''}</div></td>
        <td>${d.forma === 'Fiado' ? 'a su cuenta' : esc(d.forma)}</td><td class="num">${plata(d.total)}</td>
        <td class="num"><button class="link" data-imp-dev="${d.id}">Imprimir</button></td></tr>`).join('')}</tbody></table>` : ''}
      <div class="fila fin">${puedeDevolver ? '<button class="btn izq" id="devolver">Devolver productos</button>' : ''}
        <button class="btn" id="reimprimir">Imprimir ticket</button>
        ${admin && !v.anulada ? '<button class="btn peligro" id="anular">Anular venta</button>' : ''}<button class="btn primario" data-cerrar>Cerrar</button></div>`, { ancho: true });
    if ($('#devolver', m.el)) $('#devolver', m.el).onclick = () => { m.cerrar(); correr(async () => devolver(v, (await llamar('estado_caja')).formas_pago, ctx, alCambiar)); };
    $('#reimprimir', m.el).onclick = () => imprimir(ticketVenta(v, ctx.config));
    $$('[data-imp-dev]', m.el).forEach(b => b.onclick = () => imprimir(ticketDevolucion(v.devoluciones.find(d => d.id === +b.dataset.impDev), v, ctx.config)));
    if ($('#anular', m.el)) $('#anular', m.el).onclick = async () => {
      const resto = +v.total - +v.devuelto;
      const fiado = v.pagos.filter(p => p.forma === 'Fiado').reduce((s, p) => s + +p.monto, 0) * (+v.total ? resto / +v.total : 0), deCaja = resto - fiado;
      if (!await confirmar('Anular venta', `${+v.devuelto ? `Ya tuvo devoluciones por ${plata(v.devuelto)}: se anula solo lo que quedó. ` : ''}Se devuelve el stock${deCaja > 0.004 ? `, salen ${plata(deCaja)} de la caja del turno abierto` : ''}${fiado > 0.004 ? ` y se le descuentan ${plata(fiado)} de la cuenta a ${v.cliente.nombre}` : ''}.`, 'Anular')) return;
      correr(async () => { await llamar('anular_venta', { p_id: v.id, p_motivo: null }); m.cerrar(); aviso(`Venta #${v.numero} anulada`, 'ok'); await cat.actualizar(); alCambiar(); });
    };
  });
}

// Devolver parte o toda una venta. Se reintegra lo que pagó por eso (con el descuento y los recargos de la venta);
// la cuenta final la hace la base. El empleado necesita el PIN del dueño.
function devolver(v, formasPago, ctx, alCambiar) {
  const factor = +v.subtotal > 0 ? +v.total / +v.subtotal : 1;
  const filas = v.items.map(i => ({ i, queda: Math.round((+i.cantidad - +i.devuelto) * 1000) / 1000, cantidad: '', vuelve: true })).filter(f => f.queda > 0.0005);
  const formaPago = v.pagos.find(p => p.forma !== 'Fiado')?.forma || (v.cliente ? 'Fiado' : formasPago[0]);
  const formas = [...formasPago, ...(v.cliente ? ['Fiado'] : [])];
  const m = modal(`Devolver productos de la venta #${v.numero}`, `<form class="form ancho" id="f-dev">
    <p class="muted">Elegí qué devuelve y cuántos. Se le reintegra lo que pagó por eso, con los descuentos y recargos que tuvo la venta.</p>
    <div class="tabla-caja"><table class="tabla" id="dv-tabla"></table></div>
    <div class="fila"><label class="crece">Cómo se le devuelve la plata<select class="input" name="forma">${formas.map(f => `<option value="${esc(f)}" ${f === formaPago ? 'selected' : ''}>${f === 'Fiado' ? 'A su cuenta (fiado)' : esc(f)}</option>`).join('')}</select></label>
      <label class="crece">Motivo<input class="input" name="motivo" maxlength="200" placeholder="opcional"></label></div>
    <p class="muted chico" id="dv-nota"></p>
    <div class="fila entre"><span>Se le devuelve</span><span class="total chico-total" id="dv-total">${plata(0)}</span></div>
    <div class="fila fin"><button type="button" class="btn" data-cerrar>Cancelar</button><button class="btn primario">Devolver</button></div></form>`, { ancho: true });
  const reintegro = () => {
    const todo = filas.every(f => Math.round((f.queda - (numero(f.cantidad) || 0)) * 1000) / 1000 <= 0.0005);
    if (todo) return +v.total - +v.devuelto;
    return filas.reduce((s, f) => s + Math.round(+f.i.importe / +f.i.cantidad * (numero(f.cantidad) || 0) * factor * 100) / 100, 0);
  };
  const pintar = () => {
    $('#dv-tabla', m.el).innerHTML = `<thead><tr><th>Producto</th><th class="num">Puede devolver</th><th class="num">Devuelve</th><th>Vuelve al stock</th></tr></thead><tbody>
      ${filas.map((f, k) => `<tr><td>${esc(f.i.nombre)}</td><td class="num">${cant(f.queda)}${f.i.por_peso ? ' kg' : ''} <button type="button" class="link" data-todo="${k}">Todo</button></td>
        <td class="num"><input class="input cant" data-cant="${k}" value="${esc(f.cantidad)}" inputmode="decimal" placeholder="0"></td>
        <td>${f.i.producto_id ? `<label class="check"><input type="checkbox" data-vuelve="${k}" ${f.vuelve ? 'checked' : ''}> sí</label>` : '—'}</td></tr>`).join('')}</tbody>`;
    $$('[data-cant]', m.el).forEach(inp => inp.oninput = () => { filas[+inp.dataset.cant].cantidad = inp.value; totales(); });
    $$('[data-todo]', m.el).forEach(b => b.onclick = () => { filas[+b.dataset.todo].cantidad = String(filas[+b.dataset.todo].queda); pintar(); });
    $$('[data-vuelve]', m.el).forEach(c => c.onchange = () => { filas[+c.dataset.vuelve].vuelve = c.checked; });
    totales();
  };
  const totales = () => {
    $('#dv-total', m.el).textContent = plata(reintegro());
    const f = $('[name=forma]', m.el).value;
    $('#dv-nota', m.el).textContent = f === 'Fiado' ? 'Se descuenta de su cuenta (o le queda a favor).' : ['Efectivo'].includes(f) ? 'Sale de la caja del turno.' : `Sale de la caja del turno como ${f}: el reintegro real se hace por el posnet o el banco.`;
  };
  $('[name=forma]', m.el).onchange = totales;
  pintar();
  $('#f-dev', m.el).onsubmit = ev => {
    ev.preventDefault();
    const f = new FormData(ev.target);
    const items = filas.filter(x => numero(x.cantidad) > 0).map(x => ({ id: x.i.id, cantidad: numero(x.cantidad), vuelve_stock: x.vuelve }));
    if (!items.length) return aviso('Elegí qué productos devuelve');
    if (filas.some(x => numero(x.cantidad) > x.queda + 0.0005)) return aviso('Hay más cantidad de la que se puede devolver');
    correr(async () => {
      const args = { p_venta_id: v.id, p_items: items, p_forma: f.get('forma'), p_motivo: f.get('motivo'), p_autorizacion: null };
      let r;
      try { r = await llamar('devolver_venta', args); } catch (err) {
        if (err.codigo !== 'autorizacion') throw err;
        const token = await pedirAutorizacion(ctx.usuarios, err.message);
        if (!token) return;
        r = await llamar('devolver_venta', { ...args, p_autorizacion: token });
      }
      m.cerrar();
      await cat.actualizar();
      // comprobante con lugar para la firma del cliente
      const d = r.devoluciones[r.devoluciones.length - 1];
      const m2 = modal(`${r.devolucion.etiqueta} registrada`, `<p>Se le devuelven <b>${plata(r.devolucion.total)}</b>.</p>
        <p class="muted">El comprobante tiene lugar para la firma del cliente.</p>
        <div class="fila fin"><button class="btn" data-cerrar>Listo</button><button class="btn primario" id="imp-dev">Imprimir comprobante</button></div>`,
        { alCerrar: () => alCambiar() });
      $('#imp-dev', m2.el).onclick = () => imprimir(ticketDevolucion(d, r, ctx.config));
    });
  };
}
