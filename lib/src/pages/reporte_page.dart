import 'dart:math' as math;
import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/caja_sesion.dart';
import '../models/comprobante.dart';
import '../models/conexion.dart';
import '../models/centro_costo.dart';
import '../services/asiento_compra.dart';
import '../services/excel_servicio.dart';
import '../services/ws_cliente.dart';
import '../storage/archivos.dart';
import '../storage/repositorio.dart';
import '../theme/tema.dart';
import '../widgets/entrada.dart';

/// Seccion REPORTE: permite revisar el rango y enviar los comprobantes a Excel
/// por WhatsApp o registrar sus asientos en SISCONT.
class ReportePage extends StatefulWidget {
  /// Comprobantes guardados en el telefono (los refresca la pantalla padre).
  final List<Comprobante> items;
  final VoidCallback? onItemsChanged;
  final String? initialCajaId;

  const ReportePage({
    super.key,
    required this.items,
    this.onItemsChanged,
    this.initialCajaId,
  });

  @override
  State<ReportePage> createState() => _ReportePageState();
}

class _ReportePageState extends State<ReportePage> {
  late DateTime _desde;
  late DateTime _hasta;
  bool _ocupado = false;
  bool _usarRangoFechas = false;
  String _ultimoArchivo = '';
  String _mensajeOcupado = 'Generando Excel...';
  String _cajaSeleccionadaId = '';
  String _centroCostoSeleccionado = '';
  String _desgloseGrafico = 'productos';

  static const String _sinCaja = '__sin_caja__';

  @override
  void initState() {
    super.initState();
    final hoy = DateTime.now();
    _desde = DateTime(hoy.year, hoy.month, 1);
    _hasta = DateTime(hoy.year, hoy.month, hoy.day);
    final cajaInicial =
        widget.initialCajaId ??
        Repositorio.i.cajaActiva?.id ??
        Repositorio.i.cierresCaja.firstOrNull?.id;
    if (cajaInicial != null) {
      _cajaSeleccionadaId = cajaInicial;
      final caja = _cajasReporte
          .where((item) => item.id == cajaInicial)
          .firstOrNull;
      if (caja != null) {
        final fechaFinal = caja.fechaCierre ?? hoy;
        _desde = DateTime(
          caja.fechaApertura.year,
          caja.fechaApertura.month,
          caja.fechaApertura.day,
        );
        _hasta = DateTime(fechaFinal.year, fechaFinal.month, fechaFinal.day);
      }
    }
  }

  // -------------------------------------------------------------- filtrado ---

  DateTime? _fechaComprobante(Comprobante c) => c.fechaRegistro;

  List<CajaSesion> get _cajasReporte => <CajaSesion>[
    ...Repositorio.i.cajasActivas,
    ...Repositorio.i.cierresCaja,
  ];

  List<CentroCosto> get _centrosCostoReporte {
    final centros = <String, CentroCosto>{
      for (final centro in Repositorio.i.centrosCostoLocales)
        centro.codigo: centro,
    };
    for (final comprobante in widget.items) {
      final codigo = comprobante['ccosto'].trim();
      if (codigo.isNotEmpty && !centros.containsKey(codigo)) {
        centros[codigo] = CentroCosto(codigo: codigo, nombre: codigo);
      }
    }
    return centros.values.toList()..sort(
      (a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()),
    );
  }

  String _cajaIdComprobante(Comprobante comprobante) =>
      comprobante['cajaId'].trim().isNotEmpty
      ? comprobante['cajaId'].trim()
      : (Repositorio.i.gastoPorComprobante(comprobante.id)?.cajaId ?? '');

  List<Comprobante> get _filtrados {
    final desde = DateTime(_desde.year, _desde.month, _desde.day);
    final hasta = DateTime(_hasta.year, _hasta.month, _hasta.day, 23, 59, 59);
    final lista = <Comprobante>[];
    for (final c in widget.items) {
      final f = _fechaComprobante(c);
      if (f == null) continue;
      if (_usarRangoFechas && (f.isBefore(desde) || f.isAfter(hasta))) {
        continue;
      }
      if (_cajaSeleccionadaId == _sinCaja) {
        if (_cajaIdComprobante(c).isNotEmpty) continue;
      } else if (_cajaSeleccionadaId.isNotEmpty &&
          _cajaIdComprobante(c) != _cajaSeleccionadaId) {
        continue;
      }
      if (_centroCostoSeleccionado.isNotEmpty &&
          c['ccosto'].trim() != _centroCostoSeleccionado) {
        continue;
      }
      lista.add(c);
    }
    lista.sort((a, b) {
      final fa = _fechaComprobante(a) ?? DateTime(2000);
      final fb = _fechaComprobante(b) ?? DateTime(2000);
      return fa.compareTo(fb);
    });
    return lista;
  }

