import 'package:flutter/material.dart';

import '../models/origenes_caja.dart';
import '../storage/repositorio.dart';
import '../theme/tema.dart';
import '../widgets/entrada.dart';

class OrigenesCajaPage extends StatefulWidget {
  const OrigenesCajaPage({super.key});

  @override
  State<OrigenesCajaPage> createState() => _OrigenesCajaPageState();
}

class _OrigenesCajaPageState extends State<OrigenesCajaPage> {
  final _formKey = GlobalKey<FormState>();
  final _gasto = TextEditingController();
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    final origenes = Repositorio.i.origenesCaja;
    _gasto.text = origenes.gasto;
  }

  @override
  void dispose() {
    _gasto.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _guardando = true);
    try {
      await Repositorio.i.guardarOrigenesCaja(
        OrigenesCaja(gasto: _gasto.text.trim()),
      );
      if (!mounted) return;
      setState(() => _guardando = false);
      _avisar('Origen de gasto guardado correctamente.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      _avisar('No se pudo guardar el origen de gasto: $e', error: true);
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
      title: const Text('ORIGEN DE GASTO'),
    ),
    body: ListView(
      padding: const EdgeInsets.all(12),
      children: <Widget>[
        Tarjeta(
          titulo: 'ORIGEN DE GASTO',
          icono: Icons.input_outlined,
          hijo: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                TextFormField(
                  controller: _gasto,
                  enabled: !_guardando,
                  decoration: const InputDecoration(
                    labelText: 'Origen gasto',
                    hintText: '01',
                    border: OutlineInputBorder(),
                  ),
                  validator: _validar,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _guardando ? null : _guardar,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(_guardando ? 'Guardando...' : 'Guardar origen'),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  String? _validar(String? value) =>
      value == null || value.trim().isEmpty ? 'Ingrese el origen.' : null;
}
