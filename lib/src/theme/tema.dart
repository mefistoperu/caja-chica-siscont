import 'package:flutter/material.dart';

/// Colores, tipografias y medidas tomados de `assets/css/theme.css?v=6` y del
/// `<style>` inline de `app/Views/pages/voucher.php`, para que la app se vea
/// igual que la seccion `/voucher` del sistema original.
class Paleta {
  const Paleta._();

  // Navegacion (AdminLTE .navbar-white / .main-header)
  static const Color navbar = Color(0xFFFFFFFF);
  static const Color navbarBorde = Color(0xFFDEE2E6);
  static const Color navLink = Color(0x80000000); // rgba(0,0,0,.5)
  static const Color navLinkHover = Color(0xB3000000); // rgba(0,0,0,.7)
  static const Color navLinkActivo = Color(0xE6000000); // rgba(0,0,0,.9)

  // Fondo del contenido (.content-wrapper)
  static const Color contenido = Color(0xFFF4F6F9);
  static const Color footer = Color(0xFFFFFFFF);
  static const Color footerTexto = Color(0xFF869099);

  // Panel principal (.modal-voucher .modal-content)
  static const Color panel = Color(0xFF5CBDB9);
  static const Color panelModal = Color(0xFF4EC5BE); // .modal-datos-voucher
  static const Color bordeOscuro = Color(0xFF333333);
  static const Color sombraModal = Color(0x80000000);
  static const Color barraTitulo = Color(0xFFF0F0F0);
  static const Color bordeBarra = Color(0xFF999999);

  // Etiquetas del modal de datos
  static const Color etiqueta = Color(0xFF003366); // .label-voucher

  // Controles (.form-control-custom)
  static const Color controlBorde = Color(0xFFD4DEE7);
  static const Color controlFoco = Color(0xFF328F8C);
  static const Color origenFondo = Color(0xFF0D6EFD);
  static const Color origenBorde = Color(0xFF0A58CA);

  // Tabla (.voucher-table)
  static const Color tablaCabecera = Color(0xFF9BD3D0);
  static const Color tablaBorde = Color(0xFFCCCCCC);
  static const Color tablaBordeFuerte = Color(0xFF666666);
  static const Color tablaHover = Color(0xFFF0F8F7);
  static const Color filaSeleccionada = Color(0xFF0D6EFD);
  static const Color texto = Color(0xFF000000);

  // Totales (.totals-input)
  static const Color totalesFondo = Color(0xFFE9ECEF);

  // Botones
  static const Color btnFondo = Color(0xFFD1D5DB); // .btn-custom
  static const Color btnPie = Color(0xFFF0F0F0); // .btn-voucher-footer
  static const Color btnPieHover = Color(0xFFDCDCDC);
  static const Color btnPieActive = Color(0xFFC8C8C8);
  static const Color btnIcono = Color(0xFFE0E0E0); // .btn-icon-voucher
  static const Color btnIconoHover = Color(0xFFD0D0D0);
  static const Color exito = Color(0xFF28A745); // .btn-success
  static const Color peligro = Color(0xFFDC3545); // .text-danger

  // Linea divisoria del modal
  static const Color divisor = Color(0x80FFFFFF); // rgba(255,255,255,.5)
  static const Color separadorColumna = Color(
    0x66FFFFFF,
  ); // rgba(255,255,255,.4)
}

/// Medidas exactas del CSS (1rem = 16px en el original).
class Medidas {
  const Medidas._();

  static const double navAlto = 56; // 3.5rem
  static const double logoAlto = 40;
  static const double logoAncho =
      204; // 271x53 a 40px de alto, como el original
  static const double controlAlto = 24; // .form-control-custom
  static const double controlFuente = 12; // 0.75rem
  static const double tablaFuente = 11.5; // 0.72rem
  static const double tablaFilaAlto = 18;
  static const double etiquetaFuente = 12; // 0.75rem
  static const double modalEtiquetaFuente = 13.1; // 0.82rem
  static const double tituloFuente = 14.4; // 0.9rem
  static const double totalesFuente = 12.8; // 0.8rem
  static const double tablaScrollAlto = 400; // 35vh / max-height
  static const double tablaScrollMin = 150; // min-height

  /// `.tabla-scroll-container { height:35vh; max-height:400px; min-height:150px }`
  /// Resuelto contra el viewport para que en un celular la tabla no se coma
  /// media pantalla.
  static double tablaAlto(BuildContext context) {
    return (MediaQuery.sizeOf(context).height * 0.35).clamp(
      tablaScrollMin,
      tablaScrollAlto,
    );
  }
}

/// Familia tipografica del original ("Source Sans Pro" cae a Segoe UI).
const String familiaFuente = 'Segoe UI';

