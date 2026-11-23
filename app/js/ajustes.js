// Ajustes (solo dueño): datos del negocio y ticket, formas de pago, recargos, tope de descuento, balanza, billetes
// y motivos de las entradas y salidas de mercadería
import { llamar } from './base.js';
import { $, $$, esc, numero, aviso, correr } from './ui.js';
import { ayudaInstalador } from './instalador.js';
import { imprimir, ticketVenta } from './impresion.js';
import { ATAJO_FABRICA, atajoDe, textoAtajo, atajoApretado, problemaAtajo } from './teclado.js';

export async function pantallaAjustes(vista, ctx) {
  const [c, motivos] = await Promise.all([llamar('estado_caja'), llamar('motivos_remito')]);
  let formas = c.formas_pago.filter(f => f !== 'Efectivo');
  const recargos = { ...c.recargos };
  const n = { nombre: ctx.negocio.nombre, ...(ctx.config.negocio || {}) };
  const modo = ctx.config.ticket || 'preguntar';
  const papel = String(ctx.config.papel || '58');
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
      ${ayudaInstalador()}
      <label>Ancho del papel<select class="input" name="papel">
        ${[['58', '58 mm (impresora térmica chica)'], ['76', '76 mm (comandera, como la Epson TM-U220)']].map(([v, t]) => `<option value="${v}" ${papel === v ? 'selected' : ''}>${t}</option>`).join('')}</select></label>
      <div class="fila"><button class="btn primario">Guardar</button><button type="button" class="btn" id="prueba">Imprimir un ticket de prueba</button></div>
    </form>
    <div class="form ancho recuadro-blanco" id="logo-negocio"><h3>Logo del negocio</h3>
      <p class="muted chico">Se ve al abrir la app, arriba en el menú y al elegir el usuario. Una imagen cuadrada (o casi) queda mejor; la app la achica sola.</p>
      <div class="logo-fila"><div class="logo-vista" id="logo-vista"></div>
        <div class="fila"><label class="btn"><input type="file" id="logo-archivo" accept="image/*" hidden>📷 Elegir imagen</label>
          <button type="button" class="btn" id="logo-quitar">Quitar</button></div></div>
    </div>
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
    <form class="form ancho recuadro-blanco" id="f-teclado">
      <h3>Teclado</h3>
      <label>Atajo para ir al menú<input class="input" id="atajo" readonly value="${esc(textoAtajo(atajoDe(ctx.config)))}" aria-describedby="atajo-ayuda"></label>
      <p class="muted chico" id="atajo-ayuda">Hacé clic en el campo y apretá la combinación (por ejemplo Ctrl + ← o Alt + M). Lleva el cursor al menú de la izquierda;
        ahí ↑ ↓ cambian de sección, Enter la abre y Ctrl + → pasa a la pantalla. Vale para todas las PC del negocio.</p>
      <p class="chico mal" id="atajo-problema" hidden></p>
      <div class="fila"><button class="btn primario">Guardar</button><button type="button" class="btn" id="atajo-fabrica">Volver a ${esc(textoAtajo(ATAJO_FABRICA))}</button></div>
    </form>
    <div class="form ancho recuadro-blanco"><h3>Lectura de facturas con IA</h3><div id="uso-ia" class="muted">…</div></div>`;
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
  // Logo del negocio: se achica a 256 px (como mucho) y se guarda como imagen chica en la config ('logo')
  const pintarLogo = () => {
    const l = typeof ctx.config.logo === 'string' && ctx.config.logo.startsWith('data:image/') ? ctx.config.logo : '';
    $('#logo-vista').innerHTML = l ? `<img src="${esc(l)}" alt="Logo del negocio">` : '<span class="muted chico">Sin logo: se usa el de la app</span>';
    $('#logo-quitar').hidden = !l;
  };
  const guardarLogo = valor => correr(async () => {
    await llamar('guardar_config', { p_clave: 'logo', p_valor: valor });
    ctx.config.logo = valor; ctx.cambiarLogo?.(valor); pintarLogo();
    aviso(valor ? 'Logo guardado' : 'Logo quitado', 'ok');
  });
  $('#logo-archivo').onchange = e => {
    const archivo = e.target.files[0]; e.target.value = '';
    if (!archivo) return;
    if (!archivo.type.startsWith('image/')) return aviso('Elegí una imagen (foto, PNG, JPG…)');
    const img = new Image(), url = URL.createObjectURL(archivo);
    img.onerror = () => { URL.revokeObjectURL(url); aviso('No se pudo abrir esa imagen'); };
    img.onload = () => {
      URL.revokeObjectURL(url);
      const k = Math.min(1, 256 / Math.max(img.width, img.height));
      const c = Object.assign(document.createElement('canvas'), { width: Math.round(img.width * k), height: Math.round(img.height * k) });
      c.getContext('2d').drawImage(img, 0, 0, c.width, c.height);
      let datos = '';
      for (const q of [0.9, 0.8, 0.65, 0.5]) { datos = c.toDataURL('image/webp', q); if (datos.length < 60000) break; }
      if (!datos.startsWith('data:image/webp')) datos = c.toDataURL('image/png');   // navegador sin webp
      if (datos.length >= 60000) return aviso('La imagen es demasiado pesada: probá con una más simple');
      guardarLogo(datos);
    };
    img.src = url;
  };
  $('#logo-quitar').onclick = () => guardarLogo('');
  pintarLogo();
  $('#f-negocio').onsubmit = e => {
    e.preventDefault();
    const f = new FormData(e.target);
    const datos = Object.fromEntries(['nombre', 'cuit', 'direccion', 'telefono', 'pie_ticket'].map(k => [k, String(f.get(k)).trim()]));
    correr(async () => {
      await llamar('guardar_config', { p_clave: 'negocio', p_valor: datos });
      await llamar('guardar_config', { p_clave: 'ticket', p_valor: f.get('ticket') });
      await llamar('guardar_config', { p_clave: 'papel', p_valor: f.get('papel') });
      ctx.config.negocio = datos; ctx.config.ticket = f.get('ticket'); ctx.config.papel = f.get('papel');   // las demás secciones lo ven sin recargar
      aviso('Datos guardados', 'ok');
    });
  };
  $('#prueba').onclick = () => imprimir(ticketVenta({
    numero: 0, fecha: new Date().toISOString(), cliente: null, subtotal: 1500, descuento: 0, recargo: 0, total: 1500, paga_con: 2000, anulada: false,
    items: [{ nombre: 'Producto de prueba', cantidad: 1, precio: 1000, importe: 1000 }, { nombre: 'Otro producto', cantidad: 2, precio: 250, importe: 500 }],
    pagos: [{ forma: 'Efectivo', monto: 1500, recargo: 0 }],
  }, { ...ctx.config, papel: $('#f-negocio [name=papel]').value, negocio: Object.fromEntries(['nombre', 'cuit', 'direccion', 'telefono', 'pie_ticket'].map(k => [k, $(`#f-negocio [name=${k}]`).value])) }));
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
