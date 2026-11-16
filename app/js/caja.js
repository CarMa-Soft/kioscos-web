// Caja: abrir y cerrar el turno, ingresos y egresos, ventas del turno (ver y anular)
import { llamar } from './base.js';
import * as cat from './catalogo.js';
import { $, $$, esc, plata, cant, hora, fecha, numero, aviso, correr, modal, confirmar } from './ui.js';

export async function pantallaCaja(vista, ctx) {
  const e = await llamar('estado_caja');
  const admin = ctx.yo.rol === 'admin';
  if (!e.turno) {
    vista.innerHTML = `<h2>Caja cerrada</h2><p class="muted">Para vender hay que abrir el turno.</p>
      <form class="form" id="f-abrir"><label>Efectivo inicial en la caja<input class="input grande" name="inicial" inputmode="decimal" value="0" autofocus></label>
      <div class="fila"><button class="btn primario">Abrir turno</button></div></form>`;
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
      <div class="acciones"><button class="btn" id="ingreso">Ingreso</button><button class="btn" id="egreso">Egreso</button>
      ${propio || admin ? '<button class="btn primario" id="cerrar">Cerrar turno</button>' : ''}</div></div>
    <div class="tarjetas"><div class="tarjeta"><div class="etq">Efectivo que tiene que haber</div><div class="valor">${plata(t.esperado)}</div></div>
      ${formas.map(([f, v]) => `<div class="tarjeta"><div class="etq">${esc(f)}</div><div class="valor">${plata(v)}</div></div>`).join('')}
      <div class="tarjeta"><div class="etq">Ventas</div><div class="valor">${e.ventas.filter(v => !v.anulada).length}</div></div></div>
    <h3>Ventas del turno</h3>
    <div class="tabla-caja"><table class="tabla">${e.ventas.length ? `<thead><tr><th>#</th><th>Hora</th><th>Productos</th><th>Vendió</th><th class="num">Total</th><th></th></tr></thead><tbody>
      ${e.ventas.map(v => `<tr class="${v.anulada ? 'anulada' : ''}"><td>${v.numero}</td><td>${hora(v.fecha)}</td><td class="corto">${esc(v.resumen || '')}</td><td>${esc(v.usuario)}</td>
        <td class="num">${plata(v.total)}${v.anulada ? ' <span class="etiqueta">anulada</span>' : ''}</td><td><button class="link" data-venta="${v.id}">Ver</button></td></tr>`).join('')}</tbody>`
      : '<tbody><tr><td class="muted vacio">Todavía no hay ventas en este turno.</td></tr></tbody>'}</table></div>
    <h3>Movimientos</h3>
    <div class="tabla-caja"><table class="tabla"><tbody>${e.movimientos.map(m => `<tr><td>${hora(m.fecha)}</td><td>${esc(m.concepto)}<div class="muted chico">${esc(m.usuario)}</div></td>
      <td>${esc(m.forma)}</td><td class="num ${m.tipo === 'egreso' ? 'mal' : ''}">${m.tipo === 'egreso' ? '−' : ''}${plata(m.monto)}</td></tr>`).join('') || '<tr><td class="muted vacio">Sin movimientos.</td></tr>'}</tbody></table></div>`;

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

  function cerrar() {
    const m = modal('Cerrar turno', `<form class="form" id="f-cerrar">
      <label>Efectivo contado en la caja<input class="input grande" name="contado" inputmode="decimal" required autofocus></label>
      <label>Retiro <span class="muted">(lo que te llevás; el resto queda para el próximo turno)</span><input class="input" name="retiro" inputmode="decimal" value="0"></label>
      <label>Notas<input class="input" name="notas" maxlength="500"></label>
      <div class="fila fin"><button type="button" class="btn" data-cerrar>Cancelar</button><button class="btn primario">Cerrar turno</button></div></form>`);
    $('#f-cerrar', m.el).onsubmit = ev => {
      ev.preventDefault();
      const f = new FormData(ev.target), contado = numero(f.get('contado')), retiro = numero(f.get('retiro')) || 0;
      if (!(contado >= 0)) return aviso('Poné el efectivo contado');
      correr(async () => {
        const r = await llamar('cerrar_turno', { p_contado: contado, p_retiro: retiro, p_notas: f.get('notas') });
        m.cerrar();
        const d = +r.diferencia;
        modal('Turno cerrado', `<dl class="kv"><dt>Tenía que haber</dt><dd>${plata(r.esperado)}</dd><dt>Contado</dt><dd>${plata(r.contado)}</dd>
          <dt>Diferencia</dt><dd class="${Math.abs(d) >= 0.01 ? 'mal' : 'ok'}">${Math.abs(d) < 0.01 ? 'Justo' : (d > 0 ? 'Sobran ' : 'Faltan ') + plata(Math.abs(d))}</dd>
          <dt>Retiro</dt><dd>${plata(r.retiro)}</dd></dl><div class="fila fin"><button class="btn primario" data-cerrar>Listo</button></div>`, { alCerrar: () => ctx.recargar() });
      });
    };
  }

  function verVenta(id) {
    correr(async () => {
      const v = await llamar('venta', { p_id: id });
      const m = modal(`Venta #${v.numero}`, `<p class="muted">${fecha(v.fecha)} · ${esc(v.usuario)}${v.anulada ? ` · <b class="mal">Anulada</b> por ${esc(v.anulada_por)}${v.motivo_anulacion ? ': ' + esc(v.motivo_anulacion) : ''}` : ''}</p>
        <table class="tabla"><tbody>${v.items.map(i => `<tr><td>${esc(i.nombre)}</td><td class="num">${cant(i.cantidad)}${i.por_peso ? ' kg' : ''}</td><td class="num">${plata(i.importe)}</td></tr>`).join('')}</tbody>
        <tfoot><tr><th colspan="2">Total</th><th class="num">${plata(v.total)}</th></tr></tfoot></table>
        <p>${v.pagos.map(p => `${esc(p.forma)} ${plata(p.monto)}`).join(' · ')}${v.paga_con ? ` · pagó con ${plata(v.paga_con)}` : ''}</p>
        <div class="fila fin">${admin && !v.anulada ? '<button class="btn peligro" id="anular">Anular venta</button>' : ''}<button class="btn primario" data-cerrar>Cerrar</button></div>`, { ancho: true });
      if ($('#anular', m.el)) $('#anular', m.el).onclick = async () => {
        if (!await confirmar('Anular venta', `Se devuelve el stock y salen ${plata(v.total)} de la caja del turno abierto.`, 'Anular')) return;
        correr(async () => { await llamar('anular_venta', { p_id: v.id, p_motivo: null }); m.cerrar(); aviso(`Venta #${v.numero} anulada`, 'ok'); await cat.actualizar(); ctx.recargar(); });
      };
    });
  }
}
