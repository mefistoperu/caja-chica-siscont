/// Capa de archivos multiplataforma.
///
/// En movil/escritorio se usan archivos reales (`dart:io` + path_provider);
/// en web (Firefox/Chrome) se mantienen en memoria y se descargan con Blob,
/// porque el navegador no tiene sistema de archivos accesible.
library;

export 'archivos_io.dart'
    if (dart.library.js_interop) 'archivos_web.dart';
