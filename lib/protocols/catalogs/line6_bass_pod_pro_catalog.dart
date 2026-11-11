import '../../models/device_family.dart';
import '../../models/parameter_descriptor.dart';
import 'effect_catalog.dart';

/// Built-in effect and model catalog for the Line 6 Bass Pod Pro rackmount processor.
class Line6BassPodProCatalog {
  static const List<String> ampModels = [
    'Tube Preamp',
    'Classic (SVT)',
    'Brit Major (Marshall Major)',
    'Silver Panel (Bassman)',
    'Session (Eden WT-800)',
    'California (Mesa 400+)',
    'Submaster (SWR SM-400)',
    'Rock Classic (Ampeg SVT)',
    'Modern Class (SWR)',
    'British Class (Vox AC-100)',
    'Stadium (Sunn Coliseum)',
    'Motor City (B-15)',
    'Fuzz Bass',
    'Sub Synth',
    'Double Dynamic',
    'Bypass',
  ];

  static const List<String> cabModels = [
    '1x12 1964 Flip Top',
    '1x15 1968 Sunn',
    '2x10 1998 Modern',
    '2x15 1972 California',
    '4x10 1995 Line 6 custom',
    '4x12 1967 British',
    '8x10 1974 Classic',
    'No Cabinet',
  ];

  static const List<String> effectTypes = [
    'Bypass',
    'Chorus',
    'Flanger',
    'Rotary Speaker',
    'Envelope Follower',
    'Octaver',
    'Delay',
    'Tremolo',
  ];

  /// Standard Amp block parameter descriptors.
  static const List<ParameterDescriptor> ampParameters = [
    ParameterDescriptor(
      id: 'drive',
      name: 'Drive',
      min: 0,
      max: 127,
      defaultValue: 64,
    ),
    ParameterDescriptor(
      id: 'bass',
      name: 'Bass',
      min: 0,
      max: 127,
      defaultValue: 64,
    ),
    ParameterDescriptor(
      id: 'mid',
      name: 'Mid',
      min: 0,
      max: 127,
      defaultValue: 64,
    ),
    ParameterDescriptor(
      id: 'treble',
      name: 'Treble',
      min: 0,
      max: 127,
      defaultValue: 64,
    ),
    ParameterDescriptor(
      id: 'channel_volume',
      name: 'Channel Volume',
      min: 0,
      max: 127,
      defaultValue: 100,
    ),
  ];

  /// Standard Cabinet block parameter descriptors.
  static const List<ParameterDescriptor> cabParameters = [
    ParameterDescriptor(
      id: 'cabinet_model',
      name: 'Cabinet Model',
      min: 0,
      max: 7,
      defaultValue: 0,
      labels: cabModels,
    ),
  ];

  /// Standard Compressor block parameter descriptors.
  static const List<ParameterDescriptor> compressorParameters = [
    ParameterDescriptor(
      id: 'threshold',
      name: 'Threshold / Ratio',
      min: 0,
      max: 127,
      defaultValue: 64,
    ),
    ParameterDescriptor(
      id: 'enabled',
      name: 'Compressor State',
      min: 0,
      max: 1,
      defaultValue: 1,
      labels: ['Off', 'On'],
    ),
  ];

  /// Standard Modulation / FX block parameter descriptors.
  static const List<ParameterDescriptor> fxParameters = [
    ParameterDescriptor(
      id: 'tweak',
      name: 'Tweak',
      min: 0,
      max: 127,
      defaultValue: 64,
    ),
    ParameterDescriptor(
      id: 'fx_type',
      name: 'Effect Type',
      min: 0,
      max: 7,
      defaultValue: 0,
      labels: effectTypes,
    ),
  ];

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

    // 8 Cabinet Models
    for (int i = 0; i < cabModels.length; i++) {
      list.add(EffectDefinition(
        effectId: 'line6_cab_$i',
        name: cabModels[i],
        category: 'Cabinet',
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

    // 8 Effect Types
    for (int i = 0; i < effectTypes.length; i++) {
      list.add(EffectDefinition(
        effectId: 'line6_fx_$i',
        name: effectTypes[i],
        category: i == 6 ? 'Delay' : (i == 0 ? 'Bypass' : 'Modulation'),
        deviceFamily: DeviceFamily.line6BassPodPro,
        parameters: fxParameters,
      ));
    }

    return list;
  }
}
