class OrigenesCaja {
  final String gasto;

  const OrigenesCaja({this.gasto = '01'});

  Map<String, dynamic> toJson() => <String, dynamic>{
    'gasto': gasto,
  };

  factory OrigenesCaja.fromJson(Map<String, dynamic> json) => OrigenesCaja(
    gasto: '${json['gasto'] ?? '01'}',
  );
}
