import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../config.dart';
import '../storage/archivos.dart';

class IaException implements Exception {
  final String mensaje;
  IaException(this.mensaje);
  @override
  String toString() => mensaje;
}

/// Resultado de leer un comprobante con IA.
class ResultadoIa {
  final Map<String, dynamic> datos;
  final String motor;
  final String fuenteTexto;
  const ResultadoIa(this.datos, this.motor, this.fuenteTexto);
}

/// Lee un comprobante (foto o PDF) con Groq y devuelve los datos estructurados.
///
/// - Imagen: un solo llamado al modelo de vision (`qwen/qwen3.8-27b`) que
///   transcribe y devuelve el JSON.
/// - PDF con texto: se extrae el texto en el telefono (Syncfusion, gratis y sin
///   internet) y lo estructura el modelo de texto (`openai/gpt-oss-120b`).
/// - PDF escaneado (sin capa de texto): se pide una foto del documento.
class GroqServicio {
  const GroqServicio();

  static const String _prompt = '''
Eres un asistente contable peruano. Recibes la foto o el texto de un comprobante
de pago (factura, boleta, recibo por honorarios, nota de credito/debito) y
devuelves UNICAMENTE un objeto JSON valido, sin explicaciones ni markdown.

Esquema exacto (todas las claves son obligatorias, usa "" o 0 si no aparece):
{
  "tipo_documento": "01 factura | 02 boleta | 03 nota credito | 04 nota debito | 07 retencion | 08 recibo honorarios | 00 otro",
  "serie_numero": "F001-00000123",
  "fecha_emision": "AAAA-MM-DD",
  "fecha_vencimiento": "AAAA-MM-DD o vacio",
  "ruc": "RUC del EMISOR, 11 digitos",
  "razon_social": "nombre o razon social del EMISOR",
  "moneda": "PEN o USD",
  "tipo_cambio": 0.0000,
  "base_gravada": 0.00,
  "base_exonerada": 0.00,
  "base_inafecta": 0.00,
  "descuento": 0.00,
  "isc": 0.00,
  "igv": 0.00,
  "otros_tributos": 0.00,
  "impuesto_bolsa": 0.00,
  "total": 0.00,
  "detalle_items": [
    {"descripcion": "producto o servicio", "cantidad": 1, "precio": 0.00, "importe": 0.00}
  ],
  "glosa": "descripcion corta del concepto, nunca el importe escrito en letras",
  "tipo_doc_identidad": "6 si es RUC, 1 si es DNI, 0 si no se ve",
  "medio_pago": "efectivo/transferencia/tarjeta/deposito o vacio",
  "apellido1": "", "apellido2": "", "nombre": "",
  "retencion": 0,
  "cod_tasa": "", "ind_ret": "",
  "confianza": 0.0
}

Reglas:
1. Los montos son numeros (sin simbolos de moneda, sin separador de miles).
2. "total" es el total a pagar, no el subtotal.
3. Si el documento es un recibo por honorarios y no hay IMPORTE TOTAL, usa la
   linea "total / (retencion) / neto" o el neto como total.
4. ruc y razon_social son SIEMPRE del emisor (proveedor), no del cliente.
5. Fechas en formato AAAA-MM-DD. Si el anio tiene 2 digitos, asume 20xx.
6. Prioriza los montos impresos junto a OP. GRAVADAS, EXONERADAS e
   INAFECTAS. No mezcles bases exoneradas o inafectas con base_gravada. Solo
   deduce base_gravada de total - IGV - otros si toda la operación es gravada.
7. Revisa TODAS las paginas y extrae cada fila de producto o servicio de la
   tabla, en el mismo orden, en "detalle_items". No resumas, agrupes ni omitas
   filas legibles. Incluye descripcion, cantidad, precio unitario e importe
   total de linea. "importe" es el valor de la linea antes de IGV e impuestos.
   No incluyas en el detalle subtotales, descuentos generales, impuestos,
   totales, leyendas ni importes escritos en letras.
8. La suma de importes debe aproximarse a base_gravada + base_exonerada +
   base_inafecta. No cambies los importes individuales para forzar la suma: si
   existe una diferencia, conserva los importes impresos y no los inventes.
9. "glosa" nunca puede ser una cifra en letras, el monto de la factura, ni una
   leyenda como "DOS MIL ... CON 00/100 SOLES". Usa el primer concepto legible
   o una descripcion breve del comprobante.
10. No inventes datos: lo que no se lea queda "" o 0.
11. "tipo_cambio" es el tipo de cambio impreso en el comprobante; si no aparece
    deja 0, no uses 1 como valor supuesto.
12. Devuelve el JSON sin bloques de codigo ni texto adicional.
''';

  // ------------------------------------------------------------- publico ---

  Future<ResultadoIa> analizar(String ruta) async {
    if (!existeDocumento(ruta)) {
      throw IaException('No se encontro el archivo.');
    }
    final bytes = await leerDocumento(ruta);
    final ext = ruta.toLowerCase().split('.').last;

    if (ext == 'pdf') {
      final texto = _extraerTextoPdf(bytes);
      if (texto.trim().length < 40) {
        throw IaException(
          'El PDF no tiene texto seleccionable (parece escaneado). '
          'Tome una foto del documento para leerlo.',
        );
      }
      final datos = await _estructurarTexto(texto);
      return ResultadoIa(
        datos,
        'groq:${AppConfig.modelosTexto.first}',
        'pdf-texto',
      );
    }

    final mime = _mime(ext);
    final b64 = base64Encode(bytes);
    final datos = await _datosDesdeImagen(b64, mime);
    return ResultadoIa(datos, 'groq:${AppConfig.modeloVision}', 'groq-vision');
  }

