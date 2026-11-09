import 'package:flutter/material.dart';

import '../storage/repositorio.dart';
import '../theme/tema.dart';

class CuentasContablesPage extends StatefulWidget {
  const CuentasContablesPage({super.key});

  @override
  State<CuentasContablesPage> createState() => _CuentasContablesPageState();
}

class _CuentasContablesPageState extends State<CuentasContablesPage> {
  static const List<(String, String)> _campos = <(String, String)>[
    ('ctaGastos', 'Cuenta de gastos'),
    ('ctaIgv', 'Cuenta de IGV'),
    ('ctaOTrib', 'Cuenta de otros tributos'),
  ];

  final _formKey = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _controladores =
      <String, TextEditingController>{
        for (final (clave, _) in _campos)
          clave: TextEditingController(
            text: Repositorio.i.cuentasContablesExcel[clave] ?? '',
          ),
      };
  bool _guardando = false;

  @override
  void dispose() {
    for (final controlador in _controladores.values) {
      controlador.dispose();
    }
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _guardando = true);
    try {
      await Repositorio.i.guardarCuentasContablesExcel(<String, String>{
        for (final (clave, _) in _campos) clave: _controladores[clave]!.text,
      });
      if (!mounted) return;
      setState(() => _guardando = false);
      _avisar('Parámetros guardados. Se aplicarán a los comprobantes nuevos.');
    } catch (error) {
      if (!mounted) return;
      setState(() => _guardando = false);
      _avisar('No se pudieron guardar los parámetros: $error', error: true);
    }
  }

  void _avisar(String mensaje, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
        backgroundColor: error ? Paleta.peligro : Paleta.exito,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Paleta.contenido,
    appBar: AppBar(
      backgroundColor: Paleta.panel,
      foregroundColor: Colors.white,
      title: const Text('PARÁMETROS CONTABLES'),
    ),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const Text(
                  'Parámetros predeterminados para los comprobantes y el Excel.',
                  style: TextStyle(color: Paleta.footerTexto, fontSize: 13),
                ),
                const SizedBox(height: 16),
                for (final (clave, etiqueta) in _campos) ...<Widget>[
                  TextFormField(
                    key: ValueKey<String>('cuenta-fija-$clave'),
                    controller: _controladores[clave],
                    enabled: !_guardando,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: etiqueta,
                      border: const OutlineInputBorder(),
                    ),
                    validator: clave == 'ctaOTrib'
                        ? null
                        : (valor) => valor == null || valor.trim().isEmpty
                              ? 'Ingrese el código de la cuenta.'
                              : null,
                  ),
                  const SizedBox(height: 14),
                ],
                const SizedBox(height: 4),
                FilledButton.icon(
                  onPressed: _guardando ? null : _guardar,
                  icon: _guardando
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(
                    _guardando ? 'GUARDANDO...' : 'GUARDAR PARÁMETROS',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
