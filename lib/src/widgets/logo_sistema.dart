import 'package:flutter/material.dart';

class LogoSistema extends StatelessWidget {
  final double width;
  final double height;
  final bool fondoBlanco;

  const LogoSistema({
    super.key,
    required this.width,
    required this.height,
    this.fondoBlanco = false,
  });

  @override
  Widget build(BuildContext context) {
    final imagen = Image.asset(
      'assets/images/logomas.png',
      width: width,
      height: height,
      fit: BoxFit.contain,
      semanticLabel: 'Brújula Financiera Software',
    );
    if (!fondoBlanco) return imagen;
    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
      ),
      child: imagen,
    );
  }
}
