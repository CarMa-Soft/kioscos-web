// Planilla de Excel (.xlsx) armada a mano, con varias hojas: un zip con XML, comprimido con fflate (como el Excel de Pedidos).
// descargarExcel('Archivo', [{ nombre: 'Hoja', filas: [['Título', ...], [valor, ...]] }]): la primera fila de cada hoja va en negrita.
// Los números van como número (se pueden sumar en Excel); el resto, como texto.
export async function descargarExcel(archivo, hojas) {
  const { zipSync, strToU8 } = await import('https://cdn.jsdelivr.net/npm/fflate@0.8.3/+esm');
  const x = s => String(s).replace(/[<>&"]/g, c => ({ '<': '&lt;', '>': '&gt;', '&': '&amp;', '"': '&quot;' }[c])).replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f]/g, '');
  const col = n => (n >= 26 ? col(Math.floor(n / 26) - 1) : '') + String.fromCharCode(65 + (n % 26));
  const celda = (v, ref, negrita) => typeof v === 'number' && Number.isFinite(v)
    ? `<c r="${ref}"${negrita ? ' s="1"' : ''}><v>${v}</v></c>`
    : `<c r="${ref}" t="inlineStr"${negrita ? ' s="1"' : ''}><is><t xml:space="preserve">${x(v)}</t></is></c>`;
  const hoja = filas => `<?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">`
    + `<sheetData>${filas.map((f, r) => `<row r="${r + 1}">${f.map((v, c) => v === '' || v == null ? '' : celda(v, col(c) + (r + 1), r === 0)).join('')}</row>`).join('')}</sheetData></worksheet>`;
  const nombreHoja = s => x(String(s).replace(/[\\/?*[\]:]/g, '-').slice(0, 31));
  const archivos = {
    '[Content_Types].xml': `<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>${hojas.map((_, i) => `<Override PartName="/xl/worksheets/sheet${i + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>`).join('')}<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>`,
    '_rels/.rels': `<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>`,
    'xl/workbook.xml': `<?xml version="1.0" encoding="UTF-8" standalone="yes"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>${hojas.map((h, i) => `<sheet name="${nombreHoja(h.nombre)}" sheetId="${i + 1}" r:id="rId${i + 1}"/>`).join('')}</sheets></workbook>`,
    'xl/_rels/workbook.xml.rels': `<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">${hojas.map((_, i) => `<Relationship Id="rId${i + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet${i + 1}.xml"/>`).join('')}<Relationship Id="rId${hojas.length + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>`,
    'xl/styles.xml': `<?xml version="1.0" encoding="UTF-8" standalone="yes"?><styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts><fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills><borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/></cellXfs></styleSheet>`,
    ...Object.fromEntries(hojas.map((h, i) => [`xl/worksheets/sheet${i + 1}.xml`, hoja(h.filas)])),
  };
  const zip = zipSync(Object.fromEntries(Object.entries(archivos).map(([k, v]) => [k, strToU8(v)])));
  const url = URL.createObjectURL(new Blob([zip], { type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' }));
  const a = Object.assign(document.createElement('a'), { href: url, download: archivo.replace(/[\\/:*?"<>|]/g, '-') + '.xlsx' });
  document.body.append(a); a.click(); a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 5000);
}
