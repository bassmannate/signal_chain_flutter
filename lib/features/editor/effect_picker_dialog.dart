import 'package:flutter/material.dart';

import '../../models/device_family.dart';
import '../../protocols/catalogs/effect_catalog.dart';
import '../theme/studio_theme.dart';

/// Modal dialog for browsing, filtering by category, and searching the device effect catalog
/// to select an effect algorithm for swapping or adding to the signal chain.
class EffectPickerDialog extends StatefulWidget {
  final DeviceFamily deviceFamily;
  final String? currentEffectId;
  final String title;

  const EffectPickerDialog({
    super.key,
    required this.deviceFamily,
    this.currentEffectId,
    this.title = 'Select Effect',
  });

  /// Displays the effect picker dialog modally.
  static Future<EffectDefinition?> show({
    required BuildContext context,
    required DeviceFamily deviceFamily,
    String? currentEffectId,
    String title = 'Select Effect',
  }) {
    return showDialog<EffectDefinition>(
      context: context,
      builder: (context) => EffectPickerDialog(
        deviceFamily: deviceFamily,
        currentEffectId: currentEffectId,
        title: title,
      ),
    );
  }

  @override
  State<EffectPickerDialog> createState() => _EffectPickerDialogState();
}

class _EffectPickerDialogState extends State<EffectPickerDialog> {
  late final TextEditingController _searchController;
  late final List<EffectDefinition> _allEffects;
  late final List<String> _categories;

  String _selectedCategory = 'ALL';
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _allEffects = EffectCatalogRegistry.getEffectsForFamily(widget.deviceFamily);
    final rawCategories = EffectCatalogRegistry.getCategories(widget.deviceFamily);
    _categories = ['ALL', ...rawCategories];
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<EffectDefinition> get _filteredEffects {
    final query = _searchQuery.trim().toLowerCase();
    final filterCategory = _selectedCategory.toLowerCase();

    return _allEffects.where((effect) {
      // Category filter
      if (_selectedCategory != 'ALL' && effect.category.toLowerCase() != filterCategory) {
        return false;
      }
      // Query filter
      if (query.isNotEmpty) {
        final matchesName = effect.name.toLowerCase().contains(query);
        final matchesCat = effect.category.toLowerCase().contains(query);
        final matchesId = effect.effectId.toLowerCase().contains(query);
        if (!matchesName && !matchesCat && !matchesId) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredEffects;

    return Dialog(
      backgroundColor: StudioTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: StudioTheme.surfaceBorder, width: 1.5),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 680,
          maxHeight: 620,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 16, 12),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome, color: StudioTheme.colorModulation, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.grey, size: 20),
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(color: StudioTheme.surfaceBorder, height: 1),

            // Search input field
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                key: const Key('effect_picker_search_input'),
                controller: _searchController,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search by name, category, or ID...',
                  hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
                  prefixIcon: const Icon(Icons.search, color: Colors.grey, size: 20),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, color: Colors.grey, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: StudioTheme.background,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: StudioTheme.surfaceBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: StudioTheme.surfaceBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: StudioTheme.colorModulation),
                  ),
                ),
                onChanged: (val) => setState(() => _searchQuery = val),
              ),
            ),

            // Category filter chips
            SizedBox(
              height: 40,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                itemCount: _categories.length,
                separatorBuilder: (context, i) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final cat = _categories[i];
                  final isSelected = _selectedCategory == cat;
                  final chipColor = cat == 'ALL'
                      ? StudioTheme.colorModulation
                      : StudioTheme.getCategoryColor(cat);

                  return ChoiceChip(
                    key: Key('category_chip_${cat.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}'),
                    label: Text(
                      cat,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected ? Colors.white : Colors.grey.shade300,
                      ),
                    ),
                    selected: isSelected,
                    selectedColor: chipColor.withValues(alpha: 0.35),
                    backgroundColor: StudioTheme.surfaceElevated,
                    side: BorderSide(
                      color: isSelected ? chipColor : StudioTheme.surfaceBorder,
                    ),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    showCheckmark: false,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() => _selectedCategory = cat);
                      }
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            const Divider(color: StudioTheme.surfaceBorder, height: 1),

            // Effects List
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.search_off, size: 40, color: Colors.grey.shade600),
                          const SizedBox(height: 8),
                          Text(
                            'No effects found matching "$_searchQuery"',
                            style: const TextStyle(color: Colors.grey, fontSize: 13),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: filtered.length,
                      separatorBuilder: (context, i) => const Divider(
                        color: StudioTheme.surfaceBorder,
                        height: 1,
                      ),
                      itemBuilder: (context, i) {
                        final effect = filtered[i];
                        final isCurrent = widget.currentEffectId != null &&
                            (effect.effectId.toLowerCase() == widget.currentEffectId!.toLowerCase() ||
                                effect.effectId.toLowerCase() ==
                                    '0x${widget.currentEffectId!.toLowerCase()}');
                        final categoryColor = StudioTheme.getCategoryColor(effect.category);

                        return ListTile(
                          key: Key('effect_picker_item_${effect.effectId}'),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                          hoverColor: StudioTheme.surfaceElevated,
                          leading: Container(
                            width: 10,
                            height: 36,
                            decoration: BoxDecoration(
                              color: categoryColor,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          title: Row(
                            children: [
                              Text(
                                effect.name,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: isCurrent ? StudioTheme.colorModulation : Colors.white,
                                ),
                              ),
                              if (isCurrent) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: StudioTheme.colorModulation.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: StudioTheme.colorModulation, width: 0.8),
                                  ),
                                  child: const Text(
                                    'ACTIVE',
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      color: StudioTheme.colorModulation,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          subtitle: Text(
                            '${effect.category} • ${effect.parameters.length} params • ID: ${effect.effectId}',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade400,
                            ),
                          ),
                          trailing: ElevatedButton(
                            key: Key('select_effect_btn_${effect.effectId}'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isCurrent
                                  ? StudioTheme.surfaceElevated
                                  : StudioTheme.colorModulation.withValues(alpha: 0.2),
                              foregroundColor: isCurrent ? Colors.grey : StudioTheme.colorModulation,
                              side: BorderSide(
                                color: isCurrent ? StudioTheme.surfaceBorder : StudioTheme.colorModulation,
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                            onPressed: () => Navigator.of(context).pop(effect),
                            child: Text(isCurrent ? 'Current' : 'Select'),
                          ),
                          onTap: () => Navigator.of(context).pop(effect),
                        );
                      },
                    ),
            ),

            // Footer with count
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: StudioTheme.background,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${filtered.length} effects available (${_allEffects.length} total)',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel', style: TextStyle(color: Colors.grey, fontSize: 12)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

