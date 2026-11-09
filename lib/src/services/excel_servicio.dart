import 'package:excel/excel.dart';

import '../models/comprobante.dart';
import '../storage/archivos.dart';

/// Genera el Excel de compras de SISCONT para WhatsApp, una fila por
/// comprobante, con las 61 columnas de la plantilla CAJA.
class ExcelServicio {
  const ExcelServicio();

  static Future<String> generar(List<Comprobante> items) async {
    final excel = Excel.createExcel();
    excel.rename(excel.getDefaultSheet() ?? 'Sheet1', 'Hoja1');
    final hoja = excel['Hoja1'];

    // Cada comprobante se exporta como una sola venta, sin expandir sus detalles.
    final cabecera = <CellValue?>[
      for (final d in columnas) TextCellValue(d.titulo),
    ];
    hoja.appendRow(cabecera);
    for (var i = 0; i < columnas.length; i++) {
      hoja
          .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0))
          .cellStyle = CellStyle(
        bold: true,
        horizontalAlign: HorizontalAlign.Center,
      );
      hoja.setColumnWidth(i, _ancho(columnas[i]));
    }

    for (final c in items) {
      final fila = <CellValue?>[];
      for (final d in columnas) {
        switch (d.tipo) {
          case TipoCampo.numero:
            fila.add(DoubleCellValue(c.numero(d.clave)));
            break;
          case TipoCampo.fecha:
            fila.add(TextCellValue(c[d.clave]));
            break;
          default:
            fila.add(TextCellValue(c[d.clave]));
        }
      }
      hoja.appendRow(fila);
    }

    final nombre = 'CAJA_${_marca()}.xlsx';
    final bytes = excel.encode();
    if (bytes == null) {
      throw Exception('No se pudo generar el Excel.');
    }
    return guardarExporte(nombre, bytes);
  }

  static double _ancho(DefColumna d) {
    if (d.tipo == TipoCampo.numero) return 14;
    if (d.tipo == TipoCampo.fecha) return 12;
    if (d.titulo.length > 22) return 24;
    return d.titulo.length + 4.0;
  }

  static String _marca() {
    final n = DateTime.now();
    String dos(int v) => v.toString().padLeft(2, '0');
    return '${n.year}${dos(n.month)}${dos(n.day)}_${dos(n.hour)}${dos(n.minute)}';
  }
}
