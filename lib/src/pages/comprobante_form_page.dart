import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/comprobante.dart';
import '../models/tercero_local.dart';
import '../services/groq_servicio.dart';
import '../services/mapeo_comprobante.dart';
import '../storage/repositorio.dart';
import '../theme/tema.dart';
import '../widgets/entrada.dart';

/// Formulario con las 61 columnas del Excel de compras. Llega precargado por la
/// IA y el usuario corrige lo que haga falta antes de guardar en el telefono.
class ComprobanteFormPage extends StatefulWidget {
  final Comprobante comprobante;
  final bool nuevo;

  const ComprobanteFormPage({
    super.key,
    required this.comprobante,
    this.nuevo = false,
  });

  @override
  State<ComprobanteFormPage> createState() => _ComprobanteFormPageState();
}

class _ComprobanteFormPageState extends State<ComprobanteFormPage> {
  late final Comprobante _c = widget.comprobante;
  bool get _esRegistroManual =>
      _c.motor == 'manual' && _c.archivo.trim().isEmpty;
  final Map<String, TextEditingController> _ctrl =
      <String, TextEditingController>{};
  late List<_DetalleItem> _detalleItems = _leerDetalleItems(_c['detalleItems']);
  String? _errorDetalle;
  bool _leyendo = false;
  bool _mostrarMasCampos = false;
  late String _tipoAfectacion;
  late final TextEditingController _montoManual;

  @override
  void initState() {
    super.initState();
    if (_esRegistroManual) {
      _c['doc'] = '00';
      if (_c['numero'].trim().isEmpty) {
        _c['numero'] = '00000000';
      }
      if (widget.nuevo) {
        _c['tipDocIden'] = '0';
      }
      if (_c['rSocial'].trim().isEmpty) {
        _c['rSocial'] = 'PROVEEDORES VARIOS';
      }
      if (_c['ctaGastos'].trim().isEmpty ||
          _c['ctaGastos'].trim() == '601' ||
          _c['ctaGastos'].trim() == '656') {
        _c['ctaGastos'] = '60001';
      }
    }
    if (widget.nuevo) {
      _c['vouOrigen'] = Repositorio.i.origenesCaja.gasto;
      final cuentas = Repositorio.i.cuentasContablesExcel;
      for (final clave in <String>[
        'ctaGastos',
        'ctaIgv',
        'ctaOTrib',
        'ctaXPagar',
      ]) {
        _c[clave] = cuentas[clave]!;
      }
    }
    if ((_c['ccosto'].trim().isEmpty || _c['ccosto'] == '000') &&
        _c['presupuesto'].trim().isNotEmpty &&
        _c['presupuesto'] != '000') {
      _c['ccosto'] = _c['presupuesto'];
    }
    if (_c['ccosto'].trim().isEmpty) _c['ccosto'] = '000';
    if (widget.nuevo && _c['moneda'] == 'D' && _numero(_c['tc']) <= 1) {
      final tipoCambio = Repositorio.i.tipoCambioDiario;
      if (tipoCambio > 1) _c['tc'] = tipoCambio.toStringAsFixed(3);
    }
    _tipoAfectacion = _afectacionGuardada();
    for (final d in columnas) {
      _ctrl[d.clave] = TextEditingController(text: _c[d.clave]);
    }
    _montoManual = TextEditingController(
      text: _baseGuardada(_tipoAfectacion).toStringAsFixed(2),
    );
    if (_esRegistroManual || _c.archivo.trim().isNotEmpty) {
      final cajas = Repositorio.i.cajasActivas;
      final cajaGuardada = cajas
          .where((caja) => caja.id == _c['cajaId'])
          .firstOrNull;
      final cajaPredeterminada =
          cajaGuardada ??
          Repositorio.i.cajaActivaParaMoneda(
            _ctrl['moneda']!.text == 'D' ? 'USD' : 'PEN',
          ) ??
          cajas.firstOrNull;
      if (cajaPredeterminada != null) {
        _c['cajaId'] = cajaPredeterminada.id;
      }
    }
    final proveedor = _proveedorIdentificado;
    if (proveedor != null) _aplicarAsignacionesProveedor(proveedor);
    if (_esRegistroManual) _aplicarAfectacion();
  }

  @override
  void dispose() {
    _montoManual.dispose();
    for (final c in _ctrl.values) {
      c.dispose();
    }
    super.dispose();
  }

  bool _expandida(String seccion) => const <String>{
    'Documento',
    'Importes',
    'Proveedor',
    'Cuentas',
  }.contains(seccion);

