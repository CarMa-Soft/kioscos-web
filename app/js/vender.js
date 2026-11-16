// Vender: escanear o buscar, armar la venta y cobrar
import { llamar } from './base.js';
import * as cat from './catalogo.js';
import { $, $$, esc, plata, cant, numero, aviso, correr, modal } from './ui.js';

// La venta en curso sobrevive a cambiar de sección. 'clave' identifica el intento de cobro: si se corta internet
// y se vuelve a cobrar, la base reconoce la misma venta y no la registra dos veces.
let venta = { items: [], clave: crypto.randomUUID() };
const nueva = () => { venta = { items: [], clave: crypto.randomUUID() }; };
const total = () => Math.round(venta.items.reduce((s, i) => s + importe(i), 0) * 100) / 100;
const importe = i => i.producto_id ? Math.round(i.cantidad * (cat.producto(i.producto_id)?.precio ?? i.precio) * 100) / 100 : i.importe;

export async function pantallaVender(vista, ctx) {
  const caja = await llamar('estado_caja');
  vista.innerHTML = `
    ${caja.turno ? '' : '<p class="aviso mal">La caja está cerrada: <a href="#/caja">abrí tu turno en Caja</a> para poder cobrar.</p>'}
    <div class="vender">
      <div class="vender-izq">
        <input class="input grande" id="escaner" placeholder="Escaneá o escribí para buscar (Enter)" autocomplete="off" autofocus>
        <div id="resultados" class="resultados" hidden></div>
        <div class="tabla-caja"><table class="tabla" id="renglones"></table></div>
        <div class="fila"><button class="btn" id="varios">＋ Varios</button><button class="btn" id="vaciar">Vaciar</button></div>
      </div>
      <div class="vender-der">
        <div class="total-etq">Total</div><div class="total" id="total"></div>
        <button class="btn primario grande" id="cobrar">Cobrar (F2)</button>
        <p class="muted chico">Turno: ${caja.turno ? esc(caja.turno.usuario) : 'cerrado'}</p>
      </div>
    </div>`;
  const escaner = $('#escaner'), res = $('#resultados');
  pintar();

  escaner.onkeydown = e => {
    if (e.key !== 'Enter') return;
    e.preventDefault();
    const texto = escaner.value.trim();
    if (!texto) return;
    const p = cat.porCodigoDeBarras(texto);
    if (p) { escaner.value = ''; res.hidden = true; return agregar(p); }
    const lista = cat.buscar(texto);
    if (lista.length === 1) { escaner.value = ''; res.hidden = true; return agregar(lista[0]); }
    mostrarResultados(lista, texto);
  };
  escaner.oninput = () => { if (!escaner.value.trim()) res.hidden = true; };
  $('#varios').onclick = () => varios();
  $('#vaciar').onclick = () => { nueva(); pintar(); escaner.focus(); };
  $('#cobrar').onclick = () => cobrar(caja);
  ctx.alTeclear(e => { if (e.key === 'F2') { e.preventDefault(); cobrar(caja); } });

  function mostrarResultados(lista, texto) {
    res.hidden = false;
    res.innerHTML = lista.length ? lista.map(p => `<button class="resultado" data-id="${p.id}"><span>${esc(p.nombre)}</span>
        <span class="muted">${p.codigo ? esc(p.codigo) + ' · ' : ''}stock ${cant(p.stock)}</span><b>${plata(p.precio)}${p.por_peso ? '/kg' : ''}</b></button>`).join('')
      : `<p class="muted">No hay productos con "${esc(texto)}".</p>`;
    $$('.resultado', res).forEach(b => b.onclick = () => { escaner.value = ''; res.hidden = true; agregar(cat.producto(+b.dataset.id)); });
    $('.resultado', res)?.focus();
  }

  function agregar(p) {
    if (p.por_peso) return pedirPeso(p);
    const ya = venta.items.find(i => i.producto_id === p.id);
    if (ya) ya.cantidad += 1; else venta.items.push({ producto_id: p.id, nombre: p.nombre, cantidad: 1, precio: p.precio });
    pintar(); escaner.focus();
  }

  function pedirPeso(p) {
    const m = modal(`${p.nombre} — ${plata(p.precio)}/kg`, `<form class="form" id="f-peso"><label>Kilos<input class="input grande" name="kg" inputmode="decimal" autocomplete="off" required autofocus></label>
      <div class="fila fin"><button type="button" class="btn" data-cerrar>Cancelar</button><button class="btn primario">Agregar</button></div></form>`,
      { alCerrar: () => escaner.focus() });
    $('#f-peso', m.el).onsubmit = e => {
      e.preventDefault();
      const kg = numero(new FormData(e.target).get('kg'));
      if (!(kg > 0)) return aviso('Poné los kilos');
      venta.items.push({ producto_id: p.id, nombre: p.nombre, cantidad: Math.round(kg * 1000) / 1000, precio: p.precio, por_peso: true });
      m.cerrar(); pintar();
    };
  }

  function varios() {
    const m = modal('Varios', `<form class="form" id="f-varios"><label>Descripción<input class="input" name="nombre" placeholder="Varios" maxlength="120"></label>
      <label>Importe<input class="input grande" name="importe" inputmode="decimal" autocomplete="off" required autofocus></label>
      <div class="fila fin"><button type="button" class="btn" data-cerrar>Cancelar</button><button class="btn primario">Agregar</button></div></form>`,
      { alCerrar: () => escaner.focus() });
    $('[name=importe]', m.el).focus();
    $('#f-varios', m.el).onsubmit = e => {
      e.preventDefault();
      const f = new FormData(e.target), imp = numero(f.get('importe'));
      if (!(imp > 0)) return aviso('Poné el importe');
      venta.items.push({ producto_id: null, nombre: f.get('nombre').trim() || 'Varios', cantidad: 1, importe: Math.round(imp * 100) / 100 });
      m.cerrar(); pintar();
    };
  }

  function pintar() {
    const t = $('#renglones');
    t.innerHTML = venta.items.length ? `<thead><tr><th>Producto</th><th class="num">Cant.</th><th class="num">Precio</th><th class="num">Importe</th><th></th></tr></thead><tbody>
      ${venta.items.map((i, k) => `<tr><td>${esc(i.nombre)}${i.producto_id && !cat.producto(i.producto_id) ? ' <span class="mal">(ya no está en el catálogo)</span>' : ''}</td>
        <td class="num">${i.producto_id ? `<input class="input cant" data-cant="${k}" value="${cant(i.cantidad)}" inputmode="decimal">` : '1'}</td>
        <td class="num">${i.producto_id ? plata(cat.producto(i.producto_id)?.precio ?? i.precio) + (i.por_peso ? '/kg' : '') : ''}</td>
        <td class="num"><b>${plata(importe(i))}</b></td><td><button class="link" data-quitar="${k}" title="Quitar">✕</button></td></tr>`).join('')}</tbody>`
      : '<tbody><tr><td class="muted vacio">Escaneá un producto o buscalo por nombre.</td></tr></tbody>';
    $('#total').textContent = plata(total());
    $$('[data-quitar]', t).forEach(b => b.onclick = () => { venta.items.splice(+b.dataset.quitar, 1); pintar(); escaner.focus(); });
    $$('[data-cant]', t).forEach(inp => {
      inp.onfocus = () => inp.select();
      inp.onchange = () => {
        const i = venta.items[+inp.dataset.cant], n = numero(inp.value);
        if (!(n > 0)) { venta.items.splice(+inp.dataset.cant, 1); return pintar(); }
        i.cantidad = i.por_peso ? Math.round(n * 1000) / 1000 : Math.round(n);
        pintar();
      };
      inp.onkeydown = e => { if (e.key === 'Enter') { e.preventDefault(); inp.blur(); escaner.focus(); } };
    });
  }

  function cobrar(caja) {
    if (!venta.items.length) return aviso('La venta no tiene productos');
    if (!caja.turno) return aviso('La caja está cerrada: abrí tu turno en Caja');
    const t = total(), formas = caja.formas_pago;
    let pagos = [{ forma: formas[0], monto: t }];
    const m = modal(`Cobrar ${plata(t)}`, `<form class="form ancho" id="f-cobro"><div id="pagos"></div>
      <button type="button" class="link" id="otra">＋ Pagar con otra forma también</button>
      <label id="paga-con-l">Paga con (efectivo)<input class="input grande" name="paga_con" inputmode="decimal" autocomplete="off"></label>
      <p class="vuelto" id="vuelto"></p>
      <div class="fila fin"><button type="button" class="btn" data-cerrar>Cancelar</button><button class="btn primario grande" id="confirmar">Confirmar</button></div></form>`,
      { alCerrar: () => $('#escaner')?.focus() });
    const pintarPagos = () => {
      $('#pagos', m.el).innerHTML = pagos.map((p, k) => `<div class="fila"><select class="input" data-forma="${k}">${formas.map(f => `<option ${f === p.forma ? 'selected' : ''}>${esc(f)}</option>`).join('')}</select>
        <input class="input" data-monto="${k}" value="${p.monto}" inputmode="decimal" ${pagos.length === 1 ? 'readonly' : ''}>
        ${pagos.length > 1 ? `<button type="button" class="link" data-sacar="${k}">✕</button>` : ''}</div>`).join('');
      $$('[data-forma]', m.el).forEach(s => s.onchange = () => { pagos[+s.dataset.forma].forma = s.value; vuelto(); });
      $$('[data-monto]', m.el).forEach(i => i.oninput = () => { pagos[+i.dataset.monto].monto = numero(i.value); vuelto(); });
      $$('[data-sacar]', m.el).forEach(b => b.onclick = () => { pagos.splice(+b.dataset.sacar, 1); if (pagos.length === 1) pagos[0].monto = t; pintarPagos(); });
      vuelto();
    };
    const efectivo = () => pagos.filter(p => p.forma === 'Efectivo').reduce((s, p) => s + (+p.monto || 0), 0);
    const vuelto = () => {
      $('#paga-con-l', m.el).hidden = !efectivo();
      const con = numero($('[name=paga_con]', m.el).value);
      $('#vuelto', m.el).textContent = con > 0 && efectivo() ? (con >= efectivo() ? `Vuelto: ${plata(con - efectivo())}` : 'Falta plata') : '';
    };
    $('#otra', m.el).onclick = () => {
      const resto = Math.max(0, Math.round((t - pagos.reduce((s, p) => s + (+p.monto || 0), 0)) * 100) / 100);
      pagos.push({ forma: formas.find(f => !pagos.some(p => p.forma === f)) || formas[0], monto: resto }); pintarPagos();
    };
    $('[name=paga_con]', m.el).oninput = vuelto;
    pintarPagos();
    $('#f-cobro', m.el).onsubmit = e => {
      e.preventDefault();
      const suma = Math.round(pagos.reduce((s, p) => s + (+p.monto || 0), 0) * 100) / 100;
      if (Math.abs(suma - t) > 0.005) return aviso(`Los pagos suman ${plata(suma)} y el total es ${plata(t)}`);
      const boton = $('#confirmar', m.el);
      boton.disabled = true;
      correr(async () => {
        const items = venta.items.map(i => i.producto_id ? { producto_id: i.producto_id, cantidad: i.cantidad } : { nombre: i.nombre, importe: i.importe });
        const con = numero($('[name=paga_con]', m.el).value);
        const r = await llamar('registrar_venta', { p_clave: venta.clave, p_items: items, p_pagos: pagos, p_paga_con: con > 0 ? con : null });
        m.cerrar();
        nueva(); pintar();
        // repetida: el intento anterior sí se había guardado (se cortó la respuesta); no se registró de nuevo
        if (r.repetida) aviso(`Esta venta ya se había registrado como #${r.numero} (${plata(r.total)}): no se cobró de nuevo`, 'info');
        else aviso(`Venta #${r.numero} registrada${con > 0 && efectivo() && con >= efectivo() ? ' · Vuelto ' + plata(con - efectivo()) : ''}`, 'ok');
        cat.actualizar().then(pintar).catch(() => {});
      }).finally(() => { boton.disabled = false; });
    };
  }
}
