class CajaSesion {
  final String id;
  final String moneda;
  final double montoApertura;
  final DateTime fechaApertura;
  final double? montoCierre;
  final DateTime? fechaCierre;
  final int? voucher;

  const CajaSesion({
    required this.id,
    required this.moneda,
    required this.montoApertura,
    required this.fechaApertura,
    this.montoCierre,
    this.fechaCierre,
    this.voucher,
  });

  bool get estaAbierta => fechaCierre == null;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'moneda': moneda,
    'montoApertura': montoApertura,
    'fechaApertura': fechaApertura.toIso8601String(),
    'montoCierre': montoCierre,
    'fechaCierre': fechaCierre?.toIso8601String(),
    'voucher': voucher,
  };

  factory CajaSesion.fromJson(Map<String, dynamic> json) => CajaSesion(
    id: '${json['id'] ?? ''}',
    moneda: '${json['moneda'] ?? 'PEN'}',
    montoApertura: double.parse('${json['montoApertura'] ?? 0}'),
    fechaApertura: DateTime.parse('${json['fechaApertura']}'),
    montoCierre: json['montoCierre'] == null
        ? null
        : double.parse('${json['montoCierre']}'),
    fechaCierre: json['fechaCierre'] == null
        ? null
        : DateTime.parse('${json['fechaCierre']}'),
    voucher: json['voucher'] == null ? null : int.parse('${json['voucher']}'),
  );

  CajaSesion cerrar({
    required DateTime fecha,
    required double monto,
    required int voucher,
  }) => CajaSesion(
    id: id,
    moneda: moneda,
    montoApertura: montoApertura,
    fechaApertura: fechaApertura,
    montoCierre: monto,
    fechaCierre: fecha,
    voucher: voucher,
  );

  CajaSesion actualizarMontoCierre(double monto) => CajaSesion(
    id: id,
    moneda: moneda,
    montoApertura: montoApertura,
    fechaApertura: fechaApertura,
    montoCierre: monto,
    fechaCierre: fechaCierre,
    voucher: voucher,
  );

  static String nuevoId() => '${DateTime.now().microsecondsSinceEpoch}';
}