  String get _filtroCajaTexto {
    if (_cajaSeleccionadaId.isEmpty) return 'Todas las cajas';
    if (_cajaSeleccionadaId == _sinCaja) return 'Sin caja asignada';
    final caja = _cajasReporte
        .where((item) => item.id == _cajaSeleccionadaId)
        .firstOrNull;
    if (caja == null) return 'Caja seleccionada';
    return 'Caja ${caja.moneda} (${caja.estaAbierta ? 'abierta' : 'cerrada'})';
  }

  void _seleccionarCajaReporte(String id) {
    setState(() {
      _cajaSeleccionadaId = id;
      if (id.isEmpty && !_usarRangoFechas) {
        final hoy = DateTime.now();
        _desde = DateTime(hoy.year, hoy.month, 1);
        _hasta = DateTime(hoy.year, hoy.month, hoy.day);
      } else if (id.isNotEmpty && id != _sinCaja && !_usarRangoFechas) {
        final caja = _cajasReporte.where((item) => item.id == id).firstOrNull;
        if (caja != null) {
          final fechaFinal = caja.fechaCierre ?? DateTime.now();
          _desde = DateTime(
            caja.fechaApertura.year,
            caja.fechaApertura.month,
            caja.fechaApertura.day,
          );
          _hasta = DateTime(fechaFinal.year, fechaFinal.month, fechaFinal.day);
        }
      }
    });
  }

  double get _total => _filtrados.fold<double>(0, (s, c) => s + c.total);

  List<_ProductoCompra> get _productosMasComprados {
    final agrupados = <String, _ProductoCompra>{};
    for (final comprobante in _filtrados) {
      final fuente = comprobante['detalleItems'].trim();
      if (fuente.isEmpty) continue;
      final detalle = jsonDecode(fuente);
      if (detalle is! List) continue;
      for (final raw in detalle) {
        if (raw is! Map) continue;
        final nombre = '${raw['descripcion'] ?? ''}'.trim();
        final importe = _numeroReporte(raw['importe']);
        if (nombre.isEmpty || importe <= 0) continue;
        final cantidadCapturada = _numeroReporte(raw['cantidad']);
        final cantidad = cantidadCapturada > 0 ? cantidadCapturada : 1;
        final clave = nombre.toLowerCase();
        final previo = agrupados[clave];
        agrupados[clave] = _ProductoCompra(
          nombre: previo?.nombre ?? nombre,
          cantidad: cantidad + (previo?.cantidad ?? 0),
          importe: importe + (previo?.importe ?? 0),
        );
      }
    }

    final ordenados = agrupados.values.toList()
      ..sort((a, b) => b.cantidad.compareTo(a.cantidad));
    if (ordenados.length <= 5) return ordenados;
    final otros = ordenados
        .skip(5)
        .fold<double>(0, (suma, item) => suma + item.cantidad);
    final importeOtros = ordenados
        .skip(5)
        .fold<double>(0, (suma, item) => suma + item.importe);
    return <_ProductoCompra>[
      ...ordenados.take(5),
      _ProductoCompra(nombre: 'Otros', cantidad: otros, importe: importeOtros),
    ];
  }

