// Ajustes (solo dueño): datos del negocio y ticket, formas de pago, recargos, tope de descuento, balanza, billetes
// y motivos de las entradas y salidas de mercadería
import { llamar } from './base.js';
import { $, $$, esc, numero, aviso, correr } from './ui.js';
import { imprimir, ticketVenta } from './impresion.js';

export async function pantallaAjustes(vista, ctx) {
  const [c, motivos] = await Promise.all([llamar('estado_caja'), llamar('motivos_remito')]);
  let formas = c.formas_pago.filter(f => f !== 'Efectivo');
  const recargos = { ...c.recargos };
  const n = { nombre: ctx.negocio.nombre, ...(ctx.config.negocio || {}) };
  const modo = ctx.config.ticket || 'preguntar';
  vista.innerHTML = `<h2>Ajustes</h2>
    <form class="form ancho recuadro-blanco" id="f-negocio">
      <h3>Datos del negocio (para el ticket)</h3>
      <div class="fila"><label class="crece">Nombre<input class="input" name="nombre" maxlength="80" value="${esc(n.nombre || '')}"></label>
        <label class="crece">CUIT<input class="input" name="cuit" maxlength="20" value="${esc(n.cuit || '')}"></label></div>
      <div class="fila"><label class="crece">Dirección<input class="input" name="direccion" maxlength="120" value="${esc(n.direccion || '')}"></label>
        <label class="crece">Teléfono<input class="input" name="telefono" maxlength="40" value="${esc(n.telefono || '')}"></label></div>
      <label>Pie del ticket<input class="input" name="pie_ticket" maxlength="120" value="${esc(n.pie_ticket ?? '¡Gracias por su compra!')}"></label>
      <label>Ticket después de cada venta<select class="input" name="ticket">
        ${[['preguntar', 'Preguntar (P imprime)'], ['siempre', 'Imprimir siempre'], ['nunca', 'No imprimir']].map(([v, t]) => `<option value="${v}" ${modo === v ? 'selected' : ''}>${t}</option>`).join('')}</select></label>
      <p class="muted chico">Para que imprima directo, sin la ventana de impresión, abrí Chrome con la opción <span class="mono">--kiosk-printing</span>
        y dejá la impresora de tickets como predeterminada.</p>
      <div class="fila"><button class="btn primario">Guardar</button><button type="button" class="btn" id="prueba">Imprimir un ticket de prueba</button></div>
    </form>
    <form class="form ancho recuadro-blanco" id="f-cobro">
      <h3>Formas de pago y recargos</h3>
      <p class="muted">Los precios de los productos son para efectivo. Cada forma puede llevar un recargo en %, que se suma al cobrar
        (redondeado a pesos). Efectivo siempre está y nunca lleva recargo; Fiado aparece al elegir un cliente.</p>
      <div id="formas"></div>
      <div class="fila"><input class="input crece" id="nueva" placeholder="Nueva forma de pago (ej: Cuenta DNI)" maxlength="40"><button type="button" class="btn" id="agregar">Agregar</button></div>
      <h3>Descuentos de los empleados</h3>
      <label>Tope de descuento sin autorización (%)<input class="input" name="tope" inputmode="decimal" value="${c.tope_descuento}"></label>
      <p class="muted chico">Si un empleado rebaja más que esto (sumando los precios cambiados y el descuento general), la venta necesita el PIN de un dueño. El dueño no tiene tope.</p>
      <div class="fila"><button class="btn primario">Guardar</button></div>
    </form>
    <form class="form ancho recuadro-blanco" id="f-caja">
      <h3>Balanza</h3>
      <p class="muted">Las etiquetas de la balanza (EAN-13) traen el código de balanza (PLU) del producto y el peso o el importe.
        Cada producto por kilo tiene que tener su código de balanza en Productos.</p>
      <label class="check"><input type="checkbox" name="activa" ${c.balanza?.activa ? 'checked' : ''}> Leer etiquetas de balanza al escanear</label>
      <div class="fila"><label class="crece">Prefijo de las etiquetas<input class="input" name="prefijo" maxlength="2" inputmode="numeric" value="${esc(c.balanza?.prefijo || '20')}"></label>
        <label class="crece">La etiqueta trae<select class="input" name="tipo">
          ${[['peso', 'El peso (gramos)'], ['importe', 'El importe (pesos)'], ['importe_centavos', 'El importe (con centavos)']].map(([v, t]) => `<option value="${v}" ${c.balanza?.tipo === v ? 'selected' : ''}>${t}</option>`).join('')}</select></label></div>
      <h3>Billetes para el cierre de caja</h3>
      <p class="muted">Los valores que aparecen al contar la caja. Separalos con comas (pueden salir billetes nuevos).</p>
      <input class="input" name="billetes" value="${esc((c.billetes || []).join(', '))}">
      <div class="fila"><button class="btn primario">Guardar</button></div>
    </form>
    <form class="form ancho recuadro-blanco" id="f-motivos">
      <h3>Motivos de entradas y salidas de mercadería</h3>
      <p class="muted">Uno por renglón. Son los que se eligen al cargar una entrada o una salida.</p>
      <div class="fila"><label class="crece">Entradas<textarea class="input" name="ingreso" rows="6">${esc((motivos.ingreso || []).join('\n'))}</textarea></label>
        <label class="crece">Salidas<textarea class="input" name="egreso" rows="6">${esc((motivos.egreso || []).join('\n'))}</textarea></label></div>
      <div class="fila"><button class="btn primario">Guardar</button></div>
    </form>`;
  $('#f-motivos').onsubmit = e => {
    e.preventDefault();
    const f = new FormData(e.target);
    const lineas = k => String(f.get(k)).split(/\r?\n/).map(x => x.trim()).filter(Boolean);
    correr(async () => {
      await llamar('guardar_motivos_remito', { p: { ingreso: lineas('ingreso'), egreso: lineas('egreso') } });
      aviso('Motivos guardados', 'ok');
    });
  };
  $('#f-negocio').onsubmit = e => {
    e.preventDefault();
    const f = new FormData(e.target);
    const datos = Object.fromEntries(['nombre', 'cuit', 'direccion', 'telefono', 'pie_ticket'].map(k => [k, String(f.get(k)).trim()]));
    correr(async () => {
      await llamar('guardar_config', { p_clave: 'negocio', p_valor: datos });
      await llamar('guardar_config', { p_clave: 'ticket', p_valor: f.get('ticket') });
      ctx.config.negocio = datos; ctx.config.ticket = f.get('ticket');   // las demás secciones lo ven sin recargar
      aviso('Datos guardados', 'ok');
    });
  };
  $('#prueba').onclick = () => imprimir(ticketVenta({
    numero: 0, fecha: new Date().toISOString(), cliente: null, subtotal: 1500, descuento: 0, recargo: 0, total: 1500, paga_con: 2000, anulada: false,
    items: [{ nombre: 'Producto de prueba', cantidad: 1, precio: 1000, importe: 1000 }, { nombre: 'Otro producto', cantidad: 2, precio: 250, importe: 500 }],
    pagos: [{ forma: 'Efectivo', monto: 1500, recargo: 0 }],
  }, { ...ctx.config, negocio: Object.fromEntries(['nombre', 'cuit', 'direccion', 'telefono', 'pie_ticket'].map(k => [k, $(`#f-negocio [name=${k}]`).value])) }));
  $('#f-caja').onsubmit = e => {
    e.preventDefault();
    const f = new FormData(e.target);
    const billetes = String(f.get('billetes')).split(/[,;\s]+/).map(x => x.trim()).filter(Boolean);
    correr(async () => {
      await llamar('guardar_ajustes_caja', { p_balanza: { activa: f.get('activa') === 'on', prefijo: f.get('prefijo'), tipo: f.get('tipo') }, p_billetes: billetes });
      aviso('Ajustes guardados', 'ok');
    });
  };
  const pintar = () => {
    $('#formas').innerHTML = `<table class="tabla"><thead><tr><th>Forma</th><th class="num">Recargo %</th><th></th></tr></thead><tbody>
      <tr><td>Efectivo</td><td class="num muted">—</td><td></td></tr>
      ${formas.map((f, k) => `<tr><td>${esc(f)}</td><td class="num"><input class="input corto" data-rec="${esc(f)}" inputmode="decimal" value="${recargos[f] ?? ''}" placeholder="0"></td>
        <td class="num"><button type="button" class="link" data-sacar="${k}">Sacar</button></td></tr>`).join('')}
      <tr><td>Fiado</td><td class="num"><input class="input corto" data-rec="Fiado" inputmode="decimal" value="${recargos.Fiado ?? ''}" placeholder="0"></td><td></td></tr></tbody></table>`;
    $$('[data-rec]').forEach(i => i.oninput = () => { recargos[i.dataset.rec] = i.value; });
    $$('[data-sacar]').forEach(b => b.onclick = () => { formas.splice(+b.dataset.sacar, 1); pintar(); });
  };
  $('#agregar').onclick = () => {
    const f = $('#nueva').value.trim();
    if (!f) return;
    if (['efectivo', 'fiado', ...formas.map(x => x.toLowerCase())].includes(f.toLowerCase())) return aviso('Esa forma de pago ya está');
    formas.push(f); $('#nueva').value = ''; pintar();
  };
  $('#nueva').onkeydown = e => { if (e.key === 'Enter') { e.preventDefault(); $('#agregar').click(); } };
  $('#f-cobro').onsubmit = e => {
    e.preventDefault();
    const tope = numero(new FormData(e.target).get('tope'));
    if (!(tope >= 0 && tope <= 100)) return aviso('El tope tiene que ser entre 0 y 100');
    const rec = {};
    for (const f of [...formas, 'Fiado']) { const v = numero(recargos[f]); if (v > 0) rec[f] = v; }
    correr(async () => {
      const r = await llamar('guardar_ajustes_cobro', { p_formas: ['Efectivo', ...formas], p_recargos: rec, p_tope: tope });
      formas = r.formas_pago.filter(f => f !== 'Efectivo');
      aviso('Ajustes guardados', 'ok'); pintar();
    });
  };
  pintar();
}
