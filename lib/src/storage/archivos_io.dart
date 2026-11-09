import 'dart:io';

import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../config.dart';

Directory? _documentos;
Directory? _exportes;

const String _mimeExcel =
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

/// Crea (si hace falta) las carpetas privadas de la app.
Future<void> iniciarArchivos() async {
  if (_documentos != null && _exportes != null) return;
  final base = await getApplicationDocumentsDirectory();
  _documentos = Directory(
    '${base.path}${Platform.pathSeparator}${AppConfig.carpetaDocumentos}',
  );
  _exportes = Directory(
    '${base.path}${Platform.pathSeparator}${AppConfig.carpetaExportes}',
  );
  if (!_documentos!.existsSync()) _documentos!.createSync(recursive: true);
  if (!_exportes!.existsSync()) _exportes!.createSync(recursive: true);
}

/// Guarda los bytes de un comprobante y devuelve su ruta.
Future<String> guardarDocumento(String nombreSugerido, List<int> bytes) async {
  await iniciarArchivos();
  final limpio = nombreSugerido.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  final marca = DateTime.now().millisecondsSinceEpoch;
  final destino = File(
    '${_documentos!.path}${Platform.pathSeparator}${marca}_$limpio',
  );
  await destino.writeAsBytes(bytes, flush: true);
  return destino.path;
}

Future<List<int>> leerDocumento(String ref) async {
  final archivo = File(ref);
  if (!archivo.existsSync()) {
    throw StateError('El archivo ya no esta en el telefono.');
  }
  return archivo.readAsBytes();
}

bool existeDocumento(String ref) => ref.isNotEmpty && File(ref).existsSync();

String nombreDeReferencia(String ref) => ref.split(Platform.pathSeparator).last;

String get espacioDocumentos {
  final carpeta = _documentos;
  if (carpeta == null || !carpeta.existsSync()) return '0 KB';
  var total = 0;
  for (final f in carpeta.listSync()) {
    if (f is File) total += f.lengthSync();
  }
  if (total < 1024 * 1024) return '${(total / 1024).toStringAsFixed(0)} KB';
  return '${(total / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// Guarda el Excel exportado y devuelve su ruta.
Future<String> guardarExporte(String nombre, List<int> bytes) async {
  await iniciarArchivos();
  final ruta = '${_exportes!.path}${Platform.pathSeparator}$nombre';
  await File(ruta).writeAsBytes(bytes, flush: true);
  return ruta;
}

bool existeExporte(String ref) => ref.isNotEmpty && File(ref).existsSync();

Future<void> abrirReferencia(String ref) async {
  await OpenFilex.open(ref);
}

Future<void> compartirExporte(
  String ref, {
  required String asunto,
  required String texto,
}) async {
  await SharePlus.instance.share(
    ShareParams(
      files: <XFile>[XFile(ref, mimeType: _mimeExcel)],
      subject: asunto,
      text: texto,
    ),
  );
}
