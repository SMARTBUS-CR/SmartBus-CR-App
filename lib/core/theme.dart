import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Official branding palette — SmartBus Global.
/// Do not change these values without updating the visual identity guide.
class SmartBusColors {
  // Primary colors
  static const azulCorporativo = Color(0xFF0A2A88);
  static const azulPrincipal = Color(0xFF1565C0);
  static const verdeTurquesa = Color(0xFF00BFA5);
  static const verdeMenta = Color(0xFF3B8574);
  static const turquesaClaro = Color(0xFF00E5C3);
  static const blanco = Color(0xFFFFFFFF);
  static const grisOscuro = Color(0xFF1A1A1A);
  static const grisClaro = Color(0xFFF5F7FA);

  // Application states
  static const enCamino = verdeTurquesa;
  static const proximaLlegada = azulPrincipal;
  static const advertencia = Color(0xFFF59E0B);
  static const retraso = Color(0xFFF97316);
  static const error = Color(0xFFDC2626);
  static const completado = Color(0xFF16A34A);

  // Brand gradient: corporate blue -> primary blue -> turquoise.
  static const brandGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    stops: [0.0, 0.55, 1.0],
    colors: [azulCorporativo, azulPrincipal, verdeTurquesa],
  );

  // --- Backwards-compatible aliases (previous usage in the code) ---
  static const navy = azulCorporativo;
  static const teal = verdeTurquesa;
  static const bg = grisClaro;
  static const alert = advertencia;
  static const success = completado;
}

class SmartBusTheme {
  static ThemeData get light {
    final textTheme = GoogleFonts.interTextTheme().copyWith(
      displayLarge: GoogleFonts.poppins(fontWeight: FontWeight.w700),
      displayMedium: GoogleFonts.poppins(fontWeight: FontWeight.w700),
      displaySmall: GoogleFonts.poppins(fontWeight: FontWeight.w700),
      headlineLarge: GoogleFonts.poppins(fontWeight: FontWeight.w600),
      headlineMedium: GoogleFonts.poppins(fontWeight: FontWeight.w600),
      headlineSmall: GoogleFonts.poppins(fontWeight: FontWeight.w600),
      titleLarge: GoogleFonts.poppins(fontWeight: FontWeight.w600),
      titleMedium: GoogleFonts.poppins(fontWeight: FontWeight.w600),
      titleSmall: GoogleFonts.poppins(fontWeight: FontWeight.w600),
    ).apply(
      bodyColor: SmartBusColors.grisOscuro,
      displayColor: SmartBusColors.grisOscuro,
    );

    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: SmartBusColors.grisClaro,
      textTheme: textTheme,
      colorScheme: ColorScheme.fromSeed(
        seedColor: SmartBusColors.azulPrincipal,
        primary: SmartBusColors.azulPrincipal,
        secondary: SmartBusColors.verdeTurquesa,
        error: SmartBusColors.error,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: SmartBusColors.azulCorporativo,
        foregroundColor: SmartBusColors.blanco,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.poppins(
          color: SmartBusColors.blanco,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: SmartBusColors.azulPrincipal,
          foregroundColor: SmartBusColors.blanco,
          textStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      cardTheme: CardThemeData(
        color: SmartBusColors.grisClaro,
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: SmartBusColors.blanco,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}