  /// Extrae el texto de un PDF sin salir del telefono.
  String _extraerTextoPdf(List<int> bytes) {
    PdfDocument? doc;
    try {
      doc = PdfDocument(inputBytes: bytes);
      return PdfTextExtractor(doc).extractText();
    } catch (_) {
      return '';
    } finally {
      doc?.dispose();
    }
  }

  // --------------------------------------------------------------- llamadas ---

  Future<Map<String, dynamic>> _datosDesdeImagen(
    String base64Img,
    String mime,
  ) async {
    final contenido = await _chat(
      modelo: AppConfig.modeloVision,
      mensajes: <Map<String, dynamic>>[
        <String, dynamic>{'role': 'system', 'content': _prompt},
        <String, dynamic>{
          'role': 'user',
          'content': <Map<String, dynamic>>[
            <String, dynamic>{
              'type': 'text',
              'text': 'Lee este comprobante y devuelve el JSON del esquema.',
            },
            <String, dynamic>{
              'type': 'image_url',
              'image_url': <String, dynamic>{
                'url': 'data:$mime;base64,$base64Img',
              },
            },
          ],
        },
      ],
      maxTokens: 4096,
    );
    return _jsonDe(contenido);
  }

  Future<Map<String, dynamic>> _estructurarTexto(String texto) async {
    final contenido = await _chat(
      modelo: AppConfig.modelosTexto.first,
      mensajes: <Map<String, dynamic>>[
        <String, dynamic>{'role': 'system', 'content': _prompt},
        <String, dynamic>{
          'role': 'user',
          'content': 'TEXTO COMPLETO DEL COMPROBANTE:\n$texto',
        },
      ],
      maxTokens: 4096,
    );
    return _jsonDe(contenido);
  }

  /// POST a Groq rotando claves y reintentando ante 429/5xx.
  Future<String> _chat({
    required String modelo,
    required List<Map<String, dynamic>> mensajes,
    int maxTokens = 1600,
  }) async {
    if (AppConfig.groqKeys.isEmpty) {
      throw IaException('Falta configurar la clave de Groq.');
    }

    String? ultimoError;
    for (final key in AppConfig.groqKeys) {
      for (var intento = 1; intento <= 2; intento++) {
        try {
          final resp = await http
              .post(
                Uri.parse(AppConfig.groqUrl),
                headers: <String, String>{
                  'Authorization': 'Bearer $key',
                  'Content-Type': 'application/json',
                },
                body: jsonEncode(<String, dynamic>{
                  'model': modelo,
                  'messages': mensajes,
                  'temperature': 0.1,
                  'max_tokens': maxTokens,
                }),
              )
              .timeout(const Duration(seconds: 120));

          if (resp.statusCode == 200) {
            final cuerpo = jsonDecode(utf8.decode(resp.bodyBytes));
            final texto = cuerpo['choices']?[0]?['message']?['content'];
            if (texto is String && texto.trim().isNotEmpty) return texto;
            ultimoError = 'La IA devolvio una respuesta vacia.';
            break;
          }

          final detalle = _mensajeError(resp);
          if (resp.statusCode == 429) {
            final espera = _retryAfter(resp);
            if (intento == 1 && espera <= 25) {
              await Future<void>.delayed(Duration(seconds: espera));
              continue;
            }
            ultimoError = 'Limite de uso de la IA alcanzado. $detalle';
            break; // pasa a la siguiente clave
          }
          if (resp.statusCode == 401 || resp.statusCode == 403) {
            ultimoError = 'La clave de la IA no es valida. $detalle';
            break;
          }
          if (resp.statusCode == 413) {
            throw IaException('El archivo es demasiado grande para la IA.');
          }
          if (resp.statusCode >= 500 && intento == 1) {
            await Future<void>.delayed(const Duration(seconds: 3));
            continue;
          }
          ultimoError = 'Error de la IA (${resp.statusCode}). $detalle';
          break;
        } on TimeoutException {
          ultimoError = 'La IA tardo demasiado en responder.';
          break;
        } on IaException {
          rethrow;
        } catch (e) {
          ultimoError = 'No se pudo conectar con la IA. Revise su internet.';
          break;
        }
      }
    }
    throw IaException(ultimoError ?? 'No se pudo analizar el comprobante.');
  }

  static int _retryAfter(http.Response r) {
    final v = int.tryParse(r.headers['retry-after'] ?? '');
    if (v == null) return 6;
    return v < 2 ? 6 : v + 1;
  }

  static String _mensajeError(http.Response r) {
    try {
      final j = jsonDecode(r.body);
      final m = j['error']?['message'];
      if (m is String && m.isNotEmpty) return m;
    } catch (_) {}
    return '';
  }

  static String _mime(String ext) {
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      default:
        return 'image/jpeg';
    }
  }

  /// Limpia bloques markdown y recorta el primer objeto JSON.
  static Map<String, dynamic> _jsonDe(String texto) {
    var s = texto.trim();
    final inicio = s.indexOf('{');
    final fin = s.lastIndexOf('}');
    if (inicio < 0 || fin <= inicio) {
      throw IaException('La IA no devolvio los datos en el formato esperado.');
    }
    s = s.substring(inicio, fin + 1);
    try {
      final j = jsonDecode(s);
      if (j is Map) return j.cast<String, dynamic>();
    } catch (_) {}
    throw IaException('No se pudo interpretar la respuesta de la IA.');
  }
}
