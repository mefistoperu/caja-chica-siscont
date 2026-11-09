import 'package:flutter/material.dart';

import '../models/concepto_gasto.dart';
import '../storage/repositorio.dart';
import '../theme/tema.dart';

class ConceptosGastoPage extends StatefulWidget {
  const ConceptosGastoPage({super.key});

  @override
  State<ConceptosGastoPage> createState() => _ConceptosGastoPageState();
}

class _ConceptosGastoPageState extends State<ConceptosGastoPage> {
  final TextEditingController _buscar = TextEditingController();
  List<ConceptoGasto> _conceptos = <ConceptoGasto>[];
  String? _error;

  List<ConceptoGasto> get _filtrados {
    final consulta = _buscar.text.trim().toLowerCase();
    if (consulta.isEmpty) return _conceptos;
    return _conceptos
        .where(
          (item) =>
              item.codigo.toLowerCase().contains(consulta) ||
              item.nombre.toLowerCase().contains(consulta),
        )
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _buscar.dispose();
    super.dispose();
  }

  void _cargar() {
    try {
      setState(() {
        _conceptos = Repositorio.i.conceptosGastoLocales;
        _error = null;
      });
    } catch (error) {
      setState(() => _error = 'No se pudieron cargar los conceptos: $error');
    }
  }

  Future<void> _editar([ConceptoGasto? concepto]) async {
    final resultado = await showDialog<_ConceptoEditado>(
      context: context,
      builder: (context) => _ConceptoDialog(concepto: concepto),
    );
    if (resultado == null) return;
    try {
      await Repositorio.i.guardarConceptoGastoLocal(
        codigo: resultado.codigo,
        nombre: resultado.nombre,
        codigoOriginal: concepto?.codigo,
      );
      _cargar();
      _avisar(
        concepto == null
            ? 'Concepto de gasto creado.'
            : 'Concepto de gasto actualizado.',
      );
    } catch (error) {
      _avisar('No se pudo guardar el concepto de gasto: $error', error: true);
    }
  }

  Future<void> _eliminar(ConceptoGasto concepto) async {
    if (concepto.codigo == '60001') {
      _avisar(
        'El concepto predeterminado 60001 no se puede eliminar.',
        error: true,
      );
      return;
    }
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar concepto de gasto'),
        content: Text(
          '¿Desea eliminar ${concepto.codigo} - ${concepto.nombre}?',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Paleta.peligro),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    try {
      await Repositorio.i.eliminarConceptoGastoLocal(concepto.codigo);
      _cargar();
      _avisar('Concepto de gasto eliminado.');
    } catch (error) {
      _avisar('No se pudo eliminar el concepto de gasto: $error', error: true);
    }
  }

  void _avisar(String mensaje, {bool error = false}) {
    if (!mounted) return;
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
    final conceptos = _filtrados;
    return Scaffold(
      backgroundColor: Paleta.contenido,
      appBar: AppBar(
        backgroundColor: Paleta.panel,
        foregroundColor: Colors.white,
        title: const Text('CONCEPTOS DE GASTO'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _cargar,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Nuevo concepto',
            onPressed: () => _editar(),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: <Widget>[
          const Card(
            child: Padding(
              padding: EdgeInsets.all(14),
              child: Row(
                children: <Widget>[
                  Icon(Icons.phone_android_outlined, color: Paleta.panel),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Los conceptos se guardan localmente. Gastos varios (60001) es el concepto predeterminado.',
                      style: TextStyle(color: Paleta.footerTexto, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_error != null)
            Card(
              color: const Color(0xFFFFF3F2),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Paleta.peligro),
                ),
              ),
            ),
          TextField(
            controller: _buscar,
            decoration: const InputDecoration(
              labelText: 'Buscar código o concepto',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          if (conceptos.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No hay conceptos de gasto registrados.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else
            for (final concepto in conceptos)
              Card(
                child: ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.receipt_long_outlined),
                  ),
                  title: Text(concepto.nombre),
                  subtitle: Text('Código: ${concepto.codigo}'),
                  trailing: PopupMenuButton<String>(
                    onSelected: (accion) {
                      if (accion == 'editar') _editar(concepto);
                      if (accion == 'eliminar') _eliminar(concepto);
                    },
                    itemBuilder: (context) => const <PopupMenuEntry<String>>[
                      PopupMenuItem(value: 'editar', child: Text('Editar')),
                      PopupMenuItem(value: 'eliminar', child: Text('Eliminar')),
                    ],
                  ),
                  onTap: () => _editar(concepto),
                ),
              ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editar(),
        icon: const Icon(Icons.add),
        label: const Text('Nuevo concepto'),
      ),
    );
  }
}

class _ConceptoEditado {
  final String codigo;
  final String nombre;

  const _ConceptoEditado(this.codigo, this.nombre);
}

class _ConceptoDialog extends StatefulWidget {
  final ConceptoGasto? concepto;

  const _ConceptoDialog({this.concepto});

  @override
  State<_ConceptoDialog> createState() => _ConceptoDialogState();
}

class _ConceptoDialogState extends State<_ConceptoDialog> {
  late final TextEditingController _codigo = TextEditingController(
    text: widget.concepto?.codigo ?? '',
  );
  late final TextEditingController _nombre = TextEditingController(
    text: widget.concepto?.nombre ?? '',
  );

  @override
  void dispose() {
    _codigo.dispose();
    _nombre.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.concepto == null ? 'Nuevo concepto de gasto' : 'Editar concepto',
    ),
    content: SizedBox(
      width: 380,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            controller: _nombre,
            enabled: widget.concepto?.codigo != '60001',
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Concepto de gasto / Nombre',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _codigo,
            enabled: widget.concepto?.codigo != '60001',
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(labelText: 'Código'),
          ),
          if (widget.concepto?.codigo == '60001') ...<Widget>[
            const SizedBox(height: 8),
            const Text(
              'El concepto predeterminado no se puede modificar.',
              style: TextStyle(color: Paleta.footerTexto, fontSize: 12),
            ),
          ],
        ],
      ),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: widget.concepto?.codigo == '60001'
            ? () => Navigator.pop(context)
            : () {
                if (_codigo.text.trim().isEmpty ||
                    _nombre.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Ingrese el código y el nombre.'),
                    ),
                  );
                  return;
                }
                Navigator.pop(
                  context,
                  _ConceptoEditado(_codigo.text.trim(), _nombre.text.trim()),
                );
              },
        child: Text(widget.concepto?.codigo == '60001' ? 'Cerrar' : 'Guardar'),
      ),
    ],
  );
}
