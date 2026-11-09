import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/comprobante.dart';
import '../models/movimiento_caja.dart';
import '../models/tipo_movimiento_caja.dart';
import '../models/usuario.dart';
import '../services/groq_servicio.dart';
import '../services/mapeo_comprobante.dart';
import '../services/ws_cliente.dart';
import '../storage/archivos.dart';
import '../storage/repositorio.dart';
import '../theme/tema.dart';
import '../widgets/entrada.dart';
import '../widgets/logo_sistema.dart';
import 'comprobante_form_page.dart';
import 'centros_costo_page.dart';
import 'caja_page.dart';
import 'conexiones_page.dart';
import 'conceptos_gasto_page.dart';
import 'cuentas_contables_page.dart';
import 'reporte_page.dart';
import 'terceros_locales_page.dart';

/// Pantalla principal: adjuntar (foto / galeria / PDF), listar y exportar.
class HomePage extends StatefulWidget {
  final Usuario usuario;
  final VoidCallback onSalir;

  const HomePage({super.key, required this.usuario, required this.onSalir});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final GroqServicio _ia = const GroqServicio();
  late List<Comprobante> _items = Repositorio.i.comprobantes;
  bool _ocupado = false;
  String _mensaje = '';

  /// 0 = seccion para importar/tomar foto, 1 = seccion del reporte.
  int _seccion = 0;

