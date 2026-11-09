import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:efsiscont_flutter/src/models/caja_sesion.dart';
import 'package:efsiscont_flutter/src/models/comprobante.dart';
import 'package:efsiscont_flutter/src/models/movimiento_caja.dart';
import 'package:efsiscont_flutter/src/models/origenes_caja.dart';
import 'package:efsiscont_flutter/src/models/tercero_local.dart';
import 'package:efsiscont_flutter/src/models/tipo_movimiento_caja.dart';
import 'package:efsiscont_flutter/src/storage/repositorio.dart';
import 'package:efsiscont_flutter/src/pages/cuentas_contables_page.dart';
import 'package:efsiscont_flutter/src/pages/origenes_caja_page.dart';
import 'package:efsiscont_flutter/src/pages/tipos_movimiento_caja_page.dart';
import 'package:efsiscont_flutter/src/theme/tema.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  Directory? directorioTemporal;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    directorioTemporal = await Directory.systemTemp.createTemp(
      'efsiscont_caja_test_',
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

  test('guarda y elimina ingresos de caja localmente', () async {
    await Repositorio.i.abrirCaja(moneda: 'USD', montoApertura: 0);
    final caja = Repositorio.i.cajaActiva!;
    final ingreso = MovimientoCaja(
      id: 'ingreso-1',
      cajaId: caja.id,
      moneda: 'USD',
      tipoMovimientoId: 'yape',
      tipoMovimiento: 'Yape',
      concepto: 'Cobro de servicio',
      monto: 125.5,
      fecha: DateTime(2026, 10, 28),
    );

    await Repositorio.i.registrarMovimientoCaja(ingreso);
    final guardado = Repositorio.i.movimientosCaja.single;

    expect(guardado.moneda, 'USD');
    expect(guardado.tipoMovimientoId, 'yape');
    expect(guardado.tipoMovimiento, 'Yape');
    expect(guardado.concepto, 'Cobro de servicio');
    expect(guardado.monto, 125.5);
    expect(guardado.fecha, DateTime(2026, 10, 28));

    await Repositorio.i.eliminarMovimientoCaja(ingreso.id);
    expect(Repositorio.i.movimientosCaja, isEmpty);
  });

  test('el ingreso de Caja registra y vincula su cliente local', () async {
    await Repositorio.i.abrirCaja(moneda: 'PEN', montoApertura: 0);
    final caja = Repositorio.i.cajaActiva!;
    final ingreso = MovimientoCaja(
      id: 'ingreso-cliente-1',
      cajaId: caja.id,
      moneda: 'PEN',
      tipo: 'ingreso',
      concepto: 'Cobro de servicio',
      monto: 75,
      fecha: DateTime(2026, 11, 2),
    );

    await Repositorio.i.registrarIngresoCajaConCliente(
      ingreso,
      nombre: 'Cliente de Caja',
      tipoDocumento: 'DNI',
      numeroDocumento: '12345678',
    );

    final cliente = Repositorio.i.tercerosLocales.singleWhere(
      (item) => item.numeroDocumento == '12345678',
    );
    final movimiento = Repositorio.i.movimientosCaja.single;
    expect(cliente.tipo, 'cliente');
    expect(cliente.nombre, 'Cliente de Caja');
    expect(cliente.numeroDocumento, '12345678');
    expect(movimiento.terceroId, cliente.id);
    expect(movimiento.terceroNombre, cliente.nombre);
    expect(movimiento.terceroTipoDocumento, 'DNI');
    expect(movimiento.terceroDocumento, '12345678');
    expect(Repositorio.i.saldoCalculadoCaja(caja), 75);
  });

  test(
    'guarda clientes y proveedores locales sin duplicar documentos',
    () async {
      final cliente = await Repositorio.i.guardarTerceroLocal(
        const TerceroLocal(
          id: '',
          tipo: 'cliente',
          tipoDocumento: 'RUC',
          numeroDocumento: '20123456789',
          nombre: 'Cliente Local',
        ),
      );
      final proveedor = await Repositorio.i.guardarTerceroLocal(
        const TerceroLocal(
          id: '',
          tipo: 'proveedor',
          tipoDocumento: 'RUC',
          numeroDocumento: '20-123-456789',
          nombre: 'Proveedor Local',
        ),
      );

      expect(Repositorio.i.tercerosLocales, hasLength(2));
      expect(proveedor.id, cliente.id);
      expect(
        Repositorio.i.tercerosLocales
            .singleWhere((item) => item.id == cliente.id)
            .tipo,
        'ambos',
      );
      expect(
        Repositorio.i.proveedoresLocales
            .singleWhere((item) => item.id == cliente.id)
            .nombre,
        'Proveedor Local',
      );
    },
  );

  test('registra proveedor desde comprobante localmente', () async {
    final comprobante = Comprobante.vacio()
      ..['ruc'] = '20123456789'
      ..['rSocial'] = 'Proveedor del comprobante'
      ..['tipDocIden'] = '6';

    await Repositorio.i.guardarProveedorDesdeComprobante(comprobante);

    final proveedor = Repositorio.i.proveedoresLocales.singleWhere(
      (item) => item.numeroDocumento == '20123456789',
    );
    expect(proveedor.tipoDocumento, 'RUC');
    expect(proveedor.numeroDocumento, '20123456789');
  });

  test('pre-guarda Proveedores Varios como proveedor local predeterminado', () {
    final proveedor = Repositorio.i.proveedoresLocales.singleWhere(
      (item) => item.nombre == 'PROVEEDORES VARIOS',
    );

    expect(proveedor.tipoDocumento, 'Otro');
    expect(proveedor.numeroDocumento, isEmpty);
  });

  test('pre-guarda Gastos varios 60001 y permite agregar conceptos', () async {
    final predeterminado = Repositorio.i.conceptosGastoLocales.single;
    expect(predeterminado.codigo, '60001');
    expect(predeterminado.nombre, 'Gastos varios');

    await Repositorio.i.inicializar();
    expect(Repositorio.i.conceptosGastoLocales, hasLength(1));
    expect(Repositorio.i.conceptosGastoLocales.single.codigo, '60001');
    expect(Repositorio.i.conceptosGastoLocales.single.nombre, 'Gastos varios');

    await Repositorio.i.guardarConceptoGastoLocal(
      codigo: '60002',
      nombre: 'Servicios',
    );
    expect(Repositorio.i.conceptosGastoLocales, hasLength(2));

    await Repositorio.i.eliminarConceptoGastoLocal('60002');
    expect(Repositorio.i.conceptosGastoLocales, hasLength(1));
    await expectLater(
      Repositorio.i.eliminarConceptoGastoLocal('60001'),
      throwsStateError,
    );
  });

  test(
    'el correlativo local de comprobantes 00 inicia en cero y aumenta',
    () async {
      expect(await Repositorio.i.consumirNumeroOtroComprobante(), '00000000');
      expect(await Repositorio.i.consumirNumeroOtroComprobante(), '00000001');
    },
  );

  test('crea el tipo de cambio diario con 1.000 si no existe', () async {
    expect(Repositorio.i.tipoCambioDiario, 1);
    expect(Repositorio.i.tiposCambioDiarios.values, contains(1));
  });

  test('guarda tipo de cambio por día y conserva el historial', () async {
    final ayer = DateTime.now().subtract(const Duration(days: 1));
    await Repositorio.i.guardarTipoCambioDiario(3.75, fecha: ayer);
    await Repositorio.i.guardarTipoCambioDiario(3.82);

    expect(Repositorio.i.tipoCambioDiario, 3.82);
    expect(
      Repositorio
          .i
          .tiposCambioDiarios['${ayer.year.toString().padLeft(4, '0')}-'
          '${ayer.month.toString().padLeft(2, '0')}-'
          '${ayer.day.toString().padLeft(2, '0')}'],
      3.75,
    );
  });

  test(
    'consulta SUNAT solo cuando el tipo de cambio es 1.000 o menor',
    () async {
      var consultas = 0;
      final actualizo = await Repositorio.i
          .actualizarTipoCambioDiarioSiNecesario(
            consultar: (_) async {
              consultas++;
              return 3.467;
            },
          );

      expect(actualizo, isTrue);
      expect(Repositorio.i.tipoCambioDiario, 3.467);

      final segundaActualizacion = await Repositorio.i
          .actualizarTipoCambioDiarioSiNecesario(
            consultar: (_) async {
              consultas++;
              return 3.5;
            },
          );

      expect(segundaActualizacion, isFalse);
      expect(consultas, 1);
      expect(Repositorio.i.tipoCambioDiario, 3.467);
    },
  );

  test('conserva ingresos existentes sin datos de apertura', () async {
    final preferencias = await SharedPreferences.getInstance();
    await preferencias.setString(
      'ingresos_caja',
      jsonEncode(<Map<String, Object>>[
        <String, Object>{
          'id': 'anterior-1',
          'moneda': 'PEN',
          'concepto': 'Ingreso guardado anteriormente',
          'monto': 42.5,
          'fecha': '2026-10-28',
        },
      ]),
    );

    final movimiento = Repositorio.i.movimientosCaja.single;

    expect(movimiento.tipo, 'ingreso');
    expect(movimiento.cajaId, isEmpty);
    expect(movimiento.concepto, 'Ingreso guardado anteriormente');
    expect(movimiento.monto, 42.5);
  });

  test(
    'guarda el origen de gasto y usa 01 como valor predeterminado',
    () async {
      expect(Repositorio.i.origenesCaja.gasto, '01');

      await Repositorio.i.guardarOrigenesCaja(const OrigenesCaja(gasto: '02'));

      expect(Repositorio.i.origenesCaja.gasto, '02');
    },
  );

  test('el origen de gasto predeterminado es 01', () {
    expect(Repositorio.i.origenesCaja.gasto, '01');
  });

  testWidgets('el mantenimiento muestra solo el origen de gasto en 01', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: temaEfsiscont(), home: const OrigenesCajaPage()),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TextFormField), findsOneWidget);
    expect(find.text('Origen ingreso'), findsNothing);
    expect(find.text('Origen gasto'), findsOneWidget);
    expect(
      tester.widget<TextFormField>(find.byType(TextFormField)).controller!.text,
      '01',
    );
  });

  test('guarda las cuentas fijas que se aplican al Excel de compras', () async {
    expect(Repositorio.i.cuentasContablesExcel, <String, String>{
      'ctaGastos': '60001',
      'ctaIgv': '40002',
      'ctaOTrib': '40112',
      'ctaXPagar': '42121',
    });

    await Repositorio.i.guardarCuentasContablesExcel(<String, String>{
      'ctaGastos': '60101',
      'ctaIgv': '40111',
      'ctaOTrib': '40112',
    });

    expect(Repositorio.i.cuentasContablesExcel, <String, String>{
      'ctaGastos': '60101',
      'ctaIgv': '40111',
      'ctaOTrib': '40112',
      'ctaXPagar': '42121',
    });
  });

  testWidgets('el mantenimiento de cuentas es un formulario fijo', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: temaEfsiscont(), home: const CuentasContablesPage()),
    );
    await tester.pumpAndSettle();

    expect(find.text('PARÁMETROS CONTABLES'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(3));
    expect(find.byType(ListTile), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey<String>('cuenta-fija-ctaGastos')),
      '60101',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('cuenta-fija-ctaIgv')),
      '40111',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('cuenta-fija-ctaOTrib')),
      '40112',
    );
    expect(find.text('Cuenta por pagar'), findsNothing);
    await tester.tap(find.text('GUARDAR PARÁMETROS'));
    await tester.pumpAndSettle();

    expect(Repositorio.i.cuentasContablesExcel['ctaGastos'], '60101');
    expect(Repositorio.i.cuentasContablesExcel['ctaIgv'], '40111');
    expect(Repositorio.i.cuentasContablesExcel['ctaOTrib'], '40112');
    expect(Repositorio.i.cuentasContablesExcel['ctaXPagar'], '42121');
  });

  test('inicializa el tipo EFECTIVO con cuenta fija 60002', () async {
    final efectivo = Repositorio.i.tiposMovimientoCaja.single;

    expect(efectivo.nombre, 'EFECTIVO');
    expect(efectivo.cuentaIngreso, '60002');
    expect(efectivo.cuentaGasto, '60002');

    await expectLater(
      Repositorio.i.eliminarTipoMovimientoCaja(efectivo.id),
      throwsStateError,
    );
  });

  testWidgets('la configuración de tipo de movimiento oculta las cuentas', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: temaEfsiscont(),
        home: const TiposMovimientoCajaPage(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('EFECTIVO'), findsOneWidget);
    expect(find.text('Cuenta contable de ingreso'), findsNothing);
    expect(find.text('Cuenta contable de gasto'), findsNothing);
    await tester.tap(find.text('EFECTIVO'));
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsOneWidget);
    expect(find.text('La cuenta contable asignada es 60002.'), findsOneWidget);
  });

  test('guarda tipos con cuenta contable fija 60002', () async {
    final tipo = TipoMovimientoCaja(
      id: 'yape',
      nombre: 'Yape',
      cuentaIngreso: '104101',
      cuentaGasto: '639901',
    );
    await Repositorio.i.guardarTipoMovimientoCaja(tipo);
    await Repositorio.i.guardarTipoMovimientoCaja(
      const TipoMovimientoCaja(
        id: 'yape',
        nombre: 'Yape',
        cuentaIngreso: '104102',
        cuentaGasto: '639902',
      ),
    );

    expect(Repositorio.i.tiposMovimientoCaja, hasLength(2));
    final yape = Repositorio.i.tiposMovimientoCaja.singleWhere(
      (item) => item.id == 'yape',
    );
    expect(yape.cuentaIngreso, '60002');
    expect(yape.cuentaGasto, '60002');

    await Repositorio.i.eliminarTipoMovimientoCaja('yape');
    expect(
      Repositorio.i.tiposMovimientoCaja.map((item) => item.nombre),
      <String>['EFECTIVO'],
    );
  });

  test(
    'apertura calcula el cierre con ingresos y gastos y asigna voucher',
    () async {
      await Repositorio.i.abrirCaja(moneda: 'PEN', montoApertura: 0);
      final caja = Repositorio.i.cajaActiva!;

      await expectLater(
        Repositorio.i.abrirCaja(moneda: 'PEN', montoApertura: 0),
        throwsStateError,
      );

      await Repositorio.i.registrarMovimientoCaja(
        MovimientoCaja(
          id: 'ingreso-1',
          cajaId: caja.id,
          moneda: 'PEN',
          tipo: 'ingreso',
          concepto: 'Cobro',
          monto: 150,
          fecha: DateTime.now(),
        ),
      );
      await Repositorio.i.registrarMovimientoCaja(
        MovimientoCaja(
          id: 'gasto-1',
          cajaId: caja.id,
          moneda: 'PEN',
          tipo: 'gasto',
          concepto: 'Compra menor',
          monto: 35.5,
          fecha: DateTime.now(),
        ),
      );

      expect(Repositorio.i.saldoCalculadoCaja(caja), 114.5);
      final cierre = await Repositorio.i.cerrarCaja();
      expect(cierre.montoCierre, 114.5);
      expect(cierre.voucher, 1);
      expect(cierre.estaAbierta, isFalse);
      expect(Repositorio.i.cajaActiva, isNull);
      expect(Repositorio.i.cierresCaja, hasLength(1));
    },
  );

  test('permite una caja por moneda y cerrar una sin cerrar la otra', () async {
    await Repositorio.i.abrirCaja(moneda: 'PEN', montoApertura: 10);
    await Repositorio.i.abrirCaja(moneda: 'USD', montoApertura: 20);

    expect(Repositorio.i.cajasActivas, hasLength(2));
    expect(
      Repositorio.i.cajasActivas.map((caja) => caja.moneda).toSet(),
      <String>{'PEN', 'USD'},
    );
    await expectLater(
      Repositorio.i.abrirCaja(moneda: 'PEN', montoApertura: 0),
      throwsStateError,
    );

    final soles = Repositorio.i.cajaActivaParaMoneda('PEN')!;
    final dolares = Repositorio.i.cajaActivaParaMoneda('USD')!;
    for (final (caja, moneda, id) in <(CajaSesion, String, String)>[
      (soles, 'PEN', 'movimiento-pen'),
      (dolares, 'USD', 'movimiento-usd'),
    ]) {
      await Repositorio.i.registrarMovimientoCaja(
        MovimientoCaja(
          id: id,
          cajaId: caja.id,
          moneda: moneda,
          concepto: 'Ingreso $moneda',
          monto: 5,
          fecha: DateTime.now(),
        ),
      );
    }

    await Repositorio.i.cerrarCaja(cajaId: soles.id);
    expect(Repositorio.i.cajasActivas, hasLength(1));
    expect(Repositorio.i.cajaActiva?.id, dolares.id);
    expect(Repositorio.i.monedaCajaPorId(soles.id), 'PEN');
    expect(Repositorio.i.monedaCajaPorId(dolares.id), 'USD');
    expect(Repositorio.i.cierresCaja.single.id, soles.id);
  });

  test('el comprobante actualiza su salida sin duplicarla', () async {
    await Repositorio.i.abrirCaja(moneda: 'PEN', montoApertura: 100);
    final caja = Repositorio.i.cajaActiva!;
    final comprobante = Comprobante.vacio()
      ..['numero'] = 'F001-123'
      ..['biogA'] = '50';

    await Repositorio.i.guardarComprobanteConGasto(
      comprobante,
      MovimientoCaja(
        id: 'gasto-${comprobante.id}',
        cajaId: caja.id,
        moneda: 'PEN',
        tipo: 'gasto',
        comprobanteId: comprobante.id,
        concepto: 'Comprobante F001-123',
        monto: 50,
        fecha: DateTime.now(),
      ),
    );
    comprobante['biogA'] = '70';
    await Repositorio.i.guardarComprobanteConGasto(
      comprobante,
      MovimientoCaja(
        id: 'gasto-${comprobante.id}',
        cajaId: caja.id,
        moneda: 'PEN',
        tipo: 'gasto',
        comprobanteId: comprobante.id,
        concepto: 'Comprobante F001-123',
        monto: 70,
        fecha: DateTime.now(),
      ),
    );

    expect(Repositorio.i.movimientosCaja, hasLength(1));
    expect(Repositorio.i.movimientosCaja.single.monto, 70);
    expect(Repositorio.i.saldoCalculadoCaja(caja), 30);
    expect(Repositorio.i.comprobantes.single['biogA'], '70');
  });

  test(
    'una salida vinculada se conserva al cerrar y elimina se bloquea',
    () async {
      await Repositorio.i.abrirCaja(moneda: 'PEN', montoApertura: 100);
      final caja = Repositorio.i.cajaActiva!;
      final comprobante = Comprobante.vacio();
      await Repositorio.i.guardarComprobanteConGasto(
        comprobante,
        MovimientoCaja(
          id: 'gasto-${comprobante.id}',
          cajaId: caja.id,
          moneda: 'PEN',
          tipo: 'gasto',
          comprobanteId: comprobante.id,
          concepto: 'Comprobante',
          monto: 10,
          fecha: DateTime.now(),
        ),
      );
      await Repositorio.i.cerrarCaja();

      await expectLater(
        Repositorio.i.eliminarComprobante(comprobante.id),
        throwsStateError,
      );
      expect(Repositorio.i.comprobantes, hasLength(1));
      expect(Repositorio.i.cierresCaja.single.montoCierre, 90);
    },
  );

  test('el correlativo del voucher se reinicia al cambiar de mes', () {
    final abril = DateTime(2026, 4, 30);
    final cierres = List<CajaSesion>.generate(
      10,
      (indice) => CajaSesion(
        id: 'abril-$indice',
        moneda: 'PEN',
        montoApertura: 0,
        fechaApertura: abril,
      ).cerrar(fecha: abril, monto: 0, voucher: indice + 1),
    );

    expect(
      Repositorio.siguienteVoucherCaja(cierres, DateTime(2026, 4, 30)),
      11,
    );
    expect(Repositorio.siguienteVoucherCaja(cierres, DateTime(2026, 5, 1)), 1);
  });
}
