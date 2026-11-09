import 'dart:convert';
import 'dart:io';

import 'package:efsiscont_flutter/src/models/comprobante.dart';
import 'package:efsiscont_flutter/src/models/movimiento_caja.dart';
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
      'efsiscont_reporte_test_',
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

  testWidgets('el gráfico muestra productos más comprados y agrupa Otros', (
    tester,
  ) async {
    final compras = <Comprobante>[
      _conProducto(_compra('Proveedor A', '20100000001', 600), 'Producto A', 6),
      _conProducto(_compra('Proveedor B', '20100000002', 500), 'Producto B', 5),
      _conProducto(_compra('Proveedor C', '20100000003', 400), 'Producto C', 4),
      _conProducto(_compra('Proveedor D', '20100000004', 300), 'Producto D', 3),
      _conProducto(_compra('Proveedor E', '20100000005', 200), 'Producto E', 2),
      _conProducto(_compra('Proveedor F', '20100000006', 100), 'Producto F', 1),
      _conProducto(_compra('Proveedor G', '20100000007', 50), 'Producto G', .5),
      _conProducto(_compra('Proveedor A', '20100000001', 50), 'Producto A', .5),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ReportePage(items: compras)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('PRODUCTOS MÁS COMPRADOS'), findsOneWidget);
    expect(find.text('Producto E'), findsWidgets);
    expect(find.text('Otros'), findsOneWidget);
    expect(find.textContaining('6.50 ítem(s)'), findsOneWidget);
    expect(find.textContaining('(29.5%)'), findsOneWidget);
    expect(
      find.text('Total unidades/ítems: 22.00 · Importe: S/ 2200.00'),
      findsOneWidget,
    );
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('el reporte filtra por centro de costos', (tester) async {
    if (Repositorio.i.cajaActiva == null) {
      await Repositorio.i.abrirCaja(moneda: 'PEN', montoApertura: 0);
    }
    final caja = Repositorio.i.cajaActiva!;
    final compraA = _conProducto(
      _compra('Proveedor A', '20100000030', 100)
        ..['ccosto'] = 'CC01'
        ..['cajaId'] = caja.id,
      'Producto A',
      2,
    );
    final compraB = _conProducto(
      _compra('Proveedor B', '20100000031', 50)
        ..['ccosto'] = 'CC02'
        ..['cajaId'] = caja.id,
      'Producto B',
      1,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReportePage(
            items: <Comprobante>[compraA, compraB],
            initialCajaId: '',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Todos los centros de costos'), findsOneWidget);
    expect(find.text('Producto A'), findsOneWidget);
    expect(find.text('Producto B'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('reporte-centro-')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CC02').last);
    await tester.pumpAndSettle();

    expect(find.text('Producto A'), findsNothing);
    expect(find.text('Producto B'), findsWidgets);
    expect(
      find.text('Total unidades/ítems: 1.00 · Importe: S/ 50.00'),
      findsOneWidget,
    );
    expect(find.text('Buscar por rango de fechas'), findsOneWidget);
  });

  testWidgets('el desglose de proveedores incluye gastos manuales de Caja', (
    tester,
  ) async {
    await Repositorio.i.abrirCaja(moneda: 'PEN', montoApertura: 0);
    final caja = Repositorio.i.cajaActiva!;
    final compra = _conProducto(
      _compra('Proveedor de compra', '20100000032', 100)..['cajaId'] = caja.id,
      'Producto comprado',
      1,
    );
    await Repositorio.i.registrarMovimientoCaja(
      MovimientoCaja(
        id: 'gasto-manual-reporte',
        cajaId: caja.id,
        moneda: 'PEN',
        tipo: 'gasto',
        tipoMovimiento: 'EFECTIVO',
        concepto: 'Gasto manual',
        monto: 30,
        fecha: DateTime.now(),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ReportePage(items: <Comprobante>[compra])),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Producto comprado'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('reporte-desglose-productos')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Proveedores y gastos').last);
    await tester.pumpAndSettle();

    expect(find.text('Proveedor de compra'), findsOneWidget);
    expect(find.text('Gasto Caja · EFECTIVO'), findsOneWidget);
    expect(find.text('Total compras y gastos: S/ 130.00'), findsOneWidget);
  });

  testWidgets(
    'el rango de fechas es opcional y filtra productos al activarlo',
    (tester) async {
      final compraActual = _conProducto(
        _compra('Proveedor actual', '20100000040', 100),
        'Producto actual',
        1,
      );
      final compraAntigua = _conProducto(
        _compra('Proveedor antiguo', '20100000041', 50)
          ..creado = '2024-01-15T12:00:00.000',
        'Producto antiguo',
        1,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReportePage(
              items: <Comprobante>[compraActual, compraAntigua],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Producto actual'), findsWidgets);
      expect(find.text('Producto antiguo'), findsWidgets);
      expect(find.text('RANGO DE FECHAS'), findsNothing);

      await tester.tap(
        find.byKey(const ValueKey<String>('reporte-toggle-fechas')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Producto actual'), findsWidgets);
      expect(find.text('Producto antiguo'), findsNothing);
      expect(find.text('RANGO DE FECHAS'), findsOneWidget);
    },
  );

  testWidgets('el filtro del reporte incluye cajas abiertas y cerradas', (
    tester,
  ) async {
    await Repositorio.i.abrirCaja(moneda: 'PEN', montoApertura: 0);
    final cajaCerrada = Repositorio.i.cajaActiva!;
    await Repositorio.i.cerrarCaja(cajaId: cajaCerrada.id);
    await Repositorio.i.abrirCaja(moneda: 'USD', montoApertura: 0);
    final cajaAbierta = Repositorio.i.cajaActiva!;
    final compras = <Comprobante>[
      _compra('Proveedor PEN', '20100000001', 100)..['cajaId'] = cajaCerrada.id,
      _compra('Proveedor USD', '20100000002', 200)..['cajaId'] = cajaAbierta.id,
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ReportePage(items: compras)),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Se incluirán 1 comprobante(s) de Caja USD (abierta).'),
      findsOneWidget,
    );
    expect(find.text('Proveedor USD'), findsWidgets);
    expect(find.text('Proveedor PEN'), findsNothing);
    expect(find.text('RANGO DE FECHAS'), findsNothing);

    await tester.tap(
      find.byKey(ValueKey<String>('reporte-caja-${cajaAbierta.id}')),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Caja PEN · Cerrada'), findsOneWidget);
    await tester.tap(find.textContaining('Caja PEN · Cerrada'));
    await tester.pumpAndSettle();

    expect(find.text('Proveedor PEN'), findsWidgets);
    expect(find.text('Proveedor USD'), findsNothing);
  });

  testWidgets('la caja cerrada habilita envíos para todo su período', (
    tester,
  ) async {
    const cajaId = 'caja-cerrada-anterior';
    const apertura = '2024-02-01T10:00:00.000';
    const cierre = '2024-02-03T18:00:00.000';
    final preferencias = await SharedPreferences.getInstance();
    await preferencias.setString(
      'cierres_caja',
      jsonEncode(<Map<String, Object>>[
        <String, Object>{
          'id': cajaId,
          'moneda': 'PEN',
          'montoApertura': 100,
          'fechaApertura': apertura,
          'montoCierre': 150,
          'fechaCierre': cierre,
          'voucher': 12,
        },
      ]),
    );
    final compra = _compra('Proveedor de caja cerrada', '20100000010', 50)
      ..creado = '2024-02-02T12:00:00.000'
      ..['cajaId'] = cajaId;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ReportePage(items: <Comprobante>[compra])),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Proveedor de caja cerrada'), findsWidgets);
    expect(find.text('RANGO DE FECHAS'), findsNothing);
    expect(
      find.text('Se incluirán 1 comprobante(s) de Caja PEN (cerrada).'),
      findsOneWidget,
    );
    expect(find.textContaining('EXCEL / WHATSAPP · CAJA PEN'), findsOneWidget);
    expect(find.textContaining('ENVIAR A SISCONT · CAJA PEN'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('reporte-toggle-fechas')),
    );
    await tester.pumpAndSettle();
    expect(find.text('RANGO DE FECHAS'), findsOneWidget);
    expect(find.text('Buscar por rango de fechas'), findsNothing);
    expect(find.text('Ocultar rango de fechas'), findsOneWidget);
    expect(find.text('Proveedor de caja cerrada'), findsNothing);
  });

  testWidgets('el reporte abre en la rendición de la caja abierta actual', (
    tester,
  ) async {
    await Repositorio.i.abrirCaja(moneda: 'PEN', montoApertura: 0);
    final cajaActual = Repositorio.i.cajaActiva!;
    final compraActual = _compra(
      'Proveedor rendición actual',
      '20100000020',
      75,
    )..['cajaId'] = cajaActual.id;
    final compraAnterior = _compra('Proveedor otra caja', '20100000021', 25)
      ..['cajaId'] = 'otra-caja';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReportePage(items: <Comprobante>[compraActual, compraAnterior]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('RENDICIÓN ACTUAL'), findsOneWidget);
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.text('Cuentas por cobrar'), findsNothing);
    expect(find.text('Cuentas por pagar'), findsNothing);
    expect(find.text('Proveedor rendición actual'), findsWidgets);
    expect(find.text('Proveedor otra caja'), findsNothing);
    expect(find.text('Buscar por rango de fechas'), findsOneWidget);
    expect(find.text('RANGO DE FECHAS'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey<String>('reporte-toggle-fechas')),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();

    expect(find.text('Proveedor otra caja'), findsWidgets);
    expect(find.text('RANGO DE FECHAS'), findsOneWidget);
    expect(find.text('Ocultar rango de fechas'), findsOneWidget);
  });
}

Comprobante _compra(String proveedor, String ruc, double monto) =>
    Comprobante.vacio()
      ..creado = DateTime.now().toIso8601String()
      ..['rSocial'] = proveedor
      ..['ruc'] = ruc
      ..['biogA'] = monto.toStringAsFixed(2);

Comprobante _conProducto(
  Comprobante comprobante,
  String nombre,
  double cantidad,
) {
  comprobante['detalleItems'] = jsonEncode(<Map<String, String>>[
    <String, String>{
      'descripcion': nombre,
      'cantidad': cantidad.toString(),
      'precio': (comprobante.total / cantidad).toStringAsFixed(2),
      'importe': comprobante.total.toStringAsFixed(2),
    },
  ]);
  return comprobante;
}
