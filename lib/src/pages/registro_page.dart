import 'package:flutter/material.dart';

import '../models/usuario.dart';
import '../storage/repositorio.dart';
import '../theme/tema.dart';
import '../widgets/entrada.dart';
import '../widgets/logo_sistema.dart';

/// Registro local: correo, usuario, contrasena y celular.
class RegistroPage extends StatefulWidget {
  const RegistroPage({super.key});

  @override
  State<RegistroPage> createState() => _RegistroPageState();
}

class _RegistroPageState extends State<RegistroPage> {
  final TextEditingController _correo = TextEditingController();
  final TextEditingController _usuario = TextEditingController();
  final TextEditingController _clave = TextEditingController();
  final TextEditingController _clave2 = TextEditingController();
  final TextEditingController _celular = TextEditingController();
  bool _verClave = false;
  bool _cargando = false;
  String? _error;

  @override
  void dispose() {
    _correo.dispose();
    _usuario.dispose();
    _clave.dispose();
    _clave2.dispose();
    _celular.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    FocusScope.of(context).unfocus();
    if (_clave.text != _clave2.text) {
      setState(() => _error = 'Las contrasenas no coinciden.');
      return;
    }
    setState(() {
      _cargando = true;
      _error = null;
    });
    final error = await Repositorio.i.registrar(
      correo: _correo.text,
      usuario: _usuario.text,
      contrasena: _clave.text,
      celular: _celular.text,
    );
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _cargando = false;
        _error = error;
      });
      return;
    }
    final u = await Repositorio.i.validar(_correo.text.trim(), _clave.text);
    if (!mounted) return;
    setState(() => _cargando = false);
    if (u == null) {
      setState(() => _error = 'No se pudo crear la cuenta. Intente de nuevo.');
      return;
    }
    Navigator.of(context).pop<Usuario>(u);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Paleta.contenido,
      appBar: AppBar(
        backgroundColor: Paleta.panel,
        foregroundColor: Colors.white,
        title: Row(
          children: const <Widget>[
            LogoSistema(width: 61, height: 40, fondoBlanco: true),
            SizedBox(width: 10),
            Text('Crear cuenta', style: TextStyle(fontSize: 16)),
          ],
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(18),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Tarjeta(
                titulo: 'DATOS DEL USUARIO',
                icono: Icons.person_add_alt,
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
                hijo: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    EntradaTexto(
                      etiqueta: 'Correo electronico',
                      controlador: _correo,
                      ayuda: 'nombre@correo.com',
                      teclado: TextInputType.emailAddress,
                    ),
                    EntradaTexto(
                      etiqueta: 'Usuario',
                      controlador: _usuario,
                      ayuda: 'mínimo 3 caracteres',
                    ),
                    EntradaTexto(
                      etiqueta: 'Celular',
                      controlador: _celular,
                      ayuda: '999888777',
                      teclado: TextInputType.phone,
                    ),
                    EntradaTexto(
                      etiqueta: 'Contrasena',
                      controlador: _clave,
                      ayuda: 'mínimo 6 caracteres',
                      contrasena: !_verClave,
                      sufijo: IconButton(
                        icon: Icon(
                          _verClave ? Icons.visibility_off : Icons.visibility,
                          size: 18,
                        ),
                        onPressed: () => setState(() => _verClave = !_verClave),
                      ),
                    ),
                    EntradaTexto(
                      etiqueta: 'Repetir contrasena',
                      controlador: _clave2,
                      contrasena: !_verClave,
                      onSubmitted: (_) => _guardar(),
                    ),
                    if (_error != null)
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
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _cargando
                                ? null
                                : () => Navigator.of(context).pop(),
                            child: const Text('Cancelar'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: SizedBox(
                            height: 44,
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: Paleta.exito,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ),
                              onPressed: _cargando ? null : _guardar,
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
                                      'CREAR CUENTA',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Padding(
                      padding: EdgeInsets.only(top: 10),
                      child: Text(
                        'La cuenta se guarda en la base de datos Siscont.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          color: Paleta.footerTexto,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
