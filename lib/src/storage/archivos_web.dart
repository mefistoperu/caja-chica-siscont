import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// En el navegador no hay sistema de archivos: los comprobantes se guardan en
/// memoria durante la sesion y los Excel se descargan con un Blob.
/// (La app esta pensada para el telefono; web es solo para pruebas.)
final Map<String, Uint8List> _documentos = <String, Uint8List>{};
final Map<String, Uint8List> _exportes = <String, Uint8List>{};

const String _mimeExcel =
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

Future<void> iniciarArchivos() async {}

Future<String> guardarDocumento(String nombreSugerido, List<int> bytes) async {
  final limpio = nombreSugerido.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  final marca = DateTime.now().millisecondsSinceEpoch;
  final ref = 'navegador/documentos/${marca}_$limpio';
  _documentos[ref] = Uint8List.fromList(bytes);
  return ref;
}

Future<List<int>> leerDocumento(String ref) async {
  final bytes = _documentos[ref];
  if (bytes == null) {
    throw StateError('El archivo ya no esta disponible en esta sesion.');
  }
  return bytes;
}

bool existeDocumento(String ref) => _documentos.containsKey(ref);

String nombreDeReferencia(String ref) => ref.split('/').last;

String get espacioDocumentos {
  var total = 0;
  for (final bytes in _documentos.values) {
    total += bytes.length;
  }
  if (total < 1024 * 1024) return '${(total / 1024).toStringAsFixed(0)} KB';
  return '${(total / (1024 * 1024)).toStringAsFixed(1)} MB';
}

Future<String> guardarExporte(String nombre, List<int> bytes) async {
  final ref = 'navegador/exportes/$nombre';
  _exportes[ref] = Uint8List.fromList(bytes);
  return ref;
}

bool existeExporte(String ref) => _exportes.containsKey(ref);

Future<void> abrirReferencia(String ref) async {
  final bytes = _documentos[ref];
  if (bytes == null) return;
  web.window.open(_urlBlob(bytes, _mimeDe(ref)), '_blank');
}

Future<void> compartirExporte(
  String ref, {
  required String asunto,
  required String texto,
}) async {
  final bytes = _exportes[ref];
  if (bytes == null) {
    throw StateError('El archivo no esta disponible.');
  }
  _descargar(bytes, nombreDeReferencia(ref));
}

void _descargar(Uint8List bytes, String nombre) {
  final ancla = web.document.createElement('a') as web.HTMLAnchorElement;
  ancla.href = _urlBlob(bytes, _mimeExcel);
  ancla.download = nombre;
  ancla.click();
  web.URL.revokeObjectURL(ancla.href);
}

String _urlBlob(Uint8List bytes, String mime) {
  final partes = <JSAny>[bytes.toJS].toJS;
  final blob = web.Blob(partes, web.BlobPropertyBag(type: mime));
  return web.URL.createObjectURL(blob);
}

String _mimeDe(String ref) {
  final ext = ref.toLowerCase().split('.').last;
  if (ext == 'pdf') return 'application/pdf';
  if (ext == 'png') return 'image/png';
  if (ext == 'webp') return 'image/webp';
  if (ext == 'gif') return 'image/gif';
  return 'image/jpeg';
}

/// Utilidad para depuracion: tamano total en bytes.
int get bytesEnMemoria => _documentos.values.fold(0, (a, b) => a + b.length);

/// Utilidad para depuracion: contenido en base64 de un documento.
String? base64DeDocumento(String ref) {
  final bytes = _documentos[ref];
  return bytes == null ? null : base64Encode(bytes);
}
