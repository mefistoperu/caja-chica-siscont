class TerceroLocal {
  final String id;
  final String tipo;
  final String tipoDocumento;
  final String numeroDocumento;
  final String nombre;
  final String direccion;
  final String telefono;
  final String correo;
  final String centroCostoCodigo;
  final String conceptoGastoCodigo;

  const TerceroLocal({
    required this.id,
    required this.tipo,
    required this.tipoDocumento,
    required this.numeroDocumento,
    required this.nombre,
    this.direccion = '',
    this.telefono = '',
    this.correo = '',
    this.centroCostoCodigo = '',
    this.conceptoGastoCodigo = '',
  });

  bool get esProveedor => tipo == 'proveedor' || tipo == 'ambos';

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'tipo': tipo,
    'tipoDocumento': tipoDocumento,
    'numeroDocumento': numeroDocumento,
    'nombre': nombre,
    'direccion': direccion,
    'telefono': telefono,
    'correo': correo,
    'centroCostoCodigo': centroCostoCodigo,
    'conceptoGastoCodigo': conceptoGastoCodigo,
  };

  factory TerceroLocal.fromJson(Map<String, dynamic> json) => TerceroLocal(
    id: '${json['id'] ?? ''}',
    tipo: '${json['tipo'] ?? 'proveedor'}',
    tipoDocumento: '${json['tipoDocumento'] ?? 'RUC'}',
    numeroDocumento: '${json['numeroDocumento'] ?? ''}',
    nombre: '${json['nombre'] ?? ''}',
    direccion: '${json['direccion'] ?? ''}',
    telefono: '${json['telefono'] ?? ''}',
    correo: '${json['correo'] ?? ''}',
    centroCostoCodigo: '${json['centroCostoCodigo'] ?? ''}',
    conceptoGastoCodigo: '${json['conceptoGastoCodigo'] ?? ''}',
  );

  static String nuevoId() => '${DateTime.now().microsecondsSinceEpoch}';
}
