class CentroCosto {
  final String codigo;
  final String nombre;

  const CentroCosto({required this.codigo, required this.nombre});

  factory CentroCosto.fromJson(Map<String, dynamic> json) => CentroCosto(
    codigo: '${json['CODIGO'] ?? json['codigo'] ?? ''}'.trim(),
    nombre: '${json['NOM'] ?? json['nom'] ?? json['nombre'] ?? ''}'.trim(),
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'codigo': codigo,
    'nombre': nombre,
  };
}
