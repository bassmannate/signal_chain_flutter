import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/parameter_descriptor.dart';
import '../theme/studio_theme.dart';

/// Dark studio rotary knob widget representing an adjustable hardware effect parameter.
///
/// Features:
/// - Custom painted dial with radial value sweep and metallic bevel.
/// - Mouse scroll wheel adjustment via [PointerScrollEvent].
/// - Vertical drag adjustment via [GestureDetector].
/// - Double-tap to reset to default value.
/// - Crisp monospace formatted value display matching pedal hardware screens.
class RotaryKnobWidget extends StatefulWidget {
  final ParameterValue param;
  final int paramIndex;
  final int slotIndex;
  final Color accentColor;
  final ValueChanged<int> onChanged;
  final double dialSize;

  const RotaryKnobWidget({
    super.key,
    required this.param,
    required this.paramIndex,
    required this.slotIndex,
    required this.accentColor,
    required this.onChanged,
    this.dialSize = 52.0,
  });

  @override
  State<RotaryKnobWidget> createState() => _RotaryKnobWidgetState();
}

class _RotaryKnobWidgetState extends State<RotaryKnobWidget> {
  double? _dragStartValue;
  double _accumulatedDelta = 0.0;
  bool _isHovered = false;

  ParameterDescriptor get descriptor => widget.param.descriptor;
  double get min => descriptor.min;
  double get max => descriptor.max;
  double get range => max > min ? max - min : 1.0;
  double get currentValue => widget.param.currentValue.clamp(min, max);

  /// Normalized value from 0.0 (min) to 1.0 (max).
  double get normalizedValue => ((currentValue - min) / range).clamp(0.0, 1.0);

  void _updateValue(double newValue) {
    final clamped = newValue.clamp(min, max);
    final rounded = clamped.round();
    if (rounded != widget.param.currentValue.round()) {
      widget.onChanged(rounded);
    }
  }

  void _handleScroll(PointerScrollEvent event) {
    if (range <= 0) return;

    // Check if shift is pressed for coarse adjustment
    final isShift = HardwareKeyboard.instance.isShiftPressed;
    final double stepSize = isShift
        ? math.max(1.0, (range / 10).roundToDouble())
        : descriptor.step.clamp(1.0, 5.0);

    if (event.scrollDelta.dy < 0) {
      // Scroll Up -> Increment
      _updateValue(currentValue + stepSize);
    } else if (event.scrollDelta.dy > 0) {
      // Scroll Down -> Decrement
      _updateValue(currentValue - stepSize);
    }
  }

  void _onVerticalDragStart(DragStartDetails details) {
    _dragStartValue = currentValue;
    _accumulatedDelta = 0.0;
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    if (_dragStartValue == null) return;

    // Upward drag (negative dy) increases value; downward decreases.
    _accumulatedDelta -= details.delta.dy;

    // Sensitivity: 120 pixels of drag spans full parameter range (or minimum 1 step per 3 pixels)
    final double dragSensitivity = math.max(100.0, range * 2.0);
    final double deltaVal = (_accumulatedDelta / dragSensitivity) * range;

    _updateValue(_dragStartValue! + deltaVal);
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    _dragStartValue = null;
    _accumulatedDelta = 0.0;
  }

  void _onDoubleTap() {
    _updateValue(descriptor.defaultValue);
  }

