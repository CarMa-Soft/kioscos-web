// Encargos: lo que un cliente encarga sin pagar (o dejando una seña). No es una venta: no toca el stock.
// La seña entra a la caja al encargar; cuando lo viene a buscar, Vender lo pasa a la venta y la seña se descuenta.
import { llamar } from './base.js';
import * as cat from './catalogo.js';
import { $, $$, esc, plata, cant, numero, aviso, correr, modal, confirmar } from './ui.js';

// Alta de un encargo. formas: las formas de pago del negocio (para la seña).
export function nuevoEncargo({ formas, alGuardar }) {
  let prod = null, clientes = [];
  llamar('clientes').then(l => {
    clientes = l.filter(c => c.activo);
    const dl = $('#enc-clientes', m.el);
    if (dl) dl.innerHTML = clientes.map(c => `<option value="${esc(c.nombre)}">`).join('');
  }).catch(() => {});
  const m = modal('Nuevo encargo', `<form class="form ancho" id="f-enc">
    <label>Producto<input class="input" id="enc-buscar" placeholder="Buscalo por nombre o escaneá el código" autocomplete="off" autofocus></label>
    <div class="resultados" id="enc-res" hidden></div>
    <div id="enc-prod"></div>
    <div class="fila"><label class="crece">Cantidad<input class="input" name="cantidad" inputmode="decimal" value="1" required></label>
      <label class="crece">A nombre de<input class="input" name="nombre" maxlength="80" list="enc-clientes" autocomplete="off" placeholder="Nombre o cliente" required></label>
      <label class="crece">Teléfono<input class="input" name="telefono" maxlength="40" inputmode="tel" placeholder="Opcional"></label></div>
    <datalist id="enc-clientes"></datalist>
    <div class="fila"><label class="crece">Seña $<input class="input" name="sena" inputmode="decimal" placeholder="0 si no deja"></label>
      <label class="crece">Forma de la seña<select class="input" name="sena_forma">${formas.map(f => `<option>${esc(f)}</option>`).join('')}</select></label></div>
    <label>Notas<input class="input" name="notas" maxlength="200" placeholder="Opcional. Ej.: lo pasa a buscar el viernes"></label>
    <p class="muted chico">No es una venta: no toca el stock. Se suma a Pedidos para pedirlo al proveedor. La seña entra a la caja ahora y se
      descuenta cuando lo venga a buscar.</p>
    <div class="fila fin"><button type="button" class="btn" data-cerrar>Cancelar</button><button class="btn primario">Guardar encargo</button></div></form>`, { ancho: true });
  const f = $('#f-enc', m.el), buscar = $('#enc-buscar', m.el), res = $('#enc-res', m.el);
  const elegir = p => {
    prod = p; res.hidden = true; buscar.value = '';
    $('#enc-prod', m.el).innerHTML = `<div class="enc-elegido"><b>${esc(p.nombre)}</b> <span class="muted">· ${plata(p.precio)}${p.por_peso ? '/kg' : ''} · stock ${cant(p.stock)}</span></div>`;
    f.elements.cantidad.focus(); f.elements.cantidad.select();
  };
  buscar.oninput = () => {
    const t = buscar.value.trim();
    if (t.length < 2 || /^\d{6,}$/.test(t)) { res.hidden = true; return; }
    const ver = cat.buscar(t, 8);
    res.hidden = false;
    res.innerHTML = ver.map(p => `<button type="button" class="resultado" data-id="${p.id}"><span>${esc(p.nombre)}</span><span class="muted">stock ${cant(p.stock)}</span><b>${plata(p.precio)}</b></button>`).join('')
      || `<p class="muted sin">No hay productos con "${esc(t)}". Si no está cargado, crealo desde Vender.</p>`;
    $$('[data-id]', res).forEach(b => b.onclick = () => elegir(cat.producto(+b.dataset.id)));
  };
  buscar.onkeydown = e => {
    if (e.key !== 'Enter') return;
    e.preventDefault();
    const t = buscar.value.trim(), p = cat.porCodigoDeBarras(t) || (cat.buscar(t, 2).length === 1 ? cat.buscar(t, 1)[0] : null);
    if (p) elegir(p); else aviso(/^\d{6,}$/.test(t) ? `No hay ningún producto con el código ${t}` : 'Elegí el producto de la lista');
  };
  f.onsubmit = e => {
    e.preventDefault();
    if (!prod) { buscar.focus(); return aviso('Elegí el producto'); }
    const nombre = f.elements.nombre.value.trim(), cli = clientes.find(c => c.nombre.toLowerCase() === nombre.toLowerCase());
    const sena = numero(f.elements.sena.value) || 0, cantidad = numero(f.elements.cantidad.value);
    if (!(cantidad > 0)) return aviso('Poné la cantidad');
    if (sena < 0) return aviso('Revisá la seña');
    correr(async () => {
      const r = await llamar('registrar_encargo', { p: { producto_id: prod.id, cantidad, cliente_id: cli?.id ?? null, nombre, telefono: f.elements.telefono.value.trim(),
        notas: f.elements.notas.value.trim(), sena, sena_forma: f.elements.sena_forma.value } });
      m.cerrar();
      aviso(`Encargo #${r.numero} guardado: ${cant(r.cantidad)} ${r.nombre} para ${r.a_nombre}${+r.sena ? ` · seña ${plata(r.sena)} en la caja` : ''}`, 'ok');
      alGuardar?.(r);
    });
  };
}

