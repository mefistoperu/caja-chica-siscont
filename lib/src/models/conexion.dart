/// Conexion (empresa) guardada localmente en el dispositivo.
class Conexion {
  final int id;
  final String nombre;
  final String host;
  final String data;
  final String usuario;
  final String pass;
  final String tipo;
  final String imagen;
  final int estado;

  const Conexion({
    required this.id,
    required this.nombre,
    required this.host,
    required this.data,
    required this.usuario,
    required this.pass,
    required this.tipo,
    required this.imagen,
    required this.estado,
  });

  /// Estado 0 = activa y 1 = anulada.
  bool get activa => estado == 0;

  String get etiquetaEstado => activa ? 'ACTIVA' : 'ANULADA';

  String get subtitulo {
    if (tipo == 'ACCESS') return 'ACCESS · $data';
    if (host.isEmpty) return tipo;
    return '$tipo · $host/$data';
  }

  Conexion copyWith({
    int? id,
    String? nombre,
    String? host,
    String? data,
    String? usuario,
    String? pass,
    String? tipo,
    String? imagen,
    int? estado,
  }) {
    return Conexion(
      id: id ?? this.id,
      nombre: nombre ?? this.nombre,
      host: host ?? this.host,
      data: data ?? this.data,
      usuario: usuario ?? this.usuario,
      pass: pass ?? this.pass,
      tipo: tipo ?? this.tipo,
      imagen: imagen ?? this.imagen,
      estado: estado ?? this.estado,
    );
  }

  factory Conexion.fromJson(Map<String, dynamic> j) {
    return Conexion(
      id: _entero(j['id']),
      nombre: '${j['nombre'] ?? ''}',
      host: '${j['host'] ?? ''}',
      data: '${j['data'] ?? ''}',
      usuario: '${j['usuario'] ?? ''}',
      pass: '${j['pass'] ?? ''}',
      tipo: '${j['tipo'] ?? ''}',
      imagen: '${j['imagen'] ?? ''}',
      estado: _entero(j['estado']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'nombre': nombre,
    'host': host,
    'data': data,
    'usuario': usuario,
    'pass': pass,
    'tipo': tipo,
    'imagen': imagen,
    'estado': estado,
  };

  static int _entero(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? 0;
  }

  static const List<String> tipos = <String>['MYSQL', 'SQL', 'ACCESS'];
}

class OrigenVoucher {
  final String codigo;
  final String nombre;

  const OrigenVoucher({required this.codigo, required this.nombre});

  String get etiqueta =>
      nombre.startsWith(codigo) ? nombre : '$codigo $nombre'.trim();

  factory OrigenVoucher.fromJson(Map<String, dynamic> json) {
    return OrigenVoucher(
      codigo: '${json['TOV'] ?? ''}'.trim(),
      nombre: '${json['ORIGEN'] ?? ''}'.trim(),
    );
  }
}
