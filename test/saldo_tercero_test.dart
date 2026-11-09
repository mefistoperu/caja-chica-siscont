import 'package:efsiscont_flutter/src/models/saldo_tercero.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('lee saldos de terceros devueltos por el servicio PHP', () {
    final saldo = SaldoTercero.fromJson(<String, dynamic>{
      'rut': '20123456789',
      'razon_social': 'Proveedor Demo S.A.C.',
      'debe': '1250.50',
      'haber': 250,
      'saldo': '1000.50',
    });

    expect(saldo.rut, '20123456789');
    expect(saldo.razonSocial, 'Proveedor Demo S.A.C.');
    expect(saldo.debe, 1250.5);
    expect(saldo.haber, 250);
    expect(saldo.saldo, 1000.5);
  });
}