// Texto corto de un encargo para listas
export const detalleEncargo = e => `${esc(e.a_nombre)}${e.telefono ? ' · ' + esc(e.telefono) : ''} · encargo #${e.numero} del ${new Date(e.fecha).toLocaleDateString('es-AR')}`
  + `${+e.sena ? ` · <b>seña ${plata(e.sena)}</b>` : ' · sin seña'}${e.notas ? ` · ${esc(e.notas)}` : ''}`;

// La lista de encargos pendientes, con "Pasar a la venta" (si se pasa alPasar) y "Cancelar"
export function verEncargos(lista, { alPasar, alCambiar } = {}) {
  const m = modal('Encargos', `<div class="tabla-caja"><table class="tabla"><tbody>
    ${lista.map(e => `<tr><td><b>${cant(e.cantidad)}${e.por_peso ? ' kg' : ''} ${esc(e.nombre)}</b>${+e.entregado ? ` <span class="muted chico">(faltan de ${cant(e.encargado)}; ya se entregaron ${cant(e.entregado)})</span>` : ''}
        ${e.lista ? '<span class="etiqueta bien">llegó</span>' : +e.stock > 0 ? `<span class="etiqueta pendiente">llegaron ${cant(e.stock)}</span>` : '<span class="etiqueta pendiente">esperando mercadería</span>'}
        <div class="muted chico">${detalleEncargo(e)}</div></td>
      <td class="num nowrap">${!alPasar ? '' : +e.stock > 0 ? `<button class="btn primario chico" data-pasar="${e.id}">${e.lista ? 'Pasar a la venta' : `Pasar ${cant(e.por_peso ? +e.stock : Math.floor(+e.stock))} a la venta`}</button>`
        : '<span class="muted chico">todavía no llegó</span>'}
        <button class="btn chico" data-cancelar="${e.id}">Cancelar</button></td></tr>`).join('')}</tbody></table></div>
    <p class="muted chico">"Pasar a la venta" suma a la venta en curso lo que llegó (si llegó una parte, el resto sigue pendiente); al cobrar, la seña se descuenta.</p>
    <div class="fila fin"><button class="btn" data-cerrar>Cerrar</button></div>`, { ancho: true });
  $$('[data-pasar]', m.el).forEach(b => b.onclick = () => { m.cerrar(); alPasar(lista.find(e => e.id === +b.dataset.pasar)); });
  $$('[data-cancelar]', m.el).forEach(b => b.onclick = () => cancelar(lista.find(e => e.id === +b.dataset.cancelar), () => { m.cerrar(); alCambiar?.(); }));
}

function cancelar(e, listo) {
  if (!(+e.sena > 0)) {
    return confirmar('Cancelar encargo', `¿Cancelar el encargo #${e.numero} de ${e.a_nombre} (${cant(e.cantidad)} ${e.nombre})?`, 'Cancelar encargo').then(si => {
      if (si) correr(async () => { await llamar('cancelar_encargo', { p_id: e.id, p_devolver: null }); aviso('Encargo cancelado', 'ok'); listo(); });
    });
  }
  const m = modal(`Cancelar el encargo #${e.numero}`, `<p>${esc(e.a_nombre)} dejó una seña de <b>${plata(e.sena)}</b> (${esc(e.sena_forma || 'Efectivo')}). ¿Qué pasa con la seña?</p>
    <label>Motivo <span class="muted">(opcional)</span><input class="input" id="enc-motivo" maxlength="200"></label>
    <div class="fila fin"><button class="btn" data-cerrar>Volver</button><button class="btn" id="enc-retener">La seña queda para el negocio</button>
      <button class="btn primario" id="enc-devolver">Devolver la seña (sale de la caja)</button></div>`, { ancho: true });
  const hacer = devolver => correr(async () => {
    await llamar('cancelar_encargo', { p_id: e.id, p_devolver: devolver, p_motivo: $('#enc-motivo', m.el).value.trim() });
    m.cerrar(); aviso(devolver ? `Encargo cancelado: devolvé ${plata(e.sena)}` : 'Encargo cancelado: la seña queda para el negocio', 'ok'); listo();
  });
  $('#enc-devolver', m.el).onclick = () => hacer(true);
  $('#enc-retener', m.el).onclick = () => hacer(false);
}
