import 'dart:io';

import 'package:excel/excel.dart';
import 'package:efsiscont_flutter/src/models/comprobante.dart';
import 'package:efsiscont_flutter/src/services/excel_servicio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  Directory? directorioTemporal;

  setUp(() async {
    directorioTemporal = await Directory.systemTemp.createTemp('compras_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          pathProvider,
          (_) async => directorioTemporal!.path,
        );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    await directorioTemporal?.delete(recursive: true);
  });

  test('un comprobante nuevo trae los valores por defecto del Excel', () {
    final c = Comprobante.vacio(id: 'abc', archivo: '/tmp/f.pdf');
    expect(columnas.length, 61);
    expect(c['vouOrigen'], '01');
    expect(c['doc'], '01');
    expect(c['moneda'], 'S');
    expect(c['ctaGastos'], '656');
    expect(c['ctaIgv'], '40002');
    expect(c['ctaXPagar'], '42121');
    expect(Comprobante.fechaHoy().split('/').length, 3);
    // Todas las columnas del Excel existen en el mapa de valores.
    for (final d in columnas) {
      expect(
        c.valores.containsKey(d.clave),
        isTrue,
        reason: 'falta la columna ${d.clave}',
      );
    }
  });

  test('el tipo de documento incluye 00 - Otros para compras manuales', () {
    final documento = columnas.firstWhere((columna) => columna.clave == 'doc');
    final c = Comprobante.vacio()..['doc'] = '00';

    expect(documento.opciones, contains('00'));
    expect(c['doc'], '00');
  });

  test('los importes aceptan coma decimal y separador de miles', () {
    final c = Comprobante.vacio();
    c['biogA'] = '1,234.56';
    c['igvA'] = '222,22';
    expect(c.numero('biogA'), 1234.56);
    expect(c.numero('igvA'), 222.22);
    expect(c.total, closeTo(1456.78, 0.001));
  });

  test('el Excel de WhatsApp usa CAJA y exporta una fila por venta', () async {
    final c = Comprobante.vacio(id: 'x1', archivo: '');
    c['numero'] = 'F001-00000123';
    c['ruc'] = '20505484848';
    c['rSocial'] = 'PROVEEDOR DEMO SAC';
    c['vouOrigen'] = '09';
    c['tc'] = '3.75';
    c['ctaGastos'] = '60002';
    c['ctaIgv'] = '40002';
    c['ctaXPagar'] = '42121';
    c['ccosto'] = 'CC01';
    c['presupuesto'] = 'P01';
    c['biogA'] = '100.00';
    c['igvA'] = '18.00';
    c['detalleItems'] =
        '[{"descripcion":"Producto A","importe":"50.00"},'
        '{"descripcion":"Producto B","importe":"50.00"}]';
    final segundo = Comprobante.vacio(id: 'x2', archivo: '');
    segundo['ruc'] = '20123456789';
    segundo['rSocial'] = 'SEGUNDO PROVEEDOR';
    segundo['biogA'] = '25.00';

    c.estadoWhatsapp = 'enviado';
    final ruta = await ExcelServicio.generar([c, segundo]);
    final archivo = File(ruta);
    expect(await archivo.exists(), isTrue);
    expect(await archivo.length(), greaterThan(0));
    expect(ruta.split(Platform.pathSeparator).last, startsWith('CAJA_'));
    expect(ruta.endsWith('.xlsx'), isTrue);
    final excel = Excel.decodeBytes(await archivo.readAsBytes());
    expect(excel.tables.keys, <String>['Hoja1']);
    final filas = excel.tables['Hoja1']!.rows;
    expect(filas, hasLength(3));
    expect(filas[0], hasLength(61));
    expect(filas[0][0]!.value.toString(), 'Vou.Origen');
    expect(filas[0][5]!.value.toString(), 'Fec.Doc');
    expect(filas[0][60]!.value.toString(), 'IGV');
    expect(filas[1][32]!.value.toString(), '20505484848');
    expect(filas[1][33]!.value.toString(), 'PROVEEDOR DEMO SAC');
    for (final entrada in <(String, String)>[
      ('vouOrigen', '09'),
      ('tc', '3.75'),
      ('ctaGastos', '60002'),
      ('ctaIgv', '40002'),
      ('ctaXPagar', '42121'),
      ('ccosto', 'CC01'),
      ('presupuesto', 'P01'),
    ]) {
      final indice = columnas.indexWhere(
        (columna) => columna.clave == entrada.$1,
      );
      expect(indice, greaterThanOrEqualTo(0));
      expect(
        filas[1][indice]!.value.toString(),
        entrada.$2,
        reason: entrada.$1,
      );
    }
    expect(filas[2][32]!.value.toString(), '20123456789');
    expect(filas[2][33]!.value.toString(), 'SEGUNDO PROVEEDOR');
  });
}
