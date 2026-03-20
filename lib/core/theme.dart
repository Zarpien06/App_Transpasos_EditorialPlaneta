import 'package:flutter/material.dart';

// ─────────────────────────────────────────────
//  GRUPO PLANETA — Paleta monocromática oscura
//  Base: negro/carbón | Texto: blanco
//  Acento: azul corporativo (solo puntual)
// ─────────────────────────────────────────────

class PlanetaColors {
  PlanetaColors._();

  // ── Negros / Grises ───────────────────────
  static const Color black    = Color(0xFF0A0A0A);
  static const Color carbon   = Color(0xFF111111);
  static const Color charcoal = Color(0xFF1A1A1A);
  static const Color graphite = Color(0xFF242424);
  static const Color slate    = Color(0xFF333333);
  static const Color ash      = Color(0xFF555555);
  static const Color silver   = Color(0xFF888888);
  static const Color fog      = Color(0xFFBBBBBB);
  static const Color white    = Color(0xFFFFFFFF);

  // ── Azul corporativo (acento) ─────────────
  static const Color accent      = Color(0xFF1565C0);
  static const Color accentLight = Color(0xFF29B6F6);
  static const Color accentDark  = Color(0xFF0D3E7A);

  // ── Estado ────────────────────────────────
  static const Color success = Color(0xFF43A047);
  static const Color warning = Color(0xFFFFA726);
  static const Color error   = Color(0xFFCF6679);

  // ── Gradientes (usar directamente en widgets) ──
  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topLeft,
    end:   Alignment.bottomRight,
    colors: [Color(0xFF0A0A0A), Color(0xFF111111), Color(0xFF0A0A0A)],
  );

  static const LinearGradient buttonGradient = LinearGradient(
    begin: Alignment.topLeft,
    end:   Alignment.bottomRight,
    colors: [Color(0xFF1565C0), Color(0xFF0D3E7A)],
  );

  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topCenter,
    end:   Alignment.bottomCenter,
    colors: [Color(0xFF111111), Color(0xFF0A0A0A)],
  );
}

// ─────────────────────────────────────────────
//  TEMA PRINCIPAL
// ─────────────────────────────────────────────

