import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/centro_costo.dart';
import '../models/comprobante.dart';
import '../models/conexion.dart';
import '../models/concepto_gasto.dart';
import '../models/caja_sesion.dart';
import '../models/cuenta_contable.dart';
import '../models/licencia.dart';
import '../models/movimiento_caja.dart';
import '../models/origenes_caja.dart';
import '../models/tercero_local.dart';
import '../models/tipo_movimiento_caja.dart';
import '../models/usuario.dart';
import '../services/licencia_cliente.dart';
import '../services/ws_cliente.dart';
import 'archivos.dart' as archivos;

/// Almacenamiento de la app.
///
/// Los usuarios viven en el Web Service. Las conexiones, centros de costo,
/// cuentas contables, terceros, comprobantes, Caja, sesión y archivos se
/// guardan localmente en el dispositivo.
class Repositorio {
  Repositorio._();
  static final Repositorio i = Repositorio._();

  static const String _kSesion = 'sesion_activa';
  static const String _kLicencia = 'licencia_guardada';
  static const String _kConexionesLocales = 'conexiones_locales';
  static const String _kComprobantes = 'comprobantes';
  static const String _kIngresosCaja = 'ingresos_caja';
  static const String _kCajaActiva = 'caja_activa';
  static const String _kCierresCaja = 'cierres_caja';
  static const String _kOrigenesCaja = 'origenes_caja';
  static const String _kTiposMovimientoCaja = 'tipos_movimiento_caja';
  static const String _kTiposCambioDiarios = 'tipos_cambio_diarios';
  static const String _kTercerosLocales = 'terceros_locales';
  static const String _kCentrosCostoLocales = 'centros_costo_locales';
  static const String _kConceptosGastoLocales = 'conceptos_gasto_locales';
  static const String _kCuentasContablesLocales = 'cuentas_contables_locales';
  static const String _kCuentasContablesConfiguradas =
      'cuentas_contables_configuradas';
  static const String _kSecuencia = 'secuencia_voucher';
  static const String _kSecuenciaOtros = 'secuencia_comprobante_otros';

  late SharedPreferences _prefs;

  Future<void> inicializar() async {
    _prefs = await SharedPreferences.getInstance();
    await archivos.iniciarArchivos();
    await asegurarTipoCambioDiario();
    await _asegurarProveedorVarios();
    await _asegurarConceptoGastoVarios();
    await _asegurarTipoMovimientoCaja();
    await _asegurarCuentasContables();
    final items = comprobantes;
    final unicos = _sinDuplicados(items);
    if (unicos.length != items.length) {
      await guardarComprobantes(unicos);
    }
  }

  // ------------------------------------------------------------- usuarios ---

  /// Registra la cuenta en la base de datos del sistema (`usuarios`).
  /// Devuelve el mensaje de error o null si se creo correctamente.
  Future<String?> registrar({
    required String correo,
    required String usuario,
    required String contrasena,
    required String celular,
  }) async {
    try {
      await WsCliente.i.registrar(
        correo: correo,
        usuario: usuario,
        contrasena: contrasena,
        celular: celular,
      );
      return null;
    } on WsException catch (e) {
      return e.mensaje;
    }
  }

  /// Valida las credenciales contra el servicio de licencias.
  /// Devuelve null si el correo o la clave son incorrectos; lanza
  /// [WsException] si no hay conexion, la licencia vencio o la respuesta no es
  /// valida.
  Future<Usuario?> validar(String identificador, String contrasena) async {
    final licencia = await LicenciaCliente.i.consultar(
      correo: identificador,
      clave: contrasena,
    );
    if (!licencia.tieneLicencia) return null;
    if (!licencia.vigente) {
      throw WsException(
        'Su licencia venció el ${licencia.vencimientoTexto}. '
        'Comuníquese con el proveedor para renovarla.',
        403,
      );
    }
    await guardarLicencia(licencia);
    final correo = identificador.trim().toLowerCase();
    return Usuario(
      correo: correo,
      usuario: licencia.empresa,
      celular: '',
      hash: '',
      salt: '',
      creado: DateTime.now().toIso8601String(),
      vence: licencia.fechah,
      llave: licencia.llave,
    );
  }

  /// Guarda en el dispositivo los datos devueltos por el servicio de
  /// licencias (empresa, llave y fecha de vencimiento).
  Future<void> guardarLicencia(Licencia licencia) =>
      _prefs.setString(_kLicencia, jsonEncode(licencia.toJson()));

