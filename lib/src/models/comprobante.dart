import 'dart:convert';

/// Tipo de dato de cada columna del formato de compras de SISCONT.
enum TipoCampo { texto, numero, fecha, entero, opcion }

/// Definicion de una de las 61 columnas del Excel de compras. Es la unica
/// fuente de verdad: sirve para el formulario, el JSON local y el Excel.
class DefColumna {
  final String clave;
  final String titulo; // encabezado exacto del Excel
  final TipoCampo tipo;
  final String inicial;
  final String seccion;
  final List<String> opciones;
  final String ayuda;

  const DefColumna(
    this.clave,
    this.titulo,
    this.seccion, {
    this.tipo = TipoCampo.texto,
    this.inicial = '',
    this.opciones = const <String>[],
    this.ayuda = '',
  });
}

/// Un comprobante de compra capturado en el telefono.
class Comprobante {
  static int _secuenciaIds = 0;

  String id;
  String archivo; // ruta absoluta del pdf/imagen en el telefono
  String nombreArchivo;
  String creado; // ISO8601
  String motor; // groq:modelo / manual
  String estadoWhatsapp;
  String estadoSiscont;
  Map<String, String> valores;

  Comprobante({
    required this.id,
    required this.archivo,
    required this.nombreArchivo,
    required this.creado,
    required this.motor,
    this.estadoWhatsapp = 'pendiente',
    this.estadoSiscont = 'pendiente',
    Map<String, String>? valores,
  }) : valores = valores ?? <String, String>{};

  String operator [](String clave) => valores[clave] ?? '';

  void operator []=(String clave, String valor) => valores[clave] = valor;

  double numero(String clave) {
    var s = (valores[clave] ?? '').trim();
    if (s.isEmpty) return 0;
    // Acepta "1,234.56" y "1234,56".
    if (s.contains(',') && s.contains('.')) {
      s = s.replaceAll(',', '');
    } else if (s.contains(',')) {
      s = s.replaceAll(',', '.');
    }
    return double.tryParse(s) ?? 0;
  }

  /// Igual que [numero] pero devuelve texto vacio cuando el valor es 0.
  String importe(String clave) {
    final n = numero(clave);
    return n == 0 ? '' : n.toStringAsFixed(2);
  }

  double get total =>
      numero('biogA') +
      numero('biogB') +
      numero('biogC') +
      numero('adNoGrav') +
      numero('isc') +
      numero('igvA') +
      numero('igvB') +
      numero('igvC') +
      numero('otrosTrib') +
      numero('impBolsa');

  DateTime? get fechaRegistro => DateTime.tryParse(creado);

  String get fechaRegistroTexto {
    final fecha = fechaRegistro;
    if (fecha == null) return '';
    return '${_dos(fecha.day)}/${_dos(fecha.month)}/${fecha.year}';
  }

  String get fechaRegistroIso {
    final fecha = fechaRegistro;
    if (fecha == null) return '';
    return '${fecha.year.toString().padLeft(4, '0')}-'
        '${_dos(fecha.month)}-${_dos(fecha.day)}';
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'archivo': archivo,
    'nombreArchivo': nombreArchivo,
    'creado': creado,
    'motor': motor,
    'estadoWhatsapp': estadoWhatsapp,
    'estadoSiscont': estadoSiscont,
    'valores': valores,
  };

  factory Comprobante.fromJson(Map<String, dynamic> j) => Comprobante(
    id: '${j['id'] ?? ''}',
    archivo: '${j['archivo'] ?? ''}',
    nombreArchivo: '${j['nombreArchivo'] ?? ''}',
    creado: '${j['creado'] ?? ''}',
    motor: '${j['motor'] ?? ''}',
    estadoWhatsapp: _estado(j['estadoWhatsapp']),
    estadoSiscont: _estado(j['estadoSiscont']),
    valores:
        (j['valores'] as Map?)?.map(
          (k, v) => MapEntry('$k', v == null ? '' : '$v'),
        ) ??
        <String, String>{},
  );

  /// Crea un comprobante vacio con los valores por defecto del formato.
  static Comprobante vacio({String id = '', String archivo = ''}) {
    final idComprobante = id.isEmpty ? nuevoId() : id;
    final c = Comprobante(
      id: idComprobante,
      archivo: archivo,
      nombreArchivo: archivo.split(RegExp(r'[\\/]')).last,
      creado: DateTime.now().toIso8601String(),
      motor: 'manual',
    );
    for (final d in columnas) {
      c.valores[d.clave] = d.inicial;
    }
    c.valores['vouFecha'] = fechaHoy();
    c.valores['fecDoc'] = fechaHoy();
    return c;
  }