  String _afectacionGuardada() {
    if (_numero(_c['igvB']) > 0) return '10.5';
    if (_numero(_c['adNoGrav']) > 0) return 'exonerado';
    if (_numero(_c['biogC']) > 0) return 'inafecto';
    return '18';
  }

  double _baseGuardada(String afectacion) => switch (afectacion) {
    '10.5' => _numero(_c['biogB']),
    'exonerado' => _numero(_c['adNoGrav']),
    'inafecto' => _numero(_c['biogC']),
    _ => _numero(_c['biogA']),
  };

  void _aplicarAfectacion() {
    final monto = _numero(_montoManual.text);
    for (final clave in <String>[
      'biogA',
      'biogB',
      'biogC',
      'adNoGrav',
      'igvA',
      'igvB',
      'igvC',
    ]) {
      _ctrl[clave]!.text = '0';
    }

    switch (_tipoAfectacion) {
      case '10.5':
        _ctrl['biogB']!.text = monto.toStringAsFixed(2);
        _ctrl['igvB']!.text = _redondearMoneda(monto * 0.105);
      case 'exonerado':
        _ctrl['adNoGrav']!.text = monto.toStringAsFixed(2);
      case 'inafecto':
        _ctrl['biogC']!.text = monto.toStringAsFixed(2);
      default:
        _ctrl['biogA']!.text = monto.toStringAsFixed(2);
        _ctrl['igvA']!.text = _redondearMoneda(monto * 0.18);
    }
  }

  String _redondearMoneda(double monto) =>
      ((monto * 100).round() / 100).toStringAsFixed(2);

  String get _simboloMoneda => _ctrl['moneda']!.text == 'D' ? r'$ ' : 'S/ ';

  TerceroLocal? get _proveedorIdentificado {
    final proveedores = Repositorio.i.proveedoresLocales;
    final numero = _ctrl['ruc']!.text.trim();
    final numeroNormalizado = numero.replaceAll(RegExp(r'\D'), '');
    final nombre = _ctrl['rSocial']!.text.trim().toLowerCase();
    final encontradoPorDocumento = proveedores.where((proveedor) {
      final documentoProveedor = proveedor.numeroDocumento.replaceAll(
        RegExp(r'\D'),
        '',
      );
      return numeroNormalizado.isNotEmpty &&
          documentoProveedor.isNotEmpty &&
          documentoProveedor == numeroNormalizado;
    }).firstOrNull;
    if (encontradoPorDocumento != null) return encontradoPorDocumento;

    final encontradoPorNombre = proveedores
        .where(
          (proveedor) =>
              nombre.isNotEmpty &&
              proveedor.nombre.trim().toLowerCase() == nombre,
        )
        .firstOrNull;
    if (encontradoPorNombre != null) return encontradoPorNombre;
    if (_esRegistroManual) {
      return proveedores
          .where(
            (proveedor) =>
                proveedor.nombre.trim().toUpperCase() == 'PROVEEDORES VARIOS',
          )
          .firstOrNull;
    }
    return null;
  }

  void _aplicarAsignacionesProveedor(TerceroLocal proveedor) {
    if (proveedor.centroCostoCodigo.isNotEmpty) {
      _ctrl['ccosto']!.text = proveedor.centroCostoCodigo;
      _c['ccosto'] = proveedor.centroCostoCodigo;
    }
    if (proveedor.conceptoGastoCodigo.isNotEmpty) {
      _ctrl['ctaGastos']!.text = proveedor.conceptoGastoCodigo;
      _c['ctaGastos'] = proveedor.conceptoGastoCodigo;
    }
  }

  void _actualizarDatosProveedor(TerceroLocal proveedor) {
    final tipoDocIdentidad = switch (proveedor.tipoDocumento) {
      'RUC' => '6',
      'DNI' => '1',
      'CE' => '4',
      'Pasaporte' => '7',
      _ => '0',
    };
    _ctrl['ruc']!.text = proveedor.numeroDocumento;
    _ctrl['codigo']!.text = proveedor.numeroDocumento;
    _ctrl['rSocial']!.text = proveedor.nombre;
    _ctrl['tipDocIden']!.text = tipoDocIdentidad;
    _aplicarAsignacionesProveedor(proveedor);
  }