  /// Ultima licencia valida guardada en el dispositivo.
  Licencia? get licenciaGuardada {
    final raw = _prefs.getString(_kLicencia);
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final data = jsonDecode(raw);
      if (data is! Map) return null;
      return Licencia.fromJson(data.cast<String, dynamic>());
    } catch (_) {
      return null;
    }
  }

  Future<void> iniciarSesion(Usuario u) =>
      _prefs.setString(_kSesion, jsonEncode(u.toJson()));

  Usuario? get sesionActual {
    final raw = _prefs.getString(_kSesion);
    if (raw == null || raw.trim().isEmpty || !raw.trimLeft().startsWith('{')) {
      return null;
    }
    try {
      final data = jsonDecode(raw);
      if (data is! Map) return null;
      return Usuario.fromJson(data.cast<String, dynamic>());
    } catch (_) {
      return null;
    }
  }

  Future<void> cerrarSesion() => _prefs.remove(_kSesion);

  // -------------------------------------------------------- conexiones ---

  List<Conexion> get conexionesLocales {
    final raw = _prefs.getString(_kConexionesLocales);
    if (raw == null || raw.isEmpty) return <Conexion>[];
    final data = jsonDecode(raw);
    if (data is! List) {
      throw const FormatException(
        'El registro local de conexiones no tiene formato válido.',
      );
    }
    return data
        .whereType<Map>()
        .map((item) => Conexion.fromJson(item.cast<String, dynamic>()))
        .toList()
      ..sort((a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()));
  }

  Future<Conexion> guardarConexionLocal(
    Conexion conexion, {
    bool limpiarPass = false,
  }) async {
    final nombre = conexion.nombre.trim();
    if (nombre.isEmpty) {
      throw ArgumentError.value(conexion.nombre, 'nombre', 'Es obligatorio.');
    }

    final items = conexionesLocales;
    final indice = items.indexWhere((item) => item.id == conexion.id);
    final existente = indice >= 0 ? items[indice] : null;
    final guardada = conexion.copyWith(
      id: conexion.id > 0
          ? conexion.id
          : (items.fold<int>(0, (maximo, item) => item.id > maximo ? item.id : maximo) +
                1),
      nombre: nombre,
      host: conexion.host.trim(),
      data: conexion.data.trim(),
      usuario: conexion.usuario.trim(),
      pass: limpiarPass
          ? ''
          : (conexion.pass.isNotEmpty ? conexion.pass : existente?.pass ?? ''),
      tipo: conexion.tipo.trim().toUpperCase(),
    );

    if (indice >= 0) {
      items[indice] = guardada;
    } else {
      items.add(guardada);
    }
    await _prefs.setString(
      _kConexionesLocales,
      jsonEncode(items.map((item) => item.toJson()).toList()),
    );
    return guardada;
  }

  Future<void> cambiarEstadoConexionLocal(int id, {required int estado}) async {
    final items = conexionesLocales;
    final indice = items.indexWhere((item) => item.id == id);
    if (indice < 0) {
      throw StateError('No se encontró la conexión local solicitada.');
    }
    items[indice] = items[indice].copyWith(estado: estado);
    await _prefs.setString(
      _kConexionesLocales,
      jsonEncode(items.map((item) => item.toJson()).toList()),
    );
  }

  Future<void> eliminarConexionLocal(int id) async {
    final items = conexionesLocales.where((item) => item.id != id).toList();
    await _prefs.setString(
      _kConexionesLocales,
      jsonEncode(items.map((item) => item.toJson()).toList()),
    );
  }

  // -------------------------------------------------------- comprobantes ---

  List<Comprobante> get comprobantes =>
      comprobantesDesdeJson(_prefs.getString(_kComprobantes) ?? '');

  Future<void> guardarComprobantes(List<Comprobante> items) =>
      _prefs.setString(_kComprobantes, comprobantesAJson(items));

  Future<void> agregarComprobante(Comprobante c) async {
    final items = comprobantes;
    items.insert(0, c);
    await guardarComprobantes(items);
  }

  Future<void> actualizarComprobante(Comprobante c) async {
    if (c.id.trim().isEmpty) {
      c.id = Comprobante.nuevoId();
    }
    final items = comprobantes;
    final i = items.indexWhere((x) => x.id == c.id);
    final porDocumento = i < 0 ? comprobantePorDocumento(c) : null;
    final existente = i >= 0 ? items[i] : porDocumento;
    if (existente != null) {
      if (i < 0) {
        c
          ..['vouOrigen'] = existente['vouOrigen']
          ..['vouNumero'] = existente['vouNumero']
          ..['vouFecha'] = existente['vouFecha'];
      }
      c
        ..id = existente.id
        ..creado = existente.creado;
      if (_mismosValores(c, existente)) {
        c
          ..estadoWhatsapp = existente.estadoWhatsapp
          ..estadoSiscont = existente.estadoSiscont;
      } else {
        c
          ..estadoWhatsapp = 'pendiente'
          ..estadoSiscont = 'pendiente';
      }
      final fechaRegistro = c.fechaRegistroTexto;
      if (fechaRegistro.isNotEmpty) c['vouFecha'] = fechaRegistro;
      items.removeWhere((x) => x.id == existente.id || _mismaIdentidad(x, c));
    }
    items.insert(0, c);
    await guardarComprobantes(items);
  }

  Comprobante? comprobantePorDocumento(Comprobante c) {
    final identidad = _identidadDocumento(c);
    if (identidad == null) return null;
    for (final item in comprobantes) {
      if (_identidadDocumento(item) == identidad) return item;
    }
    return null;
  }

  List<Comprobante> _sinDuplicados(List<Comprobante> items) {
    final identidades = <String>{};
    final unicos = <Comprobante>[];
    for (final item in items) {
      final identidad = _identidadDocumento(item);
      if (identidad != null && !identidades.add(identidad)) continue;
      unicos.add(item);
    }
    return unicos;
  }

  bool _mismaIdentidad(Comprobante a, Comprobante b) {
    final identidad = _identidadDocumento(a);
    return identidad != null && identidad == _identidadDocumento(b);
  }

  String? _identidadDocumento(Comprobante c) {
    final numero = c['numero'].toUpperCase().replaceAll(
      RegExp(r'[^A-Z0-9]'),
      '',
    );
    if (numero.isEmpty) return null;

    final ruc = (c['ruc'].isNotEmpty ? c['ruc'] : c['codigo']).replaceAll(
      RegExp(r'[^0-9]'),
      '',
    );
    final proveedor = ruc.isNotEmpty
        ? ruc
        : c['rSocial'].toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (proveedor.isEmpty) return null;

    return '$proveedor|${c['doc'].trim()}|$numero';
  }

  Future<void> eliminarComprobante(String id) async {
    final gasto = gastoPorComprobante(id);
    if (gasto != null) {
      if (!cajasActivas.any((caja) => caja.id == gasto.cajaId)) {
        throw StateError(
          'El comprobante ya pertenece a un cierre de Caja y no se puede '
          'eliminar sin alterar el historial.',
        );
      }
    }
    final comprobantesAnteriores = _prefs.getString(_kComprobantes);
    final movimientosAnteriores = _prefs.getString(_kIngresosCaja);
    try {
      if (gasto != null) await eliminarMovimientoCaja(gasto.id);
      final items = comprobantes.where((c) => c.id != id).toList();
      await guardarComprobantes(items);
    } catch (error) {
      if (comprobantesAnteriores == null) {
        await _prefs.remove(_kComprobantes);
      } else {
        await _prefs.setString(_kComprobantes, comprobantesAnteriores);
      }
      if (movimientosAnteriores == null) {
        await _prefs.remove(_kIngresosCaja);
      } else {
        await _prefs.setString(_kIngresosCaja, movimientosAnteriores);
      }
      rethrow;
    }
  }

  String? monedaCajaPorId(String cajaId) {
    for (final activa in cajasActivas) {
      if (activa.id == cajaId) return activa.moneda;
    }
    for (final cierre in cierresCaja) {
      if (cierre.id == cajaId) return cierre.moneda;
    }
    return null;
  }

  List<MovimientoCaja> get movimientosCaja {
    final raw = _prefs.getString(_kIngresosCaja) ?? '';
    if (raw.isEmpty) return <MovimientoCaja>[];
    final data = jsonDecode(raw);
    if (data is! List) {
      throw const FormatException(
        'El historial de Caja no tiene formato válido.',
      );
    }
    return data
        .whereType<Map>()
        .map((item) => MovimientoCaja.fromJson(item.cast<String, dynamic>()))
        .toList()
      ..sort((a, b) {
        final porFecha = b.fecha.compareTo(a.fecha);
        return porFecha != 0 ? porFecha : b.id.compareTo(a.id);
      });
  }

  MovimientoCaja? gastoPorComprobante(String comprobanteId) {
    for (final item in movimientosCaja) {
      if (!item.esIngreso && item.comprobanteId == comprobanteId) return item;
    }
    return null;
  }

  Future<void> _guardarMovimientosCaja(List<MovimientoCaja> items) async {
    await _prefs.setString(
      _kIngresosCaja,
      jsonEncode(items.map((item) => item.toJson()).toList()),
    );
  }

  List<CajaSesion> get cajasActivas {
    final raw = _prefs.getString(_kCajaActiva);
    if (raw == null || raw.isEmpty) return <CajaSesion>[];
    final data = jsonDecode(raw);
    if (data is Map) {
      final caja = CajaSesion.fromJson(data.cast<String, dynamic>());
      return caja.estaAbierta ? <CajaSesion>[caja] : <CajaSesion>[];
    }
    if (data is! List) {
      throw const FormatException(
        'Las aperturas de Caja no tienen formato válido.',
      );
    }
    return data
        .whereType<Map>()
        .map((item) => CajaSesion.fromJson(item.cast<String, dynamic>()))
        .where((caja) => caja.estaAbierta)
        .toList();
  }

  CajaSesion? get cajaActiva => cajasActivas.firstOrNull;

  CajaSesion? cajaActivaParaMoneda(String moneda) =>
      cajasActivas.where((caja) => caja.moneda == moneda).firstOrNull;

  Future<void> _guardarCajasActivas(List<CajaSesion> cajas) async {
    if (cajas.isEmpty) {
      await _prefs.remove(_kCajaActiva);
      return;
    }
    await _prefs.setString(
      _kCajaActiva,
      jsonEncode(cajas.map((item) => item.toJson()).toList()),
    );
  }

  String _nuevoIdCaja(List<CajaSesion> abiertas) {
    final existentes = <String>{
      ...abiertas.map((caja) => caja.id),
      ...cierresCaja.map((caja) => caja.id),
    };
    var id = CajaSesion.nuevoId();
    while (existentes.contains(id)) {
      id = CajaSesion.nuevoId();
    }
    return id;
  }

  List<CajaSesion> get cierresCaja {
    final raw = _prefs.getString(_kCierresCaja) ?? '';
    if (raw.isEmpty) return <CajaSesion>[];
    final data = jsonDecode(raw);
    if (data is! List) {
      throw const FormatException(
        'El historial de cierres no tiene formato válido.',
      );
    }
    return data
        .whereType<Map>()
        .map((item) => CajaSesion.fromJson(item.cast<String, dynamic>()))
        .toList()
      ..sort((a, b) => b.fechaCierre!.compareTo(a.fechaCierre!));
  }

  Future<void> abrirCaja({
    required String moneda,
    required double montoApertura,
  }) async {
    if (moneda != 'PEN' && moneda != 'USD') {
      throw ArgumentError.value(moneda, 'moneda', 'Moneda de Caja no válida.');
    }
    final abiertas = cajasActivas;
    if (abiertas.length >= 2) {
      throw StateError('Solo se permite una Caja en soles y otra en dólares.');
    }
    if (abiertas.any((caja) => caja.moneda == moneda)) {
      throw StateError(
        'Ya existe una Caja abierta en ${moneda == 'PEN' ? 'soles' : 'dólares'}.',
      );
    }
    if (!montoApertura.isFinite || montoApertura < 0) {
      throw ArgumentError.value(
        montoApertura,
        'montoApertura',
        'El monto de apertura no puede ser negativo.',
      );
    }
    final caja = CajaSesion(
      id: _nuevoIdCaja(abiertas),
      moneda: moneda,
      montoApertura: montoApertura,
      fechaApertura: DateTime.now(),
    );
    await _guardarCajasActivas(<CajaSesion>[...abiertas, caja]);
  }

  double saldoCalculadoCaja(CajaSesion caja) {
    var saldo = caja.montoApertura;
    for (final movimiento in movimientosCaja.where(
      (item) => item.cajaId == caja.id,
    )) {
      saldo += movimiento.esIngreso ? movimiento.monto : -movimiento.monto;
    }
    return (saldo * 100).roundToDouble() / 100;
  }

  Future<void> registrarMovimientoCaja(MovimientoCaja movimiento) async {
    final caja = cajasActivas
        .where((item) => item.id == movimiento.cajaId)
        .firstOrNull;
    if (caja == null) {
      throw StateError('Abra la Caja antes de registrar movimientos.');
    }
    if (movimiento.moneda != caja.moneda) {
      throw StateError('La moneda del movimiento debe coincidir con la Caja.');
    }
    if (!movimiento.monto.isFinite || movimiento.monto <= 0) {
      throw ArgumentError.value(movimiento.monto, 'monto', 'Monto no válido.');
    }
    final items = movimientosCaja;
    items.removeWhere((item) => item.id == movimiento.id);
    items.insert(0, movimiento);
    await _guardarMovimientosCaja(items);
  }

  Future<void> registrarIngresoCajaConCliente(
    MovimientoCaja movimiento, {
    required String nombre,
    required String tipoDocumento,
    required String numeroDocumento,
  }) async {
    if (!movimiento.esIngreso) {
      throw ArgumentError('El cliente solo se puede asociar a un ingreso.');
    }
    if (nombre.trim().isEmpty || numeroDocumento.trim().isEmpty) {
      throw ArgumentError(
        'El nombre y documento del cliente son obligatorios.',
      );
    }

    final movimientosPrevios = _prefs.getString(_kIngresosCaja);
    final tercerosPrevios = _prefs.getString(_kTercerosLocales);
    try {
      final cliente = await guardarTerceroLocal(
        TerceroLocal(
          id: '',
          tipo: 'cliente',
          tipoDocumento: tipoDocumento,
          numeroDocumento: numeroDocumento,
          nombre: nombre,
        ),
      );
      final asociado = MovimientoCaja(
        id: movimiento.id,
        cajaId: movimiento.cajaId,
        moneda: movimiento.moneda,
        tipo: movimiento.tipo,
        tipoMovimientoId: movimiento.tipoMovimientoId,
        tipoMovimiento: movimiento.tipoMovimiento,
        cuentaContable: movimiento.cuentaContable,
        comprobanteId: movimiento.comprobanteId,
        terceroId: cliente.id,
        terceroNombre: cliente.nombre,
        terceroTipoDocumento: cliente.tipoDocumento,
        terceroDocumento: cliente.numeroDocumento,
        concepto: movimiento.concepto,
        monto: movimiento.monto,
        fecha: movimiento.fecha,
      );
      await registrarMovimientoCaja(asociado);
    } catch (error) {
      if (movimientosPrevios == null) {
        await _prefs.remove(_kIngresosCaja);
      } else {
        await _prefs.setString(_kIngresosCaja, movimientosPrevios);
      }
      if (tercerosPrevios == null) {
        await _prefs.remove(_kTercerosLocales);
      } else {
        await _prefs.setString(_kTercerosLocales, tercerosPrevios);
      }
      rethrow;
    }
  }

  Future<void> registrarGastoComprobante(MovimientoCaja gasto) async {
    if (gasto.esIngreso || gasto.comprobanteId.isEmpty) {
      throw ArgumentError(
        'La salida del comprobante requiere un gasto y un comprobante asociado.',
      );
    }
    if (!gasto.monto.isFinite || gasto.monto <= 0) {
      throw ArgumentError.value(gasto.monto, 'monto', 'Monto no válido.');
    }
    final actual = gastoPorComprobante(gasto.comprobanteId);
    if (actual == null) {
      await registrarMovimientoCaja(gasto);
      return;
    }

    final cierres = cierresCaja;
    final cajaCerrada = cierres.where((item) => item.id == actual.cajaId);
    final cajaActivaActual = cajasActivas.any(
      (caja) => caja.id == actual.cajaId,
    );
    if (!cajaActivaActual && cajaCerrada.isEmpty) {
      throw StateError('No se encontró la Caja original del gasto registrado.');
    }

    final actualizado = MovimientoCaja(
      id: actual.id,
      cajaId: actual.cajaId,
      moneda: actual.moneda,
      tipo: 'gasto',
      tipoMovimientoId: gasto.tipoMovimientoId,
      tipoMovimiento: gasto.tipoMovimiento,
      cuentaContable: gasto.cuentaContable,
      comprobanteId: gasto.comprobanteId,
      concepto: gasto.concepto,
      monto: gasto.monto,
      fecha: actual.fecha,
    );
    final items = movimientosCaja
      ..removeWhere((item) => item.id == actual.id)
      ..insert(0, actualizado);
    await _guardarMovimientosCaja(items);

    if (cajaCerrada.isNotEmpty) {
      final cierre = cajaCerrada.first;
      final saldo =
          cierre.montoApertura +
          items
              .where((item) => item.cajaId == cierre.id)
              .fold<double>(
                0,
                (total, item) =>
                    total + (item.esIngreso ? item.monto : -item.monto),
              );
      final historial = cierres
        ..removeWhere((item) => item.id == cierre.id)
        ..add(
          cierre.actualizarMontoCierre((saldo * 100).roundToDouble() / 100),
        );
      await _prefs.setString(
        _kCierresCaja,
        jsonEncode(historial.map((item) => item.toJson()).toList()),
      );
    }
  }

  Future<void> guardarComprobanteConGasto(
    Comprobante comprobante,
    MovimientoCaja gasto,
  ) async {
    final comprobantesAnteriores = _prefs.getString(_kComprobantes);
    final movimientosAnteriores = _prefs.getString(_kIngresosCaja);
    final cierresAnteriores = _prefs.getString(_kCierresCaja);
    await actualizarComprobante(comprobante);
    try {
      await registrarGastoComprobante(gasto);
    } catch (error) {
      if (comprobantesAnteriores == null) {
        await _prefs.remove(_kComprobantes);
      } else {
        await _prefs.setString(_kComprobantes, comprobantesAnteriores);
      }
      if (movimientosAnteriores == null) {
        await _prefs.remove(_kIngresosCaja);
      } else {
        await _prefs.setString(_kIngresosCaja, movimientosAnteriores);
      }
      if (cierresAnteriores == null) {
        await _prefs.remove(_kCierresCaja);
      } else {
        await _prefs.setString(_kCierresCaja, cierresAnteriores);
      }
      rethrow;
    }
  }

  Future<void> eliminarMovimientoCaja(String id) async {
    final coincidencias = movimientosCaja.where((item) => item.id == id);
    if (coincidencias.isEmpty) return;
    final movimiento = coincidencias.first;
    final cajaAbierta = cajasActivas.any(
      (caja) => caja.id == movimiento.cajaId,
    );
    if (movimiento.cajaId.isNotEmpty && !cajaAbierta) {
      throw StateError(
        'No se puede eliminar un movimiento de una Caja cerrada.',
      );
    }
    final items = movimientosCaja.where((item) => item.id != id).toList();
    await _guardarMovimientosCaja(items);
  }

  static int siguienteVoucherCaja(List<CajaSesion> cierres, DateTime fecha) {
    final mayor = cierres
        .where(
          (item) =>
              item.fechaCierre!.year == fecha.year &&
              item.fechaCierre!.month == fecha.month,
        )
        .fold<int>(
          0,
          (actual, item) => item.voucher != null && item.voucher! > actual
              ? item.voucher!
              : actual,
        );
    return mayor + 1;
  }

  Future<CajaSesion> cerrarCaja({String? cajaId}) async {
    final abiertas = cajasActivas;
    final caja = cajaId == null
        ? abiertas.firstOrNull
        : abiertas.where((item) => item.id == cajaId).firstOrNull;
    if (caja == null) throw StateError('No hay una Caja abierta para cerrar.');
    final fechaCierre = DateTime.now();
    final voucher = siguienteVoucherCaja(cierresCaja, fechaCierre);
    final cierre = caja.cerrar(
      fecha: fechaCierre,
      monto: saldoCalculadoCaja(caja),
      voucher: voucher,
    );
    final historico = cierresCaja..insert(0, cierre);
    await _prefs.setString(
      _kCierresCaja,
      jsonEncode(historico.map((item) => item.toJson()).toList()),
    );
    await _guardarCajasActivas(
      abiertas.where((item) => item.id != caja.id).toList(),
    );
    return cierre;
  }

  OrigenesCaja get origenesCaja {
    final raw = _prefs.getString(_kOrigenesCaja);
    if (raw == null || raw.isEmpty) return const OrigenesCaja();
    final data = jsonDecode(raw);
    if (data is! Map) {
      throw const FormatException(
        'Los orígenes de Caja no tienen formato válido.',
      );
    }
    final origenes = OrigenesCaja.fromJson(data.cast<String, dynamic>());
    return OrigenesCaja(
      gasto: origenes.gasto.trim().isEmpty ? '01' : origenes.gasto,
    );
  }

  Future<void> guardarOrigenesCaja(OrigenesCaja origenes) =>
      _prefs.setString(_kOrigenesCaja, jsonEncode(origenes.toJson()));

  static const Map<String, String> _cuentasContablesExcelPredeterminadas =
      <String, String>{
        'ctaGastos': '60001',
        'ctaIgv': '40002',
        'ctaOTrib': '40112',
        'ctaXPagar': '42121',
      };

  Map<String, String> get cuentasContablesExcel {
    final raw = _prefs.getString(_kCuentasContablesConfiguradas);
    if (raw == null || raw.isEmpty) {
      return Map<String, String>.of(_cuentasContablesExcelPredeterminadas);
    }
    final data = jsonDecode(raw);
    if (data is! Map) {
      throw const FormatException(
        'La configuración de cuentas contables no tiene formato válido.',
      );
    }
    final cuentas = <String, String>{
      ..._cuentasContablesExcelPredeterminadas,
      for (final entry in data.entries)
        if (_cuentasContablesExcelPredeterminadas.containsKey(
          entry.key.toString(),
        ))
          entry.key.toString(): '${entry.value ?? ''}'.trim(),
    };
    if (cuentas['ctaOTrib']!.isEmpty) {
      cuentas['ctaOTrib'] = _cuentasContablesExcelPredeterminadas['ctaOTrib']!;
    }
    return cuentas;
  }

  Future<void> guardarCuentasContablesExcel(Map<String, String> cuentas) async {
    final actuales = cuentasContablesExcel;
    final configuradas = <String, String>{
      for (final clave in _cuentasContablesExcelPredeterminadas.keys)
        clave: (cuentas[clave] ?? actuales[clave] ?? '').trim(),
    };
    if (configuradas['ctaOTrib']!.isEmpty) {
      configuradas['ctaOTrib'] =
          _cuentasContablesExcelPredeterminadas['ctaOTrib']!;
    }
    for (final clave in <String>['ctaGastos', 'ctaIgv', 'ctaXPagar']) {
      if (configuradas[clave]!.isEmpty) {
        throw ArgumentError('La cuenta $clave es obligatoria.');
      }
    }
    await _prefs.setString(
      _kCuentasContablesConfiguradas,
      jsonEncode(configuradas),
    );
  }

  static const List<CuentaContable> _cuentasContablesPredeterminadas =
      <CuentaContable>[
        CuentaContable(codigo: '656', nombre: 'Cuenta de gastos'),
        CuentaContable(codigo: '6211', nombre: 'Cuenta de gastos'),
        CuentaContable(codigo: '6321', nombre: 'Cuenta de gastos'),
        CuentaContable(codigo: '40002', nombre: 'IGV'),
        CuentaContable(codigo: '42121', nombre: 'Cuenta por pagar'),
        CuentaContable(codigo: '4241', nombre: 'Cuenta por pagar'),
        CuentaContable(codigo: '1011', nombre: 'Cuenta de cobro'),
      ];

  List<CuentaContable> get cuentasContablesLocales {
    final raw = _prefs.getString(_kCuentasContablesLocales);
    if (raw == null || raw.isEmpty) return _cuentasContablesPredeterminadas;
    final data = jsonDecode(raw);
    if (data is! List) {
      throw const FormatException(
        'El registro local de cuentas contables no tiene formato válido.',
      );
    }
    return data
        .whereType<Map>()
        .map((item) => CuentaContable.fromJson(item.cast<String, dynamic>()))
        .toList()
      ..sort((a, b) => a.codigo.compareTo(b.codigo));
  }

  Future<void> _asegurarCuentasContables() async {
    final raw = _prefs.getString(_kCuentasContablesLocales);
    if (raw != null && raw.isNotEmpty) return;
    await _prefs.setString(
      _kCuentasContablesLocales,
      jsonEncode(
        _cuentasContablesPredeterminadas.map((item) => item.toJson()).toList(),
      ),
    );
  }

  Future<void> guardarCuentaContable(
    CuentaContable cuenta, {
    String? codigoOriginal,
  }) async {
    final codigo = cuenta.codigo.trim();
    final nombre = cuenta.nombre.trim();
    if (codigo.isEmpty || nombre.isEmpty) {
      throw ArgumentError('El código y nombre de la cuenta son obligatorios.');
    }
    final items = cuentasContablesLocales;
    if (items.any(
      (item) => item.codigo == codigo && item.codigo != (codigoOriginal ?? ''),
    )) {
      throw ArgumentError('Ya existe una cuenta con ese código.');
    }
    if (codigoOriginal != null && codigoOriginal != codigo) {
      items.removeWhere((item) => item.codigo == codigoOriginal);
    }
    items.removeWhere((item) => item.codigo == codigo);
    items.add(CuentaContable(codigo: codigo, nombre: nombre));
    await _prefs.setString(
      _kCuentasContablesLocales,
      jsonEncode(items.map((item) => item.toJson()).toList()),
    );
  }

  Future<void> eliminarCuentaContable(String codigo) async {
    final items = cuentasContablesLocales
        .where((item) => item.codigo != codigo)
        .toList();
    await _prefs.setString(
      _kCuentasContablesLocales,
      jsonEncode(items.map((item) => item.toJson()).toList()),
    );
  }

  List<TipoMovimientoCaja> get tiposMovimientoCaja {
    final raw = _prefs.getString(_kTiposMovimientoCaja) ?? '';
    if (raw.isEmpty) return <TipoMovimientoCaja>[];
    final data = jsonDecode(raw);
    if (data is! List) {
      throw const FormatException(
        'Los tipos de movimiento de Caja no tienen formato válido.',
      );
    }
    return data
        .whereType<Map>()
        .map(
          (item) => TipoMovimientoCaja.fromJson(item.cast<String, dynamic>()),
        )
        .toList()
      ..sort(
        (a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()),
      );
  }

  Future<void> _asegurarTipoMovimientoCaja() async {
    final tipos = tiposMovimientoCaja;
    var efectivoEncontrado = false;
    var efectivosEncontrados = 0;
    final normalizados = <TipoMovimientoCaja>[];
    for (final tipo in tipos) {
      final esEfectivo = tipo.nombre.trim().toUpperCase() == 'EFECTIVO';
      if (esEfectivo) efectivosEncontrados++;
      final nombre = !esEfectivo
          ? tipo.nombre
          : efectivosEncontrados == 1
          ? 'EFECTIVO'
          : 'EFECTIVO ($efectivosEncontrados)';
      if (esEfectivo) efectivoEncontrado = true;
      normalizados.add(
        TipoMovimientoCaja(
          id: tipo.id,
          nombre: nombre,
          cuentaIngreso: '60002',
          cuentaGasto: '60002',
        ),
      );
    }
    if (!efectivoEncontrado) {
      var id = 'efectivo';
      while (normalizados.any((tipo) => tipo.id == id)) {
        id = TipoMovimientoCaja.nuevoId();
      }
      normalizados.add(
        TipoMovimientoCaja(
          id: id,
          nombre: 'EFECTIVO',
          cuentaIngreso: '60002',
          cuentaGasto: '60002',
        ),
      );
    }
    await _prefs.setString(
      _kTiposMovimientoCaja,
      jsonEncode(normalizados.map((item) => item.toJson()).toList()),
    );
  }

  Future<void> guardarTipoMovimientoCaja(TipoMovimientoCaja tipo) async {
    final items = tiposMovimientoCaja;
    final existente = items.where((item) => item.id == tipo.id).firstOrNull;
    items.removeWhere((item) => item.id == tipo.id);
    final nombre = tipo.nombre.trim();
    if (nombre.isEmpty) {
      throw ArgumentError.value(tipo.nombre, 'nombre', 'Es obligatorio.');
    }
    if (existente?.nombre == 'EFECTIVO' && nombre.toUpperCase() != 'EFECTIVO') {
      throw StateError('El tipo de movimiento predeterminado es EFECTIVO.');
    }
    if (items.any(
      (item) => item.nombre.toLowerCase() == nombre.toLowerCase(),
    )) {
      throw ArgumentError('Ya existe un tipo de movimiento con ese nombre.');
    }
    items.add(
      TipoMovimientoCaja(
        id: tipo.id,
        nombre: nombre.toUpperCase() == 'EFECTIVO' ? 'EFECTIVO' : nombre,
        cuentaIngreso: '60002',
        cuentaGasto: '60002',
      ),
    );
    await _prefs.setString(
      _kTiposMovimientoCaja,
      jsonEncode(items.map((item) => item.toJson()).toList()),
    );
  }

  List<TerceroLocal> get tercerosLocales {
    final raw = _prefs.getString(_kTercerosLocales);
    if (raw == null || raw.isEmpty) return <TerceroLocal>[];
    final data = jsonDecode(raw);
    if (data is! List) {
      throw const FormatException(
        'El registro local de clientes y proveedores no tiene formato válido.',
      );
    }
    return data
        .whereType<Map>()
        .map((item) => TerceroLocal.fromJson(item.cast<String, dynamic>()))
        .toList()
      ..sort(
        (a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()),
      );
  }

  List<TerceroLocal> get proveedoresLocales =>
      tercerosLocales.where((item) => item.esProveedor).toList();

  Future<void> _asegurarProveedorVarios() async {
    final existe = proveedoresLocales.any(
      (item) => item.nombre.trim().toUpperCase() == 'PROVEEDORES VARIOS',
    );
    if (existe) return;
    await guardarTerceroLocal(
      const TerceroLocal(
        id: 'proveedores-varios',
        tipo: 'proveedor',
        tipoDocumento: 'Otro',
        numeroDocumento: '',
        nombre: 'PROVEEDORES VARIOS',
      ),
    );
  }

  Future<TerceroLocal> guardarTerceroLocal(TerceroLocal tercero) async {
    final nombre = tercero.nombre.trim();
    if (nombre.isEmpty) {
      throw ArgumentError.value(tercero.nombre, 'nombre', 'Es obligatorio.');
    }
    final numero = tercero.numeroDocumento.trim();
    final normalizado = numero.replaceAll(RegExp(r'\D'), '');
    final items = tercerosLocales;
    final indicePorId = items.indexWhere((item) => item.id == tercero.id);
    final indice = indicePorId >= 0
        ? indicePorId
        : items.indexWhere((item) {
            final otroNumero = item.numeroDocumento.trim().replaceAll(
              RegExp(r'\D'),
              '',
            );
            if (normalizado.isNotEmpty && otroNumero.isNotEmpty) {
              return normalizado == otroNumero;
            }
            return item.nombre.trim().toLowerCase() == nombre.toLowerCase();
          });
    final tipo =
        indice >= 0 && indicePorId < 0 && items[indice].tipo != tercero.tipo
        ? 'ambos'
        : tercero.tipo;
    final guardado = TerceroLocal(
      id: indice >= 0
          ? items[indice].id
          : (tercero.id.isEmpty ? TerceroLocal.nuevoId() : tercero.id),
      tipo: tipo,
      tipoDocumento: tercero.tipoDocumento,
      numeroDocumento: numero,
      nombre: nombre,
      direccion: tercero.direccion.trim(),
      telefono: tercero.telefono.trim(),
      correo: tercero.correo.trim(),
      centroCostoCodigo: tercero.centroCostoCodigo.trim(),
      conceptoGastoCodigo: tercero.conceptoGastoCodigo.trim(),
    );
    if (indice >= 0) {
      items[indice] = guardado;
    } else {
      items.add(guardado);
    }
    await _prefs.setString(
      _kTercerosLocales,
      jsonEncode(items.map((item) => item.toJson()).toList()),
    );
    return guardado;
  }

  Future<void> guardarProveedorDesdeComprobante(Comprobante comprobante) async {
    final numero = comprobante['ruc'].trim().isNotEmpty
        ? comprobante['ruc'].trim()
        : comprobante['codigo'].trim();
    final nombre = comprobante['rSocial'].trim();
    if (numero.isEmpty && nombre.isEmpty) return;

    final tipoDocumento = switch (comprobante['tipDocIden']) {
      '6' => 'RUC',
      '1' => 'DNI',
      '4' => 'CE',
      '7' => 'Pasaporte',
      _ => 'Otro',
    };
    final numeroNormalizado = numero.replaceAll(RegExp(r'\D'), '');
    final nombreNormalizado = nombre.toLowerCase();
    final existente = proveedoresLocales.where((proveedor) {
      final otroNumero = proveedor.numeroDocumento.replaceAll(
        RegExp(r'\D'),
        '',
      );
      if (numeroNormalizado.isNotEmpty && otroNumero.isNotEmpty) {
        return numeroNormalizado == otroNumero;
      }
      return proveedor.nombre.trim().toLowerCase() == nombreNormalizado;
    }).firstOrNull;
    await guardarTerceroLocal(
      TerceroLocal(
        id: existente?.id ?? '',
        tipo: 'proveedor',
        tipoDocumento: tipoDocumento,
        numeroDocumento: numero,
        nombre: nombre.isEmpty ? numero : nombre,
        centroCostoCodigo: existente?.centroCostoCodigo ?? '',
        conceptoGastoCodigo: existente?.conceptoGastoCodigo ?? '',
      ),
    );
  }

  Future<void> eliminarTerceroLocal(String id) async {
    final items = tercerosLocales.where((item) => item.id != id).toList();
    await _prefs.setString(
      _kTercerosLocales,
      jsonEncode(items.map((item) => item.toJson()).toList()),
    );
  }

  List<CentroCosto> get centrosCostoLocales {
    final raw = _prefs.getString(_kCentrosCostoLocales);
    if (raw == null || raw.isEmpty) return <CentroCosto>[];
    final data = jsonDecode(raw);
    if (data is! List) {
      throw const FormatException(
        'El registro local de centros de costo no tiene formato válido.',
      );
    }
    return data
        .whereType<Map>()
        .map((item) => CentroCosto.fromJson(item.cast<String, dynamic>()))
        .toList()
      ..sort(
        (a, b) => a.codigo.toLowerCase().compareTo(b.codigo.toLowerCase()),
      );
  }

  Future<void> guardarCentroCostoLocal({
    required String codigo,
    required String nombre,
    String? codigoOriginal,
  }) async {
    final codigoLimpio = codigo.trim();
    final nombreLimpio = nombre.trim();
    if (codigoLimpio.isEmpty || nombreLimpio.isEmpty) {
      throw ArgumentError('El código y la descripción son obligatorios.');
    }

    final items = centrosCostoLocales;
    final original = codigoOriginal?.trim().toLowerCase();
    final indiceOriginal = original == null || original.isEmpty
        ? -1
        : items.indexWhere((item) => item.codigo.toLowerCase() == original);
    final duplicado = items.any(
      (item) =>
          item.codigo.toLowerCase() == codigoLimpio.toLowerCase() &&
          item.codigo.toLowerCase() != original,
    );
    if (duplicado) {
      throw ArgumentError('Ya existe un centro de costo con ese código.');
    }

    final centro = CentroCosto(codigo: codigoLimpio, nombre: nombreLimpio);
    if (indiceOriginal >= 0) {
      items[indiceOriginal] = centro;
    } else {
      items.add(centro);
    }
    await _prefs.setString(
      _kCentrosCostoLocales,
      jsonEncode(items.map((item) => item.toJson()).toList()),
    );
  }

  Future<void> eliminarCentroCostoLocal(String codigo) async {
    final codigoNormalizado = codigo.trim().toLowerCase();
    final items = centrosCostoLocales
        .where((item) => item.codigo.toLowerCase() != codigoNormalizado)
        .toList();
    await _prefs.setString(
      _kCentrosCostoLocales,
      jsonEncode(items.map((item) => item.toJson()).toList()),
    );
  }

  List<ConceptoGasto> get conceptosGastoLocales {
    final raw = _prefs.getString(_kConceptosGastoLocales);
    if (raw == null || raw.isEmpty) return <ConceptoGasto>[];
    final data = jsonDecode(raw);
    if (data is! List) {
      throw const FormatException(
        'El registro local de conceptos de gasto no tiene formato válido.',
      );
    }
    return data
        .whereType<Map>()
        .map((item) => ConceptoGasto.fromJson(item.cast<String, dynamic>()))
        .toList()
      ..sort(
        (a, b) => a.codigo.toLowerCase().compareTo(b.codigo.toLowerCase()),
      );
  }

  Future<void> _asegurarConceptoGastoVarios() async {
    final conceptos = conceptosGastoLocales;
    final predeterminado = conceptos.where((item) => item.codigo == '60001');
    if (predeterminado.length == 1 &&
        predeterminado.single.nombre == 'Gastos varios') {
      return;
    }
    final normalizados = <ConceptoGasto>[
      ...conceptos.where((item) => item.codigo != '60001'),
      const ConceptoGasto(codigo: '60001', nombre: 'Gastos varios'),
    ];
    await _prefs.setString(
      _kConceptosGastoLocales,
      jsonEncode(normalizados.map((item) => item.toJson()).toList()),
    );
  }

  Future<void> guardarConceptoGastoLocal({
    required String codigo,
    required String nombre,
    String? codigoOriginal,
  }) async {
    final codigoLimpio = codigo.trim();
    final nombreLimpio = nombre.trim();
    if (codigoLimpio.isEmpty || nombreLimpio.isEmpty) {
      throw ArgumentError('El código y la descripción son obligatorios.');
    }
    final items = conceptosGastoLocales;
    final original = codigoOriginal?.trim().toLowerCase();
    final indiceOriginal = original == null || original.isEmpty
        ? -1
        : items.indexWhere((item) => item.codigo.toLowerCase() == original);
    final duplicado = items.any(
      (item) =>
          item.codigo.toLowerCase() == codigoLimpio.toLowerCase() &&
          item.codigo.toLowerCase() != original,
    );
    if (duplicado) {
      throw ArgumentError('Ya existe un concepto de gasto con ese código.');
    }
    final concepto = ConceptoGasto(codigo: codigoLimpio, nombre: nombreLimpio);
    if (indiceOriginal >= 0) {
      items[indiceOriginal] = concepto;
    } else {
      items.add(concepto);
    }
    await _prefs.setString(
      _kConceptosGastoLocales,
      jsonEncode(items.map((item) => item.toJson()).toList()),
    );
  }

  Future<void> eliminarConceptoGastoLocal(String codigo) async {
    if (codigo.trim() == '60001') {
      throw StateError(
        'El concepto predeterminado 60001 no se puede eliminar.',
      );
    }
    final codigoNormalizado = codigo.trim().toLowerCase();
    final items = conceptosGastoLocales
        .where((item) => item.codigo.toLowerCase() != codigoNormalizado)
        .toList();
    await _prefs.setString(
      _kConceptosGastoLocales,
      jsonEncode(items.map((item) => item.toJson()).toList()),
    );
  }

  Map<String, double> get tiposCambioDiarios {
    final raw = _prefs.getString(_kTiposCambioDiarios);
    if (raw == null || raw.isEmpty) return <String, double>{};
    final data = jsonDecode(raw);
    if (data is! Map) {
      throw const FormatException(
        'Los tipos de cambio diarios no tienen formato válido.',
      );
    }
    return data.map(
      (key, value) => MapEntry(key.toString(), double.parse('$value')),
    );
  }

  double get tipoCambioDiario {
    final fecha = _fechaTipoCambio(DateTime.now());
    return tiposCambioDiarios[fecha] ?? 1;
  }

  Future<void> asegurarTipoCambioDiario({DateTime? fecha}) async {
    final tipos = tiposCambioDiarios;
    final clave = _fechaTipoCambio(fecha ?? DateTime.now());
    if (tipos.containsKey(clave)) return;
    tipos[clave] = 1;
    await _prefs.setString(_kTiposCambioDiarios, jsonEncode(tipos));
  }

  Future<void> guardarTipoCambioDiario(double valor, {DateTime? fecha}) async {
    if (!valor.isFinite || valor <= 0) {
      throw ArgumentError.value(valor, 'valor', 'Debe ser mayor que cero.');
    }
    final tipos = tiposCambioDiarios;
    tipos[_fechaTipoCambio(fecha ?? DateTime.now())] = valor;
    await _prefs.setString(_kTiposCambioDiarios, jsonEncode(tipos));
  }

  Future<bool> actualizarTipoCambioDiarioSiNecesario({
    required Future<double> Function(DateTime fecha) consultar,
    DateTime? fecha,
  }) async {
    final dia = fecha ?? DateTime.now();
    await asegurarTipoCambioDiario(fecha: dia);
    if ((tiposCambioDiarios[_fechaTipoCambio(dia)] ?? 1) > 1) return false;

    final valor = await consultar(dia);
    if (!valor.isFinite || valor <= 1) {
      throw const FormatException(
        'La consulta no devolvio un tipo de cambio mayor que 1.',
      );
    }
    await guardarTipoCambioDiario(valor, fecha: dia);
    return true;
  }

  String _fechaTipoCambio(DateTime fecha) =>
      '${fecha.year.toString().padLeft(4, '0')}-'
      '${fecha.month.toString().padLeft(2, '0')}-'
      '${fecha.day.toString().padLeft(2, '0')}';

  Future<void> eliminarTipoMovimientoCaja(String id) async {
    if (tiposMovimientoCaja.any(
      (tipo) => tipo.id == id && tipo.nombre == 'EFECTIVO',
    )) {
      throw StateError(
        'El tipo de movimiento predeterminado EFECTIVO no se puede eliminar.',
      );
    }
    final items = tiposMovimientoCaja.where((item) => item.id != id).toList();
    await _prefs.setString(
      _kTiposMovimientoCaja,
      jsonEncode(items.map((item) => item.toJson()).toList()),
    );
  }

  Future<void> marcarEnviado(String id, {required bool porWhatsApp}) async {
    final items = comprobantes;
    final indice = items.indexWhere((c) => c.id == id);
    if (indice < 0) {
      throw StateError(
        'No se encontró el comprobante para actualizar su estado.',
      );
    }
    if (porWhatsApp) {
      items[indice].estadoWhatsapp = 'enviado';
    } else {
      items[indice].estadoSiscont = 'enviado';
    }
    await guardarComprobantes(items);
  }

  bool _mismosValores(Comprobante a, Comprobante b) {
    if (a.valores.length != b.valores.length) return false;
    return a.valores.entries.every((e) => b.valores[e.key] == e.value);
  }

  /// Siguiente numero de voucher de compras (correlativo local).
  int siguienteVoucher() {
    final n = (_prefs.getInt(_kSecuencia) ?? 0) + 1;
    return n;
  }

  Future<int> consumirVoucher() async {
    final n = siguienteVoucher();
    await _prefs.setInt(_kSecuencia, n);
    return n;
  }

  Future<String> consumirNumeroOtroComprobante() async {
    var ultimoUsado = _prefs.getInt(_kSecuenciaOtros) ?? -1;
    for (final comprobante in comprobantes) {
      if (comprobante['doc'] != '00' || comprobante.motor != 'manual') {
        continue;
      }
      final numero = comprobante['numero'].trim();
      if (!RegExp(r'^\d{1,8}$').hasMatch(numero)) continue;
      final valor = int.tryParse(numero);
      if (valor != null && valor > ultimoUsado) ultimoUsado = valor;
    }

    final siguiente = ultimoUsado + 1;
    if (siguiente > 99999999) {
      throw StateError('Se agotó el correlativo de comprobantes tipo 00.');
    }
    await _prefs.setInt(_kSecuenciaOtros, siguiente);
    return siguiente.toString().padLeft(8, '0');
  }

  // ------------------------------------------------------------ archivos ---

  /// Guarda los bytes de un comprobante y devuelve su ruta/referencia.
  Future<String> copiarArchivo(String nombreSugerido, List<int> bytes) {
    return archivos.guardarDocumento(nombreSugerido, bytes);
  }

  /// Espacio usado por los documentos guardados (para mostrar en pantalla).
  String get espacioUsado => archivos.espacioDocumentos;
}
