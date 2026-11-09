import 'package:flutter/material.dart';

import '../models/tercero_local.dart';
import '../storage/repositorio.dart';
import '../services/ws_cliente.dart';
import '../theme/tema.dart';
import 'centros_costo_page.dart';
import 'conceptos_gasto_page.dart';

class TercerosLocalesPage extends StatefulWidget {
  const TercerosLocalesPage({super.key});

  @override
  State<TercerosLocalesPage> createState() => _TercerosLocalesPageState();
}

class _TercerosLocalesPageState extends State<TercerosLocalesPage> {
  String _busqueda = '';

  Future<void> _editar([TerceroLocal? tercero]) async {
    final resultado = await showDialog<TerceroLocal>(
      context: context,
      builder: (context) => _TerceroLocalDialog(tercero: tercero),
    );
    if (resultado == null) return;
    try {
      await Repositorio.i.guardarTerceroLocal(resultado);
      if (mounted) setState(() {});
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo guardar el proveedor local: $error'),
        ),
      );
    }
  }

  Future<void> _eliminar(TerceroLocal tercero) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar proveedor'),
        content: Text(
          '¿Desea eliminar al proveedor ${tercero.nombre} de este dispositivo?',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    try {
      await Repositorio.i.eliminarTerceroLocal(tercero.id);
      if (mounted) setState(() {});
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo eliminar el proveedor: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final consulta = _busqueda.trim().toLowerCase();
    final terceros = Repositorio.i.proveedoresLocales.where((item) {
      return consulta.isEmpty ||
          item.nombre.toLowerCase().contains(consulta) ||
          item.numeroDocumento.toLowerCase().contains(consulta);
    }).toList();

    return Scaffold(
      backgroundColor: Paleta.contenido,
      appBar: AppBar(
        backgroundColor: Paleta.panel,
        foregroundColor: Colors.white,
        title: const Text('PROVEEDORES'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Nuevo proveedor',
            onPressed: _editar,
            icon: const Icon(Icons.person_add_alt_1),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: <Widget>[
          TextField(
            decoration: const InputDecoration(
              labelText: 'Buscar por nombre o documento',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
              filled: true,
              fillColor: Colors.white,
            ),
            onChanged: (value) => setState(() => _busqueda = value),
          ),
          const SizedBox(height: 10),
          if (terceros.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No hay proveedores registrados. Agregue un proveedor; '
                  'se guardará solo en este dispositivo.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else
            for (final tercero in terceros)
              Card(
                child: ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.storefront_outlined),
                  ),
                  title: Text(tercero.nombre),
                  subtitle: Text(
                    '${tercero.tipoDocumento} ${tercero.numeroDocumento}',
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (accion) {
                      if (accion == 'editar') _editar(tercero);
                      if (accion == 'eliminar') _eliminar(tercero);
                    },
                    itemBuilder: (context) => const <PopupMenuEntry<String>>[
                      PopupMenuItem(value: 'editar', child: Text('Editar')),
                      PopupMenuItem(value: 'eliminar', child: Text('Eliminar')),
                    ],
                  ),
                  onTap: () => _editar(tercero),
                ),
              ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _editar,
            icon: const Icon(Icons.add),
            label: const Text('Agregar proveedor'),
          ),
          const SizedBox(height: 8),
          const Text(
            'Estos proveedores se almacenan localmente y no se envían a SISCONT.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Paleta.footerTexto, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _TerceroLocalDialog extends StatefulWidget {
  final TerceroLocal? tercero;

  const _TerceroLocalDialog({this.tercero});

  @override
  State<_TerceroLocalDialog> createState() => _TerceroLocalDialogState();
}

class _TerceroLocalDialogState extends State<_TerceroLocalDialog> {
  late final TextEditingController _nombre = TextEditingController(
    text: widget.tercero?.nombre ?? '',
  );
  late final TextEditingController _numero = TextEditingController(
    text: widget.tercero?.numeroDocumento ?? '',
  );
  late final TextEditingController _direccion = TextEditingController(
    text: widget.tercero?.direccion ?? '',
  );
  late final TextEditingController _telefono = TextEditingController(
    text: widget.tercero?.telefono ?? '',
  );
  late final TextEditingController _correo = TextEditingController(
    text: widget.tercero?.correo ?? '',
  );
  late String _tipoDocumento = widget.tercero?.tipoDocumento ?? 'RUC';
  late String _centroCostoCodigo = widget.tercero?.centroCostoCodigo ?? '';
  late String _conceptoGastoCodigo = widget.tercero?.conceptoGastoCodigo ?? '';
  bool _buscando = false;

  @override
  void dispose() {
    _nombre.dispose();
    _numero.dispose();
    _direccion.dispose();
    _telefono.dispose();
    _correo.dispose();
    super.dispose();
  }

  Future<void> _abrirCentrosCosto() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const CentrosCostoPage()),
    );
    if (mounted) setState(() {});
  }

  Future<void> _abrirConceptosGasto() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const ConceptosGastoPage()),
    );
    if (mounted) setState(() {});
  }

  Widget _selectorCentroCosto() {
    final centros = Repositorio.i.centrosCostoLocales;
    final codigos = centros.map((centro) => centro.codigo).toSet();
    final opciones = <DropdownMenuItem<String>>[
      const DropdownMenuItem<String>(value: '', child: Text('Sin asignar')),
      for (final centro in centros)
        DropdownMenuItem<String>(
          value: centro.codigo,
          child: Text(centro.nombre, overflow: TextOverflow.ellipsis),
        ),
      if (_centroCostoCodigo.isNotEmpty &&
          !codigos.contains(_centroCostoCodigo))
        DropdownMenuItem<String>(
          value: _centroCostoCodigo,
          child: const Text('Guardado anteriormente'),
        ),
    ];

    return DropdownButtonFormField<String>(
      key: ValueKey<String>('proveedor-centrocosto-$_centroCostoCodigo'),
      initialValue: _centroCostoCodigo,
      decoration: const InputDecoration(labelText: 'Centro de costos'),
      items: opciones,
      onChanged: (value) {
        if (value != null) setState(() => _centroCostoCodigo = value);
      },
    );
  }

  Widget _selectorConceptoGasto() {
    final conceptos = Repositorio.i.conceptosGastoLocales;
    final codigos = conceptos.map((concepto) => concepto.codigo).toSet();
    final opciones = <DropdownMenuItem<String>>[
      const DropdownMenuItem<String>(value: '', child: Text('Sin asignar')),
      for (final concepto in conceptos)
        DropdownMenuItem<String>(
          value: concepto.codigo,
          child: Text(concepto.nombre, overflow: TextOverflow.ellipsis),
        ),
      if (_conceptoGastoCodigo.isNotEmpty &&
          !codigos.contains(_conceptoGastoCodigo))
        DropdownMenuItem<String>(
          value: _conceptoGastoCodigo,
          child: const Text('Guardado anteriormente'),
        ),
    ];

    return DropdownButtonFormField<String>(
      key: ValueKey<String>('proveedor-concepto-$_conceptoGastoCodigo'),
      initialValue: _conceptoGastoCodigo,
      decoration: const InputDecoration(labelText: 'Concepto de gasto'),
      items: opciones,
      onChanged: (value) {
        if (value != null) setState(() => _conceptoGastoCodigo = value);
      },
    );
  }

  Future<void> _buscarDocumento() async {
    if (_tipoDocumento != 'RUC' && _tipoDocumento != 'DNI') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La búsqueda permite RUC o DNI.')),
      );
      return;
    }
    setState(() => _buscando = true);
    try {
      final datos = await WsCliente.i.buscarDocumentoPersona(
        numero: _numero.text,
        tipoDocumento: _tipoDocumento,
      );
      if (!mounted) return;
      setState(() {
        _numero.text = '${datos['numeroDocumento'] ?? _numero.text}';
        _nombre.text = '${datos['nombreCompleto'] ?? ''}';
        _direccion.text =
            '${datos['direccion'] ?? datos['direccionCompleta'] ?? ''}';
        _telefono.text = '${datos['telefono'] ?? ''}';
        _buscando = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Datos encontrados. Revise antes de guardar.'),
        ),
      );
    } on WsException catch (error) {
      if (!mounted) return;
      setState(() => _buscando = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.mensaje)));
    } catch (error) {
      if (!mounted) return;
      setState(() => _buscando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo buscar el documento: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.tercero == null ? 'Nuevo proveedor' : 'Editar proveedor',
    ),
    content: SingleChildScrollView(
      child: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            DropdownButtonFormField<String>(
              initialValue: _tipoDocumento,
              decoration: const InputDecoration(labelText: 'Documento'),
              items: const <DropdownMenuItem<String>>[
                DropdownMenuItem(value: 'RUC', child: Text('RUC')),
                DropdownMenuItem(value: 'DNI', child: Text('DNI')),
                DropdownMenuItem(
                  value: 'CE',
                  child: Text('Carné de extranjería'),
                ),
                DropdownMenuItem(value: 'Pasaporte', child: Text('Pasaporte')),
                DropdownMenuItem(value: 'Otro', child: Text('Otro')),
              ],
              onChanged: _buscando
                  ? null
                  : (value) {
                      if (value != null) setState(() => _tipoDocumento = value);
                    },
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _numero,
                    enabled: !_buscando,
                    decoration: const InputDecoration(
                      labelText: 'Número de documento',
                    ),
                    keyboardType: TextInputType.text,
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: IconButton.filledTonal(
                    tooltip: 'Buscar RUC/DNI',
                    onPressed: _buscando ? null : _buscarDocumento,
                    icon: _buscando
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.manage_search),
                  ),
                ),
              ],
            ),
            TextField(
              controller: _nombre,
              decoration: const InputDecoration(
                labelText: 'Nombre / razón social',
              ),
              textCapitalization: TextCapitalization.words,
            ),
            TextField(
              controller: _direccion,
              decoration: const InputDecoration(labelText: 'Dirección'),
            ),
            TextField(
              controller: _telefono,
              decoration: const InputDecoration(labelText: 'Teléfono'),
              keyboardType: TextInputType.phone,
            ),
            TextField(
              controller: _correo,
              decoration: const InputDecoration(labelText: 'Correo'),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 12),
            _selectorCentroCosto(),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _abrirCentrosCosto,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Agregar centro de costos'),
              ),
            ),
            const SizedBox(height: 12),
            _selectorConceptoGasto(),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _abrirConceptosGasto,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Agregar concepto de gasto'),
              ),
            ),
          ],
        ),
      ),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: () {
          if (_nombre.text.trim().isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Ingrese el nombre del proveedor.')),
            );
            return;
          }
          Navigator.pop(
            context,
            TerceroLocal(
              id: widget.tercero?.id ?? '',
              tipo: 'proveedor',
              tipoDocumento: _tipoDocumento,
              numeroDocumento: _numero.text,
              nombre: _nombre.text,
              direccion: _direccion.text,
              telefono: _telefono.text,
              correo: _correo.text,
              centroCostoCodigo: _centroCostoCodigo,
              conceptoGastoCodigo: _conceptoGastoCodigo,
            ),
          );
        },
        child: const Text('Guardar'),
      ),
    ],
  );
}
