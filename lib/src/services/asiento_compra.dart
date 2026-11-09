import 'dart:convert';

import '../models/comprobante.dart';

class LineaAsientoCompra {
  final String cuenta;
  final double debe;
  final double haber;
  final String descripcion;

  const LineaAsientoCompra({
    required this.cuenta,
    required this.debe,
    required this.haber,
    this.descripcion = '',
  });
}

class AsientoCompra {
  final String periodo;
  final String voucher;
  final String fechaVoucher;
  final double tipoCambio;
  final List<LineaAsientoCompra> lineas;

  const AsientoCompra({
    required this.periodo,
    required this.voucher,
    required this.fechaVoucher,
    required this.tipoCambio,
    required this.lineas,
  });
}

AsientoCompra construirAsientoCompra(Comprobante comprobante) {
  final fechaRegistro = comprobante.fechaRegistro;
  final fechaVoucher = fechaRegistro == null
      ? null
      : '${fechaRegistro.year.toString().padLeft(4, '0')}-'
            '${fechaRegistro.month.toString().padLeft(2, '0')}-'
            '${fechaRegistro.day.toString().padLeft(2, '0')}';
  if (fechaVoucher == null) {
    throw FormatException(
      'El comprobante ${comprobante.nombreArchivo} no tiene una fecha de '
      'registro válida.',
    );
  }

  final voucher = comprobante['vouNumero'].trim();
  if (!RegExp(r'^\d+$').hasMatch(voucher) || int.tryParse(voucher) == 0) {
    throw FormatException(
      'El comprobante ${comprobante.nombreArchivo} necesita un número de '
      'voucher numérico mayor que cero.',
    );
  }

  final tipoCambio = comprobante.numero('tc');
  if (comprobante['moneda'] == 'D' && tipoCambio <= 0) {
    throw FormatException(
      'El comprobante ${comprobante.nombreArchivo} necesita un tipo de cambio '
      'mayor que cero.',
    );
  }

  final basePorTipo = <String, double>{
    'biogA': _redondear(comprobante.numero('biogA')),
    'biogB': _redondear(comprobante.numero('biogB')),
    'biogC': _redondear(comprobante.numero('biogC')),
    'adNoGrav': _redondear(comprobante.numero('adNoGrav')),
  };
  final base = _redondear(
    basePorTipo.values.fold<double>(0, (suma, importe) => suma + importe),
  );
  final detalleItems = _detalleItems(comprobante);
  final igv = _redondear(
    comprobante.numero('igvA') +
        comprobante.numero('igvB') +
        comprobante.numero('igvC'),
  );
  final otros = _redondear(
    comprobante.numero('isc') +
        comprobante.numero('otrosTrib') +
        comprobante.numero('impBolsa'),
  );
  final total = _redondear(comprobante.total);
  if (total <= 0) {
    throw FormatException(
      'El comprobante ${comprobante.nombreArchivo} no tiene un total mayor '
      'que cero.',
    );
  }

  final lineas = <LineaAsientoCompra>[];
  void agregarDebe(
    String cuenta,
    double importe,
    String etiqueta, {
    String descripcion = '',
  }) {
    if (importe <= 0) return;
    if (cuenta.trim().isEmpty) {
      throw FormatException(
        'Indique la cuenta $etiqueta en el comprobante '
        '${comprobante.nombreArchivo}.',
      );
    }
    lineas.add(
      LineaAsientoCompra(
        cuenta: cuenta.trim(),
        debe: importe,
        haber: 0,
        descripcion: descripcion,
      ),
    );
  }

  final cuentaGastos = comprobante['ctaGastos'].trim();
  if (detalleItems.isNotEmpty) {
    for (final item in detalleItems) {
      agregarDebe(
        cuentaGastos,
        item.importe,
        'de gastos',
        descripcion: item.descripcion,
      );
    }
    final sumaDetalle = _redondear(
      detalleItems.fold<double>(0, (suma, item) => suma + item.importe),
    );
    final diferenciaDetalle = _redondear(base - sumaDetalle);
    if (diferenciaDetalle.abs() > 0.01) {
      if (cuentaGastos.isEmpty) {
        throw FormatException(
          'Indique la cuenta de gastos para registrar la diferencia entre '
          'productos y base del comprobante ${comprobante.nombreArchivo}.',
        );
      }
      final importeAjuste = diferenciaDetalle.abs();
      final signo = diferenciaDetalle > 0 ? '+' : '-';
      lineas.add(
        LineaAsientoCompra(
          cuenta: cuentaGastos,
          debe: diferenciaDetalle > 0 ? importeAjuste : 0,
          haber: diferenciaDetalle < 0 ? importeAjuste : 0,
          descripcion:
              'AJUSTE BASE/PRODUCTOS $signo${importeAjuste.toStringAsFixed(2)}',
        ),
      );
    }
  } else {
    for (final entrada in basePorTipo.entries) {
      agregarDebe(
        cuentaGastos,
        entrada.value,
        'de gastos',
        descripcion: _descripcionBase(entrada.key),
      );
    }
  }
  final cuentaIgv = comprobante['ctaIgv'].trim();
  if (cuentaIgv.isEmpty) {
    throw FormatException(
      'Indique la cuenta de IGV en el comprobante '
      '${comprobante.nombreArchivo}.',
    );
  }
  lineas.add(
    LineaAsientoCompra(
      cuenta: cuentaIgv,
      debe: igv,
      haber: 0,
      descripcion: igv > 0 ? 'IGV' : 'IGV (0.00)',
    ),
  );
  agregarDebe(
    comprobante['ctaOTrib'],
    otros,
    'de otros tributos',
    descripcion: 'ISC, otros tributos e impuesto a la bolsa',
  );

  final sumaDebe = _redondear(base + igv + otros);
  if ((sumaDebe - total).abs() > 0.01) {
    throw FormatException(
      'El asiento de ${comprobante.nombreArchivo} no cuadra: Debe '
      '${sumaDebe.toStringAsFixed(2)} y total '
      '${total.toStringAsFixed(2)}.',
    );
  }

  final cuentaPagar = comprobante['ctaXPagar'].trim();
  if (cuentaPagar.isEmpty) {
    throw FormatException(
      'Indique la cuenta por pagar en el comprobante '
      '${comprobante.nombreArchivo}.',
    );
  }
  lineas.add(
    LineaAsientoCompra(
      cuenta: cuentaPagar,
      debe: 0,
      haber: total,
      descripcion: 'TOTAL COMPROBANTE',
    ),
  );
  if (lineas.length < 3) {
    throw FormatException(
      'El comprobante ${comprobante.nombreArchivo} solo permite generar '
      '${lineas.length} línea(s). Revise las bases y el detalle para formar '
      'un asiento de al menos 3 líneas.',
    );
  }

  return AsientoCompra(
    periodo: fechaVoucher.substring(5, 7),
    voucher: voucher,
    fechaVoucher: fechaVoucher,
    tipoCambio: tipoCambio > 0 ? tipoCambio : 1,
    lineas: lineas,
  );
}