  Widget _selectorCaja({bool sincronizarMoneda = false}) {
    final cajas = Repositorio.i.cajasActivas;
    final seleccionada = cajas
        .where((caja) => caja.id == _c['cajaId'])
        .firstOrNull;
    if (cajas.isEmpty) {
      return const InputDecorator(
        decoration: InputDecoration(labelText: 'Caja'),
        child: Text('No hay cajas abiertas'),
      );
    }
    return DropdownButtonFormField<String>(
      key: ValueKey<String>('caja-manual-${seleccionada?.id ?? ''}'),
      initialValue: seleccionada?.id,
      decoration: const InputDecoration(labelText: 'Caja'),
      items: <DropdownMenuItem<String>>[
        for (final caja in cajas)
          DropdownMenuItem<String>(
            value: caja.id,
            child: Text(caja.moneda == 'USD' ? 'Caja USD' : 'Caja PEN'),
          ),
      ],
      onChanged: (id) {
        if (id == null) return;
        final caja = cajas.firstWhere((item) => item.id == id);
        setState(() {
          _c['cajaId'] = caja.id;
          if (sincronizarMoneda) {
            _ctrl['moneda']!.text = caja.moneda == 'USD' ? 'D' : 'S';
            _c['moneda'] = _ctrl['moneda']!.text;
            final tipoCambio = caja.moneda == 'USD'
                ? Repositorio.i.tipoCambioDiario
                : 1.0;
            if (tipoCambio > 1 || caja.moneda != 'USD') {
              _ctrl['tc']!.text = tipoCambio.toStringAsFixed(3);
              _c['tc'] = _ctrl['tc']!.text;
            }
          }
        });
      },
    );
  }