  List<_ProductoCompra> get _proveedoresYGastos {
    final agrupados = <String, _ProductoCompra>{};
    for (final comprobante in _filtrados) {
      final total = comprobante.total;
      if (total <= 0) continue;
      final nombre = comprobante['rSocial'].trim().isEmpty
          ? comprobante['ruc'].trim().isEmpty
                ? 'Sin proveedor'
                : comprobante['ruc'].trim()
          : comprobante['rSocial'].trim();
      final documento = comprobante['ruc'].trim();
      final clave = documento.isNotEmpty
          ? 'ruc:${documento.toUpperCase()}'
          : 'nombre:${nombre.toUpperCase()}';
      final previo = agrupados[clave];
      agrupados[clave] = _ProductoCompra(
        nombre: nombre,
        cantidad: total + (previo?.cantidad ?? 0),
        importe: total + (previo?.importe ?? 0),
      );
    }

    if (_centroCostoSeleccionado.isEmpty) {
      final desde = DateTime(_desde.year, _desde.month, _desde.day);
      final hasta = DateTime(_hasta.year, _hasta.month, _hasta.day, 23, 59, 59);
      for (final movimiento in Repositorio.i.movimientosCaja) {
        if (movimiento.esIngreso ||
            movimiento.comprobanteId.isNotEmpty ||
            movimiento.monto <= 0 ||
            _cajaSeleccionadaId == _sinCaja ||
            (_cajaSeleccionadaId.isNotEmpty &&
                movimiento.cajaId != _cajaSeleccionadaId)) {
          continue;
        }
        if (_usarRangoFechas &&
            (movimiento.fecha.isBefore(desde) ||
                movimiento.fecha.isAfter(hasta))) {
          continue;
        }
        final categoria = movimiento.tipoMovimiento.trim().isNotEmpty
            ? movimiento.tipoMovimiento.trim()
            : movimiento.concepto.trim();
        final nombre =
            'Gasto Caja · ${categoria.isEmpty ? 'Sin concepto' : categoria}';
        final clave = 'gasto:${movimiento.cajaId}:${categoria.toUpperCase()}';
        final previo = agrupados[clave];
        agrupados[clave] = _ProductoCompra(
          nombre: nombre,
          cantidad: movimiento.monto + (previo?.cantidad ?? 0),
          importe: movimiento.monto + (previo?.importe ?? 0),
        );
      }
    }

    final ordenados = agrupados.values.toList()
      ..sort((a, b) => b.importe.compareTo(a.importe));
    if (ordenados.length <= 5) return ordenados;
    final otros = ordenados.skip(5);
    final otrosTotal = otros.fold<double>(
      0,
      (suma, item) => suma + item.importe,
    );
    return <_ProductoCompra>[
      ...ordenados.take(5),
      _ProductoCompra(
        nombre: 'Otros',
        cantidad: otrosTotal,
        importe: otrosTotal,
      ),
    ];
  }

  static double _numeroReporte(dynamic valor) {
    if (valor is num) return valor.toDouble();
    var texto = '${valor ?? ''}'.trim();
    if (texto.contains(',') && texto.contains('.')) {
      texto = texto.replaceAll(',', '');
    } else if (texto.contains(',')) {
      texto = texto.replaceAll(',', '.');
    }
    return double.tryParse(texto) ?? 0;
  }

  // --------------------------------------------------------------- acciones ---

  Future<void> _elegir(DateTime actual, bool esDesde) async {
    final elegida = await showDatePicker(
      context: context,
      initialDate: actual,
      firstDate: DateTime(2015),
      lastDate: DateTime(2100),
      helpText: esDesde ? 'Desde' : 'Hasta',
      cancelText: 'Cancelar',
      confirmText: 'Aceptar',
    );
    if (elegida == null || !mounted) return;
    setState(() {
      if (esDesde) {
        _desde = elegida;
        if (_hasta.isBefore(elegida)) _hasta = elegida;
      } else {
        _hasta = elegida;
        if (_desde.isAfter(elegida)) _desde = elegida;
      }
    });
  }

