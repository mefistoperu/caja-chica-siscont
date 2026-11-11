import 'mapeo_comprobante.dart';
import 'ws_cliente.dart';

/// Error de lectura del comprobante que se puede mostrar tal cual al usuario.
class IaException implements Exception {
  final String mensaje;
  IaException(this.mensaje);

  @override
  String toString() => mensaje;
}

/// Resultado del analisis: datos planos listos para el formulario y motor usado.
class ResultadoIa {
  final Map<String, dynamic> datos;
  final String motor;
  final String fuenteTexto;
  const ResultadoIa(this.datos, this.motor, this.fuenteTexto);
}

/// Lee comprobantes (fotos o PDF) usando la IA configurada en el servidor.
///
/// El archivo se envia a la operacion `analizaradjunto` del WS, por lo que la
/// clave de Groq permanece en el backend y no se expone en el telefono.
class AnalisisComprobante {
  const AnalisisComprobante();

  Future<ResultadoIa> analizar({
    required List<int> bytes,
    required String nombre,
  }) async {
    try {
      final comprobante = await WsCliente.i.analizarAdjunto(
        bytes: bytes,
        nombre: nombre,
      );
      final motor = '${comprobante['motor'] ?? ''}'.trim();
      final fuente = '${comprobante['fuente_texto'] ?? ''}'.trim();
      return ResultadoIa(
        datosPlanosDesdeWs(comprobante),
        motor.isEmpty ? 'ws:analizaradjunto' : motor,
        fuente.isEmpty ? 'ws' : fuente,
      );
    } on WsException catch (e) {
      throw IaException(e.mensaje);
    }
  }
}
