import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/licencia.dart';
import 'ws_cliente.dart';

/// Cliente del servicio de licencias (`llavesweb`).
///
/// Se consulta con el correo y la contrasena del usuario:
/// `GET /llavesweb/index.php?correo=...&pcorreo=...`
class LicenciaCliente {
  LicenciaCliente._();

  static final LicenciaCliente i = LicenciaCliente._();

  static const Duration _espera = Duration(seconds: 20);

  /// Consulta la licencia del usuario.
  ///
  /// Lanza [WsException] si no hay conexion o la respuesta no es valida.
  /// Una respuesta sin llave ni empresa significa credenciales incorrectas.
  Future<Licencia> consultar({
    required String correo,
    required String clave,
  }) async {
    final uri = Uri.parse(AppConfig.licenciaUrl).replace(
      queryParameters: <String, String>{
        'correo': correo.trim(),
        'pcorreo': clave,
      },
    );

    http.Response respuesta;
    try {
      respuesta = await http
          .get(uri, headers: const <String, String>{'Accept': 'application/json'})
          .timeout(_espera);
    } catch (_) {
      throw const WsException(
        'No se pudo conectar con el servidor de licencias. '
        'Verifique su conexion a internet.',
      );
    }

    Map<String, dynamic> cuerpo;
    try {
      final decodificado = jsonDecode(utf8.decode(respuesta.bodyBytes));
      if (decodificado is! Map) throw const FormatException();
      cuerpo = decodificado.cast<String, dynamic>();
    } catch (_) {
      throw WsException(
        'Respuesta no valida del servidor de licencias '
        '(HTTP ${respuesta.statusCode}).',
        respuesta.statusCode,
      );
    }

    return Licencia.fromJson(cuerpo);
  }
}
