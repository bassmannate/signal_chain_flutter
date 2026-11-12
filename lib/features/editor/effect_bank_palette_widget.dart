import 'package:flutter/material.dart';

import '../../protocols/catalogs/effect_catalog.dart';
import '../theme/studio_theme.dart';
import 'patch_editor_controller.dart';

// Type alias EffectCatalogEntry is defined in effect_catalog.dart

/// Drag payload carrying an [EffectDefinition] from the effect palette.
class EffectDragPayload {
  final EffectDefinition entry;
  const EffectDragPayload(this.entry);
}

/// Drag payload for reordering slots within the signal chain strip.
class SlotReorderPayload {
  final int fromIndex;
  const SlotReorderPayload(this.fromIndex);
}

/// Studio dockable panel and palette widget displaying all available DSP algorithms
/// for the connected hardware family, supporting category filtering, keyword search,
/// click-to-add accessibility, and drag-and-drop onto the signal chain.
class EffectBankPaletteWidget extends StatefulWidget {
  final PatchEditorController controller;
  final bool isPanel;
  final VoidCallback? onClose;

  const EffectBankPaletteWidget({
    super.key,
    required this.controller,
    this.isPanel = false,
    this.onClose,
  });

  @override
  State<EffectBankPaletteWidget> createState() => _EffectBankPaletteWidgetState();
}

