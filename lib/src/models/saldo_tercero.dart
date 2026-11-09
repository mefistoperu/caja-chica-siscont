class SaldoTercero {
  final String rut;
  final String razonSocial;
  final double debe;
  final double haber;
  final double saldo;

  const SaldoTercero({
    required this.rut,
    required this.razonSocial,
    required this.debe,
    required this.haber,
    required this.saldo,
  });

  factory SaldoTercero.fromJson(Map<String, dynamic> json) {
    return SaldoTercero(
      rut: '${json['rut'] ?? ''}'.trim(),
      razonSocial: '${json['razon_social'] ?? ''}'.trim(),
      debe: _numero(json['debe']),
      haber: _numero(json['haber']),
      saldo: _numero(json['saldo']),
    );
  }

  static double _numero(dynamic valor) {
    if (valor is num) return valor.toDouble();
    return double.tryParse('$valor') ?? 0;
  }
}
