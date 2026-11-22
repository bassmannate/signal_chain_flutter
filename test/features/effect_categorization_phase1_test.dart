import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signal_chain_flutter/core/midi/mock_midi_transport.dart';
import 'package:signal_chain_flutter/data/zoom_zdl7_master_catalog.dart';
import 'package:signal_chain_flutter/features/connection/device_connection_controller.dart';
import 'package:signal_chain_flutter/features/editor/effect_bank_palette_widget.dart';
import 'package:signal_chain_flutter/features/editor/patch_editor_controller.dart';
import 'package:signal_chain_flutter/features/theme/studio_theme.dart';
import 'package:signal_chain_flutter/models/device_family.dart';
import 'package:signal_chain_flutter/models/effect_slot.dart';
import 'package:signal_chain_flutter/models/patch.dart';
import 'package:signal_chain_flutter/protocols/catalogs/effect_catalog.dart';
import 'package:signal_chain_flutter/protocols/catalogs/zoom_ms_plus_catalog.dart';

void main() {
  setUpAll(() {
    EffectCatalogRegistry.reset();
    EffectCatalogRegistry.ensureInitialized();
  });

  group('Phase 1.1: MS-60B+ Hardware Category Alignment', () {
    const expectedMs60bpOrder = [
      'Dynamics',
      'Filter',
      'Overdrive/Distortion',
      'Preamp',
      'Amps',
      'Modulation',
      'Pitch',
      'Synths',
      'SFX',
      'Delay',
      'Reverb',
    ];

    test('exposes exact 11 hardware categories in group order', () {
      expect(
        EffectCatalogRegistry.getCategories(DeviceFamily.zoomMs60bPlus),
        equals(expectedMs60bpOrder),
      );
      expect(
        ZoomMsPlusCatalog.categoriesForFamily(DeviceFamily.zoomMs60bPlus),
        equals(expectedMs60bpOrder),
      );
      expect(
        EffectCatalogRegistry.getCategories(DeviceFamily.zoomMs60bPlus),
        isNot(contains('Cabinet')),
      );
    });

    test('places BPM (0x07000FF0) in SFX and verifies exact category counts', () {
      final bpmMs60bp = EffectCatalogRegistry.getDefinition(
        DeviceFamily.zoomMs60bPlus,
        '0x07000FF0',
      );
      expect(bpmMs60bp.name, equals('BPM'));
      expect(bpmMs60bp.category, equals('SFX'));

      for (final otherFamily in const [
        DeviceFamily.zoomMs50gPlus,
        DeviceFamily.zoomMs70cdrPlus,
        DeviceFamily.zoomMs200dPlus,
      ]) {
        final bpm = EffectCatalogRegistry.getDefinition(
          otherFamily,
          '0x07000FF0',
        );
        expect(bpm.name, equals('BPM'));
        expect(bpm.category, equals('Special / SFX'));
      }

      final ms60Effects = EffectCatalogRegistry.getEffectsForFamily(
        DeviceFamily.zoomMs60bPlus,
      );
      final counts = <String, int>{};
      for (final e in ms60Effects) {
        counts[e.category] = (counts[e.category] ?? 0) + 1;
      }

      expect(
        counts,
        equals(const {
          'Dynamics': 10,
          'Filter': 14,
          'Overdrive/Distortion': 13,
          'Preamp': 11,
          'Amps': 11,
          'Modulation': 11,
          'Pitch': 6,
          'Synths': 3,
          'SFX': 6,
          'Delay': 7,
          'Reverb': 6,
        }),
      );
      expect(counts['Cabinet'] ?? 0, equals(0));
    });
  });

  group('Phase 1.2: EffectBankPaletteWidget Dynamic Categories & Exact Matching', () {
    Future<({
      MockMidiTransport transport,
      DeviceConnectionController connection,
      PatchEditorController editor,
    })> pumpPalette(
      WidgetTester tester, {
      required DeviceFamily family,
      Size size = const Size(340, 620),
    }) async {
      final transport = MockMidiTransport();
      final connection = DeviceConnectionController(
        transport: transport,
        defaultFamily: family,
      );
      final editor = PatchEditorController(
        transport: transport,
        connectionController: connection,
        initialPatch: Patch(
          id: 'test_${family.name}',
          name: 'Test',
          deviceFamily: family,
          slots: const [
            EffectSlot(
              slotIndex: 0,
              effectId: '0x01000010',
              effectName: 'Comp',
              isEnabled: true,
              parameters: [],
            ),
          ],
        ),
      );

      addTearDown(() async {
        editor.dispose();
        connection.dispose();
        await transport.dispose();
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: StudioTheme.darkTheme,
          home: Scaffold(
            body: SizedBox(
              width: size.width,
              height: size.height,
              child: EffectBankPaletteWidget(controller: editor),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      return (
        transport: transport,
        connection: connection,
        editor: editor,
      );
    }

    Future<void> selectPaletteCategory(WidgetTester tester, String category) async {
      await tester.tap(find.byKey(const Key('palette_category_dropdown')));
      await tester.pumpAndSettle();
      final keyFinder = find.byKey(Key('palette_category_item_$category'));
      if (keyFinder.evaluate().isEmpty) {
        await tester.scrollUntilVisible(
          keyFinder,
          100.0,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.pumpAndSettle();
      }
      if (keyFinder.evaluate().isEmpty) {
        await tester.scrollUntilVisible(
          keyFinder,
          -100.0,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.pumpAndSettle();
      }
      final itemFinder = keyFinder.last;
      await tester.ensureVisible(itemFinder);
      await tester.pumpAndSettle();
      await tester.tap(itemFinder);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    testWidgets(
      'MS-60B+ omits Cabinet, isolates Preamp vs Amps (11 each), and Modulation shows 0 amp models',
      (tester) async {
        await pumpPalette(
          tester,
          family: DeviceFamily.zoomMs60bPlus,
          size: const Size(300, 500),
        );

        final dropdownWidget = tester.widget<DropdownButton<String>>(
          find.byKey(const Key('palette_category_dropdown')),
        );
        expect(
          dropdownWidget.items!.map((item) => item.value).toList(),
          equals([
            'All',
            ...EffectCatalogRegistry.getCategories(DeviceFamily.zoomMs60bPlus),
          ]),
        );

        await tester.tap(find.byKey(const Key('palette_category_dropdown')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('palette_category_item_Cabinet')), findsNothing);
        for (final cat in EffectCatalogRegistry.getCategories(DeviceFamily.zoomMs60bPlus)) {
          final itemFinder = find.byKey(Key('palette_category_item_$cat'));
          if (itemFinder.evaluate().isEmpty) {
            await tester.scrollUntilVisible(
              itemFinder,
              100.0,
              scrollable: find.byType(Scrollable).last,
            );
            await tester.pumpAndSettle();
          }
          expect(itemFinder, findsWidgets);
        }

        // Select Modulation
        final modKeyFinder = find.byKey(const Key('palette_category_item_Modulation'));
        if (modKeyFinder.evaluate().isEmpty) {
          await tester.scrollUntilVisible(
            modKeyFinder,
            -100.0,
            scrollable: find.byType(Scrollable).last,
          );
          await tester.pumpAndSettle();
        }
        final modItem = modKeyFinder.last;
        await tester.ensureVisible(modItem);
        await tester.tap(modItem);
        await tester.pumpAndSettle();

        expect(find.text('11 EFFECTS'), findsOneWidget);
        expect(find.byKey(const Key('palette_click_0x05000020')), findsNothing); // AMPG SVT
        expect(find.byKey(const Key('palette_click_0x06000010')), findsOneWidget); // CloneCho

        // Preamp and Amps are separate 11-item categories
        await selectPaletteCategory(tester, 'Preamp');
        expect(find.text('11 EFFECTS'), findsOneWidget);
        expect(find.byKey(const Key('palette_click_0x04000010')), findsOneWidget); // Bass DRV
        expect(find.byKey(const Key('palette_click_0x05000020')), findsNothing);

        await selectPaletteCategory(tester, 'Amps');
        expect(find.text('11 EFFECTS'), findsOneWidget);
        expect(find.byKey(const Key('palette_click_0x05000020')), findsOneWidget); // AMPG SVT
        expect(find.byKey(const Key('palette_click_0x04000010')), findsNothing);

        // SFX includes BPM (0x07000FF0)
        await selectPaletteCategory(tester, 'SFX');
        expect(find.text('6 EFFECTS'), findsOneWidget);
        expect(find.byKey(const Key('palette_click_0x07000FF0')), findsOneWidget);
      },
    );

    testWidgets(
      'MS-50G+, MS-200D+, and Line 6 Bass POD Pro show non-empty dynamic categories and never leak Amp Model into Modulation',
      (tester) async {
        for (final family in const [
          DeviceFamily.zoomMs50gPlus,
          DeviceFamily.zoomMs200dPlus,
          DeviceFamily.line6BassPodPro,
        ]) {
          await pumpPalette(tester, family: family);
          final cats = EffectCatalogRegistry.getCategories(family);
          final allEffects = EffectCatalogRegistry.getEffectsForFamily(family);
          final ampIds = allEffects
              .where((e) => e.category == 'Amp Model')
              .map((e) => e.effectId)
              .toSet();

          for (final cat in cats) {
            await selectPaletteCategory(tester, cat);
            final expectedEffects = allEffects
                .where((e) => e.category.toLowerCase() == cat.toLowerCase())
                .toList();
            expect(expectedEffects, isNotEmpty);
            expect(
              find.text('${expectedEffects.length} EFFECTS'),
              findsOneWidget,
              reason: '${family.displayName} category "$cat" should show exact count',
            );
            expect(find.text('No matching effects found'), findsNothing);

            if (cat == 'Modulation') {
              for (final ampId in ampIds) {
                expect(
                  find.byKey(Key('palette_click_$ampId')),
                  findsNothing,
                  reason: '${family.displayName} Modulation must not include Amp Model $ampId',
                );
              }
            }
          }
        }
      },
    );

    testWidgets(
      'Zoom B1X FOUR exposes Cabinet and Pedal categories with their exact effects',
      (tester) async {
        await pumpPalette(tester, family: DeviceFamily.zoomB1xFour);

        await selectPaletteCategory(tester, 'Cabinet');
        expect(find.text('10 EFFECTS'), findsOneWidget);
        expect(find.byKey(const Key('palette_click_0x05800010')), findsOneWidget); // SVT8x10

        await selectPaletteCategory(tester, 'Pedal');
        expect(find.text('6 EFFECTS'), findsOneWidget);
        expect(find.byKey(const Key('palette_click_0x0b000010')), findsOneWidget); // PDL Vol
      },
    );

    testWidgets(
      'switching deviceFamily resets unsupported selected category to All and preserves shared categories',
      (tester) async {
        final handles = await pumpPalette(tester, family: DeviceFamily.zoomMs60bPlus);

        // Select MS-60B+ exclusive 'Preamp'
        await selectPaletteCategory(tester, 'Preamp');
        expect(find.text('11 EFFECTS'), findsOneWidget);

        // Switch to B1X FOUR (no Preamp) -> resets cleanly to 'All'
        handles.connection.selectDeviceFamily(DeviceFamily.zoomB1xFour);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        expect(
          find.descendant(
            of: find.byKey(const Key('palette_category_dropdown')),
            matching: find.text('All'),
          ),
          findsOneWidget,
        );
        expect(find.text('99 EFFECTS'), findsOneWidget);

        // Select shared 'Delay' on B1X FOUR (6 effects), switch to MS-60B+ -> stays on 'Delay' (7 effects)
        await selectPaletteCategory(tester, 'Delay');
        expect(find.text('6 EFFECTS'), findsOneWidget);

        handles.connection.selectDeviceFamily(DeviceFamily.zoomMs60bPlus);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        expect(
          find.descendant(
            of: find.byKey(const Key('palette_category_dropdown')),
            matching: find.text('Delay'),
          ),
          findsOneWidget,
        );
        expect(find.text('7 EFFECTS'), findsOneWidget);
      },
    );
  });

  group('Phase 1.3: StudioTheme.getCategoryColor Hardening', () {
    test('returns non-fallback colors for all MS-60B+, Zoom Four, Line 6, and Custom categories', () {
      const activeCategories = [
        'Dynamics',
        'Filter',
        'Overdrive/Distortion',
        'Preamp',
        'Amps',
        'Modulation',
        'Pitch',
        'Synths',
        'SFX',
        'Delay',
        'Reverb',
        'Cabinet',
        'Pedal',
        'Amp Model',
        'Filter / Synth',
        'Custom',
      ];

      for (final category in activeCategories) {
        final color = StudioTheme.getCategoryColor(category);
        expect(
          color,
          isNot(equals(StudioTheme.colorBypass)),
          reason: '"$category" should map to an accent color, not grey fallback',
        );
      }

      // Amps and Amp Model never collide with Modulation
      expect(StudioTheme.getCategoryColor('Amps'), equals(StudioTheme.colorAmpCab));
      expect(StudioTheme.getCategoryColor('Amp Model'), equals(StudioTheme.colorAmpCab));
      expect(StudioTheme.getCategoryColor('Amps'), isNot(equals(StudioTheme.colorModulation)));
      expect(StudioTheme.getCategoryColor('Amp Model'), isNot(equals(StudioTheme.colorModulation)));

      // Preamp has dedicated styling distinct from Amps
      expect(StudioTheme.getCategoryColor('Preamp'), equals(StudioTheme.colorPreamp));
      expect(
        StudioTheme.getCategoryColor('Preamp'),
        isNot(equals(StudioTheme.getCategoryColor('Amps'))),
      );

      // Pitch, Synths, and SFX have explicit accent colors
      expect(StudioTheme.getCategoryColor('Pitch'), equals(StudioTheme.colorPitchSynth));
      expect(StudioTheme.getCategoryColor('Synths'), equals(StudioTheme.colorPitchSynth));
      expect(StudioTheme.getCategoryColor('SFX'), equals(StudioTheme.colorSfx));

      // Bypass and Unknown use neutral fallback
      expect(StudioTheme.getCategoryColor('Bypass'), equals(StudioTheme.colorBypass));
      expect(StudioTheme.getCategoryColor('Unknown'), equals(StudioTheme.colorBypass));
    });
  });

  group('Phase 1.4: ZoomZdl7MasterCatalog Category Mapping Fixes', () {
    test('reports accurate non-shifted categories for ZDL7 0x..09 / 0x..89 IDs', () {
      const spotChecks = <String, ({String name, String category})>{
        '0x04890011': (name: 'Bass DRV', category: 'Preamp'),
        '0x04890070': (name: 'Pre1073', category: 'Preamp'),
        '0x04898030': (name: 'DjentPre', category: 'Preamp'),
        '0x05890011': (name: 'AMPG SVT', category: 'Amp'),
        '0x05890091': (name: 'FlipTop', category: 'Amp'),
        '0x05890110': (name: 'Monotone', category: 'Amp'),
        '0x06890010': (name: 'SVT8x10', category: 'Cabinet'),
        '0x06890060': (name: 'AC1x18', category: 'Cabinet'),
        '0x06890110': (name: 'MT1x15', category: 'Cabinet'),
        '0x07090010': (name: 'Tremolo', category: 'Modulation'),
        '0x070900b0': (name: 'PitchSHFT', category: 'Modulation'),
        '0x07090130': (name: 'CoronaTri', category: 'Modulation'),
        '0x07890020': (name: 'BassStCho', category: 'Modulation'),
        '0x07890050': (name: 'Ba Octave', category: 'Modulation'),
        '0x07890080': (name: 'BassPhase', category: 'Modulation'),
        '0x08090010': (name: 'Bomber', category: 'SFX'),
        '0x08090040': (name: 'LoopRoll', category: 'SFX'),
        '0x08890010': (name: 'BaStdSyn', category: 'SFX'),
        '0x08890110': (name: 'Defret', category: 'SFX'),
        '0x08890120': (name: 'PH+Dist', category: 'SFX'),
        '0x09090010': (name: 'Delay', category: 'Delay'),
        '0x09090030': (name: 'TapeEcho', category: 'Delay'),
        '0x090900a1': (name: 'Dual DLY', category: 'Delay'),
        '0x0a090010': (name: 'Air', category: 'Reverb'),
        '0x0a090070': (name: 'Plate', category: 'Reverb'),
        '0x0b890010': (name: 'BassWah', category: 'Pedal'),
      };

      for (final MapEntry(:key, :value) in spotChecks.entries) {
        final entry = ZoomZdl7MasterCatalog.entries[key];
        expect(entry, isNotNull, reason: 'Missing $key');
        expect(entry!.name, equals(value.name));
        expect(entry.category, equals(value.category));

        final resolved = EffectCatalogRegistry.getDefinition(
          DeviceFamily.zoomB1xFour,
          key,
        );
        expect(resolved.name, equals(value.name));
        expect(resolved.category, equals(value.category));
      }

      // Guard against any remaining shifted entries across entire master table
      for (final MapEntry(:key, :value) in ZoomZdl7MasterCatalog.entries.entries) {
        if (key.startsWith('0x0489')) expect(value.category, equals('Preamp'));
        if (key.startsWith('0x0589')) expect(value.category, equals('Amp'));
        if (key.startsWith('0x0689')) expect(value.category, equals('Cabinet'));
        if (key.startsWith('0x0709') || key.startsWith('0x0789')) {
          expect(value.category, equals('Modulation'));
        }
        if (key.startsWith('0x0809') || key.startsWith('0x0889')) {
          expect(value.category, equals('SFX'));
        }
        if (key.startsWith('0x0909')) expect(value.category, equals('Delay'));
      }
    });
  });
}

