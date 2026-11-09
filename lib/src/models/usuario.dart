import 'licencia.dart';

/// Usuario autenticado con la licencia de Siscont.
class Usuario {
  final String correo;
  final String usuario;
  final String celular;
  final String hash; // sha256(salt + contrasena)
  final String salt;
  final String creado;

  /// Fecha de vencimiento de la licencia en formato `AAAAMMDD`.
  final String vence;

  /// Llave de la licencia devuelta por el servicio.
  final String llave;

  const Usuario({
    required this.correo,
    required this.usuario,
    required this.celular,
    required this.hash,
    required this.salt,
    required this.creado,
    this.vence = '',
    this.llave = '',
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'correo': correo,
        'usuario': usuario,
        'celular': celular,
        'hash': hash,
        'salt': salt,
        'creado': creado,
        'vence': vence,
        'llave': llave,
      };

  factory Usuario.fromJson(Map<String, dynamic> j) => Usuario(
        correo: '${j['correo'] ?? ''}',
        usuario: '${j['usuario'] ?? ''}',
        celular: '${j['celular'] ?? ''}',
        hash: '${j['hash'] ?? ''}',
        salt: '${j['salt'] ?? ''}',
        creado: '${j['creado'] ?? ''}',
        vence: '${j['vence'] ?? ''}',
        llave: '${j['llave'] ?? ''}',
      );

  DateTime? get vencimientoLicencia => Licencia.fechaDesde(vence);

  /// La licencia sigue vigente mientras hoy no supere el dia de vencimiento.
  bool get licenciaVigente {
    final fecha = vencimientoLicencia;
    if (fecha == null) return false;
    final hoy = DateTime.now();
    return !DateTime(hoy.year, hoy.month, hoy.day).isAfter(fecha);
  }

  /// Fecha de vencimiento lista para mostrar: `dd/mm/aaaa`.
  String get vencimientoLicenciaTexto {
    final fecha = vencimientoLicencia;
    if (fecha == null) return vence;
    final dia = fecha.day.toString().padLeft(2, '0');
    final mes = fecha.month.toString().padLeft(2, '0');
    return '$dia/$mes/${fecha.year}';
  }

  String get iniciales {
    final base = usuario.trim().isNotEmpty ? usuario.trim() : correo.trim();
    if (base.isEmpty) return '?';
    final partes = base.split(RegExp(r'[\s._-]+')).where((p) => p.isNotEmpty);
    if (partes.length >= 2) {
      return (partes.first[0] + partes.elementAt(1)[0]).toUpperCase();
    }
    return base[0].toUpperCase();
  }
}