ThemeData temaEfsiscont() {
  const esquema = ColorScheme.light(
    primary: Paleta.controlFoco,
    secondary: Paleta.panel,
    surface: Colors.white,
    error: Paleta.peligro,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: esquema,
    fontFamily: familiaFuente,
    scaffoldBackgroundColor: Paleta.contenido,
    appBarTheme: const AppBarTheme(
      backgroundColor: Paleta.navbar,
      foregroundColor: Paleta.texto,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    dividerColor: Paleta.tablaBorde,
    inputDecorationTheme: const InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: Color(0xFFF9FBFC),
      contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      floatingLabelStyle: TextStyle(
        color: Paleta.controlFoco,
        fontWeight: FontWeight.w600,
      ),
      hintStyle: TextStyle(color: Paleta.footerTexto),
      prefixIconColor: Paleta.footerTexto,
      suffixIconColor: Paleta.footerTexto,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: Paleta.controlBorde, width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: Paleta.controlBorde, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: Paleta.controlFoco, width: 1.8),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: Paleta.peligro, width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: Paleta.peligro, width: 1.8),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Paleta.exito,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Paleta.etiqueta,
        side: const BorderSide(color: Paleta.controlBorde),
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: Paleta.controlFoco,
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)),
        ),
      ),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(18)),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
    ),
  );
}

/// `.form-label-custom`: 0.75rem bold negro, sin margen inferior.
const TextStyle estiloEtiqueta = TextStyle(
  fontSize: Medidas.etiquetaFuente,
  fontWeight: FontWeight.bold,
  color: Paleta.texto,
);

/// `.label-voucher` del modal de datos: 0.82rem bold azul marino.
const TextStyle estiloEtiquetaModal = TextStyle(
  fontSize: Medidas.modalEtiquetaFuente,
  fontWeight: FontWeight.bold,
  color: Paleta.etiqueta,
);

/// `.totals-label`
const TextStyle estiloTotalesEtiqueta = TextStyle(
  fontSize: Medidas.totalesFuente,
  color: Paleta.texto,
);

/// `.btn-custom`: gris claro, borde oscuro y sombra "Windows clasico".
class BtnClasico extends StatelessWidget {
  const BtnClasico({
    super.key,
    required this.texto,
    this.icono,
    this.colorIcono,
    this.onPressed,
    this.ancho,
  });

  final String texto;
  final IconData? icono;
  final Color? colorIcono;
  final VoidCallback? onPressed;
  final double? ancho;

  @override
  Widget build(BuildContext context) {
    final contenido = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icono != null) ...[
          Icon(icono, size: 13, color: colorIcono ?? Paleta.bordeOscuro),
          const SizedBox(width: 5),
        ],
        Flexible(
          child: Text(
            texto,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: Medidas.totalesFuente,
              color: Paleta.bordeOscuro,
            ),
          ),
        ),
      ],
    );

    return Container(
      width: ancho,
      decoration: BoxDecoration(
        color: onPressed == null
            ? Paleta.btnFondo.withValues(alpha: 0.5)
            : Paleta.btnFondo,
        border: Border.all(color: Paleta.bordeOscuro),
        boxShadow: const [
          BoxShadow(
            color: Color(0x4D000000),
            offset: Offset(2, 2),
            blurRadius: 4,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          hoverColor: Colors.black12,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: DefaultTextStyle(
              style: const TextStyle(fontSize: Medidas.totalesFuente),
              child: IconTheme(
                data: IconThemeData(
                  size: 13,
                  color: colorIcono ?? Paleta.bordeOscuro,
                ),
                child: contenido,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// `.btn-icon-voucher`: 24px, gris, borde 1px #666.
class BtnIconoVoucher extends StatelessWidget {
  const BtnIconoVoucher({
    super.key,
    required this.onPressed,
    this.icono,
    this.texto,
    this.tooltip,
  });

  final VoidCallback? onPressed;
  final IconData? icono;
  final String? texto;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? '',
      child: Container(
        height: Medidas.controlAlto,
        constraints: const BoxConstraints(minWidth: 28),
        decoration: BoxDecoration(
          color: onPressed == null
              ? Paleta.btnIcono.withValues(alpha: 0.5)
              : Paleta.btnIcono,
          border: Border.all(color: Paleta.tablaBordeFuerte),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            hoverColor: Paleta.btnIconoHover,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icono != null)
                    Icon(icono, size: 12, color: Paleta.bordeOscuro),
                  if (icono != null && texto != null) const SizedBox(width: 4),
                  if (texto != null)
                    Text(
                      texto!,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Paleta.bordeOscuro,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
