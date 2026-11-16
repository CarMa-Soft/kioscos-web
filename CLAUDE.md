# Kioscos y Almacenes (versión web)

Punto de venta web para kioscos y almacenes, para varios negocios con la misma app. Reemplaza a la app local "Kiosco"
(repo privado `CarMa-Soft/Kiosco`), que sigue siendo la referencia de las reglas del negocio: su `CLAUDE.md` describe
cada función y sus decisiones. Se migra por etapas (el plan está en los issues de ese repo).

**Este repo es público.** Todo lo que se sube (código, historial, issues, PR y comentarios) lo puede ver cualquiera.

## Estructura
| Carpeta | Qué es |
|---|---|
| `app/` | La app: HTML, CSS y módulos JS, sin compilar. Se publica tal cual en GitHub Pages. |
| `app/js/config.js` | Dirección del proyecto de Supabase y su clave pública (publishable). |
| `app/js/base.js` | Conexión con Supabase: `sb` (cliente), `llamar(funcion, args)` y la traducción de errores. Toda la app habla con la base desde acá. |
| `supabase/migrations/` | Cambios de la base, en orden. Se aplican solos al unirse a `main`. |
| `supabase/config.toml` | Configuración de la CLI de Supabase (solo para uso local). |
| `.github/workflows/` | `pages.yml` publica `app/`; `base.yml` aplica las migraciones. |
| `tools/servidor.js` | Servidor local: `node tools/servidor.js` → http://localhost:5180 |

## Seguridad (no negociable)
- **Claves:** en el código solo pueden ir la dirección del proyecto y la clave *publishable*. La clave secreta,
  la `service_role`, la contraseña de la base, la cadena de conexión y la clave de IA van solo en los secretos de
  GitHub Actions o de Supabase. Nunca en archivos, commits, issues ni en el chat. GitHub frena los push con claves.
- **Datos:** nunca subir datos reales (de un negocio o de la app local), ni exportaciones de la base. Las pruebas usan datos inventados.
- **La seguridad está en la base, no en las pantallas:** cualquiera puede leer el JS. Cada tabla tiene RLS
  (Supabase la activa sola en las tablas nuevas) y sus reglas. Las tablas nuevas **no** se exponen solas a la API:
  hay que dar los permisos (`grant`) a propósito, solo lo necesario.
- **Varios negocios:** cada tabla con datos de un negocio lleva `negocio_id` y reglas que solo dejan ver y tocar lo
  del propio negocio. Cada tabla nueva suma su prueba automática de que un negocio no ve lo de otro.
- **Funciones:** las operaciones que tocan varias tablas son funciones SQL atómicas que controlan el negocio y el rol
  antes de tocar algo. Siempre con `set search_path = ''` y nombres completos (`public.tabla`). Postgres deja
  ejecutar cualquier función a todos: cada función nueva lleva `revoke all ... from public` y `grant execute` solo a
  quien la necesita. `security definer` solo si hace falta, y entonces con controles explícitos.
- **Lo que no tiene que ver un empleado** (costos, márgenes, reportes) sale solo por funciones que controlan el rol.
- **Conversaciones sensibles** (precios, clientes, problemas de seguridad sin corregir) van en los issues del repo
  privado `CarMa-Soft/Kiosco`, no acá. Una falla de seguridad se avisa por "Report a vulnerability", no en un issue.
- **Scripts externos:** solo de `cdn.jsdelivr.net` y con la versión exacta (ej. `@supabase/supabase-js@2.118.0`).
  `app/index.html` tiene una Content-Security-Policy: si se agrega otro origen, hay que sumarlo ahí a propósito.

## Base de datos
- **Por ahora hay un solo proyecto** ("Kioscos y Almacenes", plan Free, región São Paulo): es desarrollo y producción
  a la vez. Una migración unida a `main` se aplica ahí enseguida. Antes del primer negocio real: plan Pro y un proyecto
  aparte para pruebas.
- **Migraciones:** un archivo nuevo por cambio en `supabase/migrations/`, con nombre `AAAAMMDDHHMMSS_descripcion.sql`
  (`supabase migration new descripcion` lo crea). **Nunca editar una migración ya unida a `main`**: se agrega otra. Si
  dos ramas agregan migraciones, el segundo en unir revisa que la suya tenga una fecha posterior a las de `main`.
- `base.yml` las aplica al unir a `main` (primero muestra cuáles con `--dry-run`). Usa el secreto `SUPABASE_DB_URL`.
- `estado_app()` devuelve la versión de la base (`base`): subirla cuando la app necesite saber que hay un cambio.

## Forma de trabajo
- **Nunca commitear ni hacer push directo a `main`** (GitHub lo impide). Todo va en una rama y entra por pull request
  aprobado por el otro; el dueño de la organización puede unir un PR propio sin aprobación, pero siempre por PR.
- PR en español. Si resuelve un issue, la primera línea es `Closes #N` (o `Closes CarMa-Soft/Kiosco#N` si el issue es del repo privado).
- Las ramas se borran solas al unir el PR.
- Commits con el email privado de GitHub (`…@users.noreply.github.com`), no el personal: `git config user.email` en este repo.
- GitHub CLI en Windows: `"C:\Program Files\GitHub CLI\gh.exe"`.
- Avisarse antes de tocar la misma función de la base o el mismo archivo a la vez.