  static String nuevoId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${_secuenciaIds++}';

  static String _estado(dynamic valor) =>
      valor == 'enviado' ? 'enviado' : 'pendiente';

  static String fechaHoy() {
    final n = DateTime.now();
    return '${_dos(n.day)}/${_dos(n.month)}/${n.year}';
  }

  static String _dos(int v) => v.toString().padLeft(2, '0');

  /// Texto corto para la lista de la pantalla principal.
  String get resumen {
    final rs = this['rSocial'];
    final num = this['numero'];
    if (rs.isNotEmpty && num.isNotEmpty) return '$rs - $num';
    if (rs.isNotEmpty) return rs;
    if (num.isNotEmpty) return num;
    return nombreArchivo;
  }
}

/// Las 61 columnas del Excel de compras SISCONT, en el orden exacto.
const List<DefColumna> columnas = <DefColumna>[
  DefColumna('vouOrigen', 'Vou.Origen', 'Voucher', inicial: '01'),
  DefColumna('vouNumero', 'Vou.Numero', 'Voucher'),
  DefColumna('vouFecha', 'Vou.Fecha', 'Voucher', tipo: TipoCampo.fecha),
  DefColumna(
    'doc',
    'Doc',
    'Documento',
    inicial: '01',
    tipo: TipoCampo.opcion,
    opciones: <String>['00', '01', '02', '03', '04', '05', '07', '08'],
    ayuda: '00 Otros, 01 Factura, 02 Boleta, 07 Retención',
  ),
  DefColumna('numero', 'Numero', 'Documento', ayuda: 'F001-00000123'),
  DefColumna('fecDoc', 'Fec.Doc', 'Documento', tipo: TipoCampo.fecha),
  DefColumna('fecVenc', 'Fec.Venc.', 'Documento', tipo: TipoCampo.fecha),
  DefColumna('codigo', 'Codigo', 'Documento', ayuda: 'RUC del proveedor'),
  DefColumna(
    'biogA',
    'B.I.O.G y E. (A)',
    'Importes',
    tipo: TipoCampo.numero,
    inicial: '0',
  ),
  DefColumna(
    'biogB',
    'B.I.O.G.y E. y NO GRA. (B)',
    'Importes',
    tipo: TipoCampo.numero,
    inicial: '0',
  ),
  DefColumna(
    'biogC',
    'B.I.O.G.sin D.C.FIS(C)',
    'Importes',
    tipo: TipoCampo.numero,
    inicial: '0',
  ),
  DefColumna(
    'adNoGrav',
    'AD. NO GRAV.',
    'Importes',
    tipo: TipoCampo.numero,
    inicial: '0',
  ),
  DefColumna('isc', 'I.S.C.', 'Importes', tipo: TipoCampo.numero, inicial: '0'),
  DefColumna(
    'igvA',
    'IGV (A)',
    'Importes',
    tipo: TipoCampo.numero,
    inicial: '0',
  ),
  DefColumna(
    'igvB',
    'IGV (B)',
    'Importes',
    tipo: TipoCampo.numero,
    inicial: '0',
  ),
  DefColumna(
    'igvC',
    'IGV (C)',
    'Importes',
    tipo: TipoCampo.numero,
    inicial: '0',
  ),
  DefColumna(
    'otrosTrib',
    'OTROS TRIB.',
    'Importes',
    tipo: TipoCampo.numero,
    inicial: '0',
  ),
  DefColumna(
    'impBolsa',
    'IMP. BOLSA',
    'Importes',
    tipo: TipoCampo.numero,
    inicial: '0',
  ),
  DefColumna(
    'moneda',
    'Moneda',
    'Importes',
    inicial: 'S',
    tipo: TipoCampo.opcion,
    opciones: <String>['S', 'D'],
  ),
  DefColumna('tc', 'TC', 'Importes', tipo: TipoCampo.numero, inicial: '1.000'),
  DefColumna('glosa', 'Glosa', 'Documento'),
  DefColumna('ctaGastos', 'Cta Gastos', 'Cuentas', inicial: '656'),
  DefColumna('ctaIgv', 'Cta IGV', 'Cuentas', inicial: '40002'),
  DefColumna('ctaOTrib', 'Cta O. Trib.', 'Cuentas'),
  DefColumna('ctaXPagar', 'Cta x Pagar', 'Cuentas', inicial: '42121'),
  DefColumna('ccosto', 'C.Costo', 'Cuentas', inicial: '000'),
  DefColumna('presupuesto', 'Presupuesto', 'Cuentas', inicial: '000'),
  DefColumna('rDoc', 'R.Doc', 'Referencias'),
  DefColumna('rNumero', 'R.numero', 'Referencias'),
  DefColumna('rFecha', 'R.Fecha', 'Referencias', tipo: TipoCampo.fecha),
  DefColumna('dNumero', 'D.Numero', 'Referencias'),
  DefColumna('dFecha', 'D.Fecha', 'Referencias', tipo: TipoCampo.fecha),
  DefColumna('ruc', 'RUC', 'Proveedor'),
  DefColumna('rSocial', 'R.Social', 'Proveedor'),
  DefColumna('tipo', 'Tipo', 'Proveedor'),
  DefColumna(
    'tipDocIden',
    'Tip.Doc.Iden',
    'Proveedor',
    inicial: '6',
    tipo: TipoCampo.opcion,
    opciones: <String>['1', '4', '6', '7', '0'],
  ),
  DefColumna('medioPago', 'Medio de Pago', 'Proveedor'),
  DefColumna('apellido1', 'Apellido 1', 'Proveedor'),
  DefColumna('apellido2', 'Apellido 2', 'Proveedor'),
  DefColumna('nombre', 'Nombre', 'Proveedor'),
  DefColumna(
    'tBien',
    'T.Bien',
    'Proveedor',
    inicial: '1',
    tipo: TipoCampo.opcion,
    opciones: <String>['1', '2', '3'],
  ),
  DefColumna('pOrigen', 'P.origen', 'Pagarés'),
  DefColumna('pVou', 'P.vou', 'Pagarés'),
  DefColumna('pFecha', 'P.fecha', 'Pagarés', tipo: TipoCampo.fecha),
  DefColumna('pFechaD', 'P.fecha D.', 'Pagarés', tipo: TipoCampo.fecha),
  DefColumna('pFechaV', 'P.fecha V.', 'Pagarés', tipo: TipoCampo.fecha),
  DefColumna('pCtaCob', 'P.cta cob', 'Pagarés'),
  DefColumna('pMPago', 'P.m.pago', 'Pagarés'),
  DefColumna('pDoc', 'P.doc', 'Pagarés'),
  DefColumna('pNumDoc', 'P.num doc', 'Pagarés'),
  DefColumna('pMoneda', 'P.moneda', 'Pagarés'),
  DefColumna(
    'pTc',
    'P.tc',
    'Pagarés',
    tipo: TipoCampo.numero,
    inicial: '1.000',
  ),
  DefColumna(
    'pMonto',
    'P.monto',
    'Pagarés',
    tipo: TipoCampo.numero,
    inicial: '0',
  ),
  DefColumna('pGlosa', 'P.glosa', 'Pagarés'),
  DefColumna('pFe', 'P.fe', 'Pagarés', tipo: TipoCampo.fecha),
  DefColumna(
    'retencion',
    'Retencion 0/1',
    'Retencion',
    inicial: '0',
    tipo: TipoCampo.opcion,
    opciones: <String>['0', '1'],
  ),
  DefColumna('pdbNdes', 'PDB ndes', 'Retencion'),
  DefColumna('codTasa', 'CodTasa', 'Retencion'),
  DefColumna('indRet', 'Ind.Ret', 'Retencion'),
  DefColumna(
    'bImp',
    'B.Imp',
    'Retencion',
    tipo: TipoCampo.numero,
    inicial: '0',
  ),
  DefColumna('igv', 'IGV', 'Retencion'),
];

DefColumna? defColumna(String clave) {
  for (final d in columnas) {
    if (d.clave == clave) return d;
  }
  return null;
}

/// Secciones en el orden en que se muestran en el formulario.
const List<String> secciones = <String>[
  'Documento',
  'Importes',
  'Proveedor',
  'Cuentas',
  'Voucher',
  'Referencias',
  'Pagarés',
  'Retencion',
];

String comprobantesAJson(List<Comprobante> items) =>
    jsonEncode(items.map((c) => c.toJson()).toList());

List<Comprobante> comprobantesDesdeJson(String fuente) {
  if (fuente.trim().isEmpty) return <Comprobante>[];
  final data = jsonDecode(fuente);
  if (data is! List) return <Comprobante>[];
  return data
      .whereType<Map>()
      .map((m) => Comprobante.fromJson(m.cast<String, dynamic>()))
      .toList();
}