  void _rango(String tipo) {
    final hoy = DateTime.now();
    setState(() {
      switch (tipo) {
        case 'hoy':
          _desde = DateTime(hoy.year, hoy.month, hoy.day);
          _hasta = _desde;
        case 'mes':
          _desde = DateTime(hoy.year, hoy.month, 1);
          _hasta = DateTime(hoy.year, hoy.month, hoy.day);
        case 'anterior':
          final primero = DateTime(hoy.year, hoy.month - 1, 1);
          _desde = primero;
          _hasta = DateTime(primero.year, primero.month + 1, 0);
        default:
          _desde = DateTime(hoy.year, 1, 1);
          _hasta = DateTime(hoy.year, hoy.month, hoy.day);
      }
    });
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

  Future<void> _exportar() async {
    final filtrados = _filtrados;
    if (filtrados.isEmpty) {
      _aviso('No hay comprobantes en ese rango de fechas.', error: true);
      return;
    }
    final lista = await _elegirReenvio(
      filtrados,
      yaEnviados: (c) => c.estadoWhatsapp == 'enviado',
      canal: 'WhatsApp',
    );
    if (lista == null || lista.isEmpty || !mounted) return;
    setState(() {
      _ocupado = true;
      _mensajeOcupado = 'Generando Excel...';
    });
    try {
      final ruta = await ExcelServicio.generar(lista);
      if (!existeExporte(ruta)) {
        throw StateError('El archivo no se guardo en el telefono.');
      }
      if (!mounted) return;
      setState(() {
        _ocupado = false;
        _ultimoArchivo = ruta;
      });

      await compartirExporte(
        ruta,
        asunto: 'Compras SISCONT',
        texto:
            'Compras SISCONT del ${_fechaTexto(_desde)} al '
            '${_fechaTexto(_hasta)} · $_filtroCajaTexto '
            '(${lista.length} comprobante(s)).',
      );
      if (!mounted) return;
      final compartido = await _confirmarEnvioWhatsapp(lista.length);
      if (compartido) {
        for (final comprobante in lista) {
          await Repositorio.i.marcarEnviado(comprobante.id, porWhatsApp: true);
        }
        widget.onItemsChanged?.call();
        _aviso(
          'Se marcaron ${lista.length} comprobante(s) como enviados por WhatsApp.',
        );
      } else {
        _aviso(
          'Excel descargado; los comprobantes siguen pendientes por WhatsApp.',
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _ocupado = false);
      _aviso(
        'No se pudo completar la exportación por WhatsApp: $e',
        error: true,
      );
    }
  }

  Future<void> _enviarASiscont() async {
    final filtrados = _filtrados;
    if (filtrados.isEmpty) {
      _aviso('No hay comprobantes en ese rango de fechas.', error: true);
      return;
    }
    final lista = await _elegirReenvio(
      filtrados,
      yaEnviados: (c) => c.estadoSiscont == 'enviado',
      canal: 'SISCONT',
    );
    if (lista == null || lista.isEmpty || !mounted) return;

    late final List<AsientoCompra> asientos;
    try {
      asientos = lista.map(construirAsientoCompra).toList();
    } on FormatException catch (e) {
      _aviso(e.message.toString(), error: true);
      return;
    }

    final ajustes = <String>[];
    for (final asiento in asientos) {
      for (final linea in asiento.lineas) {
        if (linea.descripcion.startsWith('AJUSTE BASE/PRODUCTOS')) {
          ajustes.add('Voucher ${asiento.voucher}: ${linea.descripcion}');
        }
      }
    }

    try {
      final conexiones = Repositorio.i.conexionesLocales
          .where((conexion) => conexion.activa)
          .toList();
      if (!mounted) return;
      if (conexiones.isEmpty) {
        _aviso('No hay conexiones activas en SISCONT.', error: true);
        return;
      }
      final conexion = await _elegirConexion(conexiones);
      if (conexion == null || !mounted) return;

      final origenes = await WsCliente.i.listarOrigenes(conexion: conexion);
      if (!mounted) return;
      if (origenes.isEmpty) {
        _aviso(
          'La empresa no tiene orígenes contables configurados.',
          error: true,
        );
        return;
      }
      final origen = await _elegirOrigen(origenes);
      if (origen == null || !mounted) return;

      final confirmar = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Enviar comprobantes a SISCONT'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Se enviarán ${lista.length} comprobante(s) y '
                  '${asientos.fold<int>(0, (n, a) => n + a.lineas.length)} líneas '
                  'contables de $_filtroCajaTexto a ${conexion.nombre}, '
                  'origen ${origen.etiqueta}, del '
                  '${_fechaTexto(_desde)} al ${_fechaTexto(_hasta)}.',
                ),
                if (ajustes.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 12),
                  Text(
                    'Se agregarán ${ajustes.length} línea(s) visible(s) de '
                    'ajuste en la misma cuenta de gastos para cuadrar productos '
                    'con la base imponible:\n${ajustes.join('\n')}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
                const SizedBox(height: 12),
                const Text(
                  'El número de voucher y el período se tomarán de cada comprobante.',
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Enviar'),
            ),
          ],
        ),
      );
      if (confirmar != true || !mounted) return;

      setState(() {
        _ocupado = true;
        _mensajeOcupado = 'Enviando a SISCONT...';
      });
      final totalLineas = asientos.fold<int>(0, (n, a) => n + a.lineas.length);
      var guardadas = 0;
      for (var i = 0; i < lista.length; i++) {
        final comprobante = lista[i];
        final asiento = asientos[i];
        for (final linea in asiento.lineas) {
          try {
            await WsCliente.i.grabarVoucherLinea(
              conexion: conexion,
              datos: _datosLinea(comprobante, asiento, linea, origen.codigo),
            );
            guardadas++;
          } on WsException catch (e) {
            throw StateError(
              'SISCONT guardó $guardadas de $totalLineas líneas. '
              'Falló el voucher ${asiento.voucher}: ${e.mensaje}',
            );
          }
        }
        await Repositorio.i.marcarEnviado(comprobante.id, porWhatsApp: false);
        widget.onItemsChanged?.call();
      }
      if (!mounted) return;
      setState(() => _ocupado = false);
      _aviso(
        'Envío completado: ${lista.length} comprobante(s), '
        '$guardadas líneas en ${conexion.nombre}.',
      );
    } on WsException catch (e) {
      if (!mounted) return;
      _aviso(e.mensaje, error: true);
    } catch (e) {
      if (!mounted) return;
      _aviso('No se pudo completar el envío a SISCONT: $e', error: true);
    } finally {
      if (mounted && _ocupado) setState(() => _ocupado = false);
    }
  }

  Future<List<Comprobante>?> _elegirReenvio(
    List<Comprobante> lista, {
    required bool Function(Comprobante) yaEnviados,
    required String canal,
  }) async {
    final pendientes = lista.where((c) => !yaEnviados(c)).toList();
    if (pendientes.length == lista.length) return lista;

    final decision = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Comprobantes ya enviados a $canal'),
        content: Text(
          '${lista.length - pendientes.length} documento(s) del rango ya '
          'figuran como enviados por $canal. ¿Desea incluirlos nuevamente?',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancelar'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Solo pendientes'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Incluir enviados'),
          ),
        ],
      ),
    );
    if (decision == null || !mounted) return null;
    if (decision) return lista;
    if (pendientes.isEmpty) {
      _aviso(
        'Todos ya fueron enviados. Elija “Incluir enviados” para reenviarlos.',
      );
      return null;
    }
    return pendientes;
  }

  Future<bool> _confirmarEnvioWhatsapp(int cantidad) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Confirmar envío por WhatsApp'),
            content: Text(
              'El Excel se descargó o se abrió para compartir. ¿Confirmas que '
              'enviaste $cantidad comprobante(s) por WhatsApp?',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Aún no'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Sí, enviado'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Map<String, String> _datosLinea(
    Comprobante comprobante,
    AsientoCompra asiento,
    LineaAsientoCompra linea,
    String origen,
  ) {
    final cuenta = linea.cuenta;
    final razonSocial = comprobante['rSocial'].trim();
    final ruc = comprobante['ruc'].trim().isNotEmpty
        ? comprobante['ruc'].trim()
        : comprobante['codigo'].trim();
    final nombreCuenta = cuenta == comprobante['ctaGastos'].trim()
        ? 'GASTOS'
        : cuenta == comprobante['ctaIgv'].trim()
        ? 'IGV'
        : cuenta == comprobante['ctaOTrib'].trim()
        ? 'OTROS TRIBUTOS'
        : 'CUENTAS POR PAGAR';
    final glosa = linea.descripcion.trim().isNotEmpty
        ? linea.descripcion.trim()
        : comprobante['glosa'].trim().isNotEmpty
        ? comprobante['glosa'].trim()
        : 'COMPRA ${comprobante['numero']} $razonSocial'.trim();

    return <String, String>{
      'periodo': asiento.periodo,
      'origen': origen,
      'voucher': asiento.voucher,
      'prefijo': 'ONLIN',
      'cuenta': cuenta,
      'cuentaTexto': '$cuenta $nombreCuenta',
      'moneda': comprobante['moneda'] == 'D' ? 'D' : 'S',
      'tipocambio': asiento.tipoCambio.toStringAsFixed(7),
      'debe': linea.debe.toStringAsFixed(2),
      'haber': linea.haber.toStringAsFixed(2),
      'glosa': glosa.length > 60 ? glosa.substring(0, 60) : glosa,
      'centrocostos': comprobante['ccosto'],
      'presupuesto': comprobante['presupuesto'],
      'codigo': ruc,
      'clienteTexto': '$ruc $razonSocial'.trim(),
      'documento': comprobante['doc'],
      'documentoTexto': _nombreDocumento(comprobante['doc']),
      'serienumero': comprobante['numero'],
      'fechadoc': comprobante['fecDoc'],
      'fechavoucher': comprobante.fechaRegistroTexto,
      'fechavcto': comprobante['fecVenc'],
      'tdocr': comprobante['rDoc'],
      'numeror': comprobante['rNumero'],
      'fechar': comprobante['rFecha'],
      'montor': comprobante['bImp'].isEmpty ? '0' : comprobante['bImp'],
    };
  }

  String _nombreDocumento(String codigo) {
    switch (codigo) {
      case '01':
        return 'FACTURA';
      case '02':
        return 'BOLETA';
      case '03':
        return 'NOTA DE CREDITO';
      case '04':
        return 'NOTA DE DEBITO';
      case '07':
        return 'RETENCION';
      case '08':
        return 'RECIBO POR HONORARIOS';
      default:
        return codigo;
    }
  }

  Future<Conexion?> _elegirConexion(List<Conexion> conexiones) {
    return showDialog<Conexion>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Seleccionar empresa SISCONT'),
        content: SizedBox(
          width: 420,
          child: ListView(
            shrinkWrap: true,
            children: <Widget>[
              for (final conexion in conexiones)
                ListTile(
                  leading: const Icon(Icons.storage_outlined),
                  title: Text(conexion.nombre),
                  subtitle: Text(conexion.subtitulo),
                  onTap: () => Navigator.of(ctx).pop(conexion),
                ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
  }

  Future<OrigenVoucher?> _elegirOrigen(List<OrigenVoucher> origenes) {
    return showDialog<OrigenVoucher>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Seleccionar origen contable'),
        content: SizedBox(
          width: 420,
          child: ListView(
            shrinkWrap: true,
            children: <Widget>[
              for (final origen in origenes)
                ListTile(
                  leading: const Icon(Icons.book_outlined),
                  title: Text(origen.etiqueta),
                  onTap: () => Navigator.of(ctx).pop(origen),
                ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
  }

  static String _fechaTexto(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  static String _money(double v) => v.toStringAsFixed(2);

  // -------------------------------------------------------------------- ui ---

  @override
  Widget build(BuildContext context) {
    final lista = _filtrados;
    return Stack(
      children: <Widget>[
        ListView(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 16),
          children: <Widget>[
            Tarjeta(
              titulo: 'RENDICIÓN ACTUAL',
              icono: Icons.receipt_long_outlined,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              hijo: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    _cajaSeleccionadaId.isEmpty
                        ? 'Mostrando comprobantes de todas las cajas.'
                        : _cajaSeleccionadaId == _sinCaja
                        ? 'Mostrando comprobantes sin caja asignada.'
                        : 'Se incluirán ${lista.length} comprobante(s) de '
                              '$_filtroCajaTexto.',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Paleta.footerTexto,
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    key: ValueKey<String>('reporte-caja-$_cajaSeleccionadaId'),
                    initialValue: _cajaSeleccionadaId,
                    decoration: const InputDecoration(labelText: 'Caja'),
                    items: <DropdownMenuItem<String>>[
                      const DropdownMenuItem<String>(
                        value: '',
                        child: Text('Todas las cajas'),
                      ),
                      for (final caja in _cajasReporte)
                        DropdownMenuItem<String>(
                          value: caja.id,
                          child: Text(
                            'Caja ${caja.moneda} · '
                            '${caja.estaAbierta ? 'Abierta' : 'Cerrada'}'
                            '${caja.voucher == null ? '' : ' · Voucher ${caja.voucher}'}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      const DropdownMenuItem<String>(
                        value: _sinCaja,
                        child: Text('Sin caja asignada'),
                      ),
                    ],
                    onChanged: (id) {
                      if (id != null) _seleccionarCajaReporte(id);
                    },
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    key: ValueKey<String>(
                      'reporte-centro-$_centroCostoSeleccionado',
                    ),
                    initialValue: _centroCostoSeleccionado,
                    decoration: const InputDecoration(
                      labelText: 'Centro de costos',
                    ),
                    items: <DropdownMenuItem<String>>[
                      const DropdownMenuItem<String>(
                        value: '',
                        child: Text('Todos los centros de costos'),
                      ),
                      for (final centro in _centrosCostoReporte)
                        DropdownMenuItem<String>(
                          value: centro.codigo,
                          child: Text(
                            centro.nombre,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (codigo) {
                      if (codigo != null) {
                        setState(() => _centroCostoSeleccionado = codigo);
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    key: ValueKey<String>('reporte-desglose-$_desgloseGrafico'),
                    initialValue: _desgloseGrafico,
                    decoration: const InputDecoration(
                      labelText: 'Mostrar gráfico por',
                    ),
                    items: const <DropdownMenuItem<String>>[
                      DropdownMenuItem<String>(
                        value: 'productos',
                        child: Text('Productos más comprados'),
                      ),
                      DropdownMenuItem<String>(
                        value: 'proveedores',
                        child: Text('Proveedores y gastos'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _desgloseGrafico = value);
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    key: const ValueKey<String>('reporte-toggle-fechas'),
                    onPressed: () {
                      setState(() {
                        _usarRangoFechas = !_usarRangoFechas;
                        if (_usarRangoFechas) {
                          _cajaSeleccionadaId = '';
                          final hoy = DateTime.now();
                          _desde = DateTime(hoy.year, hoy.month, 1);
                          _hasta = DateTime(hoy.year, hoy.month, hoy.day);
                        }
                      });
                    },
                    icon: Icon(
                      _usarRangoFechas
                          ? Icons.close
                          : Icons.date_range_outlined,
                    ),
                    label: Text(
                      _usarRangoFechas
                          ? 'Ocultar rango de fechas'
                          : 'Buscar por rango de fechas',
                    ),
                  ),
                  if (_usarRangoFechas) ...<Widget>[
                    const SizedBox(height: 8),
                    const Text(
                      'RANGO DE FECHAS',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Paleta.etiqueta,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: <Widget>[
                        Expanded(child: _campoFecha('Desde', _desde, true)),
                        const SizedBox(width: 8),
                        Expanded(child: _campoFecha('Hasta', _hasta, false)),
                      ],
                    ),
                    const Padding(
                      padding: EdgeInsets.only(top: 5),
                      child: Text(
                        'El rango usa la fecha de registro; la fecha del documento se conserva aparte.',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: Paleta.footerTexto,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: <Widget>[
                        _chip('Hoy', () => _rango('hoy')),
                        _chip('Este mes', () => _rango('mes')),
                        _chip('Mes anterior', () => _rango('anterior')),
                        _chip('Este año', () => _rango('anio')),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            Tarjeta(
              titulo: _desgloseGrafico == 'productos'
                  ? 'PRODUCTOS MÁS COMPRADOS'
                  : 'PROVEEDORES Y GASTOS',
              icono: Icons.pie_chart_outline,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              hijo: _graficoReporte(),
            ),
            Tarjeta(
              titulo: 'VISTA PREVIA DEL EXCEL',
              icono: Icons.table_chart_outlined,
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
              hijo: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      _dato('${lista.length}', 'Comprobantes'),
                      _sep(),
                      _dato('S/ ${_money(_total)}', 'Total'),
                      _sep(),
                      _dato('${columnas.length}', 'Columnas SISCONT'),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (lista.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: Text(
                          'No hay comprobantes guardados en ese rango.\n'
                          'Cambie las fechas o la Caja seleccionada.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Paleta.footerTexto,
                          ),
                        ),
                      ),
                    )
                  else
                    _tabla(lista),
                ],
              ),
            ),
            if (_ultimoArchivo.isNotEmpty)
              Tarjeta(
                titulo: 'ULTIMO EXCEL GUARDADO',
                icono: Icons.check_circle_outline,
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                hijo: Text(
                  nombreDeReferencia(_ultimoArchivo),
                  style: const TextStyle(fontSize: 12.5),
                ),
              ),
          ],
        ),
        if (_ocupado)
          Positioned.fill(
            child: ColoredBox(
              color: Colors.black54,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 12),
                    Text(
                      _mensajeOcupado,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final whatsapp = SizedBox(
                    height: 48,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF25D366),
                        foregroundColor: Colors.black87,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: (_ocupado || lista.isEmpty) ? null : _exportar,
                      icon: const Icon(Icons.share_outlined, size: 20),
                      label: Text(
                        _cajaSeleccionadaId.isEmpty
                            ? 'ENVIAR EXCEL POR WHATSAPP'
                            : 'EXCEL / WHATSAPP · '
                                  '${_filtroCajaTexto.toUpperCase()}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  );
                  final siscont = SizedBox(
                    height: 48,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Paleta.panel,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: (_ocupado || lista.isEmpty)
                          ? null
                          : _enviarASiscont,
                      icon: const Icon(Icons.cloud_upload_outlined, size: 20),
                      label: Text(
                        _cajaSeleccionadaId.isEmpty
                            ? 'ENVIAR A SISCONT'
                            : 'ENVIAR A SISCONT · '
                                  '${_filtroCajaTexto.toUpperCase()}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  );
                  if (constraints.maxWidth < 560) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        whatsapp,
                        const SizedBox(height: 8),
                        siscont,
                      ],
                    );
                  }

                  return Row(
                    children: <Widget>[
                      Expanded(child: whatsapp),
                      const SizedBox(width: 10),
                      Expanded(child: siscont),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _graficoReporte() {
    final esProductos = _desgloseGrafico == 'productos';
    final datos = esProductos ? _productosMasComprados : _proveedoresYGastos;
    if (datos.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Center(
          child: Text(
            'No hay datos para mostrar en esta Caja, centro y rango.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: Paleta.footerTexto),
          ),
        ),
      );
    }
    final total = datos.fold<double>(
      0,
      (suma, item) => suma + (esProductos ? item.cantidad : item.importe),
    );
    final totalImporte = datos.fold<double>(
      0,
      (suma, item) => suma + item.importe,
    );
    return Column(
      children: <Widget>[
        SizedBox(
          width: 220,
          height: 220,
          child: CustomPaint(
            painter: _GraficoTortaPainter(datos, usarCantidad: esProductos),
          ),
        ),
        Text(
          esProductos
              ? 'Total unidades/ítems: ${_money(total)} · Importe: S/ ${_money(totalImporte)}'
              : 'Total compras y gastos: S/ ${_money(totalImporte)}',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < datos.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: <Widget>[
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: _GraficoTortaPainter.colores[i],
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    datos[i].nombre,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                Text(
                  esProductos
                      ? '${_money(datos[i].cantidad)} ítem(s) · '
                            'S/ ${_money(datos[i].importe)} '
                            '(${(datos[i].cantidad * 100 / total).toStringAsFixed(1)}%)'
                      : 'S/ ${_money(datos[i].importe)} '
                            '(${(datos[i].importe * 100 / total).toStringAsFixed(1)}%)',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _campoFecha(String etiqueta, DateTime fecha, bool esDesde) {
    return InkWell(
      onTap: () => _elegir(fecha, esDesde),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          border: Border.all(color: Paleta.controlBorde),
          borderRadius: BorderRadius.circular(6),
          color: Colors.white,
        ),
        child: Row(
          children: <Widget>[
            const Icon(Icons.calendar_today_outlined, size: 15),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    etiqueta,
                    style: const TextStyle(
                      fontSize: 10,
                      color: Paleta.footerTexto,
                    ),
                  ),
                  Text(
                    _fechaTexto(fecha),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String texto, VoidCallback onTap) => OutlinedButton(
    onPressed: onTap,
    style: OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      minimumSize: const Size(0, 30),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: const TextStyle(fontSize: 11.5),
    ),
    child: Text(texto),
  );

  Widget _tabla(List<Comprobante> lista) {
    const anchos = <double>[82, 82, 45, 110, 95, 170, 85, 45, 95, 95];
    const titulos = <String>[
      'Fec.Reg.',
      'Fec.Doc',
      'Doc',
      'Numero',
      'RUC',
      'R.Social',
      'Total',
      'Mon.',
      'WhatsApp',
      'SISCONT',
    ];
    return SizedBox(
      height: 320,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: anchos.fold<double>(0, (s, w) => s + w),
          child: Column(
            children: <Widget>[
              Container(
                height: 26,
                color: Paleta.panel,
                child: Row(
                  children: <Widget>[
                    for (var i = 0; i < titulos.length; i++)
                      SizedBox(
                        width: anchos[i],
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Align(
                            alignment: i == 6
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Text(
                              titulos[i],
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: lista.length,
                  itemBuilder: (_, i) {
                    final c = lista[i];
                    final valores = <String>[
                      c.fechaRegistroTexto,
                      c['fecDoc'],
                      c['doc'],
                      c['numero'],
                      c['ruc'],
                      c['rSocial'],
                      _money(c.total),
                      c['moneda'],
                      c.estadoWhatsapp == 'enviado' ? 'Enviado' : 'Pendiente',
                      c.estadoSiscont == 'enviado' ? 'Enviado' : 'Pendiente',
                    ];
                    return Container(
                      height: 28,
                      decoration: BoxDecoration(
                        color: i.isEven
                            ? Colors.white
                            : const Color(0xFFF7F9FA),
                        border: const Border(
                          bottom: BorderSide(color: Color(0xFFE3E7EA)),
                        ),
                      ),
                      child: Row(
                        children: <Widget>[
                          for (var j = 0; j < valores.length; j++)
                            SizedBox(
                              width: anchos[j],
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                child: Align(
                                  alignment: j == 6
                                      ? Alignment.centerRight
                                      : Alignment.centerLeft,
                                  child: Text(
                                    valores[j],
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 11.5),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

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

  Widget _sep() => Container(
    width: 1,
    height: 28,
    color: Paleta.navbarBorde,
    margin: const EdgeInsets.symmetric(horizontal: 8),
  );
}

class _ProductoCompra {
  final String nombre;
  final double cantidad;
  final double importe;

  const _ProductoCompra({
    required this.nombre,
    required this.cantidad,
    required this.importe,
  });
}

class _GraficoTortaPainter extends CustomPainter {
  static const List<Color> colores = <Color>[
    Color(0xFF176B87),
    Color(0xFF64CCC5),
    Color(0xFFFFB84C),
    Color(0xFF9B5DE5),
    Color(0xFFF15BB5),
    Color(0xFF8A9A5B),
  ];

  final List<_ProductoCompra> datos;
  final bool usarCantidad;

  const _GraficoTortaPainter(this.datos, {required this.usarCantidad});

  @override
  void paint(Canvas canvas, Size size) {
    final total = datos.fold<double>(
      0,
      (suma, item) => suma + (usarCantidad ? item.cantidad : item.importe),
    );
    if (total <= 0) return;
    final bounds = Rect.fromLTWH(0, 0, size.width, size.height);
    final paint = Paint()..style = PaintingStyle.fill;
    var inicio = -math.pi / 2;
    for (var i = 0; i < datos.length; i++) {
      final valor = usarCantidad ? datos[i].cantidad : datos[i].importe;
      final barrido = valor / total * math.pi * 2;
      paint.color = colores[i];
      canvas.drawArc(bounds, inicio, barrido, true, paint);
      inicio += barrido;
    }
  }

  @override
  bool shouldRepaint(_GraficoTortaPainter oldDelegate) =>
      oldDelegate.datos != datos || oldDelegate.usarCantidad != usarCantidad;
}
