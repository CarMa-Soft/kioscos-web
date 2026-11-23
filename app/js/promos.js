// Promociones por cantidad: la misma cuenta que hace la base (promo_descuentos y promos_venta en la migración
// 20261222120000_promociones.sql); la que vale es la de la base. Todo en centavos enteros, para redondear igual.
import { plata } from './ui.js';
import * as cat from './catalogo.js';

const centavos = n => Math.round((+n || 0) * 100);

// Lo que descuenta una promoción sobre los renglones (lineas: [{ k, producto_id, cantidad, precio }]) que no están en usadas.
// Devuelve [{ k, descuento }] de cada renglón que entró en un grupo (con 0 también: ya no entra en otra promoción).
function descuentos(pr, lineas, usadas) {
  const prods = new Set(pr.productos.map(Number));
  const ls = lineas.filter(l => prods.has(+l.producto_id) && !usadas.has(l.k));
  // las unidades, de la más cara a la más barata; a igual precio, en el orden de los renglones
  const u = [];
  for (const l of ls) for (let s = 0; s < l.cantidad; s++) u.push({ k: l.k, c: centavos(l.precio), precio: +l.precio });
  u.sort((a, b) => b.precio - a.precio || a.k - b.k);
  const N = +pr.cantidad, dc = {};
  const sumar = (k, c) => { dc[k] = (dc[k] || 0) + c; };
  if (pr.tipo === 'desde_pct') {
    if (u.length >= N) u.forEach(x => sumar(x.k, Math.round(x.c * pr.pct / 100)));
  } else {
    const grupos = Math.floor(u.length / N);
    for (let g = 0; g < grupos; g++) {
      const gr = u.slice(g * N, g * N + N), sc = gr.reduce((s, x) => s + x.c, 0);
      if (pr.tipo === 'lleva_paga') gr.forEach((x, i) => sumar(x.k, i + 1 > pr.paga ? x.c : 0));
      else if (pr.tipo === 'unidad_pct') gr.forEach((x, i) => sumar(x.k, i + 1 === N ? Math.round(x.c * pr.pct / 100) : 0));
      else {   // N por $X: lo que se descuenta, repartido en proporción al precio; la última se lleva lo que sobra del redondeo
        const dg = sc > 0 ? Math.max(sc - centavos(pr.precio), 0) : 0;
        let otros = 0;
        gr.forEach((x, i) => {
          if (i + 1 < N) { const sh = sc > 0 ? Math.round(x.c * dg / sc) : 0; otros += sh; sumar(x.k, sh); }
          else sumar(x.k, dg - otros);
        });
      }
    }
  }
  return Object.keys(dc).map(Number).sort((a, b) => a - b).map(k => ({ k, descuento: dc[k] / 100 }));
}

// Un combo (promo_combo en la base): de cada componente, sus unidades de la más cara a la más barata; tantos combos como
// alcance el componente que menos tiene. Dentro de cada combo, las unidades en el orden de los componentes; con precio fijo,
// lo descontado se reparte en proporción al precio (la última unidad se lleva el redondeo); con %, por unidad.
function descuentosCombo(pr, lineas, usadas) {
  const comps = pr.componentes.map(c => ({ q: +c.cantidad, prods: new Set(c.productos.map(Number)) }));
  const unidades = comps.map(c => {
    const u = [];
    for (const l of lineas) if (c.prods.has(+l.producto_id) && !usadas.has(l.k)) for (let s = 0; s < l.cantidad; s++) u.push({ k: l.k, c: centavos(l.precio), precio: +l.precio });
    return u.sort((a, b) => b.precio - a.precio || a.k - b.k);
  });
  const veces = Math.min(...comps.map((c, i) => Math.floor(unidades[i].length / c.q)));
  const dc = {};
  const sumar = (k, c) => { dc[k] = (dc[k] || 0) + c; };
  for (let g = 0; g < veces; g++) {
    const gr = comps.flatMap((c, i) => unidades[i].slice(g * c.q, g * c.q + c.q).sort((a, b) => b.c - a.c || a.k - b.k));
    const sc = gr.reduce((s, x) => s + x.c, 0);
    if (pr.pct != null) { gr.forEach(x => sumar(x.k, Math.round(x.c * pr.pct / 100))); continue; }
    const dg = sc > 0 ? Math.max(sc - centavos(pr.precio), 0) : 0;
    let otros = 0;
    gr.forEach((x, i) => {
      if (i + 1 < gr.length) { const sh = sc > 0 ? Math.round(x.c * dg / sc) : 0; otros += sh; sumar(x.k, sh); }
      else sumar(x.k, dg - otros);
    });
  }
  return Object.keys(dc).map(Number).sort((a, b) => a - b).map(k => ({ k, descuento: dc[k] / 100 }));
}

// Todas las promociones de una venta: primero la que más descuenta; sus renglones ya no entran en otra; y así.
// promos: las vigentes de hoy (promociones_vigentes); formas: las de los pagos (sin la seña); sin: ids quitados por el cajero.
// Devuelve [{ k, promocion_id, nombre, descuento }]
export function calcularPromos(promos, lineas, formas, sin = []) {
  const usadas = new Set(), aplicadas = new Set(), res = [];
  const valeCon = pr => !pr.formas?.length || formas.every(f => pr.formas.includes(f));
  for (;;) {
    let mejor = null, mejorT = 0, mejorD = null;
    for (const pr of [...promos].sort((a, b) => a.id - b.id)) {
      if (sin.includes(pr.id) || aplicadas.has(pr.id) || !valeCon(pr)) continue;
      const d = (pr.tipo === 'combo' ? descuentosCombo : descuentos)(pr, lineas, usadas), t = d.reduce((s, x) => s + centavos(x.descuento), 0);
      if (t > mejorT) { mejor = pr; mejorT = t; mejorD = d; }
    }
    if (!mejor) break;
    aplicadas.add(mejor.id);
    mejorD.forEach(x => { usadas.add(x.k); res.push({ ...x, promocion_id: mejor.id, nombre: mejor.nombre }); });
  }
  return res;
}

