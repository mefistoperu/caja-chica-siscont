import 'package:flutter/material.dart';

import '../models/conexion.dart';
import '../storage/repositorio.dart';
import '../services/ws_cliente.dart';
import '../theme/tema.dart';
import '../widgets/logo_sistema.dart';

/// Mantenimiento local de empresas / conexiones.
class ConexionesPage extends StatefulWidget {
  const ConexionesPage({super.key});

  @override
  State<ConexionesPage> createState() => _ConexionesPageState();
}

class _ConexionesPageState extends State<ConexionesPage> {
  final TextEditingController _buscar = TextEditingController();

  List<Conexion> _conexiones = <Conexion>[];
  String _filtroEstado = 'todas';
  bool _cargando = false;
  String? _error;

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

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final buscar = _buscar.text.trim().toLowerCase();
      final lista = Repositorio.i.conexionesLocales.where((conexion) {
        final coincideEstado = switch (_filtroEstado) {
          'activas' => conexion.activa,
          'anuladas' => !conexion.activa,
          _ => true,
        };
        final coincideTexto =
            buscar.isEmpty ||
            '${conexion.nombre} ${conexion.host} ${conexion.data}'
                .toLowerCase()
                .contains(buscar);
        return coincideEstado && coincideTexto;
      }).toList();
      if (!mounted) return;
      setState(() {
        _conexiones = lista;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'Error inesperado: $e';
      });
    }
  }

  void _avisar(String mensaje, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
        backgroundColor: error ? Paleta.peligro : Paleta.panel,
      ),
    );
  }

  Future<void> _nuevo() async {
    final guardado = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _FormularioConexion(conexion: null),
    );
    if (guardado == true) {
      _avisar('Empresa registrada correctamente');
      await _cargar();
    }
  }

  Future<void> _editar(Conexion conexion) async {
    final guardado = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _FormularioConexion(conexion: conexion),
    );
    if (guardado == true) {
      _avisar('Empresa actualizada correctamente');
      await _cargar();
    }
  }

  Future<void> _probar(Conexion conexion) async {
    try {
      final r = await WsCliente.i.probarConeccion(conexion);
      final d = r['data'];
      final datos = d is Map ? d : r;
      final lineas = <String>[
        '${r['mensaje'] ?? 'Conexión correcta'}',
        if ('${datos['driver'] ?? ''}'.isNotEmpty) 'Driver: ${datos['driver']}',
        if ('${datos['version'] ?? ''}'.isNotEmpty)
          'Versión: ${datos['version']}',
        if ('${datos['milisegundos'] ?? datos['ms'] ?? ''}'.isNotEmpty)
          'Tiempo: ${datos['milisegundos'] ?? datos['ms']} ms',
      ];
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Probar conexión'),
          content: Text('${conexion.nombre}\n\n${lineas.join('\n')}'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      );
    } on WsException catch (e) {
      _avisar(e.mensaje, error: true);
    } catch (e) {
      _avisar('No se pudo probar la conexión: $e', error: true);
    }
  }

  Future<void> _cambiarEstado(Conexion conexion) async {
    final anular = conexion.activa;
    final confirmar = await _confirmar(
      anular
          ? '¿Anular la empresa ${conexion.nombre}?'
          : '¿Reactivar la empresa ${conexion.nombre}?',
    );
    if (confirmar != true) return;

    try {
      await Repositorio.i.cambiarEstadoConexionLocal(
        conexion.id,
        estado: anular ? 1 : 0,
      );
      _avisar(
        anular
            ? 'Empresa anulada correctamente'
            : 'Empresa reactivada correctamente',
      );
      await _cargar();
    } catch (e) {
      _avisar('No se pudo actualizar la conexión local: $e', error: true);
    }
  }

  Future<void> _eliminar(Conexion conexion) async {
    final confirmar = await _confirmar(
      '¿Eliminar definitivamente la empresa ${conexion.nombre}? Esta acción no se puede deshacer.',
    );
    if (confirmar != true) return;

    try {
      await Repositorio.i.eliminarConexionLocal(conexion.id);
      _avisar('Empresa eliminada');
      await _cargar();
    } catch (e) {
      _avisar('No se pudo eliminar la conexión local: $e', error: true);
    }
  }

  Future<bool?> _confirmar(String texto) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(texto),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Aceptar'),
          ),
        ],
      ),
    );
  }

  Widget _badge(Conexion conexion) {
    final color = conexion.activa ? Paleta.exito : Paleta.peligro;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        conexion.etiquetaEstado,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  Widget _fila(Conexion conexion) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Paleta.tablaBorde),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.storage_outlined, size: 20, color: Paleta.panel),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        conexion.nombre,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Paleta.texto,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _badge(conexion),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  conexion.subtitulo,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5, color: Colors.black54),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Opciones',
            icon: const Icon(Icons.more_vert, size: 20),
            onSelected: (v) {
              switch (v) {
                case 'editar':
                  _editar(conexion);
                  break;
                case 'probar':
                  _probar(conexion);
                  break;
                case 'estado':
                  _cambiarEstado(conexion);
                  break;
                case 'eliminar':
                  _eliminar(conexion);
                  break;
              }
            },
            itemBuilder: (_) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(
                value: 'editar',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.edit_outlined, size: 18),
                  title: Text('Editar', style: TextStyle(fontSize: 13)),
                ),
              ),
              const PopupMenuItem<String>(
                value: 'probar',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.network_check, size: 18),
                  title: Text(
                    'Probar conexión',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              ),
              PopupMenuItem<String>(
                value: 'estado',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    conexion.activa
                        ? Icons.block_outlined
                        : Icons.play_circle_outline,
                    size: 18,
                  ),
                  title: Text(
                    conexion.activa ? 'Anular' : 'Reactivar',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ),
              const PopupMenuItem<String>(
                value: 'eliminar',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.delete_outline, size: 18),
                  title: Text('Eliminar', style: TextStyle(fontSize: 13)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _contenido() {
    if (_cargando) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.error_outline, color: Paleta.peligro, size: 36),
              const SizedBox(height: 10),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _cargar,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    if (_conexiones.isEmpty) {
      return const Center(
        child: Text(
          'No hay empresas registradas.',
          style: TextStyle(fontSize: 13, color: Colors.black54),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(top: 4, bottom: 16),
      itemCount: _conexiones.length,
      itemBuilder: (_, i) => _fila(_conexiones[i]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Paleta.contenido,
      appBar: AppBar(
        backgroundColor: Paleta.panel,
        foregroundColor: Colors.white,
        titleSpacing: 12,
        title: Row(
          children: <Widget>[
            const LogoSistema(width: 61, height: 40, fondoBlanco: true),
            const SizedBox(width: 10),
            const Text(
              'EMPRESAS / CONEXIONES',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
          ],
        ),
        actions: <Widget>[
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _cargando ? null : _cargar,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _nuevo,
        backgroundColor: Paleta.panel,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add, size: 20),
        label: const Text('Nueva empresa'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: TextField(
                        controller: _buscar,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => _cargar(),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: 'Buscar por nombre, base de datos o host',
                          hintStyle: const TextStyle(fontSize: 12.5),
                          prefixIcon: const Icon(Icons.search, size: 20),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: const BorderSide(
                              color: Paleta.controlBorde,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    DropdownButton<String>(
                      value: _filtroEstado,
                      underline: const SizedBox.shrink(),
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Paleta.texto,
                      ),
                      items: const <DropdownMenuItem<String>>[
                        DropdownMenuItem<String>(
                          value: 'todas',
                          child: Text('Todas'),
                        ),
                        DropdownMenuItem<String>(
                          value: 'activas',
                          child: Text('Activas'),
                        ),
                        DropdownMenuItem<String>(
                          value: 'anuladas',
                          child: Text('Anuladas'),
                        ),
                      ],
                      onChanged: (v) {
                        setState(() => _filtroEstado = v ?? 'todas');
                        _cargar();
                      },
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _cargar,
                      icon: const Icon(Icons.filter_alt_outlined, size: 18),
                      label: const Text('Filtrar'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Expanded(child: _contenido()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Formulario de alta / edición de una conexión.
class _FormularioConexion extends StatefulWidget {
  const _FormularioConexion({this.conexion});

  final Conexion? conexion;

  @override
  State<_FormularioConexion> createState() => _FormularioConexionState();
}

class _FormularioConexionState extends State<_FormularioConexion> {
  late final TextEditingController _nombre;
  late final TextEditingController _host;
  late final TextEditingController _data;
  late final TextEditingController _usuario;
  late final TextEditingController _pass;

  late String _tipo;
  bool _limpiarPass = false;
  bool _guardando = false;
  String? _error;

  bool get _esEdicion => widget.conexion != null;

  @override
  void initState() {
    super.initState();
    final c = widget.conexion;
    _nombre = TextEditingController(text: c?.nombre ?? '');
    _host = TextEditingController(text: c?.host ?? '');
    _data = TextEditingController(text: c?.data ?? '');
    _usuario = TextEditingController(text: c?.usuario ?? '');
    _pass = TextEditingController();
    _tipo = (c == null || c.tipo.isEmpty) ? 'ACCESS' : c.tipo;
  }

  @override
  void dispose() {
    _nombre.dispose();
    _host.dispose();
    _data.dispose();
    _usuario.dispose();
    _pass.dispose();
    super.dispose();
  }

  Widget _campo(
    String etiqueta,
    TextEditingController controlador, {
    String? ayuda,
    bool contrasena = false,
    bool obligatorio = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            obligatorio ? '$etiqueta *' : etiqueta,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Paleta.etiqueta,
            ),
          ),
          const SizedBox(height: 3),
          TextField(
            controller: controlador,
            obscureText: contrasena,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              isDense: true,
              hintText: ayuda,
              hintStyle: const TextStyle(fontSize: 12),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: Paleta.controlBorde),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _guardar() async {
    final nombre = _nombre.text.trim();
    if (nombre.isEmpty) {
      setState(() => _error = 'Ingrese la descripción de la empresa');
      return;
    }

    setState(() {
      _guardando = true;
      _error = null;
    });

    try {
      await Repositorio.i.guardarConexionLocal(
        Conexion(
          id: widget.conexion?.id ?? 0,
          nombre: nombre,
          host: _host.text.trim(),
          data: _data.text.trim(),
          usuario: _usuario.text.trim(),
          pass: _pass.text,
          tipo: _tipo,
          imagen: '',
          estado: widget.conexion?.estado ?? 0,
        ),
        limpiarPass: _esEdicion && _pass.text.isEmpty && _limpiarPass,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on WsException catch (e) {
      if (!mounted) return;
      setState(() {
        _guardando = false;
        _error = e.mensaje;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _guardando = false;
        _error = 'Error inesperado: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        _esEdicion ? 'Editar empresa' : 'Nueva empresa',
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _campo(
                'Descripción',
                _nombre,
                ayuda: 'NOMBRE DE LA EMPRESA',
                obligatorio: true,
              ),
              _campo('Host', _host, ayuda: 'LOCALHOST'),
              _campo('Base de datos', _data, ayuda: 'SISCONT'),
              _campo('Usuario', _usuario, ayuda: 'USUARIO'),
              _campo(
                'Contraseña',
                _pass,
                ayuda: _esEdicion
                    ? 'Dejar vacío para conservar la actual'
                    : 'CONTRASEÑA',
                contrasena: true,
              ),
              if (_esEdicion)
                CheckboxListTile(
                  value: _limpiarPass,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text(
                    'Quitar la contraseña guardada',
                    style: TextStyle(fontSize: 12),
                  ),
                  onChanged: (v) => setState(() => _limpiarPass = v ?? false),
                ),
              const SizedBox(height: 4),
              const Text(
                'Tipo de conexión',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Paleta.etiqueta,
                ),
              ),
              const SizedBox(height: 3),
              DropdownButtonFormField<String>(
                initialValue: _tipo,
                items: Conexion.tipos
                    .map(
                      (t) => DropdownMenuItem<String>(value: t, child: Text(t)),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _tipo = v ?? 'ACCESS'),
                decoration: const InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                ),
              ),
              if (_error != null) ...<Widget>[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Paleta.peligro,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _guardando ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _guardando ? null : _guardar,
          child: _guardando
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Guardar'),
        ),
      ],
    );
  }
}
