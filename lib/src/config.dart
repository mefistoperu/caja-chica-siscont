import 'package:flutter/foundation.dart';

/// Configuracion de la app movil "Caja Chica".
///
/// Los usuarios se validan en el Web Service. Las conexiones y los
/// comprobantes se guardan en el dispositivo.
/// El analisis de comprobantes (OCR e interpretacion con IA) lo realiza el
/// Web Service; la app solo envia el archivo. La otra salida a internet es el
/// envio del Excel por WhatsApp.
class AppConfig {
  const AppConfig._();

  static const String nombreApp = 'Caja Chica';
  static const String version = '1.0';

  // ------------------------------------------------------- Web Service ---
  /// Web Service local de SISCONT (XAMPP). Solo sirve en el equipo donde corre
  /// XAMPP o en un emulador; en un teléfono físico reemplazar localhost por la
  /// dirección IP del equipo.
  static const String wsUrlLocal =
      'http://localhost/proyectos/efsiscont_v2/assets/ws/ws.php';

  /// Web Service de producción (SISCONT en la nube).
  static const String wsUrlProduccion =
      'https://siscont.solutions.net.pe/assets/ws/ws.php';

  /// Cambiar a `true` para consumir el Web Service de producción.
  /// Al desplegar la app en un teléfono real, dejar en `true`.
  static const bool wsUsarProduccion = true;

  /// URL activa del Web Service. Todo el consumo pasa por aquí a través de
  /// [WsCliente].
  static const String wsUrl = wsUsarProduccion ? wsUrlProduccion : wsUrlLocal;

  static const String wsToken = '';

  // ------------------------------------------------------------ Licencia ---
  /// Servicio de licencias. Devuelve la fecha de vencimiento, la llave y la
  /// empresa a partir del correo y la contrasena del usuario.
  static const String licenciaUrlDirecta =
      'http://nubesiscont.com/llavesweb/index.php';

  /// Proxy local con CORS para Flutter Web. El servidor de licencias no envia
  /// cabeceras CORS y el navegador bloquea la peticion directa.
  static const String licenciaUrlWeb =
      'http://localhost/proyectos/efsiscont_flutter_v2/assets/ws/licencia.php';

  /// En web se usa el proxy; en movil se consulta directamente el servicio.
  static String get licenciaUrl => kIsWeb ? licenciaUrlWeb : licenciaUrlDirecta;

  /// Copias de seguridad en el telefono.
  static const String carpetaDocumentos = 'documentos';
  static const String carpetaExportes = 'exportaciones';
}
