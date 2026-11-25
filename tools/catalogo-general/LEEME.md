# Catálogo general de productos

Productos con código de barras de los datos abiertos de **Precios Claros (SEPA)**, de la Secretaría de Comercio de la Nación (datos.produccion.gob.ar). Cada archivo `productos*.csv` trae una fila por producto y por sucursal, con separador `|`.

Los CSV no se suben al repositorio (pesan 1,5 GB). Se dejan en una carpeta local, por ejemplo `Bases productos/`, que está en `.git/info/exclude`.

## Regenerarlo
```
node --max-old-space-size=6000 tools/catalogo-general/juntar.js "Bases productos" juntado.json
node tools/catalogo-general/unificar.js juntado.json "Bases productos/catalogo-general.csv"
node tools/catalogo-general/sql.js "Bases productos/catalogo-general.csv" supabase/migrations/AAAAMMDDHHMMSS_catalogo_general_datos.sql --reemplazar
```

**juntar.js:** agrupa por código. Solo entran:
- las filas con `productos_ean = 1`;
- los EAN-8, EAN-13 y UPC con dígito verificador válido.

Quedan afuera los códigos internos de cada cadena y los de balanza (empiezan con 2). Junta nombres, marcas y presentaciones, y guarda hasta 400 precios por código.

**unificar.js:** arma una fila por código.
- **Nombre:** el de la cadena que mejor describe (orden en `PREFERENCIA`), limpio.
- **Marca:** la más frecuente.
- **Contenido:** el del nombre (`X 930 CC` → `930 ml`) o, si no, el de la presentación.
- **Precio de referencia:** la mediana.
- **Cadenas:** en cuántas aparece.
- **Categoría sugerida:** deducida del nombre por palabras (`categorias.js`). La que aparece primero en el nombre gana; clasifica más o menos la mitad (casi todo lo de kiosco y almacén), el resto queda sin categoría.
- Un EAN-8 completado con ceros queda de 8 dígitos.

**sql.js:** genera la migración con los `insert`. Con `--reemplazar` (para actualizar una base ya cargada) la migración hace antes `truncate public.catalogo_general;`.

**Archivos usados** (un archivo por cadena, `id_comercio`; algunas cadenas están en dos archivos de días distintos, y no se cuentan dos veces):
`productos.csv` (9), `productos2.csv` (12), `productos3.csv` (15), `productos4.csv` (2), `productos5.csv` (10), `productos6.csv` (11),
`productos_nuevo 1.csv` (3), `productos_nuevo 2.csv` (13), `productos_nuevo 3.csv` (2), `productos_nuevo 4.csv` (10).
