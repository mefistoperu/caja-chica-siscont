import 'dart:convert';

import '../models/comprobante.dart';

/// Traduce el JSON de la IA al formato del Excel de compras de SISCONT,
/// dejando valores por defecto en las columnas que se completan a mano.
Comprobante comprobanteDesdeIa(
  Map<String, dynamic> datos, {
  required String archivo,
  required String motor,
  required int voucher,
}) {
  final c = Comprobante.vacio(archivo: archivo)
    ..motor = motor
    ..['vouNumero'] = '$voucher';

  String txt(String k) => '${datos[k] ?? ''}'.trim();
  double num(String k) {
    var s = txt(k);
    if (s.isEmpty) return 0;
    if (s.contains(',') && s.contains('.')) {
      s = s.replaceAll(',', '');
    } else if (s.contains(',')) {
      s = s.replaceAll(',', '.');
    }
    return double.tryParse(s) ?? 0;
  }

  final numero = txt('serie_numero');
  final ruc = txt('ruc').replaceAll(RegExp(r'[^0-9]'), '');
  final rs = txt('razon_social');
  final tipoDoc = _codigoDocumento(txt('tipo_documento'), numero);
  final moneda = txt('moneda').toUpperCase() == 'USD' ? 'D' : 'S';
  final igv = num('igv');
  var base = num('base_gravada');
  final total = num('total');

  // Si la IA no separo la base, se deduce del total y el IGV.
  if (base == 0 && igv > 0 && total > igv) base = total - igv;
  if (base == 0 && num('base_exonerada') == 0 && num('base_inafecta') == 0) {
    base = total > igv ? total - igv : total;
  }

  final exonerada = num('base_exonerada');
  final inafecta = num('base_inafecta');
  final noGravada = exonerada + inafecta;
  final retencion = num('retencion') > 0 ? '1' : '0';
  final detalleItems = _detalleItems(datos['detalle_items']);

  final numeroTitulo = _tituloDocumento(tipoDoc);
  var glosa = txt('glosa');
  if (_pareceImporteEnLetras(glosa)) {
    glosa = detalleItems.isNotEmpty ? detalleItems.first['descripcion']! : '';
  }
  if (glosa.isEmpty) {
    glosa = <String>[
      numeroTitulo,
      if (numero.isNotEmpty) numero,
      if (rs.isNotEmpty) rs,
    ].join(' ');
  }
  if (glosa.length > 60) glosa = glosa.substring(0, 60);

  c
    ..['doc'] = tipoDoc
    ..['numero'] = numero
    ..['fecDoc'] = _fecha(txt('fecha_emision')) ?? c['fecDoc']
    ..['fecVenc'] = _fecha(txt('fecha_vencimiento')) ?? ''
    ..['ruc'] = ruc
    ..['codigo'] = ruc
    ..['rSocial'] = rs
    ..['biogA'] = _m(base)
    ..['adNoGrav'] = _m(noGravada)
    ..['isc'] = _m(num('isc'))
    ..['igvA'] = _m(igv)
    ..['otrosTrib'] = _m(num('otros_tributos'))
    ..['impBolsa'] = _m(num('impuesto_bolsa'))
    ..['detalleItems'] = jsonEncode(detalleItems)
    ..['moneda'] = moneda
    ..['tc'] = num('tipo_cambio') > 0 ? _m(num('tipo_cambio')) : '1.000'
    ..['glosa'] = glosa
    ..['tipDocIden'] = _tipDocIdentidad(txt('tipo_doc_identidad'), ruc)
    ..['medioPago'] = txt('medio_pago')
    ..['apellido1'] = txt('apellido1')
    ..['apellido2'] = txt('apellido2')
    ..['nombre'] = txt('nombre')
    ..['retencion'] = retencion
    ..['codTasa'] = txt('cod_tasa')
    ..['indRet'] = txt('ind_ret')
    ..['bImp'] = retencion == '1' ? _m(base) : '0';

  return c;
}

List<Map<String, String>> _detalleItems(dynamic valor) {
  if (valor is! List) return <Map<String, String>>[];
  final items = <Map<String, String>>[];
  for (final item in valor) {
    if (item is! Map) continue;
    final descripcion = '${item['descripcion'] ?? ''}'.trim();
    final importe = _numeroIa(item['importe']);
    if (descripcion.isEmpty || importe <= 0) continue;
    items.add(<String, String>{
      'descripcion': descripcion,
      'cantidad': _numeroIa(item['cantidad']).toString(),
      'precio': _numeroIa(item['precio']).toString(),
      'importe': importe.toStringAsFixed(2),
    });
  }
  return items;
}

bool _pareceImporteEnLetras(String texto) => RegExp(
  r'\b(?:con\s+\d{1,2}\s*/\s*100|soles?|d[oó]lares?)\b',
  caseSensitive: false,
).hasMatch(texto);

double _numeroIa(dynamic valor) {
  if (valor is num) return valor.toDouble();
  var texto = '$valor'.trim();
  if (texto.contains(',') && texto.contains('.')) {
    texto = texto.replaceAll(',', '');
  } else if (texto.contains(',')) {
    texto = texto.replaceAll(',', '.');
  }
  return double.tryParse(texto) ?? 0;
}

String _m(double v) => v == 0 ? '0' : v.toStringAsFixed(2);

String _codigoDocumento(String crudo, String numero) {
  final t = crudo.toLowerCase();
  if (t.contains('boleta')) return '02';
  if (t.contains('reten')) return '07';
  if (t.contains('honor')) return '08';
  if (t.contains('credito') || t.contains('crédito')) return '03';
  if (t.contains('debito') || t.contains('débito')) return '04';
  if (t.contains('factura')) return '01';
  // Deduccion por la serie.
  final serie = numero.split('-').first.toUpperCase();
  if (serie.startsWith('B')) return '02';
  if (serie.startsWith('E')) return '08';
  if (serie.startsWith('R')) return '07';
  return '01';
}

String _tituloDocumento(String doc) {
  switch (doc) {
    case '02':
      return 'BOLETA';
    case '03':
      return 'NOTA DE CREDITO';
    case '04':
      return 'NOTA DE DEBITO';
    case '07':
      return 'RETENCION';
    case '08':
      return 'RECIBO HONORARIOS';
    default:
      return 'FACTURA';
  }
}

String _tipDocIdentidad(String crudo, String ruc) {
  if (crudo == '1' || crudo == '6' || crudo == '4' || crudo == '7') {
    return crudo;
  }
  if (ruc.length == 11) return '6';
  if (ruc.length == 8) return '1';
  return '6';
}

/// Acepta "2024-05-13", "13/05/2024" o "13-05-2024" y devuelve dd/mm/aaaa.
String? _fecha(String crudo) {
  final s = crudo.trim();
  if (s.isEmpty) return null;
  final iso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(s);
  if (iso != null) {
    return '${iso.group(3)}/${iso.group(2)}/${iso.group(1)}';
  }
  final dmy = RegExp(r'^(\d{1,2})[/-](\d{1,2})[/-](\d{2,4})').firstMatch(s);
  if (dmy != null) {
    final d = dmy.group(1)!.padLeft(2, '0');
    final m = dmy.group(2)!.padLeft(2, '0');
    var y = dmy.group(3)!;
    if (y.length == 2) y = '20$y';
    return '$d/$m/$y';
  }
  return null;
}
