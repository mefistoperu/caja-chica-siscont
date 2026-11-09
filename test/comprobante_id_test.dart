import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:efsiscont_flutter/src/models/comprobante.dart';
import 'package:efsiscont_flutter/src/storage/repositorio.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  Directory? directorioTemporal;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    directorioTemporal = await Directory.systemTemp.createTemp(
      'efsiscont_test_',
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

  test('guarda comprobantes sin ID como registros independientes', () async {
    final primero = Comprobante.vacio()..id = '';
    final segundo = Comprobante.vacio()..id = '';

    await Repositorio.i.actualizarComprobante(primero);
    await Repositorio.i.actualizarComprobante(segundo);

    final guardados = Repositorio.i.comprobantes;
    expect(guardados, hasLength(2));
    expect(guardados[0].id, isNotEmpty);
    expect(guardados[1].id, isNotEmpty);
    expect(guardados[0].id, isNot(guardados[1].id));
  });

  test('actualiza el mismo comprobante por RUC y numero normalizado', () async {
    final primero = Comprobante.vacio()
      ..['ruc'] = '20123456789'
      ..['doc'] = '01'
      ..['numero'] = 'F001-000005823'
      ..['vouNumero'] = '12'
      ..['glosa'] = 'Detalle anterior';
    await Repositorio.i.actualizarComprobante(primero);

    final nuevaCaptura = Comprobante.vacio(archivo: 'nueva-captura.pdf')
      ..['ruc'] = '20123456789'
      ..['doc'] = '01'
      ..['numero'] = 'F001 000005823'
      ..['vouNumero'] = '99'
      ..['glosa'] = 'Detalle actualizado';
    await Repositorio.i.marcarEnviado(primero.id, porWhatsApp: true);
    await Repositorio.i.actualizarComprobante(nuevaCaptura);

    final guardados = Repositorio.i.comprobantes;
    expect(guardados, hasLength(1));
    expect(guardados.single.id, primero.id);
    expect(guardados.single['vouNumero'], '12');
    expect(guardados.single['glosa'], 'Detalle actualizado');
    expect(guardados.single.archivo, 'nueva-captura.pdf');
    expect(guardados.single.estadoWhatsapp, 'pendiente');
    expect(guardados.single.fechaRegistroTexto, primero.fechaRegistroTexto);
  });

  test('guarda el estado enviado independiente por canal', () async {
    final comprobante = Comprobante.vacio()
      ..['ruc'] = '20123456789'
      ..['doc'] = '01'
      ..['numero'] = 'F001-222';
    await Repositorio.i.actualizarComprobante(comprobante);

    await Repositorio.i.marcarEnviado(comprobante.id, porWhatsApp: true);

    final guardado = Repositorio.i.comprobantes.single;
    expect(guardado.estadoWhatsapp, 'enviado');
    expect(guardado.estadoSiscont, 'pendiente');
  });

  test('al inicializar elimina duplicados guardados anteriormente', () async {
    final primero = Comprobante.vacio()
      ..['ruc'] = '20123456789'
      ..['doc'] = '01'
      ..['numero'] = 'F001-123';
    final segundo = Comprobante.vacio()
      ..['ruc'] = '20123456789'
      ..['doc'] = '01'
      ..['numero'] = 'F001-123';
    await Repositorio.i.guardarComprobantes(<Comprobante>[primero, segundo]);

    await Repositorio.i.inicializar();

    expect(Repositorio.i.comprobantes, hasLength(1));
    expect(Repositorio.i.comprobantes.single.id, primero.id);
  });

  test(
    'mantiene documentos distintos aunque pertenezcan al mismo proveedor',
    () async {
      final primero = Comprobante.vacio()
        ..['ruc'] = '20123456789'
        ..['doc'] = '01'
        ..['numero'] = 'F001-123';
      final segundo = Comprobante.vacio()
        ..['ruc'] = '20123456789'
        ..['doc'] = '01'
        ..['numero'] = 'F001-124';

      await Repositorio.i.actualizarComprobante(primero);
      await Repositorio.i.actualizarComprobante(segundo);

      expect(Repositorio.i.comprobantes, hasLength(2));
    },
  );
}
