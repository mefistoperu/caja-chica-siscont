import 'dart:async';

import 'package:flutter/material.dart';

import 'src/config.dart';
import 'src/models/usuario.dart';
import 'src/pages/home_page.dart';
import 'src/pages/login_page.dart';
import 'src/storage/repositorio.dart';
import 'src/theme/tema.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Repositorio.i.inicializar();
  runApp(const ComprasApp());
}

/// App movil "Caja Chica": trabaja solo con la memoria del telefono.
class ComprasApp extends StatefulWidget {
  const ComprasApp({super.key});

  @override
  State<ComprasApp> createState() => _ComprasAppState();
}

class _ComprasAppState extends State<ComprasApp> with WidgetsBindingObserver {
  Usuario? _usuario;
  String? _avisoLicencia;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final u = Repositorio.i.sesionActual;
    if (u == null) return;
    if (u.licenciaVigente) {
      _usuario = u;
    } else {
      unawaited(Repositorio.i.cerrarSesion());
      _avisoLicencia = _mensajeVencida(u);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _revisarLicencia();
  }

  /// Si la licencia venció mientras la app estaba abierta, cierra la sesión y
  /// vuelve al login bloqueado.
  void _revisarLicencia() {
    final u = _usuario;
    if (u == null || u.licenciaVigente) return;
    unawaited(Repositorio.i.cerrarSesion());
    setState(() {
      _usuario = null;
      _avisoLicencia = _mensajeVencida(u);
    });
  }

  static String _mensajeVencida(Usuario u) =>
      'Su licencia venció el ${u.vencimientoLicenciaTexto}. '
      'Comuníquese con el proveedor para renovarla.';

  void _entrar(Usuario u) => setState(() {
        _usuario = u;
        _avisoLicencia = null;
      });

  Future<void> _salir() async {
    await Repositorio.i.cerrarSesion();
    if (!mounted) return;
    setState(() {
      _usuario = null;
      _avisoLicencia = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.nombreApp,
      debugShowCheckedModeBanner: false,
      theme: temaEfsiscont(),
      home: _usuario == null
          ? LoginPage(onEntrar: _entrar, aviso: _avisoLicencia)
          : HomePage(usuario: _usuario!, onSalir: _salir),
    );
  }
}