  @override
  Widget build(BuildContext context) {
    final formattedValue = widget.param.displayValue;
    final isDiscrete = descriptor.isDiscrete;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Listener(
        onPointerSignal: (pointerSignal) {
          if (pointerSignal is PointerScrollEvent) {
            _handleScroll(pointerSignal);
          }
        },
        child: GestureDetector(
          onVerticalDragStart: _onVerticalDragStart,
          onVerticalDragUpdate: _onVerticalDragUpdate,
          onVerticalDragEnd: _onVerticalDragEnd,
          onDoubleTap: _onDoubleTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: 78,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            decoration: BoxDecoration(
              color: _isHovered
                  ? StudioTheme.surfaceElevated.withValues(alpha: 0.8)
                  : StudioTheme.surfaceElevated.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _isHovered
                    ? widget.accentColor.withValues(alpha: 0.5)
                    : Colors.transparent,
                width: 1,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Rotary Knob Canvas Dial
                CustomPaint(
                  size: Size(widget.dialSize, widget.dialSize),
                  painter: _KnobPainter(
                    normalizedValue: normalizedValue,
                    accentColor: widget.accentColor,
                    isHovered: _isHovered,
                  ),
                ),
                const SizedBox(height: 6),

                // Parameter Name Label
                Tooltip(
                  message: '${descriptor.name} (Double-tap to reset)',
                  child: Text(
                    descriptor.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: _isHovered ? Colors.white : Colors.grey.shade400,
                    ),
                  ),
                ),
                const SizedBox(height: 2),

                // Parameter Value Text
                if (isDiscrete && descriptor.effectiveLabels != null)
                  _buildDiscreteValueSelector(context, formattedValue)
                else
                  _buildContinuousValueBadge(formattedValue),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContinuousValueBadge(String formattedValue) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: StudioTheme.surface,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(
          color: _isHovered
              ? widget.accentColor.withValues(alpha: 0.4)
              : StudioTheme.surfaceBorder,
          width: 0.5,
        ),
      ),
      child: Text(
        formattedValue,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 11,
          fontFamily: 'monospace',
          fontWeight: FontWeight.bold,
          color: _isHovered ? widget.accentColor : Colors.white,
        ),
      ),
    );
  }

  Widget _buildDiscreteValueSelector(BuildContext context, String formattedValue) {
    final labels = descriptor.effectiveLabels!;
    final currentIdx = widget.param.currentValue.round().clamp(0, labels.length - 1);

    return PopupMenuButton<int>(
      tooltip: 'Select ${descriptor.name}',
      color: StudioTheme.surfaceElevated,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(maxHeight: 280),
      initialValue: currentIdx,
      onSelected: (newVal) => _updateValue(newVal.toDouble()),
      itemBuilder: (context) {
        return List.generate(labels.length, (idx) {
          final isSelected = idx == currentIdx;
          return PopupMenuItem<int>(
            value: idx,
            height: 32,
            child: Text(
              labels[idx],
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? widget.accentColor : Colors.white,
              ),
            ),
          );
        });
      },
      child: Container(
        constraints: const BoxConstraints(minHeight: 28),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: StudioTheme.surface,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: widget.accentColor.withValues(alpha: 0.4),
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                formattedValue,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.bold,
                  color: widget.accentColor,
                ),
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.arrow_drop_down, size: 13, color: widget.accentColor),
          ],
        ),
      ),
    );
  }
}

class _KnobPainter extends CustomPainter {
  final double normalizedValue;
  final Color accentColor;
  final bool isHovered;

  // Angles in radians: 135 degrees (7 o'clock) to 405 degrees (5 o'clock)
  static const double _startAngle = 135 * (math.pi / 180.0);
  static const double _sweepAngle = 270 * (math.pi / 180.0);

  const _KnobPainter({
    required this.normalizedValue,
    required this.accentColor,
    required this.isHovered,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // 1. Inactive Track Arc (Background)
    final trackRadius = radius - 4.0;
    final trackRect = Rect.fromCircle(center: center, radius: trackRadius);

    final trackPaint = Paint()
      ..color = const Color(0xFF282C34)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(trackRect, _startAngle, _sweepAngle, false, trackPaint);

    // 2. Active Track Arc (Value Sweep)
    if (normalizedValue > 0.001) {
      final activeSweep = _sweepAngle * normalizedValue;
      final activePaint = Paint()
        ..color = isHovered ? accentColor : accentColor.withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(trackRect, _startAngle, activeSweep, false, activePaint);
    }

    // 3. Knob Body (Outer Dial Circle)
    final knobRadius = radius - 8.0;

    // Bevel Outer Border
    final borderPaint = Paint()
      ..color = isHovered ? const Color(0xFF4A505C) : const Color(0xFF383C44)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, knobRadius, borderPaint);

    // Knob Face Radial / Linear Gradient
    final facePaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF2A2D33),
          const Color(0xFF1B1D21),
        ],
        stops: const [0.6, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: knobRadius));
    canvas.drawCircle(center, knobRadius, facePaint);

    // 4. Center Cap (Subtle Inner Depression)
    final innerRadius = knobRadius * 0.45;
    final innerPaint = Paint()
      ..color = const Color(0xFF141518);
    canvas.drawCircle(center, innerRadius, innerPaint);

    // 5. Radial Pointer Tick (Needle / Dot)
    final currentAngle = _startAngle + (_sweepAngle * normalizedValue);
    final indicatorStartRadius = innerRadius + 1.0;
    final indicatorEndRadius = knobRadius - 2.5;

    final startPoint = Offset(
      center.dx + indicatorStartRadius * math.cos(currentAngle),
      center.dy + indicatorStartRadius * math.sin(currentAngle),
    );
    final endPoint = Offset(
      center.dx + indicatorEndRadius * math.cos(currentAngle),
      center.dy + indicatorEndRadius * math.sin(currentAngle),
    );

    final needlePaint = Paint()
      ..color = isHovered ? Colors.white : accentColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(startPoint, endPoint, needlePaint);
  }

  @override
  bool shouldRepaint(covariant _KnobPainter oldDelegate) {
    return oldDelegate.normalizedValue != normalizedValue ||
        oldDelegate.accentColor != accentColor ||
        oldDelegate.isHovered != isHovered;
  }
}