// La condición en palabras: "3x2", "2 por $1.500", "la 2ª con 50% menos", "llevando 6 o más, 10% menos"
export function textoPromo(p) {
  if (p.tipo === 'combo') return p.pct != null ? `combo con ${p.pct}% menos` : `combo a ${plata(p.precio)}`;
  if (p.tipo === 'lleva_paga') return `${p.cantidad}x${p.paga}`;
  if (p.tipo === 'precio') return `${p.cantidad} por ${plata(p.precio)}`;
  if (p.tipo === 'unidad_pct') return `la ${p.cantidad}ª ${+p.pct === 100 ? 'gratis' : `con ${p.pct}% menos`}`;
  return +p.cantidad > 1 ? `llevando ${p.cantidad} o más, ${p.pct}% menos` : `${p.pct}% menos`;
}

const DIAS = ['', 'lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábados', 'domingos'];
export const DIAS_CORTOS = ['', 'Lu', 'Ma', 'Mi', 'Ju', 'Vi', 'Sá', 'Do'];
export const textoDias = dias => !dias?.length || dias.length === 7 ? '' : dias.map(d => DIAS[d]).join(', ').replace(/, ([^,]+)$/, ' y $1');

// "3x2 Yerba (3x2)" no: si el nombre ya dice la condición, va solo el nombre
const conCondicion = p => p.nombre.toLowerCase().includes(textoPromo(p).toLowerCase()) ? p.nombre : `${p.nombre} (${textoPromo(p)})`;

// Un componente de un combo en palabras: "Coca 2,25", o "Coca 2,25 o Sprite 2,25" (con más de tres: "uno de 5 productos")
export function textoComponente(c) {
  const ns = c.productos.map(id => cat.producto(id)?.nombre).filter(Boolean);
  return ns.length > 3 ? `uno de ${ns.length} productos (${ns.slice(0, 2).join(', ')}…)` : ns.join(' o ') || 'producto';
}
// El combo en palabras: "Fernet + Coca 2,25 o Sprite 2,25", con la cantidad si es más de 1
export const textoCombo = p => p.componentes.map(c => `${+c.cantidad > 1 ? c.cantidad + ' ' : ''}${textoComponente(c)}`).join(' + ');

// Sugerencias para Vender: promociones con productos en la venta a las que les falta poco para completarse (o el grupo
// siguiente), o que no valen con la forma de pago elegida. lineas: las que entran en promociones; aplicadas: de calcularPromos.
// (Solo si faltan hasta 3 unidades: más que eso no es una sugerencia.) Devuelve [{ promo, texto, quitada? }]
export function sugerencias(promos, lineas, formas, aplicadas, sin = []) {
  const res = [];
  for (const p of promos) {
    const prods = new Set(p.productos.map(Number));
    const u = lineas.filter(l => prods.has(+l.producto_id)).reduce((s, l) => s + +l.cantidad, 0);
    if (!u) continue;
    const enVenta = aplicadas.some(a => a.promocion_id === p.id && a.descuento > 0);
    if (sin.includes(p.id)) { res.push({ promo: p, quitada: true, texto: `${p.nombre}: la quitaste de esta venta` }); continue; }
    if (p.formas?.length && !formas.every(f => p.formas.includes(f))) {
      if (u >= +p.cantidad) res.push({ promo: p, texto: `${conCondicion(p)} vale solo con ${p.formas.join(' o ')}` });
      continue;
    }
    if (p.tipo === 'combo') {   // lo que falta para el próximo combo, si ya hay algo de él y faltan hasta 3 unidades
      const uc = p.componentes.map(c => lineas.filter(l => c.productos.map(Number).includes(+l.producto_id)).reduce((s, l) => s + +l.cantidad, 0));
      const veces = Math.min(...p.componentes.map((c, i) => Math.floor(uc[i] / c.cantidad)));
      const falta = p.componentes.map((c, i) => Math.max(0, (veces + 1) * c.cantidad - uc[i]));
      const total = falta.reduce((s, x) => s + x, 0);
      if (p.componentes.some((c, i) => uc[i] > veces * c.cantidad) && total <= 3) {
        const que = p.componentes.map((c, i) => falta[i] ? `${falta[i]} ${textoComponente(c)}` : '').filter(Boolean).join(' y ');
        res.push({ promo: p, texto: `Con ${que} más: ${enVenta ? 'otra vez ' : ''}${conCondicion(p)}` });
      }
      continue;
    }
    const N = +p.cantidad;
    if (p.tipo === 'desde_pct') {
      if (u < N && N - u <= 3) res.push({ promo: p, texto: `Llevando ${N - u} más: ${conCondicion(p)}` });
    } else if (u % N && N - u % N <= 3) {
      res.push({ promo: p, texto: `Llevando ${N - u % N} más: ${enVenta ? 'otra vez ' : ''}${conCondicion(p)}` });
    }
  }
  return res;
}
