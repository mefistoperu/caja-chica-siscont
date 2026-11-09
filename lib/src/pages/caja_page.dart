import 'package:flutter/material.dart';

import '../models/caja_sesion.dart';
import '../models/comprobante.dart';
import '../models/movimiento_caja.dart';
import '../services/ws_cliente.dart';
import '../storage/repositorio.dart';
import '../theme/tema.dart';
import '../widgets/entrada.dart';
import 'origenes_caja_page.dart';
import 'reporte_page.dart';
import 'tipo_cambio_page.dart';
import 'tipos_movimiento_caja_page.dart';

class CajaPage extends StatefulWidget {
  const CajaPage({super.key});

  @override
  State<CajaPage> createState() => _CajaPageState();
}

class _CajaPageState extends State<CajaPage> {
  final _formApertura = GlobalKey<FormState>();
  final _formMovimiento = GlobalKey<FormState>();
  final _montoApertura = TextEditingController(text: '0.00');
  final _monto = TextEditingController();

  String _monedaApertura = 'PEN';
  String? _cajaSeleccionadaId;
  String _tipo = 'ingreso';
  String? _tipoMovimientoId;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    final tipos = Repositorio.i.tiposMovimientoCaja;
    if (tipos.isNotEmpty) _tipoMovimientoId = tipos.first.id;
    _cajaSeleccionadaId = Repositorio.i.cajasActivas.firstOrNull?.id;
  }

  @override
  void dispose() {
    _montoApertura.dispose();
    _monto.dispose();
    super.dispose();
  }

  Future<void> _abrirMantenimiento(WidgetBuilder builder) async {
    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute<void>(builder: builder));
    if (!mounted) return;
    final tipos = Repositorio.i.tiposMovimientoCaja;
    setState(() {
      _tipoMovimientoId = tipos.any((tipo) => tipo.id == _tipoMovimientoId)
          ? _tipoMovimientoId
          : (tipos.isEmpty ? null : tipos.first.id);
    });
  }

  Future<void> _abrirCaja(String moneda) async {
    if (!_formApertura.currentState!.validate()) return;
    setState(() => _guardando = true);
    try {
      await Repositorio.i.abrirCaja(
        moneda: moneda,
        montoApertura: _parseMonto(_montoApertura.text),
      );
      if (!mounted) return;
      setState(() {
        _montoApertura.text = '0.00';
        _cajaSeleccionadaId = Repositorio.i.cajaActivaParaMoneda(moneda)?.id;
        _guardando = false;
      });
      _avisar('Caja abierta correctamente.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      _avisar('No se pudo abrir la Caja: $e', error: true);
    }
  }

  Future<void> _registrarMovimiento(CajaSesion caja) async {
    if (!_formMovimiento.currentState!.validate()) return;
    final tipo = Repositorio.i.tiposMovimientoCaja.firstWhere(
      (item) => item.id == _tipoMovimientoId,
    );
    final esIngreso = _tipo == 'ingreso';
    final movimiento = MovimientoCaja(
      id: MovimientoCaja.nuevoId(),
      cajaId: caja.id,
      moneda: caja.moneda,
      tipo: _tipo,
      tipoMovimientoId: tipo.id,
      tipoMovimiento: tipo.nombre,
      cuentaContable: esIngreso ? tipo.cuentaIngreso : tipo.cuentaGasto,
      concepto: tipo.nombre,
      monto: _parseMonto(_monto.text),
      fecha: DateTime.now(),
    );
    setState(() => _guardando = true);
    var tipoCambioActualizado = false;
    String? errorTipoCambio;
    try {
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
      await Repositorio.i.registrarMovimientoCaja(movimiento);
      if (!mounted) return;
      _monto.clear();
      setState(() => _guardando = false);
      final mensaje = esIngreso
          ? 'Fondos agregados a Caja.'
          : 'Gasto registrado.';
      _avisar(
        errorTipoCambio != null
            ? '$mensaje No se pudo actualizar el TC de SUNAT: $errorTipoCambio'
            : tipoCambioActualizado
            ? '$mensaje Tipo de cambio diario actualizado desde SUNAT.'
            : mensaje,
        error: errorTipoCambio != null,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      _avisar('No se pudo registrar el movimiento: $e', error: true);
    }
  }

  Future<void> _cerrarCaja(CajaSesion caja) async {
    final saldo = Repositorio.i.saldoCalculadoCaja(caja);
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cerrar Caja'),
        content: Text(
          'El saldo calculado es ${_moneda(caja.moneda)} '
          '${saldo.toStringAsFixed(2)}.\n\n'
          'Al confirmar se guardará el cierre con su voucher mensual.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Cerrar Caja'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    setState(() => _guardando = true);
    try {
      final cierre = await Repositorio.i.cerrarCaja(cajaId: caja.id);
      if (!mounted) return;
      setState(() {
        _cajaSeleccionadaId = Repositorio.i.cajasActivas.firstOrNull?.id;
        _guardando = false;
      });
      _avisar('Caja cerrada. Voucher ${cierre.voucher}.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      _avisar('No se pudo cerrar la Caja: $e', error: true);
    }
  }

  Future<void> _eliminarMovimiento(MovimientoCaja movimiento) async {
    if (movimiento.comprobanteId.isNotEmpty) {
      _avisar(
        'Elimine el comprobante desde su lista para quitar también su salida de Caja.',
        error: true,
      );
      return;
    }
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar movimiento'),
        content: Text('¿Desea eliminar "${movimiento.concepto}"?'),
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
      await Repositorio.i.eliminarMovimientoCaja(movimiento.id);
      if (mounted) setState(() {});
    } catch (e) {
      _avisar('No se pudo eliminar el movimiento: $e', error: true);
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

  String _fechaTexto(DateTime fecha) =>
      '${fecha.day.toString().padLeft(2, '0')}/'
      '${fecha.month.toString().padLeft(2, '0')}/${fecha.year}';

  String _moneda(String moneda) => moneda == 'PEN' ? 'S/' : 'US\$';

  double _parseMonto(String texto) =>
      double.parse(texto.trim().replaceAll(',', '.'));

  ButtonStyle _estiloBotonPrincipal(Color color) => FilledButton.styleFrom(
    backgroundColor: color,
    foregroundColor: Colors.white,
    minimumSize: const Size.fromHeight(52),
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
  );

  ButtonStyle _estiloBotonConfiguracion() => OutlinedButton.styleFrom(
    foregroundColor: Paleta.etiqueta,
    backgroundColor: Colors.white,
    minimumSize: const Size(150, 48),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    side: const BorderSide(color: Color(0xFFDCE4EC)),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    textStyle: const TextStyle(fontWeight: FontWeight.w600),
  );

  String? _validarMonto(String? value, {required bool permitirCero}) {
    final texto = value?.trim() ?? '';
    if (!RegExp(r'^\d+(?:[.,]\d{1,2})?$').hasMatch(texto)) {
      return 'Ingrese un monto válido con hasta 2 decimales.';
    }
    final monto = _parseMonto(texto);
    if (permitirCero ? monto < 0 : monto <= 0) {
      return permitirCero
          ? 'El monto no puede ser negativo.'
          : 'El monto debe ser mayor que cero.';
    }
    return null;
  }

  Widget _selectorMoneda({
    required String valor,
    required List<String> monedasDisponibles,
    required ValueChanged<String?>? onChanged,
  }) => DropdownButtonFormField<String>(
    initialValue: valor,
    decoration: const InputDecoration(
      labelText: 'Moneda',
      border: OutlineInputBorder(),
    ),
    items: <DropdownMenuItem<String>>[
      if (monedasDisponibles.contains('PEN'))
        const DropdownMenuItem(value: 'PEN', child: Text('Soles (PEN)')),
      if (monedasDisponibles.contains('USD'))
        const DropdownMenuItem(value: 'USD', child: Text('Dólares (USD)')),
    ],
    onChanged: onChanged,
  );

  Widget _formularioApertura(List<String> monedasDisponibles) {
    final monedaSeleccionada = monedasDisponibles.contains(_monedaApertura)
        ? _monedaApertura
        : monedasDisponibles.first;
    return Tarjeta(
      titulo: 'APERTURA DE CAJA',
      icono: Icons.lock_open_outlined,
      hijo: Form(
        key: _formApertura,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _selectorMoneda(
              valor: monedaSeleccionada,
              monedasDisponibles: monedasDisponibles,
              onChanged: _guardando
                  ? null
                  : (value) {
                      if (value != null) {
                        setState(() => _monedaApertura = value);
                      }
                    },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _montoApertura,
              enabled: !_guardando,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Monto de apertura',
                prefixText: '${_moneda(monedaSeleccionada)} ',
                border: const OutlineInputBorder(),
              ),
              validator: (value) => _validarMonto(value, permitirCero: true),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _guardando
                  ? null
                  : () => _abrirCaja(monedaSeleccionada),
              style: _estiloBotonPrincipal(Paleta.panel),
              icon: const Icon(Icons.lock_open_rounded),
              label: Text(_guardando ? 'Procesando...' : 'Abrir Caja'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _selectorCajaActiva(List<CajaSesion> cajas) => Tarjeta(
    titulo: 'CAJAS ABIERTAS (${cajas.length}/2)',
    icono: Icons.point_of_sale_outlined,
    hijo: Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (final caja in cajas)
          ChoiceChip(
            key: ValueKey<String>('caja-abierta-${caja.moneda}'),
            label: Text(caja.moneda == 'PEN' ? 'Soles (PEN)' : 'Dólares (USD)'),
            selected: caja.id == _cajaSeleccionadaId,
            onSelected: (seleccionada) {
              if (!seleccionada) return;
              setState(() => _cajaSeleccionadaId = caja.id);
            },
          ),
      ],
    ),
  );

  Widget _formularioMovimiento(CajaSesion caja) {
    final tipos = Repositorio.i.tiposMovimientoCaja
        .where(
          (tipo) => (_tipo == 'ingreso' ? tipo.cuentaIngreso : tipo.cuentaGasto)
              .trim()
              .isNotEmpty,
        )
        .toList();
    final tipoSeleccionado = tipos.any((tipo) => tipo.id == _tipoMovimientoId)
        ? _tipoMovimientoId
        : null;

    return Tarjeta(
      titulo: 'REGISTRAR MOVIMIENTO',
      icono: _tipo == 'ingreso' ? Icons.south_west : Icons.north_east,
      hijo: Form(
        key: _formMovimiento,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            DropdownButtonFormField<String>(
              initialValue: _tipo,
              decoration: const InputDecoration(
                labelText: 'Tipo de movimiento',
                border: OutlineInputBorder(),
              ),
              items: const <DropdownMenuItem<String>>[
                DropdownMenuItem(
                  value: 'ingreso',
                  child: Text('Agregar fondos / ingreso'),
                ),
                DropdownMenuItem(value: 'gasto', child: Text('Gasto / salida')),
              ],
              onChanged: _guardando
                  ? null
                  : (value) {
                      if (value != null) setState(() => _tipo = value);
                    },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: tipoSeleccionado,
              decoration: InputDecoration(
                labelText: 'Medio de pago',
                border: const OutlineInputBorder(),
              ),
              hint: const Text('Seleccione Yape, Plin, efectivo, etc.'),
              items: tipos
                  .map(
                    (tipo) => DropdownMenuItem<String>(
                      value: tipo.id,
                      child: Text(tipo.nombre),
                    ),
                  )
                  .toList(),
              onChanged: _guardando
                  ? null
                  : (value) => setState(() => _tipoMovimientoId = value),
              validator: (value) => tipos.isEmpty
                  ? 'Primero configure un tipo de movimiento.'
                  : value == null
                  ? 'Seleccione el tipo de movimiento.'
                  : null,
            ),
            if (tipos.isEmpty) ...<Widget>[
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _guardando
                      ? null
                      : () => _abrirMantenimiento(
                          (_) => const TiposMovimientoCajaPage(),
                        ),
                  icon: const Icon(Icons.settings_outlined),
                  label: const Text('Configurar tipos de movimiento'),
                ),
              ),
            ],
            const SizedBox(height: 12),
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Moneda de la Caja',
                border: OutlineInputBorder(),
              ),
              child: Text(
                caja.moneda == 'PEN' ? 'Soles (PEN)' : 'Dólares (USD)',
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _monto,
              enabled: !_guardando,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Monto',
                prefixText: '${_moneda(caja.moneda)} ',
                border: const OutlineInputBorder(),
              ),
              validator: (value) => _validarMonto(value, permitirCero: false),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _guardando ? null : () => _registrarMovimiento(caja),
              style: _estiloBotonPrincipal(
                _tipo == 'ingreso'
                    ? const Color(0xFF168A72)
                    : const Color(0xFFB54747),
              ),
              icon: Icon(
                _tipo == 'ingreso'
                    ? Icons.add_circle_outline_rounded
                    : Icons.remove_circle_outline_rounded,
              ),
              label: Text(
                _guardando
                    ? 'Guardando...'
                    : _tipo == 'ingreso'
                    ? 'Agregar fondos'
                    : 'Guardar gasto',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filaMovimiento(
    MovimientoCaja movimiento, {
    bool permitirEliminar = false,
  }) {
    final signo = movimiento.esIngreso ? '+' : '-';
    final subtitulo = <String>[_fechaTexto(movimiento.fecha)].join(' · ');
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      leading: CircleAvatar(
        backgroundColor: Paleta.panel.withValues(alpha: 0.15),
        child: Icon(
          movimiento.esIngreso ? Icons.south_west : Icons.north_east,
          color: movimiento.esIngreso ? Paleta.exito : Paleta.peligro,
        ),
      ),
      title: Text(
        movimiento.tipoMovimiento.isNotEmpty
            ? movimiento.tipoMovimiento
            : movimiento.concepto,
      ),
      subtitle: Text(subtitulo),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            '$signo${_moneda(movimiento.moneda)} '
            '${movimiento.monto.toStringAsFixed(2)}',
            style: TextStyle(
              color: movimiento.esIngreso ? Paleta.exito : Paleta.peligro,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (permitirEliminar)
            IconButton(
              tooltip: 'Eliminar movimiento',
              onPressed: () => _eliminarMovimiento(movimiento),
              icon: const Icon(Icons.delete_outline, color: Paleta.peligro),
            ),
        ],
      ),
    );
  }

  Future<void> _abrirEnviosCaja(CajaSesion caja) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(
            backgroundColor: Paleta.panel,
            foregroundColor: Colors.white,
            title: Text('ENVÍOS · CAJA ${caja.moneda}'),
          ),
          body: ReportePage(
            items: Repositorio.i.comprobantes,
            initialCajaId: caja.id,
            onItemsChanged: () {
              if (mounted) setState(() {});
            },
          ),
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  int _comprobantesDeCaja(
    CajaSesion caja,
    List<Comprobante> comprobantes,
    List<MovimientoCaja> movimientos,
  ) => comprobantes.where((comprobante) {
    final cajaId = comprobante['cajaId'].trim();
    if (cajaId.isNotEmpty) return cajaId == caja.id;
    return movimientos.any(
      (movimiento) =>
          movimiento.comprobanteId == comprobante.id &&
          movimiento.cajaId == caja.id,
    );
  }).length;

  Widget _listadoCajas(List<CajaSesion> cajas) {
    final movimientos = Repositorio.i.movimientosCaja;
    final comprobantes = Repositorio.i.comprobantes;
    final anteriores = movimientos
        .where((item) => item.cajaId.isEmpty)
        .toList();

    return Tarjeta(
      titulo: 'HISTORIAL DE CAJAS (${cajas.length})',
      icono: Icons.history,
      padding: const EdgeInsets.all(8),
      hijo: Column(
        children: <Widget>[
          if (cajas.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('Aún no hay cajas abiertas ni cerradas.'),
            ),
          for (final caja in cajas)
            Builder(
              builder: (context) {
                final movimientosCaja = movimientos
                    .where((item) => item.cajaId == caja.id)
                    .toList();
                final cantidadComprobantes = _comprobantesDeCaja(
                  caja,
                  comprobantes,
                  movimientos,
                );
                final saldo = caja.estaAbierta
                    ? Repositorio.i.saldoCalculadoCaja(caja)
                    : caja.montoCierre ?? 0;
                return ExpansionTile(
                  key: ValueKey<String>('historial-caja-${caja.id}'),
                  leading: Icon(
                    caja.estaAbierta
                        ? Icons.lock_open_outlined
                        : Icons.lock_outline,
                  ),
                  title: Text(
                    'Caja ${caja.moneda} · '
                    '${caja.estaAbierta ? 'ABIERTA' : 'CERRADA'}',
                  ),
                  subtitle: Text(
                    '${_fechaTexto(caja.fechaApertura)}'
                    '${caja.fechaCierre == null ? '' : ' → ${_fechaTexto(caja.fechaCierre!)}'}'
                    ' · Voucher ${caja.voucher ?? 'pendiente'}'
                    ' · ${_moneda(caja.moneda)} ${saldo.toStringAsFixed(2)}',
                  ),
                  children: <Widget>[
                    ListTile(
                      title: Text(
                        'Apertura: ${_moneda(caja.moneda)} '
                        '${caja.montoApertura.toStringAsFixed(2)}',
                      ),
                      subtitle: Text(
                        '$cantidadComprobantes comprobante(s) · '
                        '${movimientosCaja.length} movimiento(s)',
                      ),
                    ),
                    if (movimientosCaja.isEmpty)
                      const ListTile(
                        title: Text('Sin movimientos registrados.'),
                      )
                    else
                      for (final movimiento in movimientosCaja)
                        _filaMovimiento(
                          movimiento,
                          permitirEliminar: caja.estaAbierta,
                        ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: OutlinedButton.icon(
                              key: ValueKey<String>('caja-whatsapp-${caja.id}'),
                              onPressed: cantidadComprobantes == 0
                                  ? null
                                  : () => _abrirEnviosCaja(caja),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                ),
                              ),
                              icon: const Icon(Icons.share_outlined, size: 18),
                              label: const Text(
                                'Excel / WhatsApp',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton.icon(
                              key: ValueKey<String>('caja-siscont-${caja.id}'),
                              onPressed: cantidadComprobantes == 0
                                  ? null
                                  : () => _abrirEnviosCaja(caja),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                ),
                              ),
                              icon: const Icon(
                                Icons.cloud_upload_outlined,
                                size: 18,
                              ),
                              label: const Text(
                                'SISCONT',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          if (anteriores.isNotEmpty) ...<Widget>[
            const Divider(),
            const ListTile(
              leading: Icon(Icons.history),
              title: Text('Movimientos anteriores a la apertura'),
            ),
            for (final item in anteriores) _filaMovimiento(item),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cajasAbiertas = Repositorio.i.cajasActivas;
    final activa =
        cajasAbiertas
            .where((caja) => caja.id == _cajaSeleccionadaId)
            .firstOrNull ??
        cajasAbiertas.firstOrNull;
    final monedasAbiertas = cajasAbiertas.map((caja) => caja.moneda).toSet();
    final monedasDisponibles = <String>[
      if (!monedasAbiertas.contains('PEN')) 'PEN',
      if (!monedasAbiertas.contains('USD')) 'USD',
    ];
    final saldo = activa == null
        ? 0.0
        : Repositorio.i.saldoCalculadoCaja(activa);
    final movimientos = activa == null
        ? <MovimientoCaja>[]
        : Repositorio.i.movimientosCaja
              .where((item) => item.cajaId == activa.id)
              .toList();
    final cajasHistoricas = <CajaSesion>[
      ...cajasAbiertas,
      ...Repositorio.i.cierresCaja,
    ]..sort((a, b) => b.fechaApertura.compareTo(a.fechaApertura));

    return Scaffold(
      backgroundColor: Paleta.contenido,
      appBar: AppBar(
        backgroundColor: Paleta.panel,
        foregroundColor: Colors.white,
        title: const Text('CAJA'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: <Widget>[
          Tarjeta(
            titulo: 'CONFIGURACIÓN DE CAJA',
            icono: Icons.settings_outlined,
            hijo: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                OutlinedButton.icon(
                  onPressed: () =>
                      _abrirMantenimiento((_) => const OrigenesCajaPage()),
                  style: _estiloBotonConfiguracion(),
                  icon: const Icon(Icons.input_rounded),
                  label: const Text('Origen de gasto'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _abrirMantenimiento(
                    (_) => const TiposMovimientoCajaPage(),
                  ),
                  style: _estiloBotonConfiguracion(),
                  icon: const Icon(Icons.swap_horiz_rounded),
                  label: const Text('Tipos y cuentas'),
                ),
                OutlinedButton.icon(
                  onPressed: () =>
                      _abrirMantenimiento((_) => const TipoCambioPage()),
                  style: _estiloBotonConfiguracion(),
                  icon: const Icon(Icons.currency_exchange_rounded),
                  label: const Text('Tipo de cambio'),
                ),
              ],
            ),
          ),
          if (cajasAbiertas.isNotEmpty) _selectorCajaActiva(cajasAbiertas),
          if (monedasDisponibles.isNotEmpty)
            _formularioApertura(monedasDisponibles),
          if (monedasDisponibles.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(14),
                child: Text(
                  'Ya están abiertas las dos Cajas permitidas: una en soles y otra en dólares.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          if (activa != null) ...<Widget>[
            Tarjeta(
              titulo: activa.moneda == 'PEN'
                  ? 'CAJA ABIERTA · SOLES'
                  : 'CAJA ABIERTA · DÓLARES',
              icono: Icons.lock_open_outlined,
              hijo: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text('Apertura: ${_fechaTexto(activa.fechaApertura)}'),
                  const SizedBox(height: 4),
                  Text(
                    'Monto inicial: ${_moneda(activa.moneda)} '
                    '${activa.montoApertura.toStringAsFixed(2)}',
                  ),
                  const Divider(height: 20),
                  Text(
                    'Saldo calculado: ${_moneda(activa.moneda)} '
                    '${saldo.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    '${movimientos.where((item) => item.esIngreso).length} '
                    'ingreso(s) · '
                    '${movimientos.where((item) => !item.esIngreso).length} '
                    'gasto(s)',
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _guardando ? null : () => _cerrarCaja(activa),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFB54747),
                      backgroundColor: const Color(0xFFFFF6F5),
                      minimumSize: const Size.fromHeight(48),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                      side: const BorderSide(color: Color(0xFFF1C7C4)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      textStyle: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    icon: const Icon(Icons.lock_rounded),
                    label: const Text('Cerrar Caja y generar voucher'),
                  ),
                ],
              ),
            ),
            _formularioMovimiento(activa),
          ],
          _listadoCajas(cajasHistoricas),
        ],
      ),
    );
  }
}
