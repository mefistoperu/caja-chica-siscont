import 'package:flutter_test/flutter_test.dart';

import 'package:efsiscont_flutter/src/models/comprobante.dart';
import 'package:efsiscont_flutter/src/services/asiento_compra.dart';
import 'package:efsiscont_flutter/src/services/mapeo_comprobante.dart';

void main() {
  test('construye un asiento balanceado con las cuentas del comprobante', () {
    final comprobante = Comprobante.vacio()
      ..creado = '2026-10-25T18:00:00.000'
      ..['vouNumero'] = '15'
      ..['vouFecha'] = '26/10/2026'
      ..['fecDoc'] = '24/10/2026'
      ..['ctaGastos'] = '601'
      ..['ctaIgv'] = '40111'
      ..['ctaOTrib'] = '40112'
      ..['ctaXPagar'] = '42121'
      ..['biogA'] = '100'
      ..['biogB'] = '20'
      ..['adNoGrav'] = '5'
      ..['igvA'] = '21.6'
      ..['isc'] = '2'
      ..['otrosTrib'] = '1'
      ..['impBolsa'] = '0.4';

    final asiento = construirAsientoCompra(comprobante);

    expect(asiento.periodo, '10');
    expect(asiento.voucher, '15');
    expect(asiento.fechaVoucher, '2026-10-25');
    expect(asiento.lineas, hasLength(6));
    expect(asiento.lineas.map((linea) => linea.cuenta), <String>[
      '601',
      '601',
      '601',
      '40111',
      '40112',
      '42121',
    ]);
    expect(
      asiento.lineas.fold<double>(0, (suma, linea) => suma + linea.debe),
      closeTo(150, 0.001),
    );
    expect(
      asiento.lineas.fold<double>(0, (suma, linea) => suma + linea.haber),
      closeTo(150, 0.001),
    );
  });

  test(
    'usa fecha de registro para el voucher aunque difiera de fecha documento',
    () {
      final comprobante = Comprobante.vacio()
        ..creado = '2026-02-01T10:00:00'
        ..['vouNumero'] = '31'
        ..['vouFecha'] = '05/03/2026'
        ..['fecDoc'] = '31/01/2026'
        ..['ctaGastos'] = '601'
        ..['ctaXPagar'] = '42121'
        ..['biogA'] = '100';

      final asiento = construirAsientoCompra(comprobante);

      expect(asiento.periodo, '02');
      expect(asiento.fechaVoucher, '2026-02-01');
    },
  );

  test('crea una línea de gasto por producto más IGV y cuenta por pagar', () {
    final comprobante =
        comprobanteDesdeIa(
            <String, dynamic>{
              'fecha_emision': '2026-10-26',
              'base_gravada': 150,
              'igv': 27,
              'total': 177,
              'glosa': 'DOS MIL TRESCIENTOS CINCUENTA Y TRES CON 00/100 SOLES',
              'detalle_items': <Map<String, dynamic>>[
                <String, dynamic>{
                  'descripcion': 'Producto A',
                  'cantidad': 1,
                  'precio': 100,
                  'importe': 100,
                },
                <String, dynamic>{
                  'descripcion': 'Producto B',
                  'cantidad': 1,
                  'precio': 50,
                  'importe': 50,
                },
              ],
            },
            archivo: 'factura.pdf',
            motor: 'test',
            voucher: 22,
          )
          ..['vouFecha'] = '26/10/2026'
          ..['ctaGastos'] = '601'
          ..['ctaIgv'] = '40111'
          ..['ctaXPagar'] = '42121';

    expect(comprobante['glosa'], 'Producto A');
    expect(comprobante['detalleItems'], contains('Producto B'));
    final asiento = construirAsientoCompra(comprobante);

    expect(asiento.lineas, hasLength(4));
    expect(asiento.lineas[0].descripcion, 'Producto A');
    expect(asiento.lineas[1].descripcion, 'Producto B');
    expect(asiento.lineas[2].cuenta, '40111');
    expect(asiento.lineas[3].haber, 177);
  });

  test('agrega ajuste visible cuando productos no alcanzan la base', () {
    final comprobante = Comprobante.vacio()
      ..['vouNumero'] = '24'
      ..['vouFecha'] = '26/10/2026'
      ..['ctaGastos'] = '601'
      ..['ctaIgv'] = '40111'
      ..['ctaXPagar'] = '42121'
      ..['biogA'] = '100'
      ..['igvA'] = '18'
      ..['detalleItems'] = '[{"descripcion":"Producto A","importe":"90.00"}]';

    final asiento = construirAsientoCompra(comprobante);
    final ajuste = asiento.lineas[1];

    expect(ajuste.cuenta, '601');
    expect(ajuste.debe, 10);
    expect(ajuste.haber, 0);
    expect(ajuste.descripcion, 'AJUSTE BASE/PRODUCTOS +10.00');
    expect(
      asiento.lineas.fold<double>(0, (suma, linea) => suma + linea.debe),
      closeTo(118, 0.001),
    );
    expect(
      asiento.lineas.fold<double>(0, (suma, linea) => suma + linea.haber),
      closeTo(118, 0.001),
    );
    expect(
      asiento.lineas
          .where((linea) => linea.cuenta == '601')
          .fold<double>(0, (suma, linea) => suma + linea.debe - linea.haber),
      closeTo(100, 0.001),
    );
  });

  test('registra en Haber el ajuste cuando productos superan la base', () {
    final comprobante = Comprobante.vacio()
      ..['vouNumero'] = '25'
      ..['ctaGastos'] = '601'
      ..['ctaIgv'] = '40111'
      ..['ctaXPagar'] = '42121'
      ..['biogA'] = '100'
      ..['igvA'] = '18'
      ..['detalleItems'] = '[{"descripcion":"Producto A","importe":"110.00"}]';

    final asiento = construirAsientoCompra(comprobante);
    final ajuste = asiento.lineas[1];

    expect(ajuste.debe, 0);
    expect(ajuste.haber, 10);
    expect(ajuste.descripcion, 'AJUSTE BASE/PRODUCTOS -10.00');
    expect(
      asiento.lineas.fold<double>(0, (suma, linea) => suma + linea.debe),
      closeTo(128, 0.001),
    );
    expect(
      asiento.lineas.fold<double>(0, (suma, linea) => suma + linea.haber),
      closeTo(128, 0.001),
    );
  });

  test('mantiene la línea de IGV con cero cuando no se cobra IGV', () {
    final comprobante = Comprobante.vacio()
      ..['vouNumero'] = '23'
      ..['vouFecha'] = '26/10/2026'
      ..['ctaGastos'] = '601'
      ..['ctaXPagar'] = '42121'
      ..['biogA'] = '100';

    final asiento = construirAsientoCompra(comprobante);

    expect(asiento.lineas, hasLength(3));
    expect(asiento.lineas[0].debe, 100);
    expect(asiento.lineas[1].cuenta, '40002');
    expect(asiento.lineas[1].debe, 0);
    expect(asiento.lineas[1].haber, 0);
    expect(asiento.lineas[2].haber, 100);
  });

  test('rechaza comprobantes sin número de voucher contable', () {
    final comprobante = Comprobante.vacio()..['vouNumero'] = '';

    expect(
      () => construirAsientoCompra(comprobante),
      throwsA(isA<FormatException>()),
    );
  });
}
