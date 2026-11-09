import 'package:flutter/material.dart';

import '../models/licencia.dart';
import '../models/usuario.dart';
import '../services/ws_cliente.dart';
import '../storage/repositorio.dart';
import '../theme/tema.dart';
import '../widgets/entrada.dart';

/// Pantalla de ingreso. Las credenciales se validan contra el servicio de
/// licencias de Siscont (Nubesiscont).
class LoginPage extends StatefulWidget {
  final ValueChanged<Usuario> onEntrar;

  /// Mensaje que se muestra al abrir (por ejemplo, licencia vencida).
  final String? aviso;

  const LoginPage({super.key, required this.onEntrar, this.aviso});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _usuario = TextEditingController();
  final TextEditingController _clave = TextEditingController();
  bool _verClave = false;
  bool _cargando = false;
  String? _error;
  Licencia? _licencia;

  @override
  void initState() {
    super.initState();
    _error = widget.aviso;
    _licencia = Repositorio.i.licenciaGuardada;
  }

  @override
  void dispose() {
    _usuario.dispose();
    _clave.dispose();
    super.dispose();
  }

  Future<void> _entrar() async {
    FocusScope.of(context).unfocus();
    final id = _usuario.text.trim();
    final clave = _clave.text;
    if (id.isEmpty || clave.isEmpty) {
      setState(() => _error = 'Ingrese su correo y contrasena.');
      return;
    }
    setState(() {
      _cargando = true;
      _error = null;
    });
    await Future<void>.delayed(const Duration(milliseconds: 120));
    Usuario? u;
    try {
      u = await Repositorio.i.validar(id, clave);
    } on WsException catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = e.mensaje;
      });
      return;
    }
    if (!mounted) return;
    if (u == null) {
      setState(() {
        _cargando = false;
        _error = 'Correo o contrasena incorrectos.';
      });
      return;
    }
    await Repositorio.i.iniciarSesion(u);
    if (!mounted) return;
    setState(() => _cargando = false);
    widget.onEntrar(u);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Paleta.contenido,
      body: SafeArea(
        child: Stack(
          children: <Widget>[
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 24,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Image.asset(
                        'assets/images/logomas.png',
                        key: const ValueKey<String>('login-logo-principal'),
                        width: 256,
                        height: 166.4,
                        fit: BoxFit.contain,
                        semanticLabel: 'Brújula Financiera Software',
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'CAJA CHICA',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                          color: Paleta.etiqueta,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Comprobantes de compra en tu celular',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Paleta.footerTexto,
                        ),
                      ),
                      if (_licencia != null &&
                          _licencia!.empresa.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 8),
                        Text(
                          _licencia!.empresa,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Paleta.etiqueta,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Licencia hasta ${_licencia!.vencimientoTexto}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Paleta.footerTexto,
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      Tarjeta(
                        padding: const EdgeInsets.fromLTRB(14, 16, 14, 6),
                        hijo: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            const Text(
                              'INICIAR SESION',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Paleta.etiqueta,
                                letterSpacing: 0.6,
                              ),
                            ),
                            const SizedBox(height: 12),
                            EntradaTexto(
                              etiqueta: 'Correo electrónico',
                              controlador: _usuario,
                              ayuda: 'correo@dominio.com',
                            ),
                            EntradaTexto(
                              etiqueta: 'Contraseña',
                              controlador: _clave,
                              contrasena: !_verClave,
                              sufijo: IconButton(
                                icon: Icon(
                                  _verClave
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                  size: 18,
                                ),
                                onPressed: () =>
                                    setState(() => _verClave = !_verClave),
                              ),
                              onSubmitted: (_) => _entrar(),
                            ),
                            if (_error != null) ...<Widget>[
                              Container(
                                padding: const EdgeInsets.all(8),
                                margin: const EdgeInsets.only(bottom: 10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFDE8E8),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  children: <Widget>[
                                    const Icon(
                                      Icons.error_outline,
                                      size: 16,
                                      color: Paleta.peligro,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        _error!,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Paleta.peligro,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            SizedBox(
                              height: 44,
                              child: FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor: Paleta.panel,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                                onPressed: _cargando ? null : _entrar,
                                child: _cargando
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Text(
                                        'INGRESAR',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.6,
                                        ),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Text(
                          'El acceso se valida con la licencia Siscont.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Paleta.footerTexto,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 32,
              bottom: 16,
              width: MediaQuery.sizeOf(context).width * 0.4,
              child: IgnorePointer(
                child: Image.asset(
                  'assets/images/logotipo.png',
                  fit: BoxFit.contain,
                  alignment: Alignment.bottomLeft,
                  semanticLabel: 'Siscont Software Contable - Financiero',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
