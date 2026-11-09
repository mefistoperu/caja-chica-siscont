import 'dart:io';

import 'package:efsiscont_flutter/src/models/conexion.dart';
import 'package:efsiscont_flutter/src/storage/repositorio.dart';
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
      'caja_chica_conexiones_test_',
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

  test('guarda y edita conexiones localmente conservando la clave', () async {
    final nueva = await Repositorio.i.guardarConexionLocal(
      const Conexion(
        id: 0,
        nombre: 'Empresa local',
        host: 'localhost',
        data: 'siscont',
        usuario: 'usuario',
        pass: 'secreto',
        tipo: 'MYSQL',
        imagen: '',
        estado: 0,
      ),
    );
    expect(nueva.id, greaterThan(0));
    expect(Repositorio.i.conexionesLocales.single.pass, 'secreto');

    await Repositorio.i.guardarConexionLocal(
      nueva.copyWith(nombre: 'Empresa editada', pass: ''),
    );
    expect(Repositorio.i.conexionesLocales.single.nombre, 'Empresa editada');
    expect(Repositorio.i.conexionesLocales.single.pass, 'secreto');

    await Repositorio.i.guardarConexionLocal(
      nueva.copyWith(pass: ''),
      limpiarPass: true,
    );
    expect(Repositorio.i.conexionesLocales.single.pass, isEmpty);
  });

  test('actualiza el estado y elimina conexiones locales', () async {
    final conexion = await Repositorio.i.guardarConexionLocal(
      const Conexion(
        id: 0,
        nombre: 'Empresa local',
        host: 'localhost',
        data: 'siscont',
        usuario: 'usuario',
        pass: '',
        tipo: 'MYSQL',
        imagen: '',
        estado: 0,
      ),
    );

    await Repositorio.i.cambiarEstadoConexionLocal(conexion.id, estado: 1);
    expect(Repositorio.i.conexionesLocales.single.activa, isFalse);

    await Repositorio.i.eliminarConexionLocal(conexion.id);
    expect(Repositorio.i.conexionesLocales, isEmpty);
  });
}