final ThemeData appTheme = ThemeData(
  useMaterial3: true,
  brightness:   Brightness.dark,

  scaffoldBackgroundColor: PlanetaColors.black,
  primaryColor:            PlanetaColors.accent,

  colorScheme: const ColorScheme.dark(
    primary:          PlanetaColors.accent,
    onPrimary:        PlanetaColors.white,
    primaryContainer: PlanetaColors.accentDark,
    secondary:        PlanetaColors.accentLight,
    onSecondary:      PlanetaColors.black,
    tertiary:         PlanetaColors.silver,
    surface:          PlanetaColors.charcoal,
    onSurface:        PlanetaColors.white,
    error:            PlanetaColors.error,
    onError:          PlanetaColors.white,
    outline:          PlanetaColors.graphite,
    outlineVariant:   PlanetaColors.slate,
  ),

  // ── AppBar ───────────────────────────────
  appBarTheme: const AppBarTheme(
    backgroundColor:        PlanetaColors.carbon,
    foregroundColor:        PlanetaColors.white,
    surfaceTintColor:       Colors.transparent,
    elevation:              0,
    scrolledUnderElevation: 0,
    shadowColor:            Colors.transparent,
    centerTitle:            false,
    titleTextStyle: TextStyle(
      color:         PlanetaColors.white,
      fontSize:      18,
      fontWeight:    FontWeight.w700,
      letterSpacing: 0.2,
    ),
    iconTheme: IconThemeData(color: PlanetaColors.white),
  ),

  // ── Navigation Bar ───────────────────────
  navigationBarTheme: NavigationBarThemeData(
    backgroundColor:  PlanetaColors.carbon,
    indicatorColor:   Color(0x221565C0),
    surfaceTintColor: Colors.transparent,
    elevation:        0,
    iconTheme: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.selected)) {
        return const IconThemeData(color: PlanetaColors.accentLight);
      }
      return const IconThemeData(color: PlanetaColors.ash);
    }),
    labelTextStyle: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.selected)) {
        return const TextStyle(
          color:      PlanetaColors.accentLight,
          fontWeight: FontWeight.w600,
          fontSize:   12,
        );
      }
      return const TextStyle(color: PlanetaColors.silver, fontSize: 12);
    }),
  ),

  // ── Bottom Navigation Bar ────────────────
  bottomNavigationBarTheme: const BottomNavigationBarThemeData(
    backgroundColor:     PlanetaColors.carbon,
    selectedItemColor:   PlanetaColors.accentLight,
    unselectedItemColor: PlanetaColors.ash,
    type:                BottomNavigationBarType.fixed,
    elevation:           0,
  ),

  // ── Inputs ───────────────────────────────
  inputDecorationTheme: InputDecorationTheme(
    filled:    true,
    fillColor: PlanetaColors.charcoal,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: PlanetaColors.graphite),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: PlanetaColors.graphite),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: PlanetaColors.accentLight, width: 1.5),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: PlanetaColors.error),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: PlanetaColors.error, width: 1.5),
    ),
    labelStyle:      const TextStyle(color: PlanetaColors.silver),
    hintStyle:       const TextStyle(color: PlanetaColors.ash),
    prefixIconColor: PlanetaColors.ash,
    suffixIconColor: PlanetaColors.ash,
    contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
  ),

  // ── Elevated Button ──────────────────────
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor:         PlanetaColors.accent,
      foregroundColor:         PlanetaColors.white,
      disabledBackgroundColor: PlanetaColors.graphite,
      disabledForegroundColor: PlanetaColors.ash,
      elevation:               0,
      shadowColor:             Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 28),
      textStyle: const TextStyle(
        fontSize:      15,
        fontWeight:    FontWeight.w700,
        letterSpacing: 0.4,
      ),
    ),
  ),

  // ── Outlined Button ──────────────────────
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: PlanetaColors.white,
      side: const BorderSide(color: PlanetaColors.graphite, width: 1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
      textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
    ),
  ),

  // ── Text Button ──────────────────────────
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(
      foregroundColor: PlanetaColors.accentLight,
      textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
  ),

  // ── Cards ────────────────────────────────
  cardTheme: CardThemeData(
    color:            PlanetaColors.charcoal,
    surfaceTintColor: Colors.transparent,
    elevation:        0,
    shadowColor:      Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: PlanetaColors.graphite, width: 0.8),
    ),
    margin: const EdgeInsets.symmetric(vertical: 6),
  ),

  // ── Chip ─────────────────────────────────
  chipTheme: ChipThemeData(
    backgroundColor: PlanetaColors.charcoal,
    selectedColor:   PlanetaColors.slate,
    labelStyle:      const TextStyle(color: PlanetaColors.fog, fontSize: 13),
    side:            const BorderSide(color: PlanetaColors.graphite),
    shape:           RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    padding:         const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
  ),

  // ── Divider ──────────────────────────────
  dividerTheme: const DividerThemeData(
    color:     PlanetaColors.graphite,
    thickness: 0.6,
    space:     1,
  ),

  // ── Dialog ───────────────────────────────
  dialogTheme: DialogThemeData(
    backgroundColor:  PlanetaColors.charcoal,
    surfaceTintColor: Colors.transparent,
    elevation: 8,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    titleTextStyle: const TextStyle(
      color:      PlanetaColors.white,
      fontSize:   18,
      fontWeight: FontWeight.w700,
    ),
    contentTextStyle: const TextStyle(
      color:    PlanetaColors.fog,
      fontSize: 14,
    ),
  ),

  // ── SnackBar ─────────────────────────────
  snackBarTheme: SnackBarThemeData(
    backgroundColor:  PlanetaColors.slate,
    contentTextStyle: const TextStyle(color: PlanetaColors.white),
    actionTextColor:  PlanetaColors.accentLight,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    behavior: SnackBarBehavior.floating,
    elevation: 4,
  ),

  // ── ListTile ─────────────────────────────
  listTileTheme: const ListTileThemeData(
    tileColor:         Colors.transparent,
    iconColor:         PlanetaColors.ash,
    textColor:         PlanetaColors.white,
    contentPadding:    EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    selectedColor:     PlanetaColors.accentLight,
    selectedTileColor: Color(0xFF1A1A1A),
  ),

  // ── Switch ───────────────────────────────
  switchTheme: SwitchThemeData(
    thumbColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.selected)) return PlanetaColors.white;
      return PlanetaColors.silver;
    }),
    trackColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.selected)) return PlanetaColors.accent;
      return PlanetaColors.graphite;
    }),
  ),

  // ── Checkbox ─────────────────────────────
  checkboxTheme: CheckboxThemeData(
    fillColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.selected)) return PlanetaColors.accent;
      return Colors.transparent;
    }),
    checkColor: WidgetStateProperty.all(PlanetaColors.white),
    side: const BorderSide(color: PlanetaColors.graphite, width: 1.5),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
  ),

  // ── FAB ──────────────────────────────────
  floatingActionButtonTheme: FloatingActionButtonThemeData(
    backgroundColor: PlanetaColors.accent,
    foregroundColor: PlanetaColors.white,
    elevation:       4,
    // Sin shape fija — deja que cada FAB (normal/extended) use su forma natural
    extendedPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
  ),

  // ── Progress Indicator ───────────────────
  progressIndicatorTheme: const ProgressIndicatorThemeData(
    color:              PlanetaColors.accentLight,
    linearTrackColor:   PlanetaColors.graphite,
    circularTrackColor: Colors.transparent,
  ),

  // ── TabBar ───────────────────────────────
  tabBarTheme: const TabBarThemeData(
    indicatorColor:       PlanetaColors.accentLight,
    labelColor:           PlanetaColors.white,
    unselectedLabelColor: PlanetaColors.silver,
    indicatorSize:        TabBarIndicatorSize.tab,
    labelStyle:           TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
    unselectedLabelStyle: TextStyle(fontWeight: FontWeight.w400, fontSize: 14),
    dividerColor:         PlanetaColors.graphite,
  ),

  // ── Texto ────────────────────────────────
  textTheme: const TextTheme(
    displayLarge:   TextStyle(color: PlanetaColors.white,  fontSize: 57, fontWeight: FontWeight.w700),
    displayMedium:  TextStyle(color: PlanetaColors.white,  fontSize: 45, fontWeight: FontWeight.w700),
    displaySmall:   TextStyle(color: PlanetaColors.white,  fontSize: 36, fontWeight: FontWeight.w700),
    headlineLarge:  TextStyle(color: PlanetaColors.white,  fontSize: 32, fontWeight: FontWeight.w700),
    headlineMedium: TextStyle(color: PlanetaColors.white,  fontSize: 28, fontWeight: FontWeight.w600),
    headlineSmall:  TextStyle(color: PlanetaColors.white,  fontSize: 24, fontWeight: FontWeight.w600),
    titleLarge:     TextStyle(color: PlanetaColors.white,  fontSize: 20, fontWeight: FontWeight.w700),
    titleMedium:    TextStyle(color: PlanetaColors.white,  fontSize: 16, fontWeight: FontWeight.w600),
    titleSmall:     TextStyle(color: PlanetaColors.fog,    fontSize: 14, fontWeight: FontWeight.w600),
    bodyLarge:      TextStyle(color: PlanetaColors.white,  fontSize: 16),
    bodyMedium:     TextStyle(color: PlanetaColors.fog,    fontSize: 14),
    bodySmall:      TextStyle(color: PlanetaColors.silver, fontSize: 12),
    labelLarge:     TextStyle(color: PlanetaColors.white,  fontSize: 14, fontWeight: FontWeight.w600),
    labelMedium:    TextStyle(color: PlanetaColors.silver, fontSize: 12),
    labelSmall:     TextStyle(color: PlanetaColors.ash,    fontSize: 11),
  ),

  // ── Icons ────────────────────────────────
  iconTheme:        const IconThemeData(color: PlanetaColors.silver, size: 24),
  primaryIconTheme: const IconThemeData(color: PlanetaColors.white,  size: 24),
);