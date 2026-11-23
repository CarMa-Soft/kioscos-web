// Promociones por cantidad: la misma cuenta que hace la base (promo_descuentos y promos_venta en la migración
// 20261222120000_promociones.sql); la que vale es la de la base. Todo en centavos enteros, para redondear igual.
import { plata } from './ui.js';

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
      const d = descuentos(pr, lineas, usadas), t = d.reduce((s, x) => s + centavos(x.descuento), 0);
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
    const N = +p.cantidad;
    if (p.tipo === 'desde_pct') {
      if (u < N && N - u <= 3) res.push({ promo: p, texto: `Llevando ${N - u} más: ${conCondicion(p)}` });
    } else if (u % N && N - u % N <= 3) {
      res.push({ promo: p, texto: `Llevando ${N - u % N} más: ${enVenta ? 'otra vez ' : ''}${conCondicion(p)}` });
    }
  }
  return res;
}
