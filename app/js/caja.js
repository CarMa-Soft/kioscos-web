// Caja: abrir y cerrar el turno, ingresos y egresos, ventas del turno (ver y anular)
import { llamar } from './base.js';
import * as cat from './catalogo.js';
import { $, $$, esc, plata, cant, hora, fecha, numero, aviso, correr, modal, confirmar } from './ui.js';

export async function pantallaCaja(vista, ctx) {
  const e = await llamar('estado_caja');
  const admin = ctx.yo.rol === 'admin';
  if (!e.turno) {
    vista.innerHTML = `<div class="cabecera"><h2>Caja cerrada</h2><button class="btn" id="anteriores">Turnos anteriores</button></div>
      <p class="muted">Para vender hay que abrir el turno.</p>
      <form class="form" id="f-abrir"><label>Efectivo inicial en la caja<input class="input grande" name="inicial" inputmode="decimal" value="0" autofocus></label>
      <div class="fila"><button class="btn primario">Abrir turno</button></div></form>`;
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
    <div class="tarjetas"><div class="tarjeta"><div class="etq">Efectivo que tiene que haber</div><div class="valor">${plata(t.esperado)}</div></div>
      ${formas.map(([f, v]) => `<div class="tarjeta"><div class="etq">${esc(f)}</div><div class="valor">${plata(v)}</div></div>`).join('')}
      ${+e.fiado ? `<div class="tarjeta"><div class="etq">Fiado <span class="muted">(no entra a la caja)</span></div><div class="valor">${plata(e.fiado)}</div></div>` : ''}
      <div class="tarjeta"><div class="etq">Ventas</div><div class="valor">${e.ventas.filter(v => !v.anulada).length}</div></div></div>
    <h3>Ventas del turno</h3>
    <div class="tabla-caja"><table class="tabla">${e.ventas.length ? `<thead><tr><th>#</th><th>Hora</th><th>Productos</th><th>Vendió</th><th class="num">Total</th><th></th></tr></thead><tbody>
      ${e.ventas.map(v => `<tr class="${v.anulada ? 'anulada' : ''}"><td>${v.numero}</td><td>${hora(v.fecha)}</td><td class="corto">${esc(v.resumen || '')}${v.cliente ? `<div class="muted chico">${esc(v.cliente)}${v.fiado ? ' · fiado' : ''}</div>` : ''}</td><td>${esc(v.usuario)}</td>
        <td class="num">${plata(v.total)}${v.anulada ? ' <span class="etiqueta">anulada</span>' : ''}</td><td><button class="link" data-venta="${v.id}">Ver</button></td></tr>`).join('')}</tbody>`
      : '<tbody><tr><td class="muted vacio">Todavía no hay ventas en este turno.</td></tr></tbody>'}</table></div>
    <h3>Movimientos</h3>
    <div class="tabla-caja"><table class="tabla"><tbody>${e.movimientos.map(m => `<tr><td>${hora(m.fecha)}</td><td>${esc(m.concepto)}<div class="muted chico">${esc(m.usuario)}</div></td>
      <td>${esc(m.forma)}</td><td class="num ${m.tipo === 'egreso' ? 'mal' : ''}">${m.tipo === 'egreso' ? '−' : ''}${plata(m.monto)}</td></tr>`).join('') || '<tr><td class="muted vacio">Sin movimientos.</td></tr>'}</tbody></table></div>`;

  $('#anteriores').onclick = () => turnosAnteriores();
  $('#ingreso').onclick = () => movimiento('ingreso');
  $('#egreso').onclick = () => movimiento('egreso');
  if ($('#cerrar')) $('#cerrar').onclick = () => cerrar();
  $$('[data-venta]').forEach(b => b.onclick = () => verVenta(+b.dataset.venta));

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

  // Cierre contando los billetes de cada valor (Ajustes): el total lo suma la pantalla y lo vuelve a calcular la base
  function cerrar() {
    const billetes = (e.billetes || []).map(Number);
    const m = modal('Cerrar turno', `<form class="form ancho" id="f-cerrar">
      <p>Tiene que haber <b>${plata(t.esperado)}</b> en efectivo. Contá cuántos billetes hay de cada valor: el total se suma solo.</p>
      <table class="tabla"><thead><tr><th>Billete</th><th>Cantidad</th><th class="num">Subtotal</th></tr></thead><tbody>
        ${billetes.map(b => `<tr><td><b>${plata(b).replace(/,00$/, '')}</b></td><td><input class="input corto" data-bill="${b}" inputmode="numeric" placeholder="0"></td><td class="num" data-sub="${b}">—</td></tr>`).join('')}
        <tr><td colspan="2">Monedas y otros <span class="muted chico">(si no contás por billetes, poné acá el total)</span></td><td class="num"><input class="input corto" name="otros" inputmode="decimal" placeholder="0"></td></tr></tbody></table>
      <div class="fila entre"><span>Total contado</span><span class="total chico-total" id="contado">${plata(0)}</span></div>
      <p class="diferencia" id="dif"></p>
      <label class="check" id="ajuste-box" hidden><input type="checkbox" name="ajuste" checked> <span id="ajuste-txt"></span></label>
      <label>Retiro <span class="muted">(lo que te llevás; el resto queda para el próximo turno)</span><input class="input" name="retiro" inputmode="decimal" placeholder="0"></label>
      <label>Notas<input class="input" name="notas" maxlength="500" placeholder="opcional"></label>
      <div class="fila fin"><button type="button" class="btn" data-cerrar>Cancelar</button><button class="btn primario" id="ok">Cerrar turno</button></div></form>`, { ancho: true });
    const leer = () => {
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
    setTimeout(() => $('[data-bill]', m.el)?.focus(), 40);
    $('#f-cerrar', m.el).onsubmit = ev => {
      ev.preventDefault();
      const f = new FormData(ev.target), { det, otros, contado, invalido, hay } = leer(), retiro = numero(f.get('retiro')) || 0;
      if (invalido) return aviso('Revisá el conteo: las cantidades de billetes son números enteros');
      if (!hay) return aviso('Contá el efectivo (si no hay nada, poné 0 en "Monedas y otros")');
      if (!(retiro >= 0) || retiro > contado) return aviso('El retiro no puede ser mayor a lo contado');
      correr(async () => {
        const r = await llamar('cerrar_turno', { p_contado: null, p_retiro: retiro, p_notas: f.get('notas'), p_billetes: det, p_otros: otros, p_registrar_ajuste: f.get('ajuste') === 'on' });
        m.cerrar();
        resumenTurno(r, () => ctx.recargar());
      });
    };
  }

  // Detalle de un turno cerrado: totales, conteo de billetes y movimientos
  function resumenTurno(r, alCerrar) {
    const d = +r.diferencia, b = r.billetes;
    modal(`Turno de ${r.usuario}`, `<p class="muted">${fecha(r.apertura)} a ${fecha(r.cierre)}${r.cerrado_por && r.cerrado_por !== r.usuario ? ' · cerró ' + esc(r.cerrado_por) : ''}</p>
      <dl class="kv"><dt>Inicial</dt><dd>${plata(r.inicial)}</dd><dt>Tenía que haber</dt><dd>${plata(r.esperado)}</dd><dt>Contado</dt><dd>${plata(r.contado)}</dd>
        <dt>Diferencia</dt><dd class="${Math.abs(d) >= 0.01 ? (d > 0 ? 'ok' : 'mal') : 'ok'}">${Math.abs(d) < 0.01 ? 'Justo' : (d > 0 ? 'Sobraron ' : 'Faltaron ') + plata(Math.abs(d))}</dd>
        <dt>Retiro</dt><dd>${plata(r.retiro)}</dd><dt>Ventas</dt><dd>${r.ventas} · ${plata(r.total_ventas)}</dd></dl>
      ${b ? `<h3>Conteo</h3><table class="tabla"><tbody>${Object.entries(b.detalle || {}).sort((x, y) => +y[0] - +x[0]).map(([v, q]) => `<tr><td>${q} × ${plata(v)}</td><td class="num">${plata(q * v)}</td></tr>`).join('')}
        ${+b.otros ? `<tr><td>Monedas y otros</td><td class="num">${plata(b.otros)}</td></tr>` : ''}</tbody></table>` : ''}
      ${r.notas ? `<p><b>Notas:</b> ${esc(r.notas)}</p>` : ''}
      <h3>Movimientos</h3><div class="tabla-caja"><table class="tabla"><tbody>${(r.movimientos || []).map(x => `<tr><td>${hora(x.fecha)}</td><td>${esc(x.concepto)}${x.ajuste ? ' <span class="etiqueta">ajuste</span>' : ''}</td>
        <td>${esc(x.forma)}</td><td class="num ${x.tipo === 'egreso' ? 'mal' : ''}">${x.tipo === 'egreso' ? '−' : ''}${plata(x.monto)}</td></tr>`).join('') || '<tr><td class="muted vacio">Sin movimientos.</td></tr>'}</tbody></table></div>
      <div class="fila fin"><button class="btn primario" data-cerrar>Listo</button></div>`, { ancho: true, alCerrar });
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

  function verVenta(id) {
    correr(async () => {
      const v = await llamar('venta', { p_id: id });
      const m = modal(`Venta #${v.numero}`, `<p class="muted">${fecha(v.fecha)} · ${esc(v.usuario)}${v.cliente ? ' · cliente ' + esc(v.cliente.nombre) : ''}${v.anulada ? ` · <b class="mal">Anulada</b> por ${esc(v.anulada_por)}${v.motivo_anulacion ? ': ' + esc(v.motivo_anulacion) : ''}` : ''}</p>
        <table class="tabla"><tbody>${v.items.map(i => `<tr><td>${esc(i.nombre)}</td><td class="num">${cant(i.cantidad)}${i.por_peso ? ' kg' : ''}</td><td class="num">${plata(i.importe)}</td></tr>`).join('')}</tbody>
        <tfoot>${+v.descuento || +v.recargo ? `<tr><td colspan="2">Subtotal</td><td class="num">${plata(v.subtotal)}</td></tr>` : ''}
          ${+v.descuento ? `<tr><td colspan="2">Descuento</td><td class="num">−${plata(v.descuento)}</td></tr>` : ''}
          ${+v.recargo ? `<tr><td colspan="2">Recargo</td><td class="num">+${plata(v.recargo)}</td></tr>` : ''}
          <tr><th colspan="2">Total</th><th class="num">${plata(v.total)}</th></tr></tfoot></table>
        ${+v.descuento_renglones ? `<p class="muted chico">Precios rebajados en los renglones: ${plata(v.descuento_renglones)} menos que la lista.</p>` : ''}
        ${v.autorizo ? `<p class="muted chico">Descuento autorizado por ${esc(v.autorizo)}.</p>` : ''}
        <p>${v.pagos.map(p => `${esc(p.forma)} ${plata(p.monto)}`).join(' · ')}${v.paga_con ? ` · pagó con ${plata(v.paga_con)}` : ''}</p>
        <div class="fila fin">${admin && !v.anulada ? '<button class="btn peligro" id="anular">Anular venta</button>' : ''}<button class="btn primario" data-cerrar>Cerrar</button></div>`, { ancho: true });
      if ($('#anular', m.el)) $('#anular', m.el).onclick = async () => {
        const fiado = v.pagos.filter(p => p.forma === 'Fiado').reduce((s, p) => s + +p.monto, 0), deCaja = +v.total - fiado;
        if (!await confirmar('Anular venta', `Se devuelve el stock${deCaja > 0 ? `, salen ${plata(deCaja)} de la caja del turno abierto` : ''}${fiado > 0 ? ` y se le descuentan ${plata(fiado)} de la cuenta a ${v.cliente.nombre}` : ''}.`, 'Anular')) return;
        correr(async () => { await llamar('anular_venta', { p_id: v.id, p_motivo: null }); m.cerrar(); aviso(`Venta #${v.numero} anulada`, 'ok'); await cat.actualizar(); ctx.recargar(); });
      };
    });
  }
}
