// Vender: escanear o buscar (con resultados mientras se escribe), armar la venta y cobrar desde el panel de la derecha.
// La cuenta (descuentos, recargos, dos medios de pago) es la misma que hace la base; la que vale es la de la base.
import { llamar } from './base.js';
import * as cat from './catalogo.js';
import { $, $$, esc, plata, cant, numero, aviso, correr, modal, confirmar, pedirAutorizacion } from './ui.js';
import { formCliente, textoSaldo } from './clientes.js';

const r2 = n => Math.round((+n || 0) * 100) / 100;
const r3 = n => Math.round((+n || 0) * 1000) / 1000;

// La venta en curso sobrevive a cambiar de sección. 'clave' identifica el intento de cobro: si se corta internet
// y se vuelve a cobrar, la base reconoce la misma venta y no la registra dos veces.
const vacia = () => ({ items: [], clave: crypto.randomUUID(), cliente: null, forma: 'Efectivo', dos: null, desc: '', descPct: false, pagaCon: '' });
let venta = vacia();

export async function pantallaVender(vista, ctx) {
  const caja = await llamar('estado_caja');
  const pct = f => f === 'Efectivo' ? 0 : +(caja.recargos?.[f] || 0);
  const formas = () => venta.cliente ? [...caja.formas_pago, 'Fiado'] : caja.formas_pago;
  if (!formas().includes(venta.forma)) venta.forma = 'Efectivo';

  vista.innerHTML = `
    ${caja.turno ? '' : '<p class="aviso mal">La caja está cerrada: <a href="#/caja">abrí tu turno en Caja</a> para poder cobrar.</p>'}
    <div class="vender">
      <div class="vender-izq">
        <div class="buscador">
          <input class="input grande" id="escaner" placeholder="Escaneá o escribí para buscar" autocomplete="off" autofocus>
          <div id="resultados" class="resultados flotan" hidden></div>
        </div>
        <p class="muted chico ayuda">Enter agrega · ↑↓ para elegir · <span class="mono">3*</span> antes del código carga 3 · clic en el precio para cambiarlo</p>
        <div class="tabla-caja"><table class="tabla" id="renglones"></table></div>
        <div class="fila"><button class="btn" id="varios">＋ Varios</button><button class="btn" id="vaciar">Vaciar</button></div>
      </div>
      <div class="vender-der" id="panel"></div>
    </div>`;
  const escaner = $('#escaner'), res = $('#resultados');
  let sugeridos = [], marcado = 0;

  // ---------- Buscar y agregar ----------
  // Etiqueta de balanza (EAN-13): prefijo + PLU (hasta el dígito 7) + 5 dígitos de peso (gramos) o importe + verificador
  function leerBalanza(t) {
    const b = caja.balanza;
    if (!b?.activa || !/^\d{13}$/.test(t) || !t.startsWith(b.prefijo)) return null;
    const plu = String(parseInt(t.slice(b.prefijo.length, 7), 10)), valor = +t.slice(7, 12);
    const p = cat.porCodigoDeBalanza(plu);
    if (!p || !p.por_peso) return { error: `La etiqueta es de la balanza pero no hay ningún producto por kilo con código de balanza ${plu}` };
    if (b.tipo === 'peso') return { p, cantidad: r3(valor / 1000) };
    const imp = b.tipo === 'importe_centavos' ? valor / 100 : valor;
    if (!(p.precio > 0)) return { error: `${p.nombre} no tiene precio cargado` };
    return { p, cantidad: r3(imp / p.precio), importe: r2(imp) };
  }
  const separarCantidad = texto => { const m = texto.match(/^(\d+(?:[.,]\d+)?)\s*\*\s*(.+)$/); return m ? [numero(m[1]), m[2].trim()] : [1, texto]; };
  escaner.oninput = () => {
    const [, texto] = separarCantidad(escaner.value.trim());
    if (texto.length < 2 || /^\d{6,}$/.test(texto)) { res.hidden = true; sugeridos = []; return; }   // un código se agrega con Enter
    sugeridos = cat.buscar(texto, 12); marcado = 0;
    pintarSugeridos(texto);
  };
  escaner.onkeydown = e => {
    if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
      if (res.hidden || !sugeridos.length) return;
      e.preventDefault();
      marcado = (marcado + (e.key === 'ArrowDown' ? 1 : -1) + sugeridos.length) % sugeridos.length;
      return pintarSugeridos();
    }
    if (e.key === 'Escape') { escaner.value = ''; res.hidden = true; return; }
    if (e.key !== 'Enter') return;
    e.preventDefault();
    const [n, texto] = separarCantidad(escaner.value.trim());
    if (!texto) return;
    const bal = leerBalanza(texto);
    if (bal?.error) { escaner.select(); return aviso(bal.error); }
    if (bal) {
      escaner.value = ''; res.hidden = true;
      venta.items.push({ producto_id: bal.p.id, nombre: bal.p.nombre, cantidad: bal.cantidad, precio: null, por_peso: true, etiqueta: bal.importe ?? null });
      pintar(); return escaner.focus();
    }
    const p = cat.porCodigoDeBarras(texto) || (!res.hidden && sugeridos[marcado]) || (cat.buscar(texto, 2).length === 1 ? cat.buscar(texto, 1)[0] : null);
    if (p) return agregar(p, n > 0 ? n : 1);
    aviso(/^\d{6,}$/.test(texto) ? `No hay ningún producto con el código ${texto}` : `No hay productos con "${texto}"`);
  };
  function pintarSugeridos(texto) {
    res.hidden = false;
    res.innerHTML = sugeridos.length ? sugeridos.map((p, k) => `<button class="resultado ${k === marcado ? 'marcado' : ''}" data-k="${k}" tabindex="-1"><span>${esc(p.nombre)}</span>
        <span class="muted">${p.codigo ? esc(p.codigo) + ' · ' : ''}stock ${cant(p.stock)}</span><b>${plata(p.precio)}${p.por_peso ? '/kg' : ''}</b></button>`).join('')
      : `<p class="muted sin">No hay productos con "${esc(texto ?? escaner.value)}".</p>`;
    $$('[data-k]', res).forEach(b => b.onmousedown = e => { e.preventDefault(); agregar(sugeridos[+b.dataset.k], separarCantidad(escaner.value.trim())[0] || 1); });
  }
  function agregar(p, n = 1) {
    escaner.value = ''; res.hidden = true; sugeridos = [];
    if (p.por_peso) return pedirPeso(p);
    if (!p.por_peso) n = Math.max(1, Math.round(n));
    const ya = venta.items.find(i => i.producto_id === p.id && i.precio == null);
    if (ya) ya.cantidad += n; else venta.items.push({ producto_id: p.id, nombre: p.nombre, cantidad: n, precio: null });
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
      venta.items.push({ producto_id: p.id, nombre: p.nombre, cantidad: r3(kg), precio: null, por_peso: true });
      m.cerrar(); pintar();
    };
  }
  function varios() {
    const m = modal('Varios', `<form class="form" id="f-varios"><label>Descripción<input class="input" name="nombre" placeholder="Varios" maxlength="120"></label>
      <label>Importe<input class="input grande" name="importe" inputmode="decimal" autocomplete="off" required></label>
      <div class="fila fin"><button type="button" class="btn" data-cerrar>Cancelar</button><button class="btn primario">Agregar</button></div></form>`,
      { alCerrar: () => escaner.focus() });
    $('[name=importe]', m.el).focus();
    $('#f-varios', m.el).onsubmit = e => {
      e.preventDefault();
      const f = new FormData(e.target), imp = numero(f.get('importe'));
      if (!(imp > 0)) return aviso('Poné el importe');
      venta.items.push({ producto_id: null, nombre: f.get('nombre').trim() || 'Varios', cantidad: 1, importe: r2(imp) });
      m.cerrar(); pintar();
    };
  }
  // Precio de un renglón solo para esta venta: un precio, o "10%" de descuento sobre el de lista
  function cambiarPrecio(i) {
    const lista = cat.producto(i.producto_id)?.precio ?? 0;
    const m = modal('Precio para esta venta', `<form class="form" id="f-precio"><p class="muted">${esc(i.nombre)} — no cambia el precio del producto (lista ${plata(lista)}).</p>
      <label>Precio${i.por_peso ? ' por kilo' : ''}, o descuento en %<input class="input grande" name="precio" value="${i.precio ?? lista}" autocomplete="off" autofocus></label>
      <p class="muted chico">Ej: <span class="mono">10%</span> = ${plata(lista * 0.9)}</p>
      <div class="fila fin"><button type="button" class="btn izq" id="lista">Volver al de lista</button><button type="button" class="btn" data-cerrar>Cancelar</button><button class="btn primario">Aplicar</button></div></form>`,
      { alCerrar: () => escaner.focus() });
    setTimeout(() => $('[name=precio]', m.el).select(), 40);
    $('#lista', m.el).onclick = () => { i.precio = null; m.cerrar(); pintar(); };
    $('#f-precio', m.el).onsubmit = e => {
      e.preventDefault();
      const txt = new FormData(e.target).get('precio').trim();
      let v;
      if (/%$/.test(txt)) {
        const p = numero(txt.slice(0, -1));
        if (!(p > 0 && p <= 100)) return aviso('El porcentaje tiene que ser entre 1 y 100');
        v = lista * (1 - p / 100);
      } else v = numero(txt);
      if (!(v >= 0)) return aviso('Precio inválido');
      i.precio = r2(v) === r2(lista) ? null : r2(v);
      i.etiqueta = null;   // con otro precio ya no vale el importe de la etiqueta
      m.cerrar(); pintar();
    };
  }

  // ---------- La cuenta ----------
  const precioDe = i => i.precio ?? cat.producto(i.producto_id)?.precio ?? 0;
  // con etiqueta de balanza que trae el importe, vale ese importe (la base controla que coincida con kilos × precio)
  const importe = i => i.producto_id ? (i.etiqueta != null ? i.etiqueta : r2(i.cantidad * precioDe(i))) : i.importe;
  const lineaPago = (forma, base) => { const p = pct(forma), rec = p ? Math.round(base * p / 100) : 0; return { forma, base: r2(base), recargo: rec, monto: r2(base + rec) }; };
  function totales() {
    const subtotal = r2(venta.items.reduce((s, i) => s + importe(i), 0));
    const dv = Math.max(0, numero(venta.desc) || 0);
    const descuento = venta.descPct ? r2(subtotal * Math.min(dv, 100) / 100) : Math.min(r2(dv), subtotal);
    const base = r2(subtotal - descuento);
    let pagos;
    if (!venta.dos) pagos = [lineaPago(venta.forma, base)];
    else {
      // lo que se escribe en el primero es lo que el cliente paga con ese medio (con su recargo); el resto va al segundo
      const m1 = Math.max(0, numero(venta.dos.monto1) || 0);
      const b1 = Math.min(base, r2(m1 / (1 + pct(venta.dos.forma1) / 100)));
      pagos = [lineaPago(venta.dos.forma1, b1), lineaPago(venta.dos.forma2, r2(base - b1))];
    }
    const recargo = r2(pagos.reduce((s, p) => s + p.recargo, 0));
    return { subtotal, descuento, base, pagos, recargo, total: r2(base + recargo) };
  }

  // ---------- Pintar ----------
  function pintar() {
    const t = $('#renglones');
    t.innerHTML = venta.items.length ? `<thead><tr><th>Producto</th><th class="num">Cant.</th><th class="num">Precio</th><th class="num">Importe</th><th></th></tr></thead><tbody>
      ${venta.items.map((i, k) => { const p = i.producto_id && cat.producto(i.producto_id); return `<tr><td>${esc(i.nombre)}${i.producto_id && !p ? ' <span class="mal">(ya no está en el catálogo)</span>' : ''}</td>
        <td class="num">${i.producto_id ? `<input class="input cant" data-cant="${k}" value="${cant(i.cantidad)}" inputmode="decimal">` : '1'}</td>
        <td class="num">${i.producto_id ? `<button class="link" data-precio="${k}" title="Cambiar el precio para esta venta">${plata(precioDe(i))}${i.por_peso ? '/kg' : ''}</button>${i.precio != null && p ? `<div class="muted chico"><s>${plata(p.precio)}</s></div>` : ''}` : ''}</td>
        <td class="num"><b>${plata(importe(i))}</b></td><td><button class="link" data-quitar="${k}" title="Quitar">✕</button></td></tr>`; }).join('')}</tbody>`
      : '<tbody><tr><td class="muted vacio">Escaneá un producto o buscalo por nombre.</td></tr></tbody>';
    $$('[data-quitar]', t).forEach(b => b.onclick = () => { venta.items.splice(+b.dataset.quitar, 1); pintar(); escaner.focus(); });
    $$('[data-precio]', t).forEach(b => b.onclick = () => cambiarPrecio(venta.items[+b.dataset.precio]));
    $$('[data-cant]', t).forEach(inp => {
      inp.onfocus = () => inp.select();
      inp.onchange = () => {
        const i = venta.items[+inp.dataset.cant], n = numero(inp.value);
        if (!(n > 0)) { venta.items.splice(+inp.dataset.cant, 1); return pintar(); }
        i.cantidad = i.por_peso ? r3(n) : Math.round(n);
        i.etiqueta = null;   // cambiaron los kilos: el importe sale de kilos × precio
        pintar();
      };
      inp.onkeydown = e => { if (e.key === 'Enter') { e.preventDefault(); inp.blur(); escaner.focus(); } };
    });
    pintarPanel();
  }

  function pintarPanel() {
    const tt = totales(), c = venta.cliente, fs = formas(), d = venta.dos;
    const efectivo = tt.pagos.filter(p => p.forma === 'Efectivo').reduce((s, p) => s + p.monto, 0);
    const opciones = sel => fs.map(f => `<option value="${esc(f)}" ${f === sel ? 'selected' : ''}>${esc(f)}${pct(f) ? ` (+${pct(f)}%)` : ''}</option>`).join('');
    const enfocado = document.activeElement?.id;
    $('#panel').innerHTML = `
      <div class="cliente-venta">${c ? `<div><span class="muted">Cliente</span> <b>${esc(c.nombre)}</b><div class="muted chico">${textoSaldo(c.saldo)}</div></div>
        <button class="link" id="quitar-cliente">Quitar</button>` : '<button class="btn" id="elegir-cliente">👤 Elegir cliente</button>'}</div>
      <div class="cuenta">
        ${tt.descuento || tt.recargo ? `<div class="renglon-cuenta"><span>Subtotal</span><span>${plata(tt.subtotal)}</span></div>` : ''}
        ${tt.descuento ? `<div class="renglon-cuenta ok"><span>Descuento</span><span>−${plata(tt.descuento)}</span></div>` : ''}
        ${tt.pagos.filter(p => p.recargo).map(p => `<div class="renglon-cuenta"><span>Recargo ${esc(p.forma)} ${pct(p.forma)}%</span><span>+${plata(p.recargo)}</span></div>`).join('')}
        <div class="total-etq">Total</div><div class="total">${plata(tt.total)}</div>
      </div>
      <div class="bloque"><div class="fila entre"><b>Forma de pago</b>${d ? '<button class="link" id="uno">Un solo medio</button>' : '<button class="link" id="dos">Dos medios</button>'}</div>
        ${d ? `<div class="dos-medios">
            <label>1. <select class="input" id="f1">${opciones(d.forma1)}</select><input class="input" id="m1" inputmode="decimal" placeholder="¿Cuánto paga?" value="${esc(d.monto1)}"></label>
            <label>2. <select class="input" id="f2">${opciones(d.forma2)}</select><span class="resto">${plata(tt.pagos[1].monto)}</span></label>
            <p class="muted chico">En el primero poné cuánto paga con ese medio; el resto va solo al segundo.</p></div>`
          : `<div class="formas">${fs.map(f => `<button class="forma ${f === venta.forma ? 'elegida' : ''}" data-forma="${esc(f)}">${esc(f)}${pct(f) ? `<small>+${pct(f)}%</small>` : ''}</button>`).join('')}</div>`}
      </div>
      <div class="bloque"><label class="fila entre"><b>Descuento</b><span class="segmentos"><button class="${venta.descPct ? '' : 'elegido'}" data-modo="$">$</button><button class="${venta.descPct ? 'elegido' : ''}" data-modo="%">%</button></span></label>
        <input class="input" id="desc" inputmode="decimal" placeholder="0" value="${esc(venta.desc)}"></div>
      ${efectivo > 0 ? `<div class="bloque"><b>Paga con</b> <span class="muted chico">(efectivo: ${plata(efectivo)})</span>
        <input class="input grande" id="paga-con" inputmode="decimal" placeholder="Monto que entrega" value="${esc(venta.pagaCon)}">
        <div class="billetes">${[1000, 2000, 10000, 20000].filter(b => b >= efectivo / 20).slice(0, 4).map(b => `<button class="btn chico" data-billete="${b}">${plata(b).replace(/,00$/, '')}</button>`).join('')}</div>
        <p class="vuelto">${(() => { const pc = numero(venta.pagaCon); return pc > 0 ? (pc >= efectivo ? `Vuelto: ${plata(pc - efectivo)}` : `<span class="mal">Faltan ${plata(efectivo - pc)}</span>`) : ''; })()}</p></div>` : ''}
      <button class="btn primario grande" id="cobrar" ${caja.turno ? '' : 'disabled'}>Cobrar ${plata(tt.total)} <span class="tecla">F2</span></button>
      <p class="muted chico">Turno: ${caja.turno ? esc(caja.turno.usuario) : 'cerrado'}</p>`;
    // eventos del panel
    if (c) $('#quitar-cliente').onclick = () => { venta.cliente = null; if (!formas().includes(venta.forma)) venta.forma = 'Efectivo'; if (d && (d.forma1 === 'Fiado' || d.forma2 === 'Fiado')) venta.dos = null; pintar(); escaner.focus(); };
    else $('#elegir-cliente').onclick = () => elegirCliente();
    $$('[data-forma]').forEach(b => b.onclick = () => { venta.forma = b.dataset.forma; pintarPanel(); escaner.focus(); });
    if ($('#dos')) $('#dos').onclick = () => { venta.dos = { forma1: 'Efectivo', monto1: '', forma2: fs.find(f => f !== 'Efectivo') || 'Efectivo' }; pintarPanel(); $('#m1').focus(); };
    if ($('#uno')) $('#uno').onclick = () => { venta.dos = null; pintarPanel(); };
    if (d) {
      $('#f1').onchange = e => { d.forma1 = e.target.value; pintarPanel(); };
      $('#f2').onchange = e => { d.forma2 = e.target.value; pintarPanel(); };
      $('#m1').oninput = e => { d.monto1 = e.target.value; refrescar('m1'); };
    }
    $('#desc').oninput = e => { venta.desc = e.target.value; refrescar('desc'); };
    $$('[data-modo]').forEach(b => b.onclick = () => { venta.descPct = b.dataset.modo === '%'; pintarPanel(); });
    if ($('#paga-con')) $('#paga-con').oninput = e => { venta.pagaCon = e.target.value; refrescar('paga-con'); };
    $$('[data-billete]').forEach(b => b.onclick = () => { venta.pagaCon = b.dataset.billete; pintarPanel(); });
    $('#cobrar').onclick = () => cobrar();
    if (enfocado && $('#' + enfocado) && $('#panel').contains($('#' + enfocado))) { const el = $('#' + enfocado); el.focus(); el.setSelectionRange?.(el.value.length, el.value.length); }
  }
  // Al escribir en un campo del panel se redibuja el panel conservando el cursor en ese campo
  const refrescar = id => { pintarPanel(); const el = $('#' + id); if (el) { el.focus(); el.setSelectionRange?.(el.value.length, el.value.length); } };

  // ---------- Cliente ----------
  function elegirCliente() {
    correr(async () => {
      const lista = (await llamar('clientes')).filter(c => c.activo);
      const m = modal('Elegir cliente', `<input class="input" id="buscar-cli" placeholder="Buscar por nombre o teléfono" autocomplete="off" autofocus>
        <div class="resultados" id="lista-cli"></div>
        <div class="fila fin"><button class="btn izq" id="nuevo-cli">＋ Nuevo cliente</button><button class="btn" data-cerrar>Cancelar</button></div>`,
        { alCerrar: () => $('#escaner')?.focus() });
      const elegir = c => { venta.cliente = c; m.cerrar(); pintar(); };
      const pintarLista = () => {
        const f = $('#buscar-cli', m.el).value.trim().toLowerCase();
        const ver = lista.filter(c => !f || c.nombre.toLowerCase().includes(f) || (c.telefono || '').includes(f)).slice(0, 50);
        $('#lista-cli', m.el).innerHTML = ver.map(c => `<button class="resultado" data-id="${c.id}"><span>${esc(c.nombre)}</span><span class="muted">${esc(c.telefono || '')}</span>
          <b class="${+c.saldo > 0.004 ? 'mal' : ''}">${textoSaldo(c.saldo)}</b></button>`).join('') || '<p class="muted sin">No hay clientes con ese nombre.</p>';
        $$('[data-id]', m.el).forEach(b => b.onclick = () => elegir(lista.find(c => c.id === +b.dataset.id)));
      };
      $('#buscar-cli', m.el).oninput = pintarLista;
      $('#buscar-cli', m.el).onkeydown = e => { if (e.key === 'Enter') { e.preventDefault(); $('[data-id]', m.el)?.click(); } };
      $('#nuevo-cli', m.el).onclick = () => {
        const escrito = $('#buscar-cli', m.el).value.trim();
        formCliente(null, false, c => elegir(c));
        $('#f-cli [name=nombre]').value = escrito;
      };
      pintarLista();
    });
  }

  // ---------- Cobrar ----------
  let cobrando = false;
  async function cobrar() {
    if (cobrando) return;
    if (!venta.items.length) return aviso('La venta no tiene productos');
    if (!caja.turno) return aviso('La caja está cerrada: abrí tu turno en Caja');
    const tt = totales();
    if (venta.dos) {
      if (!(numero(venta.dos.monto1) > 0)) { $('#m1')?.focus(); return aviso('Poné cuánto paga con el primer medio'); }
      if (venta.dos.forma1 === venta.dos.forma2) return aviso('Elegiste dos veces el mismo medio de pago');
    }
    if (tt.pagos.some(p => p.forma === 'Fiado') && !venta.cliente) return aviso('Para fiar elegí el cliente');
    const efectivo = tt.pagos.filter(p => p.forma === 'Efectivo').reduce((s, p) => s + p.monto, 0), pc = numero(venta.pagaCon);
    if (pc > 0 && pc < efectivo) { $('#paga-con')?.focus(); return aviso(`Con ${plata(pc)} no alcanza: faltan ${plata(efectivo - pc)}`); }
    const args = {
      p_clave: venta.clave,
      p_items: venta.items.map(i => i.producto_id ? { producto_id: i.producto_id, cantidad: i.cantidad, ...(i.precio != null ? { precio: i.precio } : {}),
        ...(i.etiqueta != null ? { importe: i.etiqueta } : {}) } : { nombre: i.nombre, importe: i.importe }),
      p_pagos: tt.pagos.filter(p => p.base > 0).map(p => ({ forma: p.forma, base: p.base })),
      p_paga_con: pc > 0 ? pc : null, p_cliente_id: venta.cliente?.id ?? null, p_forzar_limite: false,
      p_descuento: tt.descuento, p_autorizacion: null,
    };
    cobrando = true;
    try {
      await correr(async () => {
        let r;
        for (;;) {
          try { r = await llamar('registrar_venta', args); break; } catch (err) {
            if (err.codigo === 'limite') {   // pasaría el límite de fiado: no se registró nada
              if (!await confirmar('Límite de fiado', err.message + '. ¿Fiar igual?', 'Fiar igual')) return;
              args.p_forzar_limite = true;
            } else if (err.codigo === 'autorizacion') {   // descuento por encima del tope del empleado
              const token = await pedirAutorizacion(ctx.usuarios, err.message);
              if (!token) return;
              args.p_autorizacion = token;
            } else throw err;
          }
        }
        venta = vacia(); pintar(); escaner.focus();
        if (r.repetida) aviso(`Esta venta ya se había registrado como #${r.numero} (${plata(r.total)}): no se cobró de nuevo`, 'info');
        else aviso(`Venta #${r.numero} registrada${pc > 0 && efectivo ? ' · Vuelto ' + plata(pc - efectivo) : ''}`, 'ok');
        cat.actualizar().then(pintar).catch(() => {});
      });
    } finally { cobrando = false; }
  }

  $('#varios').onclick = () => varios();
  $('#vaciar').onclick = async () => { if (!venta.items.length || await confirmar('Vaciar', '¿Sacar todos los productos de la venta?', 'Vaciar')) { venta = vacia(); pintar(); escaner.focus(); } };
  escaner.onblur = () => setTimeout(() => { if (document.activeElement !== escaner) res.hidden = true; }, 150);
  ctx.alTeclear(e => {
    if (e.key === 'F2') { e.preventDefault(); cobrar(); }
    if (e.key === 'F1') { e.preventDefault(); venta.forma = 'Efectivo'; venta.dos = null; pintarPanel(); }
  });
  pintar();
}
