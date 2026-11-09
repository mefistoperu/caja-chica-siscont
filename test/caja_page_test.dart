import 'dart:io';

import 'package:efsiscont_flutter/src/models/comprobante.dart';
import 'package:efsiscont_flutter/src/models/tipo_movimiento_caja.dart';
import 'package:efsiscont_flutter/src/pages/caja_page.dart';
import 'package:efsiscont_flutter/src/pages/reporte_page.dart';
import 'package:efsiscont_flutter/src/storage/repositorio.dart';
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
      'efsiscont_caja_page_test_',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          pathProvider,
          (_) async => directorioTemporal!.path,
        );
    await Repositorio.i.inicializar();
    await Repositorio.i.guardarTipoMovimientoCaja(
      const TipoMovimientoCaja(
        id: 'yape',
        nombre: 'Yape',
        cuentaIngreso: '101',
        cuentaGasto: '201',
      ),
    );
    await Repositorio.i.abrirCaja(moneda: 'PEN', montoApertura: 0);
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    await directorioTemporal?.delete(recursive: true);
  });

  testWidgets('Caja solo solicita medio de pago y monto al registrar', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: CajaPage()));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Medio de pago'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Medio de pago'), findsOneWidget);
    expect(find.text('Monto'), findsOneWidget);
    expect(find.text('Nombre del cliente *'), findsNothing);
    expect(find.text('N.º documento *'), findsNothing);
    expect(find.text('Concepto'), findsNothing);
  });

  testWidgets('muestra la segunda caja en dólares y permite seleccionarla', (
    tester,
  ) async {
    await Repositorio.i.abrirCaja(moneda: 'USD', montoApertura: 15);

    await tester.pumpWidget(const MaterialApp(home: CajaPage()));
    await tester.pumpAndSettle();

    expect(find.text('CAJAS ABIERTAS (2/2)'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('caja-abierta-PEN')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('caja-abierta-USD')),
      findsOneWidget,
    );
    expect(
      find.text(
        'Ya están abiertas las dos Cajas permitidas: una en soles y otra en dólares.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey<String>('caja-abierta-USD')));
    await tester.pumpAndSettle();
    expect(find.text('CAJA ABIERTA · DÓLARES'), findsOneWidget);
  });

  testWidgets('lista cajas abiertas y cerradas con acciones de envío', (
    tester,
  ) async {
    final cajaCerrada = Repositorio.i.cajaActiva!;
    await Repositorio.i.cerrarCaja(cajaId: cajaCerrada.id);
    await Repositorio.i.abrirCaja(moneda: 'USD', montoApertura: 10);
    final comprobante = Comprobante.vacio()
      ..creado = DateTime.now().toIso8601String()
      ..['rSocial'] = 'Proveedor de caja cerrada'
      ..['cajaId'] = cajaCerrada.id
      ..['vouNumero'] = '12'
      ..['biogA'] = '100.00';
    await Repositorio.i.guardarComprobantes(<Comprobante>[comprobante]);

    await tester.pumpWidget(const MaterialApp(home: CajaPage()));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('HISTORIAL DE CAJAS (2)'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('HISTORIAL DE CAJAS (2)'), findsOneWidget);
    expect(find.textContaining('Caja PEN · CERRADA'), findsOneWidget);
    expect(find.textContaining('Caja USD · ABIERTA'), findsOneWidget);

    final cajaTile = find.byKey(
      ValueKey<String>('historial-caja-${cajaCerrada.id}'),
    );
    await tester.drag(find.byType(ListView).first, const Offset(0, -450));
    await tester.pumpAndSettle();
    await tester.tap(cajaTile);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).first, const Offset(0, -450));
    await tester.pumpAndSettle();
    expect(find.text('1 comprobante(s) · 0 movimiento(s)'), findsOneWidget);

    final enviarWhatsapp = find.byKey(
      ValueKey<String>('caja-whatsapp-${cajaCerrada.id}'),
    );
    await tester.drag(find.byType(ListView).first, const Offset(0, -450));
    await tester.pumpAndSettle();
    final enviarSiscont = find.byKey(
      ValueKey<String>('caja-siscont-${cajaCerrada.id}'),
    );
    expect(
      tester.getTopLeft(enviarWhatsapp).dy,
      tester.getTopLeft(enviarSiscont).dy,
    );
    await tester.tap(enviarWhatsapp);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Proveedor de caja cerrada'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byType(ReportePage), findsOneWidget);
    expect(find.textContaining('Caja PEN (cerrada)'), findsOneWidget);
    expect(find.text('Proveedor de caja cerrada'), findsOneWidget);
    expect(find.textContaining('ENVIAR A SISCONT · CAJA PEN'), findsOneWidget);
  });
}
