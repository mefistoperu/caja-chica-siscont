import 'package:flutter/material.dart';

import '../theme/tema.dart';

/// Campo de texto con etiqueta arriba, usado en login, registro y formularios.
class EntradaTexto extends StatelessWidget {
  final String etiqueta;
  final TextEditingController controlador;
  final String? ayuda;
  final bool oscuro;
  final bool contrasena;
  final TextInputType teclado;
  final int? maxLongitud;
  final Widget? sufijo;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onTap;

  const EntradaTexto({
    super.key,
    required this.etiqueta,
    required this.controlador,
    this.ayuda,
    this.oscuro = false,
    this.contrasena = false,
    this.teclado = TextInputType.text,
    this.maxLongitud,
    this.sufijo,
    this.onChanged,
    this.onSubmitted,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          etiqueta,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: oscuro ? Colors.white70 : Paleta.etiqueta,
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: controlador,
          obscureText: contrasena,
          keyboardType: teclado,
          maxLength: maxLongitud,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          onTap: onTap,
          textCapitalization: teclado == TextInputType.text
              ? TextCapitalization.sentences
              : TextCapitalization.none,
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            isDense: true,
            counterText: '',
            hintText: ayuda,
            suffixIcon: sufijo,
            filled: true,
            fillColor: oscuro ? Colors.white : const Color(0xFFF9FBFC),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 15,
            ),
            border: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: const BorderRadius.all(Radius.circular(12)),
              borderSide: BorderSide(
                color: oscuro ? Colors.white24 : Paleta.controlBorde,
              ),
            ),
            focusedBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
              borderSide: BorderSide(color: Paleta.controlFoco, width: 1.8),
            ),
          ),
        ),
        const SizedBox(height: 10),
      ],
    );
  }
}

/// Boton grande con icono, para las acciones de la pantalla principal.
class BotonAccion extends StatelessWidget {
  final String texto;
  final String ayuda;
  final IconData icono;
  final VoidCallback? onTap;
  final Color color;

  const BotonAccion({
    super.key,
    required this.texto,
    required this.ayuda,
    required this.icono,
    required this.onTap,
    this.color = Paleta.panel,
  });

  @override
  Widget build(BuildContext context) {
    final habilitado = onTap != null;
    final fondo = habilitado ? color : color.withValues(alpha: 0.45);
    return LayoutBuilder(
      builder: (context, constraints) {
        final mostrarAyuda = constraints.maxWidth >= 150;
        return Material(
          color: Colors.transparent,
          elevation: habilitado ? 3 : 0,
          shadowColor: color.withValues(alpha: 0.28),
          borderRadius: BorderRadius.circular(14),
          child: Ink(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[
                  Color.lerp(fondo, Colors.white, 0.12)!,
                  Color.lerp(fondo, Colors.black, 0.12)!,
                ],
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.32)),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: onTap,
              child: Stack(
                children: <Widget>[
                  Positioned(
                    top: -34,
                    right: -24,
                    child: Container(
                      width: 108,
                      height: 108,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.07),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 14,
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withValues(alpha: 0.18),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.32),
                              ),
                            ),
                            child: Icon(icono, color: Colors.white, size: 25),
                          ),
                          const SizedBox(height: 9),
                          Text(
                            texto,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (mostrarAyuda) ...<Widget>[
                            const SizedBox(height: 3),
                            Text(
                              ayuda,
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.86),
                                fontSize: 10.5,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Tarjeta blanca con titulo opcional.
class Tarjeta extends StatelessWidget {
  final String? titulo;
  final IconData? icono;
  final Widget hijo;
  final EdgeInsets padding;

  const Tarjeta({
    super.key,
    this.titulo,
    this.icono,
    required this.hijo,
    this.padding = const EdgeInsets.all(12),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Paleta.navbarBorde),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (titulo != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: const BoxDecoration(
                color: Paleta.panel,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(7),
                  topRight: Radius.circular(7),
                ),
              ),
              child: Row(
                children: <Widget>[
                  if (icono != null) ...<Widget>[
                    Icon(icono, size: 16, color: Colors.white),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    titulo!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
          Padding(padding: padding, child: hijo),
        ],
      ),
    );
  }
}
