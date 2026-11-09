import 'dart:io';

import 'package:efsiscont_flutter/src/models/comprobante.dart';
import 'package:efsiscont_flutter/src/models/origenes_caja.dart';
import 'package:efsiscont_flutter/src/models/tercero_local.dart';
import 'package:efsiscont_flutter/src/pages/comprobante_form_page.dart';
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
      'efsiscont_form_test_',
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

  testWidgets('el registro manual mantiene ocultas las cuentas contables', (
    tester,
  ) async {
    final comprobante = Comprobante.vacio()
      ..motor = 'manual'
      ..['numero'] = '';

    await tester.pumpWidget(
      MaterialApp(
        theme: temaEfsiscont(),
        home: ComprobanteFormPage(comprobante: comprobante, nuevo: true),
      ),
    );
    await tester.pumpAndSettle();

    expect(comprobante['numero'], '00000000');
    expect(comprobante['doc'], '00');
    expect(comprobante['tipDocIden'], '0');
    expect(find.text('00 - Otros'), findsNothing);
    expect(comprobante['rSocial'], 'PROVEEDORES VARIOS');
    expect(find.text('Documento: OTROS (00)'), findsOneWidget);
    expect(find.text('Vou.Origen'), findsNothing);
    expect(find.text('Vou.Numero'), findsNothing);
    expect(find.text('Centro de costos'), findsOneWidget);
    expect(find.text('Tipo de afectación'), findsOneWidget);
    expect(find.text('Monto'), findsOneWidget);
    expect(find.text('Monto de apertura'), findsNothing);
    for (final clave in <String>[
      'ctaGastos',
      'ctaIgv',
      'ctaOTrib',
      'ctaXPagar',
    ]) {
      expect(find.byKey(ValueKey<String>('campo-$clave')), findsNothing);
    }
    expect(find.text('CUENTAS CONTABLES'), findsNothing);
    expect(find.text('Proveedor'), findsOneWidget);
    expect(find.text('Caja'), findsOneWidget);
    expect(find.text('PROVEEDORES VARIOS'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Mostrar campos adicionales'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Mostrar campos adicionales'));
    await tester.pumpAndSettle();
    for (final clave in <String>[
      'ctaGastos',
      'ctaIgv',
      'ctaOTrib',
      'ctaXPagar',
    ]) {
      expect(find.byKey(ValueKey<String>('campo-$clave')), findsNothing);
    }
  });

  testWidgets('el registro manual guarda la caja y proveedor seleccionados', (
    tester,
  ) async {
    await Repositorio.i.abrirCaja(moneda: 'PEN', montoApertura: 0);
    await Repositorio.i.abrirCaja(moneda: 'USD', montoApertura: 0);
    final cajas = Repositorio.i.cajasActivas;
    final cajaPen = cajas.singleWhere((caja) => caja.moneda == 'PEN');
    final cajaUsd = cajas.singleWhere((caja) => caja.moneda == 'USD');
    final proveedores = Repositorio.i.proveedoresLocales;
    final proveedorVarios = proveedores.singleWhere(
      (proveedor) => proveedor.nombre == 'PROVEEDORES VARIOS',
    );
    final comprobante = Comprobante.vacio()
      ..motor = 'manual'
      ..['numero'] = '';

    await tester.pumpWidget(_app(comprobante));
    await tester.pumpAndSettle();

    expect(comprobante['cajaId'], cajaPen.id);
    expect(
      tester
          .state<FormFieldState<String>>(
            find.byKey(
              ValueKey<String>('proveedor-manual-${proveedorVarios.id}'),
            ),
          )
          .value,
      proveedorVarios.id,
    );

    await tester.tap(find.byKey(ValueKey<String>('caja-manual-${cajaPen.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Caja USD').last);
    await tester.pumpAndSettle();
    expect(comprobante['cajaId'], cajaUsd.id);

    await tester.tap(find.byTooltip('Guardar'));
    await tester.pumpAndSettle();

    expect(comprobante['cajaId'], cajaUsd.id);
    expect(comprobante['moneda'], 'D');
    expect(comprobante['rSocial'], 'PROVEEDORES VARIOS');
  });

  testWidgets('calcula base e IGV del 18 por ciento', (tester) async {
    final comprobante = await _guardarConAfectacion(tester, '18');

    expect(comprobante['biogA'], '100.00');
    expect(comprobante['igvA'], '18.00');
    expect(comprobante['biogB'], '0');
    expect(comprobante.total, 118);
  });

  testWidgets('calcula base e IGV del 10.5 por ciento', (tester) async {
    final comprobante = await _guardarConAfectacion(tester, '10.5');

    expect(comprobante['biogB'], '100.00');
    expect(comprobante['igvB'], '10.50');
    expect(comprobante['biogA'], '0');
    expect(comprobante.total, 110.5);
  });

  testWidgets('guarda exonerado sin calcular IGV', (tester) async {
    final exonerado = await _guardarConAfectacion(tester, 'exonerado');
    expect(exonerado['adNoGrav'], '100.00');
    expect(exonerado['igvA'], '0');
    expect(exonerado.total, 100);
  });

  testWidgets('guarda inafecto sin calcular IGV', (tester) async {
    final inafecto = await _guardarConAfectacion(tester, 'inafecto');
    expect(inafecto['biogC'], '100.00');
    expect(inafecto['igvA'], '0');
    expect(inafecto.total, 100);
  });

  testWidgets('el control presupuestal muestra el nombre del centro local', (
    tester,
  ) async {
    await Repositorio.i.guardarCentroCostoLocal(
      codigo: 'CC01',
      nombre: 'Administración',
    );
    final comprobante = Comprobante.vacio(archivo: '')
      ..motor = 'manual'
      ..['presupuesto'] = 'CC01';

    await tester.pumpWidget(_app(comprobante));
    await tester.pumpAndSettle();

    expect(find.text('Administración'), findsOneWidget);
  });

  testWidgets('el concepto de gasto seleccionable asigna su código', (
    tester,
  ) async {
    await Repositorio.i.guardarConceptoGastoLocal(
      codigo: '60002',
      nombre: 'Servicios',
    );
    final comprobante = Comprobante.vacio(archivo: '')
      ..motor = 'manual'
      ..['ctaGastos'] = '60001';
    await tester.pumpWidget(_app(comprobante));
    await tester.pumpAndSettle();

    expect(find.text('Gastos varios'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey<String>('concepto-gasto-60001')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Servicios'), findsOneWidget);
    await tester.tap(find.text('Servicios'));
    await tester.pumpAndSettle();
    expect(
      tester
          .state<FormFieldState<String>>(
            find.byKey(const ValueKey<String>('concepto-gasto-60002')),
          )
          .value,
      '60002',
    );
    await tester.tap(find.byTooltip('Guardar'));
    await tester.pumpAndSettle();

    expect(comprobante['ctaGastos'], '60002');
  });

  testWidgets('seleccionar proveedor carga sus asignaciones guardadas', (
    tester,
  ) async {
    await Repositorio.i.guardarCentroCostoLocal(
      codigo: 'CC01',
      nombre: 'Administración',
    );
    await Repositorio.i.guardarConceptoGastoLocal(
      codigo: '60002',
      nombre: 'Servicios',
    );
    await Repositorio.i.guardarTerceroLocal(
      const TerceroLocal(
        id: '',
        tipo: 'proveedor',
        tipoDocumento: 'RUC',
        numeroDocumento: '20555555555',
        nombre: 'Proveedor asociado',
        centroCostoCodigo: 'CC01',
        conceptoGastoCodigo: '60002',
      ),
    );
    final comprobante = Comprobante.vacio(archivo: 'factura.pdf')
      ..motor = 'groq';

    await tester.pumpWidget(_app(comprobante));
    await tester.pumpAndSettle();

    final botonProveedor = find.text('Seleccionar proveedor local');
    await tester.scrollUntilVisible(
      botonProveedor,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(botonProveedor);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Proveedor asociado'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Guardar'));
    await tester.pumpAndSettle();

    expect(comprobante['rSocial'], 'Proveedor asociado');
    expect(comprobante['ccosto'], 'CC01');
    expect(comprobante['ctaGastos'], '60002');
  });

  testWidgets('preselecciona asignaciones del proveedor detectado en adjunto', (
    tester,
  ) async {
    await Repositorio.i.guardarCentroCostoLocal(
      codigo: 'CC01',
      nombre: 'Administración',
    );
    await Repositorio.i.guardarConceptoGastoLocal(
      codigo: '60002',
      nombre: 'Servicios',
    );
    await Repositorio.i.guardarTerceroLocal(
      const TerceroLocal(
        id: '',
        tipo: 'proveedor',
        tipoDocumento: 'RUC',
        numeroDocumento: '20555555555',
        nombre: 'Proveedor registrado',
        centroCostoCodigo: 'CC01',
        conceptoGastoCodigo: '60002',
      ),
    );
    final comprobante = Comprobante.vacio(archivo: 'factura.pdf')
      ..motor = 'groq'
      ..['ruc'] = '20-555-555-555'
      ..['rSocial'] = 'Nombre leído por IA';

    await tester.pumpWidget(_app(comprobante));
    await tester.pumpAndSettle();

    expect(
      tester
          .state<FormFieldState<String>>(
            find.byKey(const ValueKey<String>('centrocosto-CC01')),
          )
          .value,
      'CC01',
    );
    expect(
      tester
          .state<FormFieldState<String>>(
            find.byKey(const ValueKey<String>('concepto-gasto-60002')),
          )
          .value,
      '60002',
    );
    expect(comprobante['rSocial'], 'Nombre leído por IA');

    await tester.tap(find.byTooltip('Guardar'));
    await tester.pumpAndSettle();
    expect(comprobante['ccosto'], 'CC01');
    expect(comprobante['ctaGastos'], '60002');
  });

  testWidgets('preselecciona asignaciones de PROVEEDORES VARIOS en manual', (
    tester,
  ) async {
    await Repositorio.i.guardarCentroCostoLocal(
      codigo: 'CC02',
      nombre: 'Operaciones',
    );
    await Repositorio.i.guardarConceptoGastoLocal(
      codigo: '60003',
      nombre: 'Transporte',
    );
    await Repositorio.i.guardarTerceroLocal(
      const TerceroLocal(
        id: 'proveedores-varios',
        tipo: 'proveedor',
        tipoDocumento: 'Otro',
        numeroDocumento: '',
        nombre: 'PROVEEDORES VARIOS',
        centroCostoCodigo: 'CC02',
        conceptoGastoCodigo: '60003',
      ),
    );
    final comprobante = Comprobante.vacio()
      ..motor = 'manual'
      ..['numero'] = '';

    await tester.pumpWidget(_app(comprobante));
    await tester.pumpAndSettle();

    expect(comprobante['ccosto'], 'CC02');
    expect(comprobante['ctaGastos'], '60003');
    expect(
      tester
          .state<FormFieldState<String>>(
            find.byKey(const ValueKey<String>('centrocosto-CC02')),
          )
          .value,
      'CC02',
    );
    expect(
      tester
          .state<FormFieldState<String>>(
            find.byKey(const ValueKey<String>('concepto-gasto-60003')),
          )
          .value,
      '60003',
    );
  });

  testWidgets(
    'el comprobante adjunto permite asignar centro de costos y concepto',
    (tester) async {
      await Repositorio.i.abrirCaja(moneda: 'PEN', montoApertura: 0);
      await Repositorio.i.abrirCaja(moneda: 'USD', montoApertura: 0);
      final cajas = Repositorio.i.cajasActivas;
      final cajaPen = cajas.singleWhere((caja) => caja.moneda == 'PEN');
      final cajaUsd = cajas.singleWhere((caja) => caja.moneda == 'USD');
      await Repositorio.i.guardarCentroCostoLocal(
        codigo: 'CC01',
        nombre: 'Administración',
      );
      await Repositorio.i.guardarConceptoGastoLocal(
        codigo: '60002',
        nombre: 'Servicios',
      );
      final comprobante = Comprobante.vacio(archivo: 'factura.pdf')
        ..motor = 'groq';

      await tester.pumpWidget(_app(comprobante));
      await tester.pumpAndSettle();

      expect(find.text('ASIGNACIÓN LOCAL'), findsOneWidget);
      expect(find.text('Centro de costos'), findsOneWidget);
      expect(find.text('Concepto de gasto'), findsOneWidget);
      expect(find.text('Caja'), findsOneWidget);
      expect(find.text('Gastos varios'), findsOneWidget);
      expect(comprobante['cajaId'], cajaPen.id);

      await tester.tap(find.byKey(const ValueKey<String>('centrocosto-000')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Administración').last);
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('concepto-gasto-60001')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Servicios').last);
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(ValueKey<String>('caja-manual-${cajaPen.id}')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Caja USD').last);
      await tester.pumpAndSettle();
      expect(comprobante['cajaId'], cajaUsd.id);
      expect(comprobante['moneda'], 'S');

      await tester.tap(find.byTooltip('Guardar'));
      await tester.pumpAndSettle();

      expect(comprobante['ccosto'], 'CC01');
      expect(comprobante['ctaGastos'], '60002');
      expect(comprobante['cajaId'], cajaUsd.id);
      expect(comprobante['moneda'], 'S');
    },
  );

  testWidgets('las cuentas contables son editables como texto', (tester) async {
    final comprobante = Comprobante.vacio(archivo: 'factura.pdf')
      ..motor = 'groq';
    await tester.pumpWidget(_app(comprobante));
    await tester.pumpAndSettle();

    for (final clave in <String>[
      'ctaGastos',
      'ctaIgv',
      'ctaOTrib',
      'ctaXPagar',
    ]) {
      await tester.scrollUntilVisible(
        find.byKey(ValueKey<String>('campo-$clave')),
        240,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.byKey(ValueKey<String>('campo-$clave')),
        findsOneWidget,
        reason: '$clave debe ser un campo de texto',
      );
    }
    expect(comprobante['ctaIgv'], '40002');
    expect(comprobante['ctaXPagar'], '42121');
    await tester.enterText(
      find.byKey(const ValueKey<String>('campo-ctaGastos')),
      '60099',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('campo-ctaIgv')),
      '40111',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('campo-ctaOTrib')),
      '40112',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('campo-ctaXPagar')),
      '42122',
    );
    await tester.tap(find.byTooltip('Guardar'));
    await tester.pumpAndSettle();
    expect(comprobante['ctaGastos'], '60099');
    expect(comprobante['ctaIgv'], '40111');
    expect(comprobante['ctaOTrib'], '40112');
    expect(comprobante['ctaXPagar'], '42122');
  });

  testWidgets('usa el origen de gasto configurado al crear un comprobante', (
    tester,
  ) async {
    await Repositorio.i.guardarOrigenesCaja(const OrigenesCaja(gasto: '09'));
    final comprobante = Comprobante.vacio(archivo: 'factura.pdf')
      ..motor = 'groq';

    await tester.pumpWidget(_app(comprobante));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Guardar'));
    await tester.pumpAndSettle();

    expect(comprobante['vouOrigen'], '09');
  });

  testWidgets(
    'usa las cuentas fijas configuradas en el nuevo comprobante para el Excel',
    (tester) async {
      await Repositorio.i.guardarCuentasContablesExcel(<String, String>{
        'ctaGastos': '60101',
        'ctaIgv': '40111',
        'ctaOTrib': '40112',
        'ctaXPagar': '42122',
      });
      final comprobante = Comprobante.vacio(archivo: 'factura.pdf')
        ..motor = 'groq';

      await tester.pumpWidget(_app(comprobante));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Guardar'));
      await tester.pumpAndSettle();

      expect(comprobante['ctaGastos'], '60101');
      expect(comprobante['ctaIgv'], '40111');
      expect(comprobante['ctaOTrib'], '40112');
      expect(comprobante['ctaXPagar'], '42122');
    },
  );

  testWidgets('usa el tipo de cambio diario al registrar un comprobante USD', (
    tester,
  ) async {
    await Repositorio.i.guardarTipoCambioDiario(3.75);
    final comprobante = Comprobante.vacio(archivo: 'factura.pdf')
      ..motor = 'groq'
      ..['moneda'] = 'D';

    await tester.pumpWidget(_app(comprobante));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Guardar'));
    await tester.pumpAndSettle();

    expect(comprobante['tc'], '3.750');
  });
}

Future<Comprobante> _guardarConAfectacion(
  WidgetTester tester,
  String afectacion,
) async {
  final comprobante = Comprobante.vacio(archivo: '')
    ..motor = 'manual'
    ..['numero'] = '00000000';
  await tester.pumpWidget(_app(comprobante));
  await tester.pumpAndSettle();

  await tester.enterText(find.byType(TextField).first, '100');
  await tester.pumpAndSettle();
  if (afectacion != '18') {
    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('afectacion-18')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('afectacion-18')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_etiquetaAfectacion(afectacion)).last);
    await tester.pumpAndSettle();
  }
  await tester.tap(find.byTooltip('Guardar'));
  await tester.pumpAndSettle();
  return comprobante;
}

String _etiquetaAfectacion(String afectacion) => switch (afectacion) {
  '10.5' => 'Gravado 10.5%',
  'exonerado' => 'Exonerado',
  'inafecto' => 'Inafecto',
  _ => 'Gravado 18%',
};

Widget _app(Comprobante comprobante) => MaterialApp(
  theme: temaEfsiscont(),
  home: ComprobanteFormPage(comprobante: comprobante, nuevo: true),
);