  Widget _selectorProveedorManual() {
    final proveedores = Repositorio.i.proveedoresLocales;
    final seleccionado = _proveedorIdentificado;
    return DropdownButtonFormField<String>(
      key: ValueKey<String>('proveedor-manual-${seleccionado?.id ?? ''}'),
      initialValue: seleccionado?.id,
      decoration: const InputDecoration(labelText: 'Proveedor'),
      items: <DropdownMenuItem<String>>[
        for (final proveedor in proveedores)
          DropdownMenuItem<String>(
            value: proveedor.id,
            child: Text(proveedor.nombre, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (id) {
        if (id == null) return;
        final proveedor = proveedores.firstWhere((item) => item.id == id);
        setState(() {
          _actualizarDatosProveedor(proveedor);
        });
      },
    );
  }

  void _volcar() {
    for (final d in columnas) {
      _c[d.clave] = _ctrl[d.clave]!.text.trim();
    }
    _c['detalleItems'] = jsonEncode(
      _detalleItems
          .where(
            (item) =>
                item.descripcion.trim().isNotEmpty && _numero(item.importe) > 0,
          )
          .map((item) => item.toJson())
          .toList(),
    );
  }

  Widget _selectoresCatalogosLocales() => Tarjeta(
    titulo: 'ASIGNACIÓN LOCAL',
    icono: Icons.account_tree_outlined,
    hijo: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _selectorCentroCosto(),
        const SizedBox(height: 12),
        _selectorConcepto(),
        const SizedBox(height: 12),
        _selectorCaja(),
      ],
    ),
  );

  Widget _selectorConcepto() {
    final conceptos = Repositorio.i.conceptosGastoLocales;
    final codigoGuardado = _ctrl['ctaGastos']!.text.trim();
    final codigos = conceptos.map((concepto) => concepto.codigo).toSet();
    final opciones = <DropdownMenuItem<String>>[
      for (final concepto in conceptos)
        DropdownMenuItem<String>(
          value: concepto.codigo,
          child: Text(concepto.nombre, overflow: TextOverflow.ellipsis),
        ),
      if (codigoGuardado.isNotEmpty && !codigos.contains(codigoGuardado))
        DropdownMenuItem<String>(
          value: codigoGuardado,
          child: const Text('Guardado anteriormente'),
        ),
    ];
    final valor = codigos.contains(codigoGuardado)
        ? codigoGuardado
        : (codigoGuardado.isNotEmpty
              ? codigoGuardado
              : (codigos.contains('60001')
                    ? '60001'
                    : opciones.firstOrNull?.value));

    return DropdownButtonFormField<String>(
      key: ValueKey<String>('concepto-gasto-$valor'),
      initialValue: valor,
      decoration: const InputDecoration(labelText: 'Concepto de gasto'),
      items: opciones,
      onChanged: (seleccion) {
        if (seleccion == null) return;
        setState(() {
          _ctrl['ctaGastos']!.text = seleccion;
          _c['ctaGastos'] = seleccion;
        });
      },
    );
  }

  Widget _selectorCentroCosto() {
    final centros = Repositorio.i.centrosCostoLocales;
    final codigoGuardado = _ctrl['ccosto']!.text.trim();
    final codigos = centros.map((centro) => centro.codigo).toSet();
    final opciones = <DropdownMenuItem<String>>[
      if (centros.isEmpty || !codigos.contains('000'))
        const DropdownMenuItem<String>(
          value: '000',
          child: Text('Sin asignar'),
        ),
      for (final centro in centros)
        DropdownMenuItem<String>(
          value: centro.codigo,
          child: Text(centro.nombre, overflow: TextOverflow.ellipsis),
        ),
      if (codigoGuardado.isNotEmpty &&
          !codigos.contains(codigoGuardado) &&
          codigoGuardado != '000')
        DropdownMenuItem<String>(
          value: codigoGuardado,
          child: const Text('Guardado anteriormente'),
        ),
    ];
    final valor = opciones.any((opcion) => opcion.value == codigoGuardado)
        ? codigoGuardado
        : '000';

    return DropdownButtonFormField<String>(
      key: ValueKey<String>('centrocosto-$valor'),
      initialValue: valor,
      decoration: const InputDecoration(labelText: 'Centro de costos'),
      items: opciones,
      onChanged: (seleccion) {
        if (seleccion == null) return;
        setState(() {
          _ctrl['ccosto']!.text = seleccion;
          _c['ccosto'] = seleccion;
        });
      },
    );
  }

  void _guardar() {
    if (_esRegistroManual &&
        (!_numero(_montoManual.text).isFinite ||
            _numero(_montoManual.text) <= 0)) {
      _aviso('Ingrese un monto mayor que cero.', error: true);
      return;
    }
    if (_esRegistroManual) _ctrl['doc']!.text = '00';
    if (_esRegistroManual) _aplicarAfectacion();
    _volcar();
    Navigator.of(context).pop<Comprobante>(_c);
  }

  Future<void> _seleccionarProveedorLocal() async {
    final proveedores = Repositorio.i.proveedoresLocales;
    if (proveedores.isEmpty) {
      _aviso(
        'Todavía no hay proveedores locales. Guarde el comprobante y sus datos '
        'se agregarán automáticamente, o regístrelo desde Proveedores locales.',
        error: true,
      );
      return;
    }
    final proveedor = await showDialog<TerceroLocal>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Seleccionar proveedor local'),
        content: SizedBox(
          width: 420,
          height: 360,
          child: ListView.builder(
            itemCount: proveedores.length,
            itemBuilder: (context, index) {
              final item = proveedores[index];
              return ListTile(
                leading: const Icon(Icons.storefront_outlined),
                title: Text(item.nombre),
                subtitle: Text('${item.tipoDocumento} ${item.numeroDocumento}'),
                onTap: () => Navigator.pop(context, item),
              );
            },
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
    if (proveedor == null || !mounted) return;
    setState(() {
      _actualizarDatosProveedor(proveedor);
    });
  }

  Future<void> _releer() async {
    if (_c.archivo.isEmpty) return;
    setState(() => _leyendo = true);
    try {
      final camposConfigurados = <String>{
        'vouOrigen',
        'ctaGastos',
        'ctaIgv',
        'ctaOTrib',
        'ctaXPagar',
        'ccosto',
        'presupuesto',
      };
      final valoresConfigurados = <String, String>{
        for (final clave in camposConfigurados) clave: _ctrl[clave]!.text,
      };
      final tipoCambioSeleccionado = _numero(_ctrl['tc']!.text);
      final r = await const GroqServicio().analizar(_c.archivo);
      final leido = comprobanteDesdeIa(
        r.datos,
        archivo: _c.archivo,
        motor: r.motor,
        voucher: int.tryParse(_c['vouNumero']) ?? 0,
      );
      leido.id = _c.id;
      leido.creado = _c.creado;
      for (final d in columnas) {
        final configurado = valoresConfigurados[d.clave]?.trim() ?? '';
        final conservarTipoCambio =
            d.clave == 'tc' && tipoCambioSeleccionado > 1;
        final valor = configurado.isNotEmpty
            ? configurado
            : conservarTipoCambio
            ? tipoCambioSeleccionado.toStringAsFixed(3)
            : leido[d.clave];
        _c[d.clave] = valor;
        _ctrl[d.clave]!.text = valor;
      }
      final proveedor = _proveedorIdentificado;
      if (proveedor != null) _aplicarAsignacionesProveedor(proveedor);
      if (!mounted) return;
      setState(() {
        _leyendo = false;
        _reemplazarDetalleItems(leido['detalleItems']);
      });
      _aviso('Datos leidos de nuevo. Revise antes de guardar.');
    } on IaException catch (e) {
      if (!mounted) return;
      setState(() => _leyendo = false);
      _aviso(e.mensaje, error: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _leyendo = false);
      _aviso('No se pudo leer: $e', error: true);
    }
  }

  List<_DetalleItem> _leerDetalleItems(String fuente) {
    if (fuente.trim().isEmpty) return <_DetalleItem>[];
    try {
      final decoded = jsonDecode(fuente);
      if (decoded is! List) {
        _errorDetalle = 'El detalle guardado no tiene un formato válido.';
        return <_DetalleItem>[];
      }
      return decoded
          .whereType<Map>()
          .map((item) => _DetalleItem.fromJson(item))
          .toList();
    } on FormatException {
      _errorDetalle = 'No se pudo leer el detalle guardado.';
      return <_DetalleItem>[];
    }
  }

  void _reemplazarDetalleItems(String fuente) {
    _detalleItems = _leerDetalleItems(fuente);
  }

  void _aviso(String texto, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texto, style: const TextStyle(fontSize: 13)),
        backgroundColor: error ? Paleta.peligro : Paleta.exito,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  double get _total {
    // Solo las columnas que forman el importe del comprobante; el tipo de
    // cambio, pagos y retenciones no son importes de la compra.
    const importes = <String>[
      'biogA',
      'biogB',
      'biogC',
      'adNoGrav',
      'isc',
      'igvA',
      'igvB',
      'igvC',
      'otrosTrib',
      'impBolsa',
    ];
    double s = 0;
    for (final clave in importes) {
      final ctrl = _ctrl[clave];
      if (ctrl == null) continue;
      s += _numero(ctrl.text);
    }
    return s;
  }

  static double _numero(String s) {
    var v = s.trim();
    if (v.isEmpty) return 0;
    if (v.contains(',') && v.contains('.')) {
      v = v.replaceAll(',', '');
    } else if (v.contains(',')) {
      v = v.replaceAll(',', '.');
    }
    return double.tryParse(v) ?? 0;
  }

  Future<void> _elegirFecha(DefColumna d) async {
    final ctrl = _ctrl[d.clave]!;
    final partes = ctrl.text.split('/');
    DateTime inicial = DateTime.now();
    if (partes.length == 3) {
      final dia = int.tryParse(partes[0]);
      final mes = int.tryParse(partes[1]);
      final anio = int.tryParse(partes[2]);
      if (dia != null && mes != null && anio != null) {
        inicial = DateTime(anio, mes, dia);
      }
    }
    final elegida = await showDatePicker(
      context: context,
      initialDate: inicial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: d.titulo,
    );
    if (elegida == null) return;
    setState(() {
      ctrl.text =
          '${elegida.day.toString().padLeft(2, '0')}/'
          '${elegida.month.toString().padLeft(2, '0')}/${elegida.year}';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Paleta.contenido,
      appBar: AppBar(
        backgroundColor: Paleta.panel,
        foregroundColor: Colors.white,
        title: Text(
          _esRegistroManual
              ? 'Registro manual de compra'
              : widget.nuevo
              ? 'Nuevo comprobante'
              : 'Editar comprobante',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        actions: <Widget>[
          IconButton(
            tooltip: 'Guardar',
            onPressed: _guardar,
            icon: const Icon(Icons.check),
          ),
        ],
      ),
      body: Stack(
        children: <Widget>[
          ListView(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 14),
            children: <Widget>[
              if (_c.archivo.trim().isNotEmpty)
                Tarjeta(
                  titulo: 'ARCHIVO ADJUNTO',
                  icono: Icons.attach_file,
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  hijo: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        _c.nombreArchivo,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Leido por: ${_c.motor.isEmpty ? 'manual' : _c.motor}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Paleta.footerTexto,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: <Widget>[
                          OutlinedButton.icon(
                            onPressed: _leyendo ? null : _releer,
                            icon: const Icon(Icons.auto_awesome, size: 16),
                            label: const Text(
                              'Releer con IA',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: Paleta.exito,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                              ),
                            ),
                            onPressed: _guardar,
                            icon: const Icon(Icons.save_outlined, size: 16),
                            label: const Text(
                              'GUARDAR',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              if (_esRegistroManual)
                _formularioManual()
              else ...<Widget>[
                _selectoresCatalogosLocales(),
                _detalleWidget(),
                for (final seccion in secciones)
                  if (seccion != 'Voucher')
                    _seccionWidget(
                      seccion,
                      clavesPrincipales: _clavesPrincipales[seccion],
                    ),
              ],
              if (_esRegistroManual && _mostrarMasCampos)
                for (final seccion in secciones)
                  if (seccion != 'Voucher') _seccionWidget(seccion),
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: OutlinedButton.icon(
                  onPressed: () =>
                      setState(() => _mostrarMasCampos = !_mostrarMasCampos),
                  icon: Icon(
                    _mostrarMasCampos ? Icons.expand_less : Icons.tune_outlined,
                  ),
                  label: Text(
                    _mostrarMasCampos
                        ? 'Ocultar campos adicionales'
                        : 'Mostrar campos adicionales',
                  ),
                ),
              ),
            ],
          ),
          if (_leyendo)
            const Positioned.fill(
              child: ColoredBox(
                color: Colors.black45,
                child: Center(
                  child: CircularProgressIndicator(color: Paleta.panel),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          color: Paleta.totalesFondo,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: <Widget>[
              const Text(
                'TOTAL CALCULADO',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Text(
                '$_simboloMoneda${_total.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Paleta.etiqueta,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _formularioManual() {
    final centros = Repositorio.i.centrosCostoLocales;

    return Tarjeta(
      titulo: 'REGISTRO DE COMPRA',
      icono: Icons.receipt_long_outlined,
      hijo: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Text(
            'Documento: OTROS (00)',
            style: TextStyle(fontSize: 12, color: Paleta.footerTexto),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _montoManual,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Monto',
              prefixText: _simboloMoneda,
              hintText: '0.00',
            ),
            onChanged: (_) => setState(_aplicarAfectacion),
          ),
          const SizedBox(height: 12),
          _selectorConcepto(),
          const SizedBox(height: 12),
          _selectorCaja(sincronizarMoneda: true),
          const SizedBox(height: 12),
          _selectorProveedorManual(),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey<String>('afectacion-$_tipoAfectacion'),
            initialValue: _tipoAfectacion,
            decoration: const InputDecoration(labelText: 'Tipo de afectación'),
            items: const <DropdownMenuItem<String>>[
              DropdownMenuItem(value: '18', child: Text('Gravado 18%')),
              DropdownMenuItem(value: '10.5', child: Text('Gravado 10.5%')),
              DropdownMenuItem(value: 'exonerado', child: Text('Exonerado')),
              DropdownMenuItem(value: 'inafecto', child: Text('Inafecto')),
            ],
            onChanged: (valor) {
              if (valor == null) return;
              setState(() {
                _tipoAfectacion = valor;
                _aplicarAfectacion();
              });
            },
          ),
          const SizedBox(height: 12),
          _selectorCentroCosto(),
          if (centros.isEmpty) ...<Widget>[
            const SizedBox(height: 6),
            const Text(
              'No hay centros de costo locales. Puedes agregarlos en Mantenimiento > Centros de costo.',
              style: TextStyle(fontSize: 12, color: Paleta.footerTexto),
            ),
          ],
        ],
      ),
    );
  }

  Widget _detalleWidget() {
    final sumaDetalle = _detalleItems.fold<double>(
      0,
      (total, item) => total + _numero(item.importe),
    );
    final sumaBase =
        _numero(_ctrl['biogA']!.text) +
        _numero(_ctrl['biogB']!.text) +
        _numero(_ctrl['biogC']!.text) +
        _numero(_ctrl['adNoGrav']!.text);
    final diferencia = sumaDetalle - sumaBase;
    final coincide = _detalleItems.isEmpty || diferencia.abs() <= 0.01;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Paleta.navbarBorde),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.receipt_long_outlined, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'DETALLE DE PRODUCTOS (${_detalleItems.length})',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Paleta.etiqueta,
                  ),
                ),
              ),
            ],
          ),
          if (_errorDetalle != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _errorDetalle!,
                style: const TextStyle(color: Paleta.peligro, fontSize: 12),
              ),
            ),
          if (_detalleItems.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'La IA no detectó productos. Use "Releer con IA" para intentarlo de nuevo.',
                style: TextStyle(fontSize: 12, color: Paleta.footerTexto),
              ),
            )
          else ...<Widget>[
            _detalleTabla(),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Suma de productos: ${sumaDetalle.toStringAsFixed(2)}'
                '  ·  Base del comprobante: ${sumaBase.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 11.5,
                  color: coincide ? Paleta.footerTexto : Paleta.peligro,
                  fontWeight: coincide ? FontWeight.normal : FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _detalleTabla() => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 600) {
        return Column(
          children: <Widget>[
            for (final item in _detalleItems)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  border: Border.all(color: Paleta.navbarBorde),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      item.descripcion,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: <Widget>[
                        _detalleValor('CANTIDAD', item.cantidad),
                        _detalleValor('PRECIO UNITARIO', item.precio),
                        _detalleValor('IMPORTE', item.importe),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        );
      }

      return Table(
        columnWidths: const <int, TableColumnWidth>{
          0: FlexColumnWidth(4),
          1: FlexColumnWidth(1),
          2: FlexColumnWidth(1.5),
          3: FlexColumnWidth(1.5),
        },
        border: TableBorder(
          horizontalInside: BorderSide(color: Paleta.navbarBorde),
        ),
        children: <TableRow>[
          TableRow(
            decoration: BoxDecoration(color: Paleta.contenido),
            children: <Widget>[
              _detalleEncabezado('PRODUCTO / SERVICIO'),
              _detalleEncabezado('CANTIDAD', align: TextAlign.right),
              _detalleEncabezado('PRECIO UNITARIO', align: TextAlign.right),
              _detalleEncabezado('IMPORTE', align: TextAlign.right),
            ],
          ),
          for (final item in _detalleItems)
            TableRow(
              children: <Widget>[
                _detalleCelda(item.descripcion),
                _detalleCelda(item.cantidad, align: TextAlign.right),
                _detalleCelda(item.precio, align: TextAlign.right),
                _detalleCelda(item.importe, align: TextAlign.right),
              ],
            ),
        ],
      );
    },
  );

  Widget _detalleEncabezado(String texto, {TextAlign align = TextAlign.left}) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        child: Text(
          texto,
          textAlign: align,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: Paleta.etiqueta,
          ),
        ),
      );

  Widget _detalleCelda(String texto, {TextAlign align = TextAlign.left}) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Text(
          texto,
          textAlign: align,
          style: const TextStyle(fontSize: 12),
        ),
      );

  Widget _detalleValor(String titulo, String valor) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          titulo,
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: Paleta.footerTexto,
          ),
        ),
        const SizedBox(height: 2),
        Text(valor, style: const TextStyle(fontSize: 12)),
      ],
    ),
  );

  static const Map<String, Set<String>> _clavesPrincipales =
      <String, Set<String>>{
        'Documento': <String>{'doc', 'numero', 'fecDoc', 'glosa'},
        'Importes': <String>{'biogA', 'igvA', 'adNoGrav', 'moneda', 'tc'},
        'Proveedor': <String>{'ruc', 'rSocial', 'tipDocIden'},
        'Cuentas': <String>{
          'ccosto',
          'ctaGastos',
          'ctaIgv',
          'ctaOTrib',
          'ctaXPagar',
        },
      };

  Widget _seccionWidget(String seccion, {Set<String>? clavesPrincipales}) {
    if (!_mostrarMasCampos && clavesPrincipales == null) {
      return const SizedBox.shrink();
    }
    final campos = columnas
        .where(
          (d) =>
              d.seccion == seccion &&
              d.clave != 'vouOrigen' &&
              d.clave != 'vouNumero' &&
              d.clave != 'presupuesto' &&
              !(_esRegistroManual &&
                  <String>{
                    'ctaGastos',
                    'ctaIgv',
                    'ctaOTrib',
                    'ctaXPagar',
                  }.contains(d.clave)) &&
              (_mostrarMasCampos ||
                  (clavesPrincipales?.contains(d.clave) ?? false)),
        )
        .toList();
    if (campos.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Paleta.navbarBorde),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: _expandida(seccion),
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          title: Text(
            seccion.toUpperCase(),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Paleta.etiqueta,
              letterSpacing: 0.5,
            ),
          ),
          subtitle: Text(
            '${campos.length} campos',
            style: const TextStyle(fontSize: 10.5, color: Paleta.footerTexto),
          ),
          children: <Widget>[
            if (seccion == 'Documento' &&
                !_mostrarMasCampos &&
                !_esRegistroManual)
              const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Tipo 00 = Otros',
                    style: TextStyle(fontSize: 12, color: Paleta.footerTexto),
                  ),
                ),
              ),
            if (seccion == 'Proveedor')
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _seleccionarProveedorLocal,
                    icon: const Icon(Icons.person_search_outlined),
                    label: const Text('Seleccionar proveedor local'),
                  ),
                ),
              ),
            for (final d in campos) _campo(d),
          ],
        ),
      ),
    );
  }

  String _textoOpcion(String clave, String valor) {
    if (clave == 'doc') {
      return <String, String>{
            '00': '00 - Otros',
            '01': '01 - Factura',
            '02': '02 - Boleta',
            '03': '03 - Nota de crédito',
            '04': '04 - Nota de débito',
            '05': '05 - Otro documento',
            '07': '07 - Retención',
            '08': '08 - Recibo por honorarios',
          }[valor] ??
          valor;
    }
    if (clave == 'tipDocIden') {
      return <String, String>{
            '1': '01 - DNI',
            '4': '04 - Carnet de extranjería',
            '6': '06 - RUC',
            '7': '07 - Pasaporte',
            '0': '00 - Otros',
          }[valor] ??
          valor;
    }
    return valor;
  }

  Widget _campo(DefColumna d) {
    final ctrl = _ctrl[d.clave]!;
    if (_esRegistroManual &&
        <String>{'numero', 'doc', 'presupuesto'}.contains(d.clave)) {
      return const SizedBox.shrink();
    }
    final etiqueta = switch (d.clave) {
      'numero' => 'Número de comprobante',
      'ruc' when _esRegistroManual => 'OTROS (00)',
      _ => d.titulo,
    };
    if (d.tipo == TipoCampo.opcion) {
      final opciones = <String>[...d.opciones];
      if (ctrl.text.isNotEmpty && !opciones.contains(ctrl.text)) {
        opciones.add(ctrl.text);
      }
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: etiqueta,
            helperText: d.ayuda.isEmpty ? null : d.ayuda,
            isDense: true,
            border: const OutlineInputBorder(),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              isDense: true,
              onChanged: _esRegistroManual && d.clave == 'doc'
                  ? null
                  : (v) {
                      if (v == null) return;
                      setState(() {
                        ctrl.text = v;
                        _c[d.clave] = v;
                        if (widget.nuevo && d.clave == 'moneda') {
                          if (v == 'D' &&
                              _numero(_ctrl['tc']!.text) <= 1 &&
                              Repositorio.i.tipoCambioDiario > 1) {
                            _ctrl['tc']!.text = Repositorio.i.tipoCambioDiario
                                .toStringAsFixed(3);
                            _c['tc'] = _ctrl['tc']!.text;
                          } else if (v == 'S') {
                            _ctrl['tc']!.text = '1.000';
                            _c['tc'] = '1.000';
                          }
                        }
                      });
                    },
              value: opciones.contains(ctrl.text) && ctrl.text.isNotEmpty
                  ? ctrl.text
                  : null,
              hint: const Text('Seleccionar', style: TextStyle(fontSize: 12.5)),
              items: <DropdownMenuItem<String>>[
                for (final o in opciones)
                  DropdownMenuItem<String>(
                    value: o,
                    child: Text(
                      _textoOpcion(d.clave, o),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        key: ValueKey<String>('campo-${d.clave}'),
        controller: ctrl,
        style: const TextStyle(fontSize: 13),
        keyboardType: d.tipo == TipoCampo.numero
            ? const TextInputType.numberWithOptions(decimal: true)
            : (d.tipo == TipoCampo.entero
                  ? TextInputType.number
                  : TextInputType.text),
        textCapitalization: d.tipo == TipoCampo.texto
            ? TextCapitalization.characters
            : TextCapitalization.none,
        onChanged: (_) {
          if (d.tipo == TipoCampo.numero || d.clave == 'ctaGastos') {
            setState(() {});
          }
        },
        decoration: InputDecoration(
          labelText: etiqueta,
          helperText: d.ayuda.isEmpty ? null : d.ayuda,
          isDense: true,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 15,
          ),
          suffixIcon: d.tipo == TipoCampo.fecha
              ? IconButton(
                  icon: const Icon(Icons.calendar_today, size: 16),
                  onPressed: () => _elegirFecha(d),
                )
              : null,
        ),
      ),
    );
  }
}

class _DetalleItem {
  final String descripcion;
  final String cantidad;
  final String precio;
  final String importe;

  const _DetalleItem({
    required this.descripcion,
    required this.cantidad,
    required this.precio,
    required this.importe,
  });

  factory _DetalleItem.fromJson(Map item) => _DetalleItem(
    descripcion: '${item['descripcion'] ?? ''}',
    cantidad: '${item['cantidad'] ?? ''}',
    precio: '${item['precio'] ?? ''}',
    importe: '${item['importe'] ?? ''}',
  );

  Map<String, String> toJson() => <String, String>{
    'descripcion': descripcion.trim(),
    'cantidad': cantidad.trim(),
    'precio': precio.trim(),
    'importe': importe.trim(),
  };
}
