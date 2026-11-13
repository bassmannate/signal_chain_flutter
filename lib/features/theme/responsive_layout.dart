import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Responsive viewport size classes matching compact phones, tablets /
/// landscape phones, and full desktop studio windows.
enum ViewportSizeClass {
  /// Narrow phones (< 600 logical pixels wide, e.g., Pixel 10 Pro XL portrait).
  compact,

  /// Tablets, landscape phones, and resized desktop windows (600–1024px wide).
  medium,

  /// Full desktop monitors (> 1024px wide).
  expanded,
}

/// Centralized responsive layout breakpoints and adaptive sizing metrics.
class ResponsiveLayoutMetrics {
  final double width;
  final double height;

  const ResponsiveLayoutMetrics({
    required this.width,
    required this.height,
  });

  factory ResponsiveLayoutMetrics.fromConstraints(BoxConstraints constraints) {
    return ResponsiveLayoutMetrics(
      width: constraints.maxWidth,
      height: constraints.maxHeight,
    );
  }

  /// Categorizes the available width into compact, medium, or expanded.
  ViewportSizeClass get sizeClass {
    if (width < 600) return ViewportSizeClass.compact;
    if (width <= 1024) return ViewportSizeClass.medium;
    return ViewportSizeClass.expanded;
  }

  bool get isCompact => sizeClass == ViewportSizeClass.compact;
  bool get isMedium => sizeClass == ViewportSizeClass.medium;
  bool get isExpanded => sizeClass == ViewportSizeClass.expanded;

  /// True when total viewport height is constrained (landscape phone or
  /// Android `adjustResize` soft keyboard open).
  bool get isShortViewport => height < 500;

  /// True when the editor body height below the connection bar cannot
  /// comfortably hold both the pedalboard strip and a bounded inspector pane.
  static bool isShortEditorBody(double availableBodyHeight) =>
      availableBodyHeight < 440;

  /// Shows the Preset Library & Hardware Bank panel docked on the right only
  /// on expanded desktop viewports with adequate vertical space.
  bool get showLibraryPanel => isExpanded && height >= 480;

  /// Shows the Effect Palette side-by-side with the Slot Inspector when there
  /// is enough horizontal room without cramping the knob grid.
  bool get showSideBySidePalette => width >= 760 && !isShortViewport;

  /// Docked Effect Palette panel width.
  double get palettePanelWidth => width > 1280 ? 320.0 : 270.0;

  /// Docked Patch Library & Hardware Bank side panel width.
  double get libraryPanelWidth => width > 1280 ? 340.0 : 300.0;

  /// Slide-over `endDrawer` width on compact and medium viewports.
  double get drawerWidth => math.min(360.0, math.max(260.0, width * 0.88));

  /// Outer workspace padding adapted to viewport size.
  double get workspacePadding => isCompact ? 8.0 : 12.0;

  /// Returns true on mobile touch platforms where immediate drags collide with
  /// scroll gestures and `LongPressDraggable` should be preferred.
  static bool isTouchPlatform(BuildContext context) {
    if (debugDefaultTargetPlatformOverride != null) {
      return debugDefaultTargetPlatformOverride == TargetPlatform.android ||
          debugDefaultTargetPlatformOverride == TargetPlatform.iOS;
    }
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      return true;
    }
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      return false;
    }
    final platform = Theme.of(context).platform;
    return platform == TargetPlatform.android || platform == TargetPlatform.iOS;
  }
}
