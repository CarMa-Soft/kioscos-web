// Etapa 1: solo comprueba que la página publicada llega a la base y que las actualizaciones de la base se aplicaron
import { llamar } from './base.js';

const caja = document.getElementById('estado');
const mostrar = (texto, clase) => { caja.textContent = texto; caja.className = 'estado ' + clase; };

try {
  const e = await llamar('estado_app');
  mostrar(`Conectado a la base (versión ${e.base}). Hora del servidor: ${new Date(e.hora).toLocaleString('es-AR')}`, 'ok');
} catch (err) {
  mostrar(err.codigo === 'PGRST202' ? 'Conectado a Supabase, pero falta aplicar la primera actualización de la base.' : 'No se pudo conectar: ' + err.message, err.codigo === 'PGRST202' ? 'aviso' : 'mal');
}
