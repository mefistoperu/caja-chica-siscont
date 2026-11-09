/// Licencia devuelta por el servicio de llaves de Nubesiscont.
///
/// El servicio responde un JSON como:
/// `{"fechah":"20260103","llave":"220d-00291","empresa":"FREDDY ZAVALA"}`
/// donde [fechah] es la fecha de vencimiento en formato `AAAAMMDD`.
class Licencia {
  final String fechah;
  final String llave;
  final String empresa;

  const Licencia({
    required this.fechah,
    required this.llave,
    required this.empresa,
  });

  factory Licencia.fromJson(Map<String, dynamic> j) => Licencia(
        fechah: '${j['fechah'] ?? ''}'.trim(),
        llave: '${j['llave'] ?? ''}'.trim(),
        empresa: '${j['empresa'] ?? ''}'.trim(),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'fechah': fechah,
        'llave': llave,
        'empresa': empresa,
      };

  /// Indica si el servicio reconocio las credenciales (empresa y llave).
  bool get tieneLicencia => llave.isNotEmpty && empresa.isNotEmpty;

  /// Fecha de vencimiento; null si [fechah] no es una fecha valida.
  DateTime? get vencimiento => fechaDesde(fechah);

  /// Vigente mientras hoy no supere el dia de vencimiento (inclusive).
  bool get vigente {
    final fecha = vencimiento;
    if (fecha == null) return false;
    final hoy = DateTime.now();
    return !DateTime(hoy.year, hoy.month, hoy.day).isAfter(fecha);
  }

  /// Fecha de vencimiento lista para mostrar: `dd/mm/aaaa`.
  String get vencimientoTexto {
    final fecha = vencimiento;
    if (fecha == null) return fechah;
    return '${_dos(fecha.day)}/${_dos(fecha.month)}/${fecha.year}';
  }

  /// Convierte `AAAAMMDD` (o cualquier texto con 8 digitos) en fecha.
  static DateTime? fechaDesde(String valor) {
    final digitos = valor.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitos.length != 8) return null;
    final anio = int.tryParse(digitos.substring(0, 4));
    final mes = int.tryParse(digitos.substring(4, 6));
    final dia = int.tryParse(digitos.substring(6, 8));
    if (anio == null || mes == null || dia == null) return null;
    if (mes < 1 || mes > 12 || dia < 1 || dia > 31) return null;
    final fecha = DateTime(anio, mes, dia);
    if (fecha.year != anio || fecha.month != mes || fecha.day != dia) {
      return null;
    }
    return fecha;
  }

  static String _dos(int n) => n.toString().padLeft(2, '0');
}
