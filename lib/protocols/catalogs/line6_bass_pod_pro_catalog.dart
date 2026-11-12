import '../../models/device_family.dart';
import '../../models/parameter_descriptor.dart';
import 'effect_catalog.dart';

/// Built-in effect and model catalog for the Line 6 Bass Pod Pro rackmount processor.
class Line6BassPodProCatalog {
  /// 16 Bass Amp Models from the Line 6 Bass POD Pro hardware specification.
  static const List<String> ampModels = [
    'Tube Preamp',
    'Session',
    'California',
    'Jazz Tone',
    'Adam & Eve',
    'Eighties',
    'Stadium',
    'Amp 360',
    'Rock Classic',
    'Brit Major',
    'Brit Super',
    'Silver Panel',
    'Brit Class A',
    'Motor City',
    'Flip Top',
    'Sub Dub',
  ];

  /// 16 Cabinet Models (index 10 is Bypass).
  static const List<String> cabModels = [
    '4x10 Hartke',
    '1x12 Versatone Pan-O-Flex',
    '1x15 Ampeg B-15',
    '4x12 Marshall 1967 w/Celestions',
    '2x15 Fender Bassman w/JBLs',
    '2x15 Mesa Boogie',
    '1x15 Polytone Mini-Brute',
    '2x15 Vox AC-100',
    '4x10 SWR Goliath',
    '4x10 Eden',
    'Bypass',
    '8x10 Ampeg SVT',
    '4x15 1976 Marshall',
    '1x18 SWR Big Ben',
    '1x12-1x18 Sunn Coliseum 8028',
    '1x18 Acoustic 360',
  ];

  /// 16 Built-in Effect Models (index 10 is Bypass).
  static const List<String> effectTypes = [
    'Orange Phase',
    'Gray Flanger',
    'Tron Up',
    'Tron Down',
    'Bass Synth',
    'S/H + Driver',
    'S/H',
    'S/H + Flanger',
    'Danish Chorus',
    'Analog Chorus',
    'Bypass',
    'Octave Down',
    'Danish Driver',
    'Large Pie',
    'Rodent',
    'Pig Foot',
  ];

  /// Standard Amp block parameter descriptors.
  static const List<ParameterDescriptor> ampParameters = [
    ParameterDescriptor(
      id: 'drive',
      name: 'Drive',
      min: 0,
      max: 126,
      defaultValue: 64,
      step: 2,
    ),
    ParameterDescriptor(
      id: 'bass',
      name: 'Bass',
      min: 0,
      max: 126,
      defaultValue: 64,
      step: 2,
    ),
    ParameterDescriptor(
      id: 'mid',
      name: 'Mid',
      min: 0,
      max: 126,
      defaultValue: 64,
      step: 2,
    ),
    ParameterDescriptor(
      id: 'treble',
      name: 'Treble',
      min: 0,
      max: 126,
      defaultValue: 64,
      step: 2,
    ),
    ParameterDescriptor(
      id: 'channel_volume',
      name: 'Channel Volume',
      min: 0,
      max: 126,
      defaultValue: 100,
      step: 2,
    ),
  ];

  /// Standard Cabinet block parameter descriptors.
  static const List<ParameterDescriptor> cabParameters = [
    ParameterDescriptor(
      id: 'cabinet_model',
      name: 'Cabinet Model',
      min: 0,
      max: 15,
      defaultValue: 0,
      labels: cabModels,
    ),
    ParameterDescriptor(
      id: 'air_level',
      name: 'A.I.R. Level',
      min: 0,
      max: 126,
      defaultValue: 0,
      step: 2,
    ),
  ];

  /// Standard Compressor block parameter descriptors.
  static const List<ParameterDescriptor> compressorParameters = [
    ParameterDescriptor(
      id: 'threshold',
      name: 'Compress',
      min: 0,
      max: 126,
      defaultValue: 0,
      step: 2,
    ),
    ParameterDescriptor(
      id: 'enabled',
      name: 'Noise Gate',
      min: 0,
      max: 1,
      defaultValue: 0,
      labels: ['Off', 'On'],
    ),
  ];

  /// Standard Modulation / FX block parameter descriptors.
  static const List<ParameterDescriptor> fxParameters = [
    ParameterDescriptor(
      id: 'tweak',
      name: 'Tweak',
      min: 0,
      max: 126,
      defaultValue: 64,
      step: 2,
    ),
    ParameterDescriptor(
      id: 'fx_type',
      name: 'Effect Type',
      min: 0,
      max: 15,
      defaultValue: 10,
      labels: effectTypes,
    ),
    ParameterDescriptor(
      id: 'fx_lo_cut',
      name: 'FX Lo Cut',
      min: 0,
      max: 126,
      defaultValue: 0,
      step: 2,
    ),
  ];

  static String _fxCategory(int index) {
    if (index == 10) return 'Bypass';
    if (index <= 1) return 'Modulation';
    if (index <= 7) return 'Filter / Synth';
    if (index <= 9) return 'Modulation';
    if (index == 11) return 'Pitch';
    return 'Drive / Fuzz';
  }

  /// Complete list of built-in [EffectDefinition]s for Line 6 Bass Pod Pro.
  static List<EffectDefinition> get builtInEffects {
    final list = <EffectDefinition>[];

    // 16 Amp Models
    for (int i = 0; i < ampModels.length; i++) {
      list.add(EffectDefinition(
        effectId: 'line6_amp_$i',
        name: ampModels[i],
        category: 'Amp Model',
        deviceFamily: DeviceFamily.line6BassPodPro,
        parameters: ampParameters,
      ));
    }

    // 16 Cabinet Models
    for (int i = 0; i < cabModels.length; i++) {
      list.add(EffectDefinition(
        effectId: 'line6_cab_$i',
        name: cabModels[i],
        category: i == 10 ? 'Bypass' : 'Cabinet',
        deviceFamily: DeviceFamily.line6BassPodPro,
        parameters: cabParameters,
      ));
    }

    // Compressor
    list.add(const EffectDefinition(
      effectId: 'line6_comp',
      name: 'Compressor',
      category: 'Dynamics',
      deviceFamily: DeviceFamily.line6BassPodPro,
      parameters: compressorParameters,
    ));
    list.add(const EffectDefinition(
      effectId: 'line6_compressor',
      name: 'Compressor',
      category: 'Dynamics',
      deviceFamily: DeviceFamily.line6BassPodPro,
      parameters: compressorParameters,
    ));

    // 16 Effect Types
    for (int i = 0; i < effectTypes.length; i++) {
      list.add(EffectDefinition(
        effectId: 'line6_fx_$i',
        name: effectTypes[i],
        category: _fxCategory(i),
        deviceFamily: DeviceFamily.line6BassPodPro,
        parameters: fxParameters,
      ));
    }

    return list;
  }
}
