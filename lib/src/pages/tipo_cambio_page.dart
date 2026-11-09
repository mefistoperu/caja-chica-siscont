import 'package:flutter/material.dart';

import '../storage/repositorio.dart';
import '../theme/tema.dart';
import '../widgets/entrada.dart';

class TipoCambioPage extends StatefulWidget {
  const TipoCambioPage({super.key});

  @override
  State<TipoCambioPage> createState() => _TipoCambioPageState();
}

class _TipoCambioPageState extends State<TipoCambioPage> {
  final TextEditingController _tipoCambio = TextEditingController();
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _tipoCambio.text = Repositorio.i.tipoCambioDiario.toStringAsFixed(3);
  }

  @override
  void dispose() {
    _tipoCambio.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final valor = double.tryParse(_tipoCambio.text.trim().replaceAll(',', '.'));
    if (valor == null || !valor.isFinite || valor <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ingrese un tipo de cambio mayor que cero.'),
        ),
      );
      return;
    }

    setState(() => _guardando = true);
    try {
      await Repositorio.i.guardarTipoCambioDiario(valor);
      if (!mounted) return;
      setState(() => _guardando = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Tipo de cambio guardado.')));
    } catch (error) {
      if (!mounted) return;
      setState(() => _guardando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar el tipo de cambio: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Paleta.contenido,
    appBar: AppBar(
      backgroundColor: Paleta.panel,
      foregroundColor: Colors.white,
      title: const Text('TIPO DE CAMBIO DIARIO'),
    ),
    body: ListView(
      padding: const EdgeInsets.all(12),
      children: <Widget>[
        Tarjeta(
          titulo: 'TIPO DE CAMBIO DE HOY',
          icono: Icons.currency_exchange,
          hijo: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(_fecha(DateTime.now())),
              const SizedBox(height: 12),
              TextField(
                controller: _tipoCambio,
                enabled: !_guardando,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Tipo de cambio',
                  hintText: '1.000',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.currency_exchange),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _guardando ? null : _guardar,
                icon: _guardando
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: const Text('Guardar tipo de cambio'),
              ),
              const SizedBox(height: 8),
              const Text(
                'El valor se conserva por fecha en este dispositivo. '
                'Si un día no tiene tipo de cambio registrado, se crea '
                'automáticamente con 1.000.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Tarjeta(
          titulo: 'HISTORIAL DIARIO',
          icono: Icons.history,
          hijo: Column(
            children: Repositorio.i.tiposCambioDiarios.entries
                .toList()
                .reversed
                .map(
                  (entry) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(entry.key),
                    trailing: Text(
                      entry.value.toStringAsFixed(3),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      ],
    ),
  );

  String _fecha(DateTime fecha) =>
      '${fecha.day.toString().padLeft(2, '0')}/'
      '${fecha.month.toString().padLeft(2, '0')}/${fecha.year}';
}
