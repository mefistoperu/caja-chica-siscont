import 'package:flutter/material.dart';

import '../models/centro_costo.dart';
import '../storage/repositorio.dart';
import '../theme/tema.dart';

class CentrosCostoPage extends StatefulWidget {
  const CentrosCostoPage({super.key});

  @override
  State<CentrosCostoPage> createState() => _CentrosCostoPageState();
}

class _CentrosCostoPageState extends State<CentrosCostoPage> {
  final TextEditingController _buscar = TextEditingController();
  List<CentroCosto> _centros = <CentroCosto>[];
  bool _cargandoCentros = true;
  String? _error;

  List<CentroCosto> get _filtrados {
    final consulta = _buscar.text.trim().toLowerCase();
    if (consulta.isEmpty) return _centros;
    return _centros
        .where(
          (centro) =>
              centro.codigo.toLowerCase().contains(consulta) ||
              centro.nombre.toLowerCase().contains(consulta),
        )
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _cargarCentros();
  }

  @override
  void dispose() {
    _buscar.dispose();
    super.dispose();
  }

  Future<void> _cargarCentros() async {
    setState(() {
      _cargandoCentros = true;
      _error = null;
    });
    try {
      final centros = Repositorio.i.centrosCostoLocales;
      if (!mounted) return;
      setState(() {
        _centros = centros;
        _cargandoCentros = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _cargandoCentros = false;
        _error = 'No se pudieron cargar los centros de costo: $error';
      });
    }
  }

  Future<void> _editar([CentroCosto? centro]) async {
    final resultado = await showDialog<_CentroCostoEditado>(
      context: context,
      builder: (context) => _CentroCostoDialog(centro: centro),
    );
    if (resultado == null) return;
    try {
      await Repositorio.i.guardarCentroCostoLocal(
        codigo: resultado.codigo,
        nombre: resultado.nombre,
        codigoOriginal: centro?.codigo,
      );
      _avisar(
        centro == null
            ? 'Centro de costo creado.'
            : 'Centro de costo actualizado.',
      );
      await _cargarCentros();
    } catch (error) {
      _avisar('No se pudo guardar el centro de costo: $error', error: true);
    }
  }

  Future<void> _eliminar(CentroCosto centro) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar centro de costo'),
        content: Text(
          '¿Desea eliminar ${centro.codigo} - ${centro.nombre} de este dispositivo?',
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
      await Repositorio.i.eliminarCentroCostoLocal(centro.codigo);
      _avisar('Centro de costo eliminado.');
      await _cargarCentros();
    } catch (error) {
      _avisar('No se pudo eliminar el centro de costo: $error', error: true);
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
    final centros = _filtrados;
    return Scaffold(
      backgroundColor: Paleta.contenido,
      appBar: AppBar(
        backgroundColor: Paleta.panel,
        foregroundColor: Colors.white,
        title: const Text('CENTROS DE COSTO'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _cargandoCentros ? null : _cargarCentros,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Nuevo centro de costo',
            onPressed: _cargandoCentros ? null : () => _editar(),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: <Widget>[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: const Row(
                children: <Widget>[
                  Icon(Icons.phone_android_outlined, color: Paleta.panel),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Estos centros se guardan solo en este dispositivo y no se envían a SISCONT.',
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
          const SizedBox(height: 4),
          TextField(
            controller: _buscar,
            decoration: const InputDecoration(
              labelText: 'Buscar código o descripción',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
              filled: true,
              fillColor: Colors.white,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          if (_cargandoCentros)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(28),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_error == null && centros.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _centros.isEmpty
                      ? 'Todavía no tienes centros de costo guardados en este dispositivo.'
                      : 'No hay resultados para la búsqueda.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else
            for (final centro in centros)
              Card(
                child: ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.account_tree_outlined),
                  ),
                  title: Text(centro.nombre),
                  subtitle: Text('Código: ${centro.codigo}'),
                  trailing: PopupMenuButton<String>(
                    onSelected: (accion) {
                      if (accion == 'editar') _editar(centro);
                      if (accion == 'eliminar') _eliminar(centro);
                    },
                    itemBuilder: (context) => const <PopupMenuEntry<String>>[
                      PopupMenuItem(value: 'editar', child: Text('Editar')),
                      PopupMenuItem(value: 'eliminar', child: Text('Eliminar')),
                    ],
                  ),
                  onTap: () => _editar(centro),
                ),
              ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _cargandoCentros ? null : () => _editar(),
        icon: const Icon(Icons.add),
        label: const Text('Nuevo centro'),
      ),
    );
  }
}

class _CentroCostoEditado {
  final String codigo;
  final String nombre;

  const _CentroCostoEditado(this.codigo, this.nombre);
}

class _CentroCostoDialog extends StatefulWidget {
  final CentroCosto? centro;

  const _CentroCostoDialog({this.centro});

  @override
  State<_CentroCostoDialog> createState() => _CentroCostoDialogState();
}

class _CentroCostoDialogState extends State<_CentroCostoDialog> {
  late final TextEditingController _codigo = TextEditingController(
    text: widget.centro?.codigo ?? '',
  );
  late final TextEditingController _nombre = TextEditingController(
    text: widget.centro?.nombre ?? '',
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
      widget.centro == null
          ? 'Nuevo centro de costo'
          : 'Editar centro de costo',
    ),
    content: SizedBox(
      width: 380,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            controller: _nombre,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Centro de costos / Nombre',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _codigo,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Código',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: () {
          if (_codigo.text.trim().isEmpty || _nombre.text.trim().isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Ingrese el código y la descripción.'),
              ),
            );
            return;
          }
          Navigator.pop(
            context,
            _CentroCostoEditado(_codigo.text.trim(), _nombre.text.trim()),
          );
        },
        child: const Text('Guardar'),
      ),
    ],
  );
}
