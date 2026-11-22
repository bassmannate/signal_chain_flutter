import 'package:flutter/material.dart';

import '../../protocols/catalogs/effect_catalog.dart';
import '../theme/studio_theme.dart';

/// Compact provenance pill badge rendered for cross-model sibling effects
/// (e.g., `MS-50G+`, `MS-70CDR+`, `B1X FOUR`) and user-imported custom `.ZD2`
/// effects (`CUSTOM`).
///
/// Renders nothing for [EffectOrigin.stock] and [EffectOrigin.unknown] so stock
/// items stay clean and unknown items retain their existing `UNKNOWN` styling.
class EffectOriginBadge extends StatelessWidget {
  final EffectDefinition definition;
  final bool compact;

  const EffectOriginBadge({
    super.key,
    required this.definition,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final String label;
    final Color accentColor;
    final String? tooltip;

    switch (definition.origin) {
      case EffectOrigin.stock:
      case EffectOrigin.unknown:
        return const SizedBox.shrink();

      case EffectOrigin.crossModel:
        label = (definition.sourceModelLabel?.trim().isNotEmpty == true)
            ? definition.sourceModelLabel!.trim()
            : 'CROSS-MODEL';
        accentColor = StudioTheme.colorPreamp;
        tooltip = 'Resolved from sibling model catalog ($label)';
        break;

      case EffectOrigin.custom:
        label = 'CUSTOM';
        accentColor = StudioTheme.colorCustom;
        final parts = <String>[
          'Custom .ZD2 Effect',
          if (definition.version != null && definition.version!.isNotEmpty)
            'v${definition.version}',
          if (definition.sourceFilename != null &&
              definition.sourceFilename!.isNotEmpty)
            definition.sourceFilename!,
          if (definition.description != null &&
              definition.description!.isNotEmpty)
            definition.description!,
        ];
        tooltip = parts.join(' • ');
        break;
    }

    final pill = Container(
      key: Key('origin_badge_${definition.origin.name}_${definition.effectId}'),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 4 : 7,
        vertical: compact ? 1 : 2.5,
      ),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(compact ? 3 : 4),
        border: Border.all(
          color: accentColor.withValues(alpha: 0.75),
          width: compact ? 0.8 : 1.0,
        ),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: compact ? 8.0 : 10.0,
          fontWeight: FontWeight.w800,
          letterSpacing: compact ? 0.3 : 0.5,
          height: 1.1,
          color: accentColor,
        ),
      ),
    );

    if (tooltip.isEmpty) return pill;
    return Tooltip(message: tooltip, child: pill);
  }
}

