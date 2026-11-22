import 'package:flutter/material.dart';

/// Dark-mode studio color palette and theme definition for Signal Chain Flutter.
class StudioTheme {
  StudioTheme._();

  // Dark studio backgrounds and surfaces
  static const Color background = Color(0xFF101216);
  static const Color surface = Color(0xFF181B20);
  static const Color surfaceElevated = Color(0xFF22262E);
  static const Color surfaceBorder = Color(0xFF2E333D);
  static const Color surfaceBorderFocused = Color(0xFF4C5566);

  // High-contrast category accent colors
  static const Color colorDynamics = Color(0xFF00E676); // Green
  static const Color colorFilterEq = Color(0xFFFF9100); // Amber / Orange
  static const Color colorDrive = Color(0xFFFF3D00); // Crimson / Red-Orange
  static const Color colorPreamp = Color(0xFFFFD740); // Warm Tube Gold
  static const Color colorAmpCab = Color(0xFFE040FB); // Violet / Purple
  static const Color colorModulation = Color(0xFF00E5FF); // Electric Cyan
  static const Color colorDelayReverb = Color(0xFF3D5AFE); // Royal Blue
  static const Color colorPitchSynth = Color(0xFFFF4081); // Bright Pink
  static const Color colorSfx = Color(0xFF7C4DFF); // Deep Purple Accent
  static const Color colorCustom = Color(0xFF26A69A); // Studio Teal
  static const Color colorAcoustic = Color(0xFFD4A373); // Warm Acoustic Wood
  static const Color colorBypass = Color(0xFF78909C); // Neutral Slate

  // Status indicators
  static const Color colorConnected = Color(0xFF00E676);
  static const Color colorDisconnected = Color(0xFFFF5252);
  static const Color colorDirty = Color(0xFFFFAB00);

  static final RegExp _modWordPattern = RegExp(r'\bmod\b');

  static const Map<String, Color> _exactCategoryColors = {
    // Zoom MS-60B+ hardware labels (0x01–0x0B)
    'dynamics': colorDynamics,
    'filter': colorFilterEq,
    'overdrive/distortion': colorDrive,
    'preamp': colorPreamp,
    'amps': colorAmpCab,
    'modulation': colorModulation,
    'pitch': colorPitchSynth,
    'synths': colorPitchSynth,
    'sfx': colorSfx,
    'delay': colorDelayReverb,
    'reverb': colorDelayReverb,
    // Other Zoom MS Plus, Zoom Four, ZDL7, and Line 6 category labels
    'filter / eq': colorFilterEq,
    'filter / synth': colorFilterEq,
    'overdrive / distortion': colorDrive,
    'drive / distortion': colorDrive,
    'drive / fuzz': colorDrive,
    'boost / drive': colorDrive,
    'overdrive': colorDrive,
    'distortion': colorDrive,
    'fuzz': colorDrive,
    'drive': colorDrive,
    'amp': colorAmpCab,
    'amp model': colorAmpCab,
    'cabinet': colorAmpCab,
    'pitch / octave': colorPitchSynth,
    'bass synth': colorPitchSynth,
    'synth': colorPitchSynth,
    'pedal': colorPitchSynth,
    'special / sfx': colorSfx,
    'acoustic': colorAcoustic,
    'custom': colorCustom,
    'bypass': colorBypass,
    'unknown': colorBypass,
  };

  /// Resolves an accent color based on effect category name.
  static Color getCategoryColor(String category) {
    final cat = category.toLowerCase().trim();
    final exact = _exactCategoryColors[cat];
    if (exact != null) return exact;

    if (cat.contains('bypass') || cat.contains('unknown')) {
      return colorBypass;
    }
    if (cat.contains('dyn') ||
        cat.contains('comp') ||
        cat.contains('limit') ||
        cat.contains('tool')) {
      return colorDynamics;
    }
    if (cat.contains('filt') || cat.contains('eq') || cat.contains('wah')) {
      return colorFilterEq;
    }
    if (cat.contains('drive') ||
        cat.contains('dist') ||
        cat.contains('fuzz') ||
        cat.contains('overdrive') ||
        cat.contains('boost')) {
      return colorDrive;
    }
    if (cat.contains('preamp')) {
      return colorPreamp;
    }
    if (cat.contains('amp') ||
        cat.contains('cab') ||
        cat.contains('stack')) {
      return colorAmpCab;
    }
    if (cat.contains('modulation') ||
        _modWordPattern.hasMatch(cat) ||
        cat.contains('chor') ||
        cat.contains('flang') ||
        cat.contains('phas') ||
        cat.contains('trem') ||
        cat.contains('rotary')) {
      return colorModulation;
    }
    if (cat.contains('delay') ||
        cat.contains('rev') ||
        cat.contains('echo') ||
        cat.contains('space') ||
        cat.contains('hall')) {
      return colorDelayReverb;
    }
    if (cat.contains('sfx') || cat.contains('special')) {
      return colorSfx;
    }
    if (cat.contains('pitch') ||
        cat.contains('synth') ||
        cat.contains('octav') ||
        cat.contains('pedal') ||
        cat.contains('expr')) {
      return colorPitchSynth;
    }
    if (cat.contains('acoustic')) {
      return colorAcoustic;
    }
    if (cat.contains('custom')) {
      return colorCustom;
    }
    return colorBypass;
  }

  /// Studio dark theme for the application.
  static ThemeData get darkTheme {
    return ThemeData.dark(useMaterial3: true).copyWith(
      scaffoldBackgroundColor: background,
      colorScheme: const ColorScheme.dark(
        primary: colorModulation,
        onPrimary: Colors.black,
        secondary: colorAmpCab,
        onSecondary: Colors.white,
        surface: surface,
        onSurface: Color(0xFFECEFF1),
        surfaceContainerHighest: surfaceElevated,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: surface,
        foregroundColor: Color(0xFFECEFF1),
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: surfaceElevated,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: surfaceBorder),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceElevated,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: surfaceBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: surfaceBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: colorModulation, width: 1.5),
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: colorModulation,
        inactiveTrackColor: surfaceBorderFocused,
        thumbColor: Colors.white,
        overlayColor: colorModulation.withValues(alpha: 0.2),
        trackHeight: 4.0,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceElevated,
        selectedColor: colorModulation.withValues(alpha: 0.25),
        side: const BorderSide(color: surfaceBorder),
        labelStyle: const TextStyle(fontSize: 12),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      ),
    );
  }
}
