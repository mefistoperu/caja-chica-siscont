class TipoMovimientoCaja {
  final String id;
  final String nombre;
  final String cuentaIngreso;
  final String cuentaGasto;

  const TipoMovimientoCaja({
    required this.id,
    required this.nombre,
    required this.cuentaIngreso,
    required this.cuentaGasto,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'nombre': nombre,
    'cuentaIngreso': cuentaIngreso,
    'cuentaGasto': cuentaGasto,
  };

  factory TipoMovimientoCaja.fromJson(Map<String, dynamic> json) =>
      TipoMovimientoCaja(
        id: '${json['id'] ?? ''}',
        nombre: '${json['nombre'] ?? ''}',
        cuentaIngreso: '${json['cuentaIngreso'] ?? ''}',
        cuentaGasto: '${json['cuentaGasto'] ?? ''}',
      );

  static String nuevoId() => '${DateTime.now().microsecondsSinceEpoch}';
}