  @override
  void initState() {
    super.initState();
    // Defensa adicional: si la licencia venció, se bloquea todo el sistema.
    if (!widget.usuario.licenciaVigente) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onSalir();
      });
    }
  }

  void _refrescar() {
    setState(() => _items = Repositorio.i.comprobantes);
  }

  void _seleccionarSeccion(int seccion) {
    Navigator.of(context).pop();
    if (_seccion != seccion) {
      setState(() => _seccion = seccion);
    }
  }

  void _abrirMantenimientoConexiones() {
    Navigator.of(context).pop();
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const ConexionesPage()));
  }

  void _abrirCentrosCosto() {
    Navigator.of(context).pop();
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const CentrosCostoPage()));
  }

  void _abrirConceptosGasto() {
    Navigator.of(context).pop();
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const ConceptosGastoPage()));
  }

  void _abrirCuentasContables() {
    Navigator.of(context).pop();
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const CuentasContablesPage()),
    );
  }

  void _abrirTercerosLocales() {
    Navigator.of(context).pop();
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const TercerosLocalesPage()),
    );
  }

  void _abrirCaja() {
    Navigator.of(context).pop();
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const CajaPage()));
  }

  Future<void> _nuevoComprobanteManual() async {
    if (!_verificarCajaAbierta()) return;
    final voucher = await Repositorio.i.consumirVoucher();
    final numeroOtro = await Repositorio.i.consumirNumeroOtroComprobante();
    final comprobante = Comprobante.vacio(archivo: '')
      ..motor = 'manual'
      ..['doc'] = '00'
      ..['numero'] = numeroOtro
      ..['vouNumero'] = '$voucher';
    if (!mounted) return;
    await _abrirFormulario(comprobante, nuevo: true);
  }

  // ------------------------------------------------------------ adjuntar ---

  Future<void> _tomarFoto() => _desdeImagen(ImageSource.camera);

  Future<void> _elegirImagen() => _desdeImagen(ImageSource.gallery);

  Future<void> _desdeImagen(ImageSource origen) async {
    if (!_verificarCajaAbierta()) return;
    try {
      final x = await ImagePicker().pickImage(
        source: origen,
        maxWidth: 1800,
        imageQuality: 85,
      );
      if (x == null) return;
      final bytes = await x.readAsBytes();
      await _procesar(bytes, x.name);
    } catch (e) {
      _aviso('No se pudo abrir la camara/galeria: $e', error: true);
    }
  }

  Future<void> _elegirPdf() async {
    if (!_verificarCajaAbierta()) return;
    try {
      final r = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: <String>['pdf'],
        withData: true,
      );
      final f = r?.files.single;
      final bytes = f?.bytes;
      if (f == null || bytes == null) {
        _aviso('No se pudo leer el archivo PDF.', error: true);
        return;
      }
      await _procesar(bytes, f.name);
    } catch (e) {
      _aviso('No se pudo abrir el archivo: $e', error: true);
    }
  }

  Future<void> _procesar(List<int> bytes, String nombre) async {
    if (!_verificarCajaAbierta()) return;
    final creado = DateTime.now().toIso8601String();
    setState(() {
      _ocupado = true;
      _mensaje = 'Guardando archivo...';
    });
    String ruta = '';
    try {
      ruta = await Repositorio.i.copiarArchivo(nombre, bytes);
      setState(() => _mensaje = 'Leyendo el comprobante con IA...');

      final resultado = await _ia.analizar(ruta);
      final c = comprobanteDesdeIa(
        resultado.datos,
        archivo: ruta,
        motor: resultado.motor,
        voucher: 0,
      )..creado = creado;
      final existente = Repositorio.i.comprobantePorDocumento(c);
      c['vouNumero'] =
          existente?['vouNumero'] ?? '${await Repositorio.i.consumirVoucher()}';

      if (!mounted) return;
      setState(() => _ocupado = false);
      await _abrirFormulario(c, nuevo: true);
    } on IaException catch (e) {
      if (!mounted) return;
      setState(() => _ocupado = false);
      await _ofrecerManual(ruta, e.mensaje, creado: creado);
    } catch (e) {
      if (!mounted) return;
      setState(() => _ocupado = false);
      await _ofrecerManual(
        ruta,
        'No se pudo leer el comprobante: $e',
        creado: creado,
      );
    }
  }

  /// Cuando la IA falla se ofrece cargar los datos a mano sin perder el archivo.
  Future<void> _ofrecerManual(
    String ruta,
    String mensaje, {
    required String creado,
  }) async {
    final manual = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: <Widget>[
            Icon(Icons.info_outline, color: Color(0xFFB8860B)),
            SizedBox(width: 8),
            Expanded(
              child: Text('No se pudo leer', style: TextStyle(fontSize: 16)),
            ),
          ],
        ),
        content: Text(mensaje, style: const TextStyle(fontSize: 13)),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Descartar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Ingresar a mano'),
          ),
        ],
      ),
    );
    if (manual == true && mounted) {
      final voucher = await Repositorio.i.consumirVoucher();
      final c = Comprobante.vacio(archivo: ruta)
        ..motor = 'manual'
        ..['vouNumero'] = '$voucher'
        ..creado = creado;
      if (!mounted) return;
      await _abrirFormulario(c, nuevo: true);
    }
  }

  Future<void> _abrirFormulario(Comprobante c, {bool nuevo = false}) async {
    final resultado = await Navigator.of(context).push<Comprobante>(
      MaterialPageRoute<Comprobante>(
        builder: (_) => ComprobanteFormPage(comprobante: c, nuevo: nuevo),
      ),
    );
    if (resultado == null) return;
    final existenteDocumento = Repositorio.i.comprobantePorDocumento(resultado);
    if (existenteDocumento != null) resultado.id = existenteDocumento.id;
    final gastoExistente = Repositorio.i.gastoPorComprobante(resultado.id);
    String? errorTipoCambio;
    var tipoCambioActualizado = false;
    if (nuevo || gastoExistente != null) {
      final cajasAbiertas = Repositorio.i.cajasActivas;
      final cajaSeleccionadaId = resultado['cajaId'].trim();
      final cajaActiva = gastoExistente == null
          ? cajaSeleccionadaId.isNotEmpty
                ? cajasAbiertas
                      .where((caja) => caja.id == cajaSeleccionadaId)
                      .firstOrNull
                : (Repositorio.i.cajaActivaParaMoneda(
                        _monedaComprobante(resultado),
                      ) ??
                      cajasAbiertas.firstOrNull)
          : cajasAbiertas
                .where((caja) => caja.id == gastoExistente.cajaId)
                .firstOrNull;
      final monedaCaja = gastoExistente == null
          ? cajaActiva?.moneda
          : Repositorio.i.monedaCajaPorId(gastoExistente.cajaId);
      if (monedaCaja == null ||
          (gastoExistente == null && cajasAbiertas.isEmpty)) {
        _aviso(
          'Abra una Caja antes de guardar una salida desde un comprobante.',
          error: true,
        );
        return;
      }
      if (resultado.total <= 0) {
        _aviso(
          'El comprobante necesita un total mayor que cero para descontarlo de Caja.',
          error: true,
        );
        return;
      }
      final tipos = Repositorio.i.tiposMovimientoCaja
          .where((tipo) => tipo.cuentaGasto.trim().isNotEmpty)
          .toList();
      if (tipos.isEmpty) {
        _aviso(
          'Configure un tipo de movimiento con cuenta de gasto antes de guardar '
          'el comprobante, en Caja > Configuración > Tipos y cuentas.',
          error: true,
        );
        return;
      }
      try {
        tipoCambioActualizado = await Repositorio.i
            .actualizarTipoCambioDiarioSiNecesario(
              consultar: WsCliente.i.obtenerTipoCambioVenta,
            );
      } on WsException catch (error) {
        errorTipoCambio = error.mensaje;
      } on FormatException catch (error) {
        errorTipoCambio = error.message;
      }
      double montoCaja;
      if (_monedaComprobante(resultado) != monedaCaja) {
        final tipoCambio = await _confirmarTipoCambio(
          resultado,
          monedaCaja: monedaCaja,
        );
        if (tipoCambio == null || !mounted) return;
        resultado['tc'] = tipoCambio.toStringAsFixed(3);
      }
      try {
        montoCaja = _importeComprobanteEnCaja(resultado, monedaCaja);
      } on FormatException catch (e) {
        _aviso(e.message, error: true);
        return;
      }
      final tipoId = await _elegirTipoGasto(
        resultado,
        tipos,
        monedaCaja: monedaCaja,
        montoCaja: montoCaja,
        tipoActual: gastoExistente?.tipoMovimientoId,
      );
      if (tipoId == null || !mounted) return;
      final tipo = tipos.firstWhere((item) => item.id == tipoId);
      final cajaId = gastoExistente?.cajaId ?? cajaActiva!.id;
      try {
        await Repositorio.i.guardarComprobanteConGasto(
          resultado,
          MovimientoCaja(
            id: gastoExistente?.id ?? 'comprobante-${resultado.id}',
            cajaId: cajaId,
            moneda: monedaCaja,
            tipo: 'gasto',
            tipoMovimientoId: tipo.id,
            tipoMovimiento: tipo.nombre,
            cuentaContable: tipo.cuentaGasto,
            comprobanteId: resultado.id,
            concepto:
                'Comprobante ${resultado['numero'].trim().isEmpty ? resultado.nombreArchivo : resultado['numero']}',
            monto: montoCaja,
            fecha: DateTime.now(),
          ),
        );
      } catch (e) {
        _aviso(
          'No se pudo guardar el comprobante y descontar Caja: $e',
          error: true,
        );
        return;
      }
    } else {
      await Repositorio.i.actualizarComprobante(resultado);
    }
    String? errorProveedorLocal;
    try {
      await Repositorio.i.guardarProveedorDesdeComprobante(resultado);
    } catch (error) {
      errorProveedorLocal = '$error';
    }
    _refrescar();
    if (mounted) {
      final mensaje = nuevo || gastoExistente != null
          ? 'Comprobante guardado y salida descontada de Caja.'
          : 'Comprobante guardado en el telefono.';
      final avisos = <String>[
        if (errorTipoCambio != null)
          'No se pudo actualizar el TC de SUNAT: $errorTipoCambio',
        if (errorProveedorLocal != null)
          'No se pudo guardar el proveedor local: $errorProveedorLocal',
        if (tipoCambioActualizado)
          'Tipo de cambio diario actualizado desde SUNAT.',
      ];
      _aviso(
        <String>[mensaje, ...avisos].join(' '),
        error: errorTipoCambio != null || errorProveedorLocal != null,
      );
    }
  }

  bool _verificarCajaAbierta() {
    if (Repositorio.i.cajaActiva != null) return true;
    _aviso(
      'Abra una Caja antes de tomar una foto o subir un archivo.',
      error: true,
    );
    return false;
  }

  double _importeComprobanteEnCaja(Comprobante comprobante, String monedaCaja) {
    final monedaDocumento = _monedaComprobante(comprobante);
    if (monedaDocumento == monedaCaja) return comprobante.total;
    final tipoCambio = comprobante.numero('tc');
    if (!tipoCambio.isFinite || tipoCambio <= 0) {
      throw FormatException(
        'Ingrese un tipo de cambio válido para convertir el comprobante.',
      );
    }
    final convertido = monedaDocumento == 'USD'
        ? comprobante.total * tipoCambio
        : comprobante.total / tipoCambio;
    return (convertido * 100).roundToDouble() / 100;
  }

  String _monedaComprobante(Comprobante comprobante) =>
      <String>{
        'D',
        'USD',
        'US\$',
      }.contains(comprobante['moneda'].trim().toUpperCase())
      ? 'USD'
      : 'PEN';

  Future<double?> _confirmarTipoCambio(
    Comprobante comprobante, {
    required String monedaCaja,
  }) async {
    final tipoCambioDocumento = comprobante.numero('tc');
    final tipoCambioPredeterminado = tipoCambioDocumento == 1
        ? Repositorio.i.tipoCambioDiario
        : tipoCambioDocumento;
    final controlador = TextEditingController(
      text: tipoCambioPredeterminado.toStringAsFixed(3),
    );
    try {
      return await showDialog<double>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Tipo de cambio'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'El comprobante está en ${_monedaComprobante(comprobante)} y '
                'Caja en $monedaCaja. '
                'Confirme el TC del comprobante para convertir el total.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controlador,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Tipo de cambio (TC)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                final texto = controlador.text.trim().replaceAll(',', '.');
                final tipoCambio = double.tryParse(texto);
                if (tipoCambio == null ||
                    !tipoCambio.isFinite ||
                    tipoCambio <= 0) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Ingrese un tipo de cambio mayor que cero.',
                      ),
                    ),
                  );
                  return;
                }
                Navigator.of(ctx).pop(tipoCambio);
              },
              child: const Text('Confirmar TC'),
            ),
          ],
        ),
      );
    } finally {
      controlador.dispose();
    }
  }

  Future<String?> _elegirTipoGasto(
    Comprobante comprobante,
    List<TipoMovimientoCaja> tipos, {
    required String monedaCaja,
    required double montoCaja,
    String? tipoActual,
  }) {
    var seleccionado = tipos.any((tipo) => tipo.id == tipoActual)
        ? tipoActual
        : tipos.first.id;
    final moneda = monedaCaja == 'PEN' ? 'S/' : 'US\$';
    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Registrar salida en Caja'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'Se descontará $moneda ${montoCaja.toStringAsFixed(2)} '
                'del comprobante ${comprobante['numero'].isEmpty ? comprobante.nombreArchivo : comprobante['numero']}.',
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: seleccionado,
                decoration: const InputDecoration(
                  labelText: 'Tipo de gasto / cuenta',
                  border: OutlineInputBorder(),
                ),
                items: tipos
                    .map(
                      (tipo) => DropdownMenuItem<String>(
                        value: tipo.id,
                        child: Text('${tipo.nombre} · ${tipo.cuentaGasto}'),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    setDialogState(() => seleccionado = value);
                  }
                },
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(seleccionado),
              child: const Text('Guardar y descontar'),
            ),
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------------------- acciones ---

  Future<void> _eliminar(Comprobante c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Eliminar comprobante',
          style: TextStyle(fontSize: 16),
        ),
        content: Text(
          'Se quitara de la lista "${c.resumen}". '
          'El archivo seguira en la memoria del telefono.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Paleta.peligro),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Repositorio.i.eliminarComprobante(c.id);
    } catch (e) {
      _aviso('No se pudo eliminar el comprobante: $e', error: true);
      return;
    }
    _refrescar();
  }

  Future<void> _verArchivo(Comprobante c) async {
    if (!existeDocumento(c.archivo)) {
      _aviso('El archivo ya no esta disponible.', error: true);
      return;
    }
    try {
      await abrirReferencia(c.archivo);
    } catch (_) {
      _aviso('No hay una app para abrir este archivo.', error: true);
    }
  }

  void _aviso(String texto, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texto, style: const TextStyle(fontSize: 13)),
        backgroundColor: error ? Paleta.peligro : Paleta.exito,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ------------------------------------------------------------------- ui ---

  /// Pestanas: 0 = comprobantes, 1 = reporte.
  Widget _selectorSeccion() {
    Widget boton(String texto, IconData icono, int seccion) {
      final bool activo = _seccion == seccion;
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          child: Material(
            color: activo ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            elevation: activo ? 2 : 0,
            shadowColor: Colors.black.withValues(alpha: 0.12),
            child: InkWell(
              borderRadius: BorderRadius.circular(9),
              onTap: () {
                if (_seccion != seccion) setState(() => _seccion = seccion);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Icon(
                      icono,
                      size: 18,
                      color: activo ? Paleta.etiqueta : Paleta.footerTexto,
                    ),
                    const SizedBox(width: 7),
                    Text(
                      texto,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                        color: activo ? Paleta.etiqueta : Paleta.footerTexto,
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

    return Container(
      color: Paleta.contenido,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        children: <Widget>[
          boton('IMPORTAR / FOTO', Icons.add_a_photo_outlined, 0),
          boton('REPORTE', Icons.table_chart_outlined, 1),
        ],
      ),
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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text(
              'CAJA CHICA',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
            Text(
              widget.usuario.usuario,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w400,
                color: Colors.white70,
              ),
            ),
          ],
        ),
      ),
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Container(
                color: Paleta.panel,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const LogoSistema(
                      width: 160,
                      height: 104,
                      fondoBlanco: true,
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: <Widget>[
                        CircleAvatar(
                          backgroundColor: Colors.white24,
                          child: Text(
                            widget.usuario.iniciales,
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                widget.usuario.usuario,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                widget.usuario.correo,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                ),
                              ),
                              Text(
                                'Licencia vence: '
                                '${widget.usuario.vencimientoLicenciaTexto}',
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 10.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              ListTile(
                leading: const Icon(Icons.receipt_long_outlined),
                title: const Text('Comprobantes'),
                selected: _seccion == 0,
                onTap: () => _seleccionarSeccion(0),
              ),
              ListTile(
                leading: const Icon(Icons.account_balance_wallet_outlined),
                title: const Text('Caja'),
                onTap: _abrirCaja,
              ),
              ListTile(
                leading: const Icon(Icons.table_chart_outlined),
                title: const Text('Reporte'),
                selected: _seccion == 1,
                onTap: () => _seleccionarSeccion(1),
              ),
              const Divider(),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text(
                  'MANTENIMIENTO',
                  style: TextStyle(
                    color: Paleta.footerTexto,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.storage_outlined),
                title: const Text('Conexiones'),
                subtitle: const Text(
                  'Conexiones guardadas en este dispositivo',
                ),
                onTap: _abrirMantenimientoConexiones,
              ),
              ListTile(
                leading: const Icon(Icons.account_tree_outlined),
                title: const Text('Centros de costo'),
                onTap: _abrirCentrosCosto,
              ),
              ListTile(
                leading: const Icon(Icons.receipt_long_outlined),
                title: const Text('Concepto de gastos'),
                onTap: _abrirConceptosGasto,
              ),
              ListTile(
                leading: const Icon(Icons.account_balance_outlined),
                title: const Text('Parámetros contables'),
                onTap: _abrirCuentasContables,
              ),
              ListTile(
                leading: const Icon(Icons.storefront_outlined),
                title: const Text('Proveedores'),
                onTap: _abrirTercerosLocales,
              ),
              const Spacer(),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Cerrar sesión'),
                onTap: () {
                  Navigator.of(context).pop();
                  widget.onSalir();
                },
              ),
            ],
          ),
        ),
      ),
      body: Stack(
        children: <Widget>[
          Column(
            children: <Widget>[
              _selectorSeccion(),
              Expanded(
                child: _seccion == 0
                    ? ListView(
                        padding: const EdgeInsets.fromLTRB(10, 8, 10, 18),
                        children: <Widget>[
                          Tarjeta(
                            titulo: 'ADJUNTAR COMPROBANTE',
                            icono: Icons.add_a_photo_outlined,
                            hijo: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: <Widget>[
                                Row(
                                  children: <Widget>[
                                    Expanded(
                                      child: BotonAccion(
                                        texto: 'Tomar foto',
                                        ayuda: 'Capturar comprobante',
                                        icono: Icons.photo_camera_outlined,
                                        onTap: _ocupado ? null : _tomarFoto,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: BotonAccion(
                                        texto: 'Galeria',
                                        ayuda: 'Elegir una imagen',
                                        icono: Icons.photo_library_outlined,
                                        color: const Color(0xFF4A90A4),
                                        onTap: _ocupado ? null : _elegirImagen,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: BotonAccion(
                                        texto: 'PDF',
                                        ayuda: 'Importar archivo PDF',
                                        icono: Icons.picture_as_pdf_outlined,
                                        color: const Color(0xFF8A5A44),
                                        onTap: _ocupado ? null : _elegirPdf,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                OutlinedButton.icon(
                                  onPressed: _ocupado
                                      ? null
                                      : _nuevoComprobanteManual,
                                  icon: const Icon(Icons.edit_note_rounded),
                                  label: const Text(
                                    'Registrar compra manual (00 - Otros)',
                                  ),
                                ),
                                const SizedBox(height: 8),
                                OutlinedButton.icon(
                                  onPressed: _ocupado
                                      ? null
                                      : () {
                                          Navigator.of(context)
                                              .push<void>(
                                                MaterialPageRoute<void>(
                                                  builder: (_) =>
                                                      const TercerosLocalesPage(),
                                                ),
                                              )
                                              .then((_) {
                                                if (mounted) setState(() {});
                                              });
                                        },
                                  icon: const Icon(Icons.storefront_outlined),
                                  label: const Text('Proveedores'),
                                ),
                              ],
                            ),
                          ),
                          Tarjeta(
                            titulo: 'RESUMEN',
                            icono: Icons.summarize_outlined,
                            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                            hijo: Row(
                              children: <Widget>[
                                _dato('${_items.length}', 'Comprobantes'),
                                _separador(),
                                _dato(
                                  'S/ ${_totalCompras().toStringAsFixed(2)}',
                                  'Total',
                                ),
                                _separador(),
                                _dato(Repositorio.i.espacioUsado, 'En memoria'),
                              ],
                            ),
                          ),
                          Tarjeta(
                            titulo: 'COMPROBANTES',
                            icono: Icons.list_alt_outlined,
                            padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                            hijo: _items.isEmpty
                                ? const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 18),
                                    child: Center(
                                      child: Text(
                                        'Aun no hay comprobantes.\nToque "Tomar foto" o "PDF" para empezar.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          color: Paleta.footerTexto,
                                        ),
                                      ),
                                    ),
                                  )
                                : Column(
                                    children: <Widget>[
                                      for (final c in _items) _fila(c),
                                    ],
                                  ),
                          ),
                        ],
                      )
                    : ReportePage(items: _items, onItemsChanged: _refrescar),
              ),
            ],
          ),
          if (_ocupado)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black54,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    margin: const EdgeInsets.symmetric(horizontal: 40),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const CircularProgressIndicator(color: Paleta.panel),
                        const SizedBox(height: 14),
                        Text(
                          _mensaje,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 13),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'La IA puede tardar unos segundos.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            color: Paleta.footerTexto,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  double _totalCompras() => _items.fold<double>(0, (sum, c) => sum + c.total);

  Widget _separador() => Container(
    width: 1,
    height: 28,
    color: Paleta.navbarBorde,
    margin: const EdgeInsets.symmetric(horizontal: 8),
  );

  Widget _dato(String valor, String etiqueta) => Expanded(
    child: Column(
      children: <Widget>[
        Text(
          valor,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: Paleta.etiqueta,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          etiqueta,
          style: const TextStyle(fontSize: 10.5, color: Paleta.footerTexto),
        ),
      ],
    ),
  );

  Widget _fila(Comprobante c) {
    final esPdf = c.archivo.toLowerCase().endsWith('.pdf');
    final importe = c.total;
    final moneda = c['moneda'] == 'D' ? 'US\$' : 'S/';
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Paleta.navbarBorde),
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.only(left: 8, right: 0),
        leading: CircleAvatar(
          radius: 16,
          backgroundColor: esPdf
              ? const Color(0xFFFBE9E7)
              : const Color(0xFFE3F2FD),
          child: Icon(
            esPdf ? Icons.picture_as_pdf_outlined : Icons.image_outlined,
            size: 18,
            color: esPdf ? const Color(0xFF8A5A44) : const Color(0xFF1565C0),
          ),
        ),
        title: Text(
          c.resumen,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Registro: ${c.fechaRegistroTexto}  ·  Doc: ${c['fecDoc']}  ·  '
              '${c['numero']}  ·  $moneda ${importe.toStringAsFixed(2)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: Paleta.footerTexto),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: <Widget>[
                _estadoEnvio('WhatsApp', c.estadoWhatsapp),
                _estadoEnvio('SISCONT', c.estadoSiscont),
              ],
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, size: 18),
          onSelected: (v) {
            switch (v) {
              case 'editar':
                _abrirFormulario(c);
                break;
              case 'ver':
                _verArchivo(c);
                break;
              case 'eliminar':
                _eliminar(c);
                break;
            }
          },
          itemBuilder: (_) => const <PopupMenuEntry<String>>[
            PopupMenuItem<String>(
              value: 'editar',
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.edit_outlined, size: 18),
                title: Text('Editar datos', style: TextStyle(fontSize: 13)),
              ),
            ),
            PopupMenuItem<String>(
              value: 'ver',
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.visibility_outlined, size: 18),
                title: Text('Ver archivo', style: TextStyle(fontSize: 13)),
              ),
            ),
            PopupMenuItem<String>(
              value: 'eliminar',
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.delete_outline,
                  size: 18,
                  color: Paleta.peligro,
                ),
                title: Text(
                  'Eliminar',
                  style: TextStyle(fontSize: 13, color: Paleta.peligro),
                ),
              ),
            ),
          ],
        ),
        onTap: () => _abrirFormulario(c),
      ),
    );
  }

  Widget _estadoEnvio(String canal, String estado) {
    final enviado = estado == 'enviado';
    final color = enviado ? Paleta.exito : Paleta.footerTexto;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        '$canal: ${enviado ? 'Enviado' : 'Pendiente'}',
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
