import 'package:flutter/material.dart';

import '../models/tipo_movimiento_caja.dart';
import '../storage/repositorio.dart';
import '../theme/tema.dart';
import '../widgets/entrada.dart';

class TiposMovimientoCajaPage extends StatefulWidget {
  const TiposMovimientoCajaPage({super.key});

  @override
  State<TiposMovimientoCajaPage> createState() =>
      _TiposMovimientoCajaPageState();
}

class _TiposMovimientoCajaPageState extends State<TiposMovimientoCajaPage> {
  Future<void> _editar([TipoMovimientoCaja? tipo]) async {
    final resultado = await showDialog<TipoMovimientoCaja>(
      context: context,
      builder: (_) => _FormularioTipoMovimiento(tipo: tipo),
    );
    if (resultado == null) return;
    try {
      await Repositorio.i.guardarTipoMovimientoCaja(resultado);
      if (!mounted) return;
      setState(() {});
      _avisar('Tipo de movimiento guardado.');
    } catch (e) {
      _avisar('No se pudo guardar el tipo de movimiento: $e', error: true);
    }
  }

  Future<void> _eliminar(TipoMovimientoCaja tipo) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar tipo de movimiento'),
        content: Text('¿Desea eliminar "${tipo.nombre}"?'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    try {
      await Repositorio.i.eliminarTipoMovimientoCaja(tipo.id);
      if (mounted) setState(() {});
    } catch (e) {
      _avisar('No se pudo eliminar el tipo de movimiento: $e', error: true);
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
  Widget build(BuildContext context) {
    final tipos = Repositorio.i.tiposMovimientoCaja;
    return Scaffold(
      backgroundColor: Paleta.contenido,
      appBar: AppBar(
        backgroundColor: Paleta.panel,
        foregroundColor: Colors.white,
        title: const Text('TIPOS DE MOVIMIENTO'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Nuevo tipo de movimiento',
            onPressed: _editar,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: <Widget>[
          Tarjeta(
            titulo: 'TIPOS DE MOVIMIENTO',
            icono: Icons.swap_horiz,
            hijo: const Text(
              'EFECTIVO está preconfigurado. La cuenta contable fija para '
              'ingresos y gastos es 60002.',
              style: TextStyle(fontSize: 13),
            ),
          ),
          Tarjeta(
            titulo: 'REGISTROS (${tipos.length})',
            icono: Icons.list_alt_outlined,
            padding: const EdgeInsets.all(8),
            hijo: tipos.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: Center(
                      child: Text('Aún no hay tipos de movimiento.'),
                    ),
                  )
                : Column(
                    children: <Widget>[
                      for (final tipo in tipos)
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                          ),
                          leading: const CircleAvatar(
                            child: Icon(Icons.swap_horiz),
                          ),
                          title: Text(tipo.nombre),
                          subtitle: const Text('Cuenta contable: 60002'),
                          onTap: () => _editar(tipo),
                          trailing: PopupMenuButton<String>(
                            onSelected: (accion) {
                              if (accion == 'editar') _editar(tipo);
                              if (accion == 'eliminar') _eliminar(tipo);
                            },
                            itemBuilder: (_) => <PopupMenuEntry<String>>[
                              const PopupMenuItem(
                                value: 'editar',
                                child: Text('Editar'),
                              ),
                              if (tipo.nombre != 'EFECTIVO')
                                const PopupMenuItem(
                                  value: 'eliminar',
                                  child: Text('Eliminar'),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _editar,
        icon: const Icon(Icons.add),
        label: const Text('Nuevo tipo'),
      ),
    );
  }
}

class _FormularioTipoMovimiento extends StatefulWidget {
  final TipoMovimientoCaja? tipo;

  const _FormularioTipoMovimiento({this.tipo});

  @override
  State<_FormularioTipoMovimiento> createState() =>
      _FormularioTipoMovimientoState();
}

class _FormularioTipoMovimientoState extends State<_FormularioTipoMovimiento> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nombre;

  @override
  void initState() {
    super.initState();
    _nombre = TextEditingController(text: widget.tipo?.nombre ?? '');
  }

  @override
  void dispose() {
    _nombre.dispose();
    super.dispose();
  }

  void _guardar() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      TipoMovimientoCaja(
        id: widget.tipo?.id ?? TipoMovimientoCaja.nuevoId(),
        nombre: _nombre.text.trim(),
        cuentaIngreso: '60002',
        cuentaGasto: '60002',
      ),
    );
  }

  String? _requerido(String? value) =>
      value == null || value.trim().isEmpty ? 'Campo obligatorio.' : null;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.tipo == null ? 'Nuevo tipo de movimiento' : 'Editar tipo',
    ),
    content: SingleChildScrollView(
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextFormField(
              controller: _nombre,
              enabled: widget.tipo?.nombre != 'EFECTIVO',
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Tipo de movimiento',
                hintText: 'Ej.: Efectivo',
                border: OutlineInputBorder(),
              ),
              validator: _requerido,
            ),
            const SizedBox(height: 8),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('La cuenta contable asignada es 60002.'),
            ),
          ],
        ),
      ),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancelar'),
      ),
      FilledButton(onPressed: _guardar, child: const Text('Guardar')),
    ],
  );
}
