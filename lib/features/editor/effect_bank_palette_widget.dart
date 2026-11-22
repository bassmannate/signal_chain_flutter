import 'package:flutter/material.dart';

import '../../models/device_family.dart';
import '../../protocols/catalogs/effect_catalog.dart';
import '../theme/responsive_layout.dart';
import '../theme/studio_theme.dart';
import 'custom_effects_dialog.dart';
import 'effect_origin_badge.dart';
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
  DeviceFamily? _lastDeviceFamily;

  @override
  void initState() {
    super.initState();
    final family = widget.controller.connectionController.activeFamily;
    _lastDeviceFamily = family;
    _syncCategoryForFamily(family);
    widget.controller.connectionController.addListener(_handleConnectionChanged);
  }

  @override
  void didUpdateWidget(covariant EffectBankPaletteWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller.connectionController !=
        widget.controller.connectionController) {
      oldWidget.controller.connectionController
          .removeListener(_handleConnectionChanged);
      widget.controller.connectionController
          .addListener(_handleConnectionChanged);
    }
    _syncCategoryForFamily(
      widget.controller.connectionController.activeFamily,
    );
  }

  @override
  void dispose() {
    widget.controller.connectionController
        .removeListener(_handleConnectionChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _handleConnectionChanged() {
    _syncCategoryForFamily(
      widget.controller.connectionController.activeFamily,
      triggerSetState: true,
    );
  }

  void _syncCategoryForFamily(
    DeviceFamily family, {
    bool triggerSetState = false,
  }) {
    if (_lastDeviceFamily == family) return;
    _lastDeviceFamily = family;
    final availableCategories = EffectCatalogRegistry.getCategories(family);
    if (_selectedCategory != 'All') {
      final matched = availableCategories.cast<String?>().firstWhere(
            (cat) => cat!.toLowerCase() == _selectedCategory.toLowerCase(),
            orElse: () => null,
          );
      _selectedCategory = matched ?? 'All';
    }
    if (triggerSetState && mounted) {
      setState(() {});
    }
  }

  bool _matchesCategory(EffectDefinition def, String category) {
    if (category == 'All') return true;
    return def.category.trim().toLowerCase() == category.trim().toLowerCase();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        widget.controller,
        widget.controller.connectionController,
        EffectCatalogRegistry.catalogRevision,
      ]),
      builder: (context, _) {
        final family = widget.controller.connectionController.activeFamily;
        final customCount = EffectCatalogRegistry.customEffectCountForFamily(family);
        final dynamicCategories = <String>[
          'All',
          ...EffectCatalogRegistry.getCategories(family),
        ];
        final effectiveSelectedCategory =
            dynamicCategories.contains(_selectedCategory)
                ? _selectedCategory
                : 'All';
        final allEffects = EffectCatalogRegistry.getEffectsForFamily(family);

        final filtered = allEffects.where((def) {
          if (!_matchesCategory(def, effectiveSelectedCategory)) return false;
          if (_searchQuery.isEmpty) return true;
          final q = _searchQuery.toLowerCase();
          return def.name.toLowerCase().contains(q) ||
              def.category.toLowerCase().contains(q) ||
              def.effectId.toLowerCase().contains(q);
        }).toList();

        return LayoutBuilder(
          builder: (context, constraints) {
            final hasBoundedHeight = constraints.hasBoundedHeight;
            final textScale = MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 1.4);
            final gridExtent = 76.0 * textScale;

            final gridContent = filtered.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        'No matching effects found',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ),
                  )
                : GridView.builder(
                    key: const Key('palette_effects_grid'),
                    shrinkWrap: !hasBoundedHeight,
                    physics: hasBoundedHeight
                        ? null
                        : const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(8),
                    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 180,
                      mainAxisExtent: gridExtent,
                      crossAxisSpacing: 6,
                      mainAxisSpacing: 6,
                    ),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final effect = filtered[index];
                      return _buildDraggableEffectItem(context, effect);
                    },
                  );

            return Container(
              decoration: BoxDecoration(
                color: StudioTheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: StudioTheme.surfaceBorder),
              ),
              child: Column(
                mainAxisSize: hasBoundedHeight ? MainAxisSize.max : MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.widgets, size: 15, color: StudioTheme.colorModulation),
                    const SizedBox(width: 6),
                    const Expanded(
                      child: Text(
                        'EFFECT PALETTE',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
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
                    if (family.isZoom6E) ...[
                      const SizedBox(width: 4),
                      Tooltip(
                        message: 'Manage Custom Effects (.ZD2)',
                        child: InkWell(
                          key: const Key('palette_custom_effects_button'),
                          borderRadius: BorderRadius.circular(10),
                          onTap: () => CustomEffectsDialog.show(
                            context: context,
                            editorController: widget.controller,
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: customCount > 0
                                  ? StudioTheme.colorCustom.withValues(alpha: 0.18)
                                  : StudioTheme.surfaceElevated,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: customCount > 0
                                    ? StudioTheme.colorCustom.withValues(alpha: 0.8)
                                    : StudioTheme.surfaceBorder,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.extension,
                                  size: 11,
                                  color: StudioTheme.colorCustom,
                                ),
                                const SizedBox(width: 3),
                                const Text(
                                  '.ZD2',
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.bold,
                                    color: StudioTheme.colorCustom,
                                  ),
                                ),
                                if (customCount > 0) ...[
                                  const SizedBox(width: 3),
                                  Container(
                                    key: const Key('palette_custom_effects_count'),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 0.5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: StudioTheme.colorCustom,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      '$customCount',
                                      style: const TextStyle(
                                        fontSize: 8.5,
                                        fontWeight: FontWeight.w900,
                                        color: Colors.black,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
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

              // Category Filter Dropdown
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Category',
                    labelStyle: const TextStyle(fontSize: 11, color: Colors.grey),
                    filled: true,
                    fillColor: StudioTheme.surfaceElevated,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(color: StudioTheme.surfaceBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(color: StudioTheme.surfaceBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(color: StudioTheme.colorModulation),
                    ),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      key: const Key('palette_category_dropdown'),
                      value: effectiveSelectedCategory,
                      isDense: true,
                      isExpanded: true,
                      menuMaxHeight: 360,
                      dropdownColor: StudioTheme.surfaceElevated,
                      style: const TextStyle(fontSize: 12, color: Colors.white),
                      items: dynamicCategories.map((cat) {
                        final catColor = cat == 'All'
                            ? StudioTheme.colorModulation
                            : StudioTheme.getCategoryColor(cat);
                        return DropdownMenuItem<String>(
                          key: Key('palette_category_item_$cat'),
                          value: cat,
                          child: Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: catColor,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  cat,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _selectedCategory = val);
                        }
                      },
                    ),
                  ),
                ),
              ),

              const Divider(color: StudioTheme.surfaceBorder, height: 1),

              // Scrollable Effects Grid
              if (hasBoundedHeight)
                Expanded(child: gridContent)
              else
                gridContent,
            ],
          ),
        );
          },
        );
      },
    );
  }

  Widget _buildDraggableEffectItem(BuildContext context, EffectDefinition effect) {
    final categoryColor = StudioTheme.getCategoryColor(effect.category);
    final isTouch = ResponsiveLayoutMetrics.isTouchPlatform(context);

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
          Row(
            children: [
              Expanded(
                child: Text(
                  '${effect.parameters.length} params',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 8.5, color: Colors.grey),
                ),
              ),
              if (effect.origin == EffectOrigin.crossModel ||
                  effect.origin == EffectOrigin.custom) ...[
                const SizedBox(width: 4),
                Flexible(
                  child: EffectOriginBadge(
                    definition: effect,
                    compact: true,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );

    final feedbackWidget = Material(
      elevation: 8,
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: 160,
        height: 68,
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
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: categoryColor,
                ),
              ),
              Text(
                effect.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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
    );

    final childWhenDragging = Opacity(
      opacity: 0.35,
      child: cardContent,
    );

    final clickChild = InkWell(
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
    );

    if (isTouch) {
      return LongPressDraggable<EffectDragPayload>(
        key: Key('palette_draggable_${effect.effectId}'),
        data: EffectDragPayload(effect),
        feedback: feedbackWidget,
        childWhenDragging: childWhenDragging,
        child: clickChild,
      );
    }

    return Draggable<EffectDragPayload>(
      key: Key('palette_draggable_${effect.effectId}'),
      data: EffectDragPayload(effect),
      feedback: feedbackWidget,
      childWhenDragging: childWhenDragging,
      child: clickChild,
    );
  }
}

