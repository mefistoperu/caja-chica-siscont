class ConceptoGasto {
  final String codigo;
  final String nombre;

  const ConceptoGasto({required this.codigo, required this.nombre});

  Map<String, dynamic> toJson() => <String, dynamic>{
    'codigo': codigo,
    'nombre': nombre,
  };

  factory ConceptoGasto.fromJson(Map<String, dynamic> json) => ConceptoGasto(
    codigo: '${json['codigo'] ?? ''}'.trim(),
    nombre: '${json['nombre'] ?? ''}'.trim(),
  );
}
