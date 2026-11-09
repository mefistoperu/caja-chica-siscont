import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/conexion.dart';
import '../models/saldo_tercero.dart';
import '../models/usuario.dart';

/// Error devuelto por el Web Service (mensaje listo para mostrar al usuario).
class WsException implements Exception {
  final String mensaje;

  /// Codigo HTTP devuelto por el servicio (0 si no hubo respuesta).
  final int codigo;

  const WsException(this.mensaje, [this.codigo = 0]);

  @override
  String toString() => mensaje;
}

/// Cliente del Web Service `assets/ws/ws.php` de efsiscont_v2.
///
/// Los usuarios se validan en el Web Service; las conexiones se almacenan
/// localmente y sus datos se envían al Web Service solo para operaciones SISCONT.
class WsCliente {
  WsCliente._();

  static final WsCliente i = WsCliente._();

  static const Duration _espera = Duration(seconds: 25);

  // ---------------------------------------------------------------- base ---

  Future<Map<String, dynamic>> _llamar(
    String op, [
    Map<String, String> datos = const <String, String>{},
  ]) async {
    final uri = Uri.parse('${AppConfig.wsUrl}?op=$op');
    http.Response r;
    final headers = <String, String>{'Accept': 'application/json'};
    if (AppConfig.wsToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer ${AppConfig.wsToken}';
    }
    try {
      r = await http.post(uri, headers: headers, body: datos).timeout(_espera);
    } catch (_) {
      throw const WsException(
        'No se pudo conectar con el servidor. '
        'Verifique que Apache y MySQL esten encendidos.',
      );
    }

    Map<String, dynamic> cuerpo;
    try {
      final decodificado = jsonDecode(utf8.decode(r.bodyBytes));
      if (decodificado is! Map) throw const FormatException();
      cuerpo = decodificado.cast<String, dynamic>();
    } catch (_) {
      throw WsException(
        'Respuesta no valida del servidor (HTTP ${r.statusCode}).',
      );
    }

    if (cuerpo['ok'] != true) {
      final mensaje = '${cuerpo['mensaje'] ?? 'Operacion rechazada.'}';
      throw WsException(
        mensaje.isEmpty ? 'Operacion rechazada.' : mensaje,
        r.statusCode,
      );
    }
    return cuerpo;
  }

  Future<double> obtenerTipoCambioVenta(DateTime fecha) async {
    final respuesta = await _llamar('tipocambio');
    final datos = _data(respuesta);
    final fechaEsperada =
        '${fecha.year.toString().padLeft(4, '0')}-'
        '${fecha.month.toString().padLeft(2, '0')}-'
        '${fecha.day.toString().padLeft(2, '0')}';
    if ('${datos['fecha'] ?? ''}' != fechaEsperada) {
      throw WsException(
        'SUNAT aun no publica el tipo de cambio para $fechaEsperada.',
      );
    }
    final venta = double.tryParse('${datos['venta'] ?? ''}');
    if (venta == null || !venta.isFinite || venta <= 1) {
      throw const WsException(
        'SUNAT devolvio un tipo de cambio de venta no valido.',
      );
    }
    return venta;
  }

  Future<Map<String, dynamic>> buscarDocumentoPersona({
    required String numero,
    required String tipoDocumento,
  }) async {
    final tipo = tipoDocumento.trim().toUpperCase();
    final documento = numero.replaceAll(RegExp(r'\D'), '');
    if ((tipo == 'RUC' && documento.length != 11) ||
        (tipo == 'DNI' && documento.length != 8) ||
        (tipo != 'RUC' && tipo != 'DNI')) {
      throw const WsException(
        'Ingrese un RUC de 11 dígitos o un DNI de 8 dígitos.',
      );
    }
    final respuesta = await _llamar('buscarpersona', <String, String>{
      'numero': documento,
      'tipodocumento': tipo,
    });
    final datos = _data(respuesta);
    final nombre = tipo == 'DNI'
        ? <String>[
            '${datos['apellidopaterno'] ?? ''}',
            '${datos['apellidomaterno'] ?? ''}',
            '${datos['nombres'] ?? ''}',
          ].where((parte) => parte.trim().isNotEmpty).join(' ')
        : '${datos['razonSocial'] ?? datos['razon_social'] ?? ''}';
    if (nombre.trim().isEmpty) {
      throw const WsException(
        'ApisPeru no devolvio un nombre para ese documento.',
      );
    }
    return <String, dynamic>{
      ...datos,
      'nombreCompleto': nombre.trim(),
      'numeroDocumento': tipo == 'RUC'
          ? '${datos['ruc'] ?? documento}'
          : documento,
    };
  }

