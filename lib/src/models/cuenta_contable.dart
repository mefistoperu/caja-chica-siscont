class CuentaContable {
  final String codigo;
  final String nombre;

  const CuentaContable({required this.codigo, required this.nombre});

  Map<String, dynamic> toJson() => <String, dynamic>{
    'codigo': codigo,
    'nombre': nombre,
  };

  factory CuentaContable.fromJson(Map<String, dynamic> json) => CuentaContable(
    codigo: '${json['codigo'] ?? ''}'.trim(),
    nombre: '${json['nombre'] ?? ''}'.trim(),
  );
}