List<_DetalleItem> _detalleItems(Comprobante comprobante) {
  final fuente = comprobante['detalleItems'].trim();
  if (fuente.isEmpty) return <_DetalleItem>[];

  final decoded = jsonDecode(fuente);
  if (decoded is! List) {
    throw FormatException(
      'El detalle de productos de ${comprobante.nombreArchivo} no es válido.',
    );
  }

  final items = <_DetalleItem>[];
  for (final raw in decoded) {
    if (raw is! Map) continue;
    final descripcion = '${raw['descripcion'] ?? ''}'.trim();
    final importe = _numero(raw['importe']);
    if (descripcion.isEmpty || importe <= 0) continue;
    items.add(_DetalleItem(descripcion, _redondear(importe)));
  }

  if (items.isEmpty) return items;
  return items;
}

double _numero(dynamic valor) {
  if (valor is num) return valor.toDouble();
  var texto = '${valor ?? ''}'.trim();
  if (texto.contains(',') && texto.contains('.')) {
    texto = texto.replaceAll(',', '');
  } else if (texto.contains(',')) {
    texto = texto.replaceAll(',', '.');
  }
  return double.tryParse(texto) ?? 0;
}

String _descripcionBase(String clave) {
  switch (clave) {
    case 'biogA':
      return 'BASE GRAVADA A';
    case 'biogB':
      return 'BASE GRAVADA B';
    case 'biogC':
      return 'BASE GRAVADA C';
    case 'adNoGrav':
      return 'BASE NO GRAVADA';
    default:
      return '';
  }
}

class _DetalleItem {
  final String descripcion;
  final double importe;

  const _DetalleItem(this.descripcion, this.importe);
}

double _redondear(double importe) => (importe * 100).round() / 100;
