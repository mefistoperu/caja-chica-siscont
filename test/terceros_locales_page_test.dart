import 'dart:io';

import 'package:efsiscont_flutter/src/models/tercero_local.dart';
import 'package:efsiscont_flutter/src/pages/terceros_locales_page.dart';
import 'package:efsiscont_flutter/src/storage/repositorio.dart';
import 'package:efsiscont_flutter/src/theme/tema.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  Directory? directorioTemporal;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    directorioTemporal = await Directory.systemTemp.createTemp(
      'efsiscont_proveedores_test_',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          pathProvider,
          (_) async => directorioTemporal!.path,
        );
    await Repositorio.i.inicializar();
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    await directorioTemporal?.delete(recursive: true);
  });

  testWidgets('registra proveedores con centro y concepto de gasto', (
    tester,
  ) async {
    await Repositorio.i.guardarTerceroLocal(
      const TerceroLocal(
        id: 'cliente-local',
        tipo: 'cliente',
        tipoDocumento: 'RUC',
        numeroDocumento: '20111111111',
        nombre: 'Cliente oculto',
      ),
    );
    await Repositorio.i.guardarCentroCostoLocal(
      codigo: 'CC01',
      nombre: 'Administración',
    );
    await Repositorio.i.guardarConceptoGastoLocal(
      codigo: '60002',
      nombre: 'Servicios',
    );

    await tester.pumpWidget(
      MaterialApp(theme: temaEfsiscont(), home: const TercerosLocalesPage()),
    );
    await tester.pumpAndSettle();

    expect(find.text('PROVEEDORES'), findsOneWidget);
    expect(find.text('Cliente oculto'), findsNothing);
    expect(find.text('Clientes'), findsNothing);

    await tester.tap(find.text('Agregar proveedor'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'Número de documento',
      ),
      '20555555555',
    );
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'Nombre / razón social',
      ),
      'Proveedor nuevo',
    );
    expect(find.text('Agregar centro de costos'), findsOneWidget);
    expect(find.text('Agregar concepto de gasto'), findsOneWidget);
    await tester.ensureVisible(find.text('Agregar centro de costos'));
    await tester.tap(find.text('Agregar centro de costos'));
    await tester.pumpAndSettle();
    expect(find.text('CENTROS DE COSTO'), findsOneWidget);
    Navigator.of(tester.element(find.text('CENTROS DE COSTO'))).pop();
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Agregar concepto de gasto'));
    await tester.tap(find.text('Agregar concepto de gasto'));
    await tester.pumpAndSettle();
    expect(find.text('CONCEPTOS DE GASTO'), findsOneWidget);
    Navigator.of(tester.element(find.text('CONCEPTOS DE GASTO'))).pop();
    await tester.pumpAndSettle();

    final selectorCentro = find.byKey(
      const ValueKey<String>('proveedor-centrocosto-'),
    );
    await tester.ensureVisible(selectorCentro);
    await tester.tap(selectorCentro);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Administración').last);
    await tester.pumpAndSettle();

    final selectorConcepto = find.byKey(
      const ValueKey<String>('proveedor-concepto-'),
    );
    await tester.ensureVisible(selectorConcepto);
    await tester.tap(selectorConcepto);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Servicios').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    final proveedor = Repositorio.i.proveedoresLocales.singleWhere(
      (item) => item.numeroDocumento == '20555555555',
    );
    expect(proveedor.tipo, 'proveedor');
    expect(proveedor.centroCostoCodigo, 'CC01');
    expect(proveedor.conceptoGastoCodigo, '60002');
    expect(find.text('Proveedor nuevo'), findsOneWidget);
    expect(find.text('Cliente oculto'), findsNothing);
  });
}