class _EffectBankPaletteWidgetState extends State<EffectBankPaletteWidget> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedCategory = 'All';

  static const List<String> categories = [
    'All',
    'Dynamics',
    'Filter',
    'Drive',
    'Amp',
    'Cabinet',
    'Modulation',
    'SFX',
    'Delay',
    'Reverb',
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _matchesCategory(EffectDefinition def, String category) {
    if (category == 'All') return true;
    final catLower = def.category.toLowerCase();
    final filterLower = category.toLowerCase();

    if (filterLower == 'dynamics') {
      return catLower.contains('dyn') || catLower.contains('comp') || catLower.contains('limit');
    } else if (filterLower == 'filter') {
      return catLower.contains('filt') || catLower.contains('eq') || catLower.contains('wah');
    } else if (filterLower == 'drive') {
      return catLower.contains('drive') || catLower.contains('dist') || catLower.contains('fuzz') || catLower.contains('overdrive');
    } else if (filterLower == 'amp') {
      return catLower.contains('amp') || catLower.contains('preamp') || catLower.contains('stack');
    } else if (filterLower == 'cabinet') {
      return catLower.contains('cab');
    } else if (filterLower == 'modulation') {
      return catLower.contains('mod') || catLower.contains('chor') || catLower.contains('flang') || catLower.contains('phas') || catLower.contains('trem');
    } else if (filterLower == 'sfx') {
      return catLower.contains('sfx') || catLower.contains('synth') || catLower.contains('pitch') || catLower.contains('octav');
    } else if (filterLower == 'delay') {
      return catLower.contains('delay') || catLower.contains('echo');
    } else if (filterLower == 'reverb') {
      return catLower.contains('rev') || catLower.contains('space') || catLower.contains('hall');
    }

    return catLower.contains(filterLower);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final family = widget.controller.connectionController.activeFamily;
        final allEffects = EffectCatalogRegistry.getEffectsForFamily(family);

        final filtered = allEffects.where((def) {
          if (!_matchesCategory(def, _selectedCategory)) return false;
          if (_searchQuery.isEmpty) return true;
          final q = _searchQuery.toLowerCase();
          return def.name.toLowerCase().contains(q) ||
              def.category.toLowerCase().contains(q) ||
              def.effectId.toLowerCase().contains(q);
        }).toList();

        return Container(
          decoration: BoxDecoration(
            color: StudioTheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: StudioTheme.surfaceBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.widgets, size: 16, color: StudioTheme.colorModulation),
                    const SizedBox(width: 8),
                    const Flexible(
                      child: Text(
                        'EFFECT PALETTE',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.0,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: StudioTheme.surfaceElevated,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: StudioTheme.surfaceBorder),
                      ),
                      child: Text(
                        '${filtered.length} EFFECTS',
                        style: const TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                          color: StudioTheme.colorModulation,
                        ),
                      ),
                    ),
                    if (widget.onClose != null) ...[
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.close, size: 16, color: Colors.grey),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: widget.onClose,
                      ),
                    ],
                  ],
                ),
              ),

              // Search Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                child: TextField(
                  key: const Key('palette_search_input'),
                  controller: _searchController,
                  style: const TextStyle(fontSize: 12, color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Search effects (e.g. Comp, SVT, Delay)...',
                    hintStyle: const TextStyle(color: Colors.grey, fontSize: 11.5),
                    prefixIcon: const Icon(Icons.search, size: 16, color: Colors.grey),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 14, color: Colors.grey),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: StudioTheme.surfaceElevated,
                    contentPadding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (val) => setState(() => _searchQuery = val),
                ),
              ),

              // Category Filter Chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                child: Row(
                  children: categories.map((cat) {
                    final isSelected = _selectedCategory == cat;
                    final catColor = cat == 'All'
                        ? StudioTheme.colorModulation
                        : StudioTheme.getCategoryColor(cat);

                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        key: Key('palette_chip_$cat'),
                        label: Text(
                          cat,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected ? Colors.white : Colors.grey,
                          ),
                        ),
                        selected: isSelected,
                        selectedColor: catColor.withValues(alpha: 0.35),
                        backgroundColor: StudioTheme.surfaceElevated,
                        side: BorderSide(
                          color: isSelected ? catColor : StudioTheme.surfaceBorder,
                          width: isSelected ? 1.5 : 1.0,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                        visualDensity: VisualDensity.compact,
                        showCheckmark: false,
                        onSelected: (selected) {
                          if (selected) {
                            setState(() => _selectedCategory = cat);
                          }
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),

              const Divider(color: StudioTheme.surfaceBorder, height: 1),

              // Scrollable Effects Grid
              Expanded(
                child: filtered.isEmpty
                    ? const Center(
                        child: Text(
                          'No matching effects found',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      )
                    : GridView.builder(
                        key: const Key('palette_effects_grid'),
                        padding: const EdgeInsets.all(8),
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 180,
                          mainAxisExtent: 64,
                          crossAxisSpacing: 6,
                          mainAxisSpacing: 6,
                        ),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final effect = filtered[index];
                          return _buildDraggableEffectItem(context, effect);
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDraggableEffectItem(BuildContext context, EffectDefinition effect) {
    final categoryColor = StudioTheme.getCategoryColor(effect.category);

    final cardContent = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: StudioTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: StudioTheme.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: categoryColor,
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  effect.category.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 8.5,
                    fontWeight: FontWeight.bold,
                    color: categoryColor,
                  ),
                ),
              ),
              const Icon(Icons.drag_indicator, size: 12, color: Colors.grey),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            effect.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          Text(
            '${effect.parameters.length} params',
            style: const TextStyle(fontSize: 8.5, color: Colors.grey),
          ),
        ],
      ),
    );

    return Draggable<EffectDragPayload>(
      key: Key('palette_draggable_${effect.effectId}'),
      data: EffectDragPayload(effect),
      feedback: Material(
        elevation: 8,
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: 160,
          height: 64,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: StudioTheme.surfaceElevated,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: categoryColor, width: 2),
              boxShadow: [
                BoxShadow(
                  color: categoryColor.withValues(alpha: 0.4),
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  effect.category.toUpperCase(),
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: categoryColor,
                  ),
                ),
                Text(
                  effect.name,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.35,
        child: cardContent,
      ),
      child: InkWell(
        key: Key('palette_click_${effect.effectId}'),
        borderRadius: BorderRadius.circular(6),
        onTap: () {
          // Accessibility tap: if space available, append; else swap selected slot
          if (widget.controller.canAddEffectSlot) {
            widget.controller.addEffectSlot(effectId: effect.effectId);
          } else if (widget.controller.selectedSlot != null) {
            widget.controller.changeSlotEffect(
              widget.controller.selectedSlotIndex,
              effect.effectId,
            );
          }
        },
        child: cardContent,
      ),
    );
  }
}

