// Ajustes (solo dueño): formas de pago, recargo de cada una y tope de descuento de los empleados
import { llamar } from './base.js';
import { $, $$, esc, numero, aviso, correr } from './ui.js';

export async function pantallaAjustes(vista) {
  const c = await llamar('estado_caja');
  let formas = c.formas_pago.filter(f => f !== 'Efectivo');
  const recargos = { ...c.recargos };
  vista.innerHTML = `<h2>Ajustes</h2>
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
    </form>`;
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
