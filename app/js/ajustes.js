// Ajustes (solo dueño): datos del negocio y ticket, formas de pago, recargos, tope de descuento, balanza, billetes
// y motivos de las entradas y salidas de mercadería
import { llamar } from './base.js';
import { $, $$, esc, numero, aviso, correr, hoyDia } from './ui.js';
import { imprimir, ticketVenta } from './impresion.js';
import { descargarExcel } from './planilla.js';
import * as cat from './catalogo.js';
import { marcar } from './inicio.js';
import { ATAJO_FABRICA, atajoDe, textoAtajo, atajoApretado, problemaAtajo } from './teclado.js';

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
    </form>
    <form class="form ancho recuadro-blanco" id="f-varios">
      <h3>Vender como "Varios"</h3>
      <label class="check"><input type="checkbox" name="varios" ${ctx.config.varios === false ? '' : 'checked'}> Permitir vender como "Varios" (descripción y precio libre, sin producto)</label>
      <p class="muted chico">Lo vendido como Varios no pasa por el stock ni por las estadísticas de productos. Sin Varios, lo que no está cargado se crea desde la caja con lo mínimo y queda a revisar en Productos.</p>
      <div class="fila"><button class="btn primario">Guardar</button></div>
    </form>
    <form class="form ancho recuadro-blanco" id="f-plazo">
      <h3>Fiado a clientes</h3>
      <label>Plazo para pagar (días)<input class="input corto" name="plazo" inputmode="numeric" value="${esc(ctx.config.plazo_clientes ?? 30)}"></label>
      <p class="muted chico">Cada compra fiada vence a los días que diga el cliente en su ficha; si no tiene, a estos. Cambiarlo cambia el vencimiento de lo que está pendiente.</p>
      <div class="fila"><button class="btn primario">Guardar</button></div>
    </form>
    <form class="form ancho recuadro-blanco" id="f-teclado">
      <h3>Teclado</h3>
      <label>Atajo para ir al menú<input class="input" id="atajo" readonly value="${esc(textoAtajo(atajoDe(ctx.config)))}" aria-describedby="atajo-ayuda"></label>
      <p class="muted chico" id="atajo-ayuda">Hacé clic en el campo y apretá la combinación (por ejemplo Ctrl + ← o Alt + M). Lleva el cursor al menú de la izquierda;
        ahí ↑ ↓ cambian de sección, Enter la abre y Ctrl + → pasa a la pantalla. Vale para todas las PC del negocio.</p>
      <p class="chico mal" id="atajo-problema" hidden></p>
      <div class="fila"><button class="btn primario">Guardar</button><button type="button" class="btn" id="atajo-fabrica">Volver a ${esc(textoAtajo(ATAJO_FABRICA))}</button></div>
    </form>
    <form class="form ancho recuadro-blanco" id="f-datos"><h3>Descargar mis datos</h3>
      <p class="muted chico">Una planilla de Excel con tus productos, clientes (con lo que deben), proveedores (con lo que les debés) y las ventas
        del período que elijas. Para tener una copia guardada o para revisar en la computadora.</p>
      <div class="fila"><label class="crece">Ventas desde<input class="input" type="date" name="desde" value="${hoyDia().slice(0, 8)}01"></label>
        <label class="crece">hasta<input class="input" type="date" name="hasta" value="${hoyDia()}"></label></div>
      <div class="fila"><button class="btn primario">⬇️ Descargar Excel</button></div>
    </form>
    <div class="form ancho recuadro-blanco"><h3>Lectura de facturas con IA</h3><div id="uso-ia" class="muted">…</div></div>`;
  $('#f-datos').onsubmit = ev => {
    ev.preventDefault();
    const f = new FormData(ev.target), desde = f.get('desde'), hasta = f.get('hasta');
    if (!desde || !hasta || hasta < desde) return aviso('Revisá las fechas');
    correr(async () => {
      const [clientes, proveedores, ventas] = await Promise.all([llamar('clientes'), llamar('proveedores'), llamar('ventas_periodo', { p_desde: desde, p_hasta: hasta })]);
      const n = v => v == null || v === '' ? '' : +v;
      const prods = cat.productos().slice().sort((a, b) => a.nombre.localeCompare(b.nombre));
      await descargarExcel(`Datos de ${ctx.negocio.nombre} ${hoyDia()}`, [
        { nombre: 'Productos', filas: [['Nombre', 'Código', 'Otros códigos', 'Categoría', 'Precio', 'Costo', 'Stock', 'Stock mínimo', 'Por kilo'],
          ...prods.map(p => [p.nombre, p.codigo || '', (p.codigos || []).join(' '), cat.categoriaNombre(p.categoria_id), n(p.precio), n(p.costo), n(p.stock), n(p.stock_min), p.por_peso ? 'sí' : ''])] },
        { nombre: 'Clientes', filas: [['Nombre', 'Teléfono', 'Dirección', 'Límite', 'Saldo (positivo = debe)', 'Notas'],
          ...clientes.map(c => [c.nombre, c.telefono || '', c.direccion || '', n(c.limite), n(c.saldo), c.notas || ''])] },
        { nombre: 'Proveedores', filas: [['Nombre', 'CUIT', 'Teléfono', 'Contacto', 'Saldo (positivo = le debés)'],
          ...proveedores.map(p => [p.nombre, p.cuit || '', p.telefono || '', p.contacto || '', n(p.saldo)])] },
        { nombre: 'Ventas', filas: [['Número', 'Fecha', 'Total', 'Devuelto', 'Anulada', 'Vendió', 'Cliente', 'Formas de pago', 'Productos'],
          ...ventas.map(v => [v.numero, new Date(v.fecha).toLocaleString('es-AR'), n(v.total), +v.devuelto ? n(v.devuelto) : '', v.anulada ? 'sí' : '',
            v.vendio || '', v.cliente || '', v.formas || '', v.productos || ''])] },
      ]);
      aviso(`Listo: ${prods.length} productos, ${clientes.length} clientes, ${proveedores.length} proveedores y ${ventas.length} ventas`, 'ok');
    });
  };
  llamar('uso_ia').then(u => {
    $('#uso-ia').innerHTML = `Este mes: <b>${u.mes.lecturas}</b> lectura${+u.mes.lecturas === 1 ? '' : 's'} · US$ ${(+u.mes.costo_usd).toFixed(2)}
      · En total: ${u.total.lecturas} · US$ ${(+u.total.costo_usd).toFixed(2)}
      <p class="chico">El costo es estimado; el detalle oficial está en la consola de Anthropic. Hasta 60 lecturas por día.</p>`;
  }).catch(() => { $('#uso-ia').textContent = 'No se pudo consultar el consumo.'; });
  $('#f-varios').onsubmit = e => {
    e.preventDefault();
    const si = new FormData(e.target).get('varios') === 'on';
    correr(async () => { await llamar('guardar_config', { p_clave: 'varios', p_valor: si }); ctx.config.varios = si; aviso('Guardado', 'ok'); });
  };
  $('#f-plazo').onsubmit = e => {
    e.preventDefault();
    const dias = numero(new FormData(e.target).get('plazo'));
    if (!(dias >= 0 && dias <= 365 && Number.isInteger(dias))) return aviso('El plazo tiene que ser de 0 a 365 días');
    correr(async () => { ctx.config.plazo_clientes = await llamar('guardar_plazo_clientes', { p_dias: dias }); aviso('Plazo guardado', 'ok'); });
  };
  // Teclado: el campo anota la combinación que se aprieta (no se escribe); se controla que no choque con otra
  let atajo = atajoDe(ctx.config);
  const mostrarAtajo = () => {
    $('#atajo').value = textoAtajo(atajo);
    const p = problemaAtajo(atajo);
    $('#atajo-problema').hidden = !p; $('#atajo-problema').textContent = p || '';
  };
  $('#atajo').onkeydown = e => {
    if (e.key === 'Tab' && !e.altKey && !e.ctrlKey) return;   // Tab sigue sirviendo para salir del campo
    e.preventDefault(); e.stopPropagation();   // que no actúe el atajo de ahora mientras se elige el nuevo
    const a = atajoApretado(e);
    if (a) { atajo = a; mostrarAtajo(); }
  };
  $('#atajo-fabrica').onclick = () => { atajo = { ...ATAJO_FABRICA }; mostrarAtajo(); };
  $('#f-teclado').onsubmit = e => {
    e.preventDefault();
    const p = problemaAtajo(atajo);
    if (p) return aviso(p);
    correr(async () => { await llamar('guardar_config', { p_clave: 'atajo_menu', p_valor: atajo }); ctx.config.atajo_menu = atajo; aviso(`Guardado: ${textoAtajo(atajo)} lleva al menú`, 'ok'); });
  };
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
  $('#prueba').onclick = () => { marcar('impresora'); prueba(); };
  const prueba = () => imprimir(ticketVenta({
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
