// Catálogo de productos en el navegador: así cada escaneo responde al instante, sin ir a internet.
// Se guarda en localStorage por negocio (sin costos: la PC la usan también los empleados) y se actualiza
// pidiendo a la base solo lo que cambió desde la última vez.
import { llamar } from './base.js';

const MARGEN_MS = 2 * 60 * 1000;   // se vuelve a pedir un poco hacia atrás, por cambios que terminaron de guardarse tarde
let clave = null, estado = null;    // estado: { ahora, productos: { id: producto }, categorias: [] }
const porCodigo = new Map(), porPlu = new Map();

const normalizar = s => String(s ?? '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '');
// Todos los códigos de un producto: el principal y los otros (por ejemplo, el del envase nuevo)
export const codigosDe = p => [p.codigo, ...(p.codigos || [])].filter(Boolean);
// Mapa código → producto, para las pantallas que trabajan con su propia lista de productos (con costos)
export const mapaPorCodigo = productos => new Map(productos.flatMap(p => codigosDe(p).map(c => [c.toLowerCase(), p])));

function indexar() {
  porCodigo.clear(); porPlu.clear();
  for (const p of Object.values(estado.productos)) {
    for (const c of codigosDe(p)) porCodigo.set(c.toLowerCase(), p);
    if (p.plu) porPlu.set(p.plu, p);
    p._busca = normalizar(p.nombre + ' ' + codigosDe(p).join(' '));
  }
}
function guardar() {
  try {
    const sinCosto = Object.fromEntries(Object.entries(estado.productos).map(([id, { costo, _busca, ...p }]) => [id, p]));
    localStorage.setItem(clave, JSON.stringify({ ...estado, productos: sinCosto }));
  } catch { /* sin espacio o sin almacenamiento: queda en memoria */ }
}

// Carga el catálogo del negocio: del navegador si lo hay (y lo actualiza), si no completo
export async function cargar(negocioId) {
  clave = 'kioscos.catalogo.' + negocioId;
  if (!estado || estado.negocio !== negocioId) {
    try { estado = JSON.parse(localStorage.getItem(clave) || 'null'); } catch { estado = null; }
    if (estado?.negocio !== negocioId) estado = null;
  }
  if (!estado) {
    const r = await llamar('catalogo');
    estado = { negocio: negocioId, ahora: r.ahora, categorias: r.categorias, productos: Object.fromEntries(r.productos.map(p => [p.id, p])) };
    indexar(); guardar();
    return;
  }
  indexar();
  await actualizar();
}

// Trae solo lo que cambió (incluye los dados de baja, que se sacan)
export async function actualizar() {
  if (!estado) return;
  const desde = new Date(new Date(estado.ahora).getTime() - MARGEN_MS).toISOString();
  const r = await llamar('catalogo', { p_desde: desde });
  for (const p of r.productos) {
    if (p.activo) estado.productos[p.id] = p; else delete estado.productos[p.id];
  }
  estado.categorias = r.categorias;
  estado.ahora = r.ahora;
  indexar(); guardar();
}

// Al cambiar de usuario se borra lo que haya en memoria con costos
export function olvidarCostos() { if (estado) for (const p of Object.values(estado.productos)) delete p.costo; }
export function olvidarTodo() { estado = null; porCodigo.clear(); porPlu.clear(); }

export const productos = () => estado ? Object.values(estado.productos) : [];
export const categorias = () => estado?.categorias || [];
export const producto = id => estado?.productos[id];
export const porCodigoDeBarras = codigo => porCodigo.get(String(codigo).trim().toLowerCase());
export const porCodigoDeBalanza = plu => porPlu.get(String(plu));
export const categoriaNombre = id => categorias().find(c => c.id === id)?.nombre || '';

// Búsqueda por nombre o código: todas las palabras tienen que estar
export function buscar(texto, max = 30) {
  const palabras = normalizar(texto).split(/\s+/).filter(Boolean);
  if (!palabras.length) return [];
  const r = [];
  for (const p of productos()) {
    if (palabras.every(w => p._busca.includes(w))) { r.push(p); if (r.length >= max) break; }
  }
  return r.sort((a, b) => a.nombre.localeCompare(b.nombre));
}
