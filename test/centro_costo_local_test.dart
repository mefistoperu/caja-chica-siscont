import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:efsiscont_flutter/src/storage/repositorio.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  Directory? directorioTemporal;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    directorioTemporal = await Directory.systemTemp.createTemp(
      'efsiscont_centros_costo_test_',
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

  test('guarda, actualiza y elimina centros de costo localmente', () async {
    await Repositorio.i.guardarCentroCostoLocal(
      codigo: '  CC01 ',
      nombre: ' Administración ',
    );
    expect(Repositorio.i.centrosCostoLocales.single.codigo, 'CC01');
    expect(Repositorio.i.centrosCostoLocales.single.nombre, 'Administración');

    await Repositorio.i.guardarCentroCostoLocal(
      codigo: 'CC02',
      nombre: 'Administración general',
      codigoOriginal: 'CC01',
    );
    expect(Repositorio.i.centrosCostoLocales.single.codigo, 'CC02');

    await Repositorio.i.eliminarCentroCostoLocal('cc02');
    expect(Repositorio.i.centrosCostoLocales, isEmpty);
  });

  test('rechaza códigos de centro de costo duplicados', () async {
    await Repositorio.i.guardarCentroCostoLocal(
      codigo: 'CC01',
      nombre: 'Administración',
    );

    await expectLater(
      Repositorio.i.guardarCentroCostoLocal(
        codigo: 'cc01',
        nombre: 'Otro centro',
      ),
      throwsArgumentError,
    );
  });
}
