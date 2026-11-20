import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'responsive_layout.dart';

/// Application-wide scroll behavior enabling mouse drag scrolling in addition
/// to touch, stylus, and trackpad input on desktop and mobile platforms.
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
        PointerDeviceKind.mouse,
        PointerDeviceKind.touch,
        PointerDeviceKind.stylus,
        PointerDeviceKind.trackpad,
      };
}

/// Reusable horizontal scroll container designed for both touch and desktop
/// mouse interaction.
///
/// Features:
/// - Owns a dedicated [ScrollController] when none is supplied, avoiding
///   [PrimaryScrollController] attachment conflicts.
/// - Wraps content in an interactive [Scrollbar] visible on desktop when
///   horizontal content overflows.
/// - Converts vertical mouse-wheel [PointerScrollEvent] deltas into horizontal
///   scrolling and consumes the resolved pointer signal when scrolled.
class HorizontalMouseScrollView extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final ScrollController? controller;
  final ScrollPhysics? physics;
  final bool? thumbVisibility;
  final double scrollbarGutter;

  const HorizontalMouseScrollView({
    super.key,
    required this.child,
    this.padding,
    this.controller,
    this.physics,
    this.thumbVisibility,
    this.scrollbarGutter = 14.0,
  });

  @override
  State<HorizontalMouseScrollView> createState() =>
      _HorizontalMouseScrollViewState();
}

class _HorizontalMouseScrollViewState extends State<HorizontalMouseScrollView> {
  ScrollController? _internalController;

  ScrollController get _effectiveController =>
      widget.controller ?? _internalController!;

  @override
  void initState() {
    super.initState();
    if (widget.controller == null) {
      _internalController = ScrollController();
    }
  }

  @override
  void didUpdateWidget(covariant HorizontalMouseScrollView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      if (widget.controller == null && _internalController == null) {
        _internalController = ScrollController();
      } else if (widget.controller != null && _internalController != null) {
        _internalController!.dispose();
        _internalController = null;
      }
    }
  }

  @override
  void dispose() {
    _internalController?.dispose();
    super.dispose();
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_effectiveController.hasClients) {
      return;
    }

    final position = _effectiveController.position;
    if (position.maxScrollExtent <= position.minScrollExtent) {
      return;
    }

    final delta = event.scrollDelta.dy != 0.0
        ? event.scrollDelta.dy
        : event.scrollDelta.dx;
    if (delta == 0.0) {
      return;
    }

    final targetOffset = (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (targetOffset == position.pixels) {
      return;
    }

    GestureBinding.instance.pointerSignalResolver.register(
      event,
      (PointerSignalEvent resolvedEvent) {
        if (!mounted || !_effectiveController.hasClients) return;
        final pos = _effectiveController.position;
        final clamped = (pos.pixels + delta).clamp(
          pos.minScrollExtent,
          pos.maxScrollExtent,
        );
        if (clamped != pos.pixels) {
          pos.jumpTo(clamped);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isTouch = ResponsiveLayoutMetrics.isTouchPlatform(context);
    final resolvedPadding = (widget.padding ?? EdgeInsets.zero)
        .resolve(Directionality.maybeOf(context) ?? TextDirection.ltr);
    final effectivePadding = resolvedPadding.copyWith(
      bottom: resolvedPadding.bottom + widget.scrollbarGutter,
    );

    return Listener(
      onPointerSignal: _handlePointerSignal,
      child: Scrollbar(
        controller: _effectiveController,
        interactive: true,
        thumbVisibility: widget.thumbVisibility ?? !isTouch,
        child: SingleChildScrollView(
          controller: _effectiveController,
          scrollDirection: Axis.horizontal,
          padding: effectivePadding,
          physics: widget.physics,
          child: widget.child,
        ),
      ),
    );
  }
}