  Map<String, dynamic> _data(Map<String, dynamic> r) {
    final d = r['data'];
    return d is Map ? d.cast<String, dynamic>() : <String, dynamic>{};
  }

  List<dynamic> _lista(Map<String, dynamic> r) {
    final d = r['data'];
    return d is List ? d : const <dynamic>[];
  }

  // ------------------------------------------------------------- usuarios ---

  /// Autentica contra `usuarios`. Acepta usuario, login, idusuario o correo.
  Future<Usuario> login(String identificador, String clave) async {
    final r = await _llamar('login', <String, String>{
      'usuario': identificador.trim(),
      'clave': clave,
    });
    final d = _data(r);
    final correo = '${d['correo'] ?? ''}';
    final nombre = '${d['usuario'] ?? d['nombre'] ?? identificador}'.trim();
    return Usuario(
      correo: correo.isEmpty ? identificador.trim().toLowerCase() : correo,
      usuario: nombre.isEmpty ? identificador.trim() : nombre,
      celular: '${d['celular'] ?? ''}',
      hash: '',
      salt: '',
      creado: DateTime.now().toIso8601String(),
    );
  }

  /// Crea la cuenta en `usuarios`. Lanza [WsException] si el servidor la rechaza.
  Future<Usuario> registrar({
    required String correo,
    required String usuario,
    required String contrasena,
    required String celular,
  }) async {
    final r = await _llamar('registrar', <String, String>{
      'usuario': usuario.trim(),
      'clave': contrasena,
      'correo': correo.trim().toLowerCase(),
      'celular': celular.trim(),
    });
    final d = _data(r);
    return Usuario(
      correo: '${d['correo'] ?? correo}'.trim().toLowerCase(),
      usuario: '${d['usuario'] ?? usuario}'.trim(),
      celular: '${d['celular'] ?? celular}'.trim(),
      hash: '',
      salt: '',
      creado: DateTime.now().toIso8601String(),
    );
  }

  // ---------------------------------------------------------- conexiones ---

  Map<String, String> _datosConexion(Conexion conexion) => <String, String>{
    'conexion': '${conexion.id}',
    'nombreConexion': conexion.nombre,
    'host': conexion.host,
    'data': conexion.data,
    'usuario': conexion.usuario,
    'pass': conexion.pass,
    'tipo': conexion.tipo,
  };

  Future<List<OrigenVoucher>> listarOrigenes({
    required Conexion conexion,
  }) async {
    final r = await _llamar('listarorigenes', _datosConexion(conexion));
    return _lista(r)
        .whereType<Map>()
        .map((e) => OrigenVoucher.fromJson(e.cast<String, dynamic>()))
        .where((origen) => origen.codigo.isNotEmpty)
        .toList();
  }

  Future<List<SaldoTercero>> listarSaldosTerceros({
    required Conexion conexion,
    required String tipo,
  }) async {
    final r = await _llamar('saldosterceros', <String, String>{
      ..._datosConexion(conexion),
      'tipo': tipo,
    });
    return _lista(r)
        .whereType<Map>()
        .map((e) => SaldoTercero.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  Future<Map<String, dynamic>> grabarVoucherLinea({
    required Conexion conexion,
    required Map<String, String> datos,
  }) {
    return _llamar('grabarvoucher', <String, String>{
      ...datos,
      ..._datosConexion(conexion),
    });
  }

  /// Diagnostico de solo lectura: devuelve `{ok, mensaje, driver, version, ms}`.
  Future<Map<String, dynamic>> probarConeccion(Conexion conexion) async {
    return _llamar('probarconexion', _datosConexion(conexion));
  }

  Future<Map<String, dynamic>> estadisticas() => _llamar('estadisticas');
}
