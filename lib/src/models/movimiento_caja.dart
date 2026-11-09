class MovimientoCaja {
  final String id;
  final String cajaId;
  final String moneda;
  final String tipo;
  final String tipoMovimientoId;
  final String tipoMovimiento;
  final String cuentaContable;
  final String comprobanteId;
  final String terceroId;
  final String terceroNombre;
  final String terceroTipoDocumento;
  final String terceroDocumento;
  final String concepto;
  final double monto;
  final DateTime fecha;

  const MovimientoCaja({
    required this.id,
    this.cajaId = '',
    required this.moneda,
    this.tipo = 'ingreso',
    this.tipoMovimientoId = '',
    this.tipoMovimiento = '',
    this.cuentaContable = '',
    this.comprobanteId = '',
    this.terceroId = '',
    this.terceroNombre = '',
    this.terceroTipoDocumento = '',
    this.terceroDocumento = '',
    required this.concepto,
    required this.monto,
    required this.fecha,
  });

  bool get esIngreso => tipo == 'ingreso';

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'cajaId': cajaId,
    'moneda': moneda,
    'tipo': tipo,
    'tipoMovimientoId': tipoMovimientoId,
    'tipoMovimiento': tipoMovimiento,
    'cuentaContable': cuentaContable,
    'comprobanteId': comprobanteId,
    'terceroId': terceroId,
    'terceroNombre': terceroNombre,
    'terceroTipoDocumento': terceroTipoDocumento,
    'terceroDocumento': terceroDocumento,
    'concepto': concepto,
    'monto': monto,
    'fecha':
        '${fecha.year.toString().padLeft(4, '0')}-'
        '${fecha.month.toString().padLeft(2, '0')}-'
        '${fecha.day.toString().padLeft(2, '0')}',
  };

  factory MovimientoCaja.fromJson(Map<String, dynamic> json) => MovimientoCaja(
    id: '${json['id'] ?? ''}',
    cajaId: '${json['cajaId'] ?? ''}',
    moneda: '${json['moneda'] ?? 'PEN'}',
    tipo: json['tipo'] == 'gasto' ? 'gasto' : 'ingreso',
    tipoMovimientoId: '${json['tipoMovimientoId'] ?? ''}',
    tipoMovimiento: '${json['tipoMovimiento'] ?? ''}',
    cuentaContable: '${json['cuentaContable'] ?? ''}',
    comprobanteId: '${json['comprobanteId'] ?? ''}',
    terceroId: '${json['terceroId'] ?? ''}',
    terceroNombre: '${json['terceroNombre'] ?? ''}',
    terceroTipoDocumento: '${json['terceroTipoDocumento'] ?? ''}',
    terceroDocumento: '${json['terceroDocumento'] ?? ''}',
    concepto: '${json['concepto'] ?? ''}',
    monto: double.parse('${json['monto'] ?? 0}'),
    fecha: DateTime.parse('${json['fecha']}'),
  );

  static String nuevoId() => '${DateTime.now().microsecondsSinceEpoch}';
}
