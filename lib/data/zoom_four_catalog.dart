import '../models/device_family.dart';
import '../models/parameter_descriptor.dart';
import '../protocols/catalogs/effect_catalog.dart';

/// Built-in effect definitions for the **Zoom B1X FOUR** (`DeviceFamily.zoomB1xFour`).
///
/// Generated from authoritative ZDL7 hardware tables (`tool/reference/zoom-b1x-four-list.txt`)
/// covering all 99 B1X FOUR effects (93 shared with B1 FOUR + 6 Pedal effects).
const List<EffectDefinition> zoomB1xFourCatalogData = [
  // SLWATK.ZD2
  EffectDefinition(
    effectId: '0x01000030',
    name: 'SlowATTCK',
    category: 'Dynamics',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 5,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Time', min: 1, max: 50, defaultValue: 15),
      ParameterDescriptor(id: 'param_1', name: 'Curve', min: 0, max: 10, defaultValue: 5),
      ParameterDescriptor(id: 'param_2', name: 'Level', min: 0, max: 100, defaultValue: 80),
    ],
  ),
  // ZNR.ZD2
  EffectDefinition(
    effectId: '0x01000040',
    name: 'ZNR',
    category: 'Dynamics',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 4,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Thrsh', min: 0, max: 100, defaultValue: 25),
      ParameterDescriptor(id: 'param_1', name: 'Detct', min: 0, max: 1, defaultValue: 0, labels: ['EfxIn', 'GtIn']),
      ParameterDescriptor(id: 'param_2', name: 'Level', min: 0, max: 100, defaultValue: 100),
    ],
  ),
  // OPTCOMP.ZD2
  EffectDefinition(
    effectId: '0x01000080',
    name: 'OptComp',
    category: 'Dynamics',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 13,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Comp', min: 0, max: 10, defaultValue: 5),
      ParameterDescriptor(id: 'param_1', name: 'Lo', min: -12, max: 12, defaultValue: 0, unit: 'dB'),
      ParameterDescriptor(id: 'param_2', name: 'Hi', min: -12, max: 12, defaultValue: 2, unit: 'dB'),
      ParameterDescriptor(id: 'param_3', name: 'Vol', min: 0, max: 100, defaultValue: 75),
    ],
  ),
  // BLACKOPT.ZD2
  EffectDefinition(
    effectId: '0x01800010',
    name: 'BlackOpt',
    category: 'Dynamics',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 14,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Comp', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_1', name: 'Tone', min: 0, max: 10, defaultValue: 5),
      ParameterDescriptor(id: 'param_2', name: 'Vol', min: 0, max: 100, defaultValue: 75),
    ],
  ),
  // LMT1176.ZD2
  EffectDefinition(
    effectId: '0x01800020',
    name: 'LMT-76',
    category: 'Dynamics',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 13,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Comp', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_1', name: 'Tone', min: 0, max: 10, defaultValue: 5),
      ParameterDescriptor(id: 'param_2', name: 'Vol', min: 0, max: 100, defaultValue: 75),
    ],
  ),
  // 160_COMP.ZD2
  EffectDefinition(
    effectId: '0x01800030',
    name: '160 Comp',
    category: 'Dynamics',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 13,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Thrsh', min: -60, max: 0, defaultValue: -20, unit: 'dB'),
      ParameterDescriptor(id: 'param_1', name: 'Ratio', min: 1, max: 20, defaultValue: 4, unit: ':1'),
      ParameterDescriptor(id: 'param_2', name: 'Gain', min: 0, max: 20, defaultValue: 6, unit: 'dB'),
      ParameterDescriptor(id: 'param_3', name: 'Knee', min: 0, max: 1, defaultValue: 0, labels: ['Hard', 'OverEasy']),
    ],
  ),
  // DUAL_CMP.ZD2
  EffectDefinition(
    effectId: '0x01800040',
    name: 'DualComp',
    category: 'Dynamics',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 8,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Lo', min: 0, max: 100, defaultValue: 45),
      ParameterDescriptor(id: 'param_1', name: 'Hi', min: 0, max: 100, defaultValue: 40),
      ParameterDescriptor(id: 'param_2', name: 'Tone', min: 0, max: 10, defaultValue: 5),
      ParameterDescriptor(id: 'param_3', name: 'Vol', min: 0, max: 100, defaultValue: 75),
    ],
  ),
  // MB_COMP.ZD2
  EffectDefinition(
    effectId: '0x01800050',
    name: 'MB Comp',
    category: 'Dynamics',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 21,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Comp', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_1', name: 'Tone', min: 0, max: 10, defaultValue: 5),
      ParameterDescriptor(id: 'param_2', name: 'Vol', min: 0, max: 100, defaultValue: 75),
    ],
  ),
  // DCOMP.ZD2
  EffectDefinition(
    effectId: '0x01800060',
    name: 'DYN Comp',
    category: 'Dynamics',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 6,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Comp', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_1', name: 'Tone', min: 0, max: 10, defaultValue: 5),
      ParameterDescriptor(id: 'param_2', name: 'Vol', min: 0, max: 100, defaultValue: 75),
    ],
  ),
  // GLAMCOMP.ZD2
  EffectDefinition(
    effectId: '0x01800070',
    name: 'Glam Comp',
    category: 'Dynamics',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 13,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Comp', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_1', name: 'Tone', min: 0, max: 10, defaultValue: 5),
      ParameterDescriptor(id: 'param_2', name: 'Vol', min: 0, max: 100, defaultValue: 75),
    ],
  ),
  // SEQFLTR.ZD2
  EffectDefinition(
    effectId: '0x02000040',
    name: 'SeqFLTR',
    category: 'Filter',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 9,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Freq', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_1', name: 'Reso', min: 0, max: 10, defaultValue: 5),
      ParameterDescriptor(id: 'param_2', name: 'Mix', min: 0, max: 100, defaultValue: 60),
      ParameterDescriptor(id: 'param_3', name: 'Level', min: 0, max: 100, defaultValue: 80),
    ],
  ),
  // EXCITER.ZD2
  EffectDefinition(
    effectId: '0x020000b0',
    name: 'Exciter',
    category: 'Filter',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 9,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Freq', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_1', name: 'Reso', min: 0, max: 10, defaultValue: 5),
      ParameterDescriptor(id: 'param_2', name: 'Mix', min: 0, max: 100, defaultValue: 60),
      ParameterDescriptor(id: 'param_3', name: 'Level', min: 0, max: 100, defaultValue: 80),
    ],
  ),
  // B_ATWAH.ZD2
  EffectDefinition(
    effectId: '0x02800010',
    name: 'BassA-Wah',
    category: 'Filter',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 7,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Freq', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_1', name: 'Reso', min: 0, max: 10, defaultValue: 5),
      ParameterDescriptor(id: 'param_2', name: 'Mix', min: 0, max: 100, defaultValue: 60),
      ParameterDescriptor(id: 'param_3', name: 'Level', min: 0, max: 100, defaultValue: 80),
    ],
  ),
  // Z_TRON.ZD2
  EffectDefinition(
    effectId: '0x02800020',
    name: 'Z Tron',
    category: 'Filter',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 6,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Freq', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_1', name: 'Reso', min: 0, max: 10, defaultValue: 5),
      ParameterDescriptor(id: 'param_2', name: 'Mix', min: 0, max: 100, defaultValue: 60),
      ParameterDescriptor(id: 'param_3', name: 'Level', min: 0, max: 100, defaultValue: 80),
    ],
  ),
  // A_FILTER.ZD2
  EffectDefinition(
    effectId: '0x02800030',
    name: 'A-Filter',
    category: 'Filter',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 7,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Freq', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_1', name: 'Reso', min: 0, max: 10, defaultValue: 5),
      ParameterDescriptor(id: 'param_2', name: 'Mix', min: 0, max: 100, defaultValue: 60),
      ParameterDescriptor(id: 'param_3', name: 'Level', min: 0, max: 100, defaultValue: 80),
    ],
  ),
  // BA_CRY.ZD2
  EffectDefinition(
    effectId: '0x02800040',
    name: 'Bass Cry',
    category: 'Filter',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 10,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Freq', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_1', name: 'Reso', min: 0, max: 10, defaultValue: 5),
      ParameterDescriptor(id: 'param_2', name: 'Mix', min: 0, max: 100, defaultValue: 60),
      ParameterDescriptor(id: 'param_3', name: 'Level', min: 0, max: 100, defaultValue: 80),
    ],
  ),
  // BA_GEQ1U.ZD2
  EffectDefinition(
    effectId: '0x02800051',
    name: 'BassGEQ',
    category: 'Filter',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 5,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Freq', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_1', name: 'Reso', min: 0, max: 10, defaultValue: 5),
      ParameterDescriptor(id: 'param_2', name: 'Mix', min: 0, max: 100, defaultValue: 60),
      ParameterDescriptor(id: 'param_3', name: 'Level', min: 0, max: 100, defaultValue: 80),
    ],
  ),
  // STBGEQ1U.ZD2
  EffectDefinition(
    effectId: '0x02800061',
    name: 'St Ba GEQ',
    category: 'Filter',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 7,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Freq', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_1', name: 'Reso', min: 0, max: 10, defaultValue: 5),
      ParameterDescriptor(id: 'param_2', name: 'Mix', min: 0, max: 100, defaultValue: 60),
      ParameterDescriptor(id: 'param_3', name: 'Level', min: 0, max: 100, defaultValue: 80),
    ],
  ),
  // BA_PEQ.ZD2
  EffectDefinition(
    effectId: '0x02800070',
    name: 'BassPEQ',
    category: 'Filter',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 4,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Freq', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_1', name: 'Reso', min: 0, max: 10, defaultValue: 5),
      ParameterDescriptor(id: 'param_2', name: 'Mix', min: 0, max: 100, defaultValue: 60),
      ParameterDescriptor(id: 'param_3', name: 'Level', min: 0, max: 100, defaultValue: 80),
    ],
  ),
  // SPLITTER.ZD2
  EffectDefinition(
    effectId: '0x02800080',
    name: 'Splitter',
    category: 'Filter',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 6,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Freq', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_1', name: 'Reso', min: 0, max: 10, defaultValue: 5),
      ParameterDescriptor(id: 'param_2', name: 'Mix', min: 0, max: 100, defaultValue: 60),
      ParameterDescriptor(id: 'param_3', name: 'Level', min: 0, max: 100, defaultValue: 80),
    ],
  ),
  // LOW_EQ.ZD2
  EffectDefinition(
    effectId: '0x02800090',
    name: 'Low EQ',
    category: 'Filter',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 4,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Freq', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_1', name: 'Reso', min: 0, max: 10, defaultValue: 5),
      ParameterDescriptor(id: 'param_2', name: 'Mix', min: 0, max: 100, defaultValue: 60),
      ParameterDescriptor(id: 'param_3', name: 'Level', min: 0, max: 100, defaultValue: 80),
    ],
  ),
  // HIGH_EQ.ZD2
  EffectDefinition(
    effectId: '0x02800095',
    name: 'High EQ',
    category: 'Filter',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 3,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Freq', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_1', name: 'Reso', min: 0, max: 10, defaultValue: 5),
      ParameterDescriptor(id: 'param_2', name: 'Mix', min: 0, max: 100, defaultValue: 60),
      ParameterDescriptor(id: 'param_3', name: 'Level', min: 0, max: 100, defaultValue: 80),
    ],
  ),
  // ENV_FLTR.ZD2
  EffectDefinition(
    effectId: '0x028000a0',
    name: 'EnvFilter',
    category: 'Filter',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 13,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Freq', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_1', name: 'Reso', min: 0, max: 10, defaultValue: 5),
      ParameterDescriptor(id: 'param_2', name: 'Mix', min: 0, max: 100, defaultValue: 60),
      ParameterDescriptor(id: 'param_3', name: 'Level', min: 0, max: 100, defaultValue: 80),
    ],
  ),
  // EP_STOMP.ZD2
  EffectDefinition(
    effectId: '0x03000020',
    name: 'EP Stomp',
    category: 'Overdrive / Distortion',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 13,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Gain', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_1', name: 'Tone', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_2', name: 'Blend', min: 0, max: 100, defaultValue: 60),
      ParameterDescriptor(id: 'param_3', name: 'Vol', min: 0, max: 100, defaultValue: 70),
    ],
  ),
  // RCBOOST.ZD2
  EffectDefinition(
    effectId: '0x03000030',
    name: 'RC Boost',
    category: 'Overdrive / Distortion',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 15,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Gain', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_1', name: 'Tone', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_2', name: 'Blend', min: 0, max: 100, defaultValue: 60),
      ParameterDescriptor(id: 'param_3', name: 'Vol', min: 0, max: 100, defaultValue: 70),
    ],
  ),
  // NYC_MUFF.ZD2
  EffectDefinition(
    effectId: '0x030000d0',
    name: 'NYC Muff',
    category: 'Overdrive / Distortion',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 14,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Gain', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_1', name: 'Tone', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_2', name: 'Blend', min: 0, max: 100, defaultValue: 60),
      ParameterDescriptor(id: 'param_3', name: 'Vol', min: 0, max: 100, defaultValue: 70),
    ],
  ),
  // SQUEAK.ZD2
  EffectDefinition(
    effectId: '0x03000130',
    name: 'Squeak',
    category: 'Overdrive / Distortion',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 13,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Gain', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_1', name: 'Tone', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_2', name: 'Blend', min: 0, max: 100, defaultValue: 60),
      ParameterDescriptor(id: 'param_3', name: 'Vol', min: 0, max: 100, defaultValue: 70),
    ],
  ),
  // BA_DRV1U.ZD2
  EffectDefinition(
    effectId: '0x03800011',
    name: 'Bass DRV',
    category: 'Overdrive / Distortion',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 15,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Level', min: 0, max: 100, defaultValue: 65),
      ParameterDescriptor(id: 'param_1', name: 'Blend', min: 0, max: 100, defaultValue: 70),
      ParameterDescriptor(id: 'param_2', name: 'Drive', min: 0, max: 100, defaultValue: 45),
      ParameterDescriptor(id: 'param_3', name: 'Bass', min: -12, max: 12, defaultValue: 2, unit: 'dB'),
      ParameterDescriptor(id: 'param_4', name: 'Trebl', min: -12, max: 12, defaultValue: 2, unit: 'dB'),
      ParameterDescriptor(id: 'param_5', name: 'Pres', min: 0, max: 100, defaultValue: 50),
    ],
  ),
  // DIPLUS1U.ZD2
  EffectDefinition(
    effectId: '0x03800021',
    name: 'D.I Plus',
    category: 'Overdrive / Distortion',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 15,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Vol', min: 0, max: 100, defaultValue: 70),
      ParameterDescriptor(id: 'param_1', name: 'Blend', min: 0, max: 100, defaultValue: 65),
      ParameterDescriptor(id: 'param_2', name: 'Gain', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_3', name: 'Bass', min: -12, max: 12, defaultValue: 2, unit: 'dB'),
      ParameterDescriptor(id: 'param_4', name: 'Mid', min: -12, max: 12, defaultValue: 0, unit: 'dB'),
      ParameterDescriptor(id: 'param_5', name: 'Trebl', min: -12, max: 12, defaultValue: 2, unit: 'dB'),
    ],
  ),
  // DRKPRE1U.ZD2
  EffectDefinition(
    effectId: '0x03800031',
    name: 'Dark Pre',
    category: 'Overdrive / Distortion',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 25,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Level', min: 0, max: 100, defaultValue: 65),
      ParameterDescriptor(id: 'param_1', name: 'Blend', min: 0, max: 100, defaultValue: 60),
      ParameterDescriptor(id: 'param_2', name: 'Drive', min: 0, max: 100, defaultValue: 55),
      ParameterDescriptor(id: 'param_3', name: 'Bass', min: -12, max: 12, defaultValue: 2, unit: 'dB'),
      ParameterDescriptor(id: 'param_4', name: 'LoMid', min: -12, max: 12, defaultValue: 0, unit: 'dB'),
      ParameterDescriptor(id: 'param_5', name: 'HiMid', min: -12, max: 12, defaultValue: 2, unit: 'dB'),
      ParameterDescriptor(id: 'param_6', name: 'Trebl', min: -12, max: 12, defaultValue: 1, unit: 'dB'),
    ],
  ),
  // BASS_BB.ZD2
  EffectDefinition(
    effectId: '0x03800040',
    name: 'Bass BB',
    category: 'Overdrive / Distortion',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 14,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Gain', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_1', name: 'Tone', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_2', name: 'Blend', min: 0, max: 100, defaultValue: 60),
      ParameterDescriptor(id: 'param_3', name: 'Vol', min: 0, max: 100, defaultValue: 70),
    ],
  ),
  // DI5.ZD2
  EffectDefinition(
    effectId: '0x03800050',
    name: 'DI-5',
    category: 'Overdrive / Distortion',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 17,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Gain', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_1', name: 'Tone', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_2', name: 'Blend', min: 0, max: 100, defaultValue: 60),
      ParameterDescriptor(id: 'param_3', name: 'Vol', min: 0, max: 100, defaultValue: 70),
    ],
  ),
  // BA_PRE.ZD2
  EffectDefinition(
    effectId: '0x03800060',
    name: 'Bass Pre',
    category: 'Overdrive / Distortion',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 18,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Gain', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_1', name: 'Tone', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_2', name: 'Blend', min: 0, max: 100, defaultValue: 60),
      ParameterDescriptor(id: 'param_3', name: 'Vol', min: 0, max: 100, defaultValue: 70),
    ],
  ),
  // B_OD.ZD2
  EffectDefinition(
    effectId: '0x03800070',
    name: 'Bass OD',
    category: 'Overdrive / Distortion',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 14,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Gain', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_1', name: 'Tone', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_2', name: 'Blend', min: 0, max: 100, defaultValue: 60),
      ParameterDescriptor(id: 'param_3', name: 'Vol', min: 0, max: 100, defaultValue: 70),
    ],
  ),
  // BA_TSDRV.ZD2
  EffectDefinition(
    effectId: '0x03800080',
    name: 'BassTsDRV',
    category: 'Overdrive / Distortion',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 16,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Gain', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_1', name: 'Tone', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_2', name: 'Blend', min: 0, max: 100, defaultValue: 60),
      ParameterDescriptor(id: 'param_3', name: 'Vol', min: 0, max: 100, defaultValue: 70),
    ],
  ),
  // DARK_OD.ZD2
  EffectDefinition(
    effectId: '0x03800090',
    name: 'Dark OD',
    category: 'Overdrive / Distortion',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 21,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Gain', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_1', name: 'Tone', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_2', name: 'Blend', min: 0, max: 100, defaultValue: 60),
      ParameterDescriptor(id: 'param_3', name: 'Vol', min: 0, max: 100, defaultValue: 70),
    ],
  ),
  // BBB_OD.ZD2
  EffectDefinition(
    effectId: '0x038000a0',
    name: 'BlueB BOD',
    category: 'Overdrive / Distortion',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 19,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Gain', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_1', name: 'Tone', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_2', name: 'Blend', min: 0, max: 100, defaultValue: 60),
      ParameterDescriptor(id: 'param_3', name: 'Vol', min: 0, max: 100, defaultValue: 70),
    ],
  ),
  // VOODOO_B.ZD2
  EffectDefinition(
    effectId: '0x038000b0',
    name: 'VooDoo-B',
    category: 'Overdrive / Distortion',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 19,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Gain', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_1', name: 'Tone', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_2', name: 'Blend', min: 0, max: 100, defaultValue: 60),
      ParameterDescriptor(id: 'param_3', name: 'Vol', min: 0, max: 100, defaultValue: 70),
    ],
  ),
  // BA_FZSML.ZD2
  EffectDefinition(
    effectId: '0x038000c0',
    name: 'BaFzSmile',
    category: 'Overdrive / Distortion',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 13,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Gain', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_1', name: 'Tone', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_2', name: 'Blend', min: 0, max: 100, defaultValue: 60),
      ParameterDescriptor(id: 'param_3', name: 'Vol', min: 0, max: 100, defaultValue: 70),
    ],
  ),
  // BA_METAL.ZD2
  EffectDefinition(
    effectId: '0x038000d0',
    name: 'BassMetal',
    category: 'Overdrive / Distortion',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 12,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Gain', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_1', name: 'Tone', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_2', name: 'Blend', min: 0, max: 100, defaultValue: 60),
      ParameterDescriptor(id: 'param_3', name: 'Vol', min: 0, max: 100, defaultValue: 70),
    ],
  ),
  // BA_OCTFZ.ZD2
  EffectDefinition(
    effectId: '0x038000e0',
    name: 'BassOctFZ',
    category: 'Overdrive / Distortion',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 26,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Gain', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_1', name: 'Tone', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_2', name: 'Blend', min: 0, max: 100, defaultValue: 60),
      ParameterDescriptor(id: 'param_3', name: 'Vol', min: 0, max: 100, defaultValue: 70),
    ],
  ),
  // SVT_1U.ZD2
  EffectDefinition(
    effectId: '0x04800011',
    name: 'AMPG SVT',
    category: 'Amp',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 22,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Gain', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_1', name: 'Bass', min: 0, max: 100, defaultValue: 55),
      ParameterDescriptor(id: 'param_2', name: 'Mid', min: 0, max: 100, defaultValue: 45),
      ParameterDescriptor(id: 'param_3', name: 'Trebl', min: 0, max: 100, defaultValue: 55),
      ParameterDescriptor(id: 'param_4', name: 'Vol', min: 0, max: 100, defaultValue: 75),
    ],
  ),
  // BMN1001U.ZD2
  EffectDefinition(
    effectId: '0x04800021',
    name: 'BMAN100',
    category: 'Amp',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 32,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Gain', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_1', name: 'Bass', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_2', name: 'Mid', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_3', name: 'Trebl', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_4', name: 'Vol', min: 0, max: 100, defaultValue: 75),
    ],
  ),
  // SWR4001U.ZD2
  EffectDefinition(
    effectId: '0x04800031',
    name: 'SMR400',
    category: 'Amp',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 25,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Gain', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_1', name: 'Bass', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_2', name: 'Mid', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_3', name: 'Trebl', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_4', name: 'Vol', min: 0, max: 100, defaultValue: 75),
    ],
  ),
  // AG750_1U.ZD2
  EffectDefinition(
    effectId: '0x04800041',
    name: 'AG 750',
    category: 'Amp',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 23,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Gain', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_1', name: 'Bass', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_2', name: 'Mid', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_3', name: 'Trebl', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_4', name: 'Vol', min: 0, max: 100, defaultValue: 75),
    ],
  ),
  // TE400_1U.ZD2
  EffectDefinition(
    effectId: '0x04800051',
    name: 'TE400SMX',
    category: 'Amp',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 19,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Gain', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_1', name: 'Bass', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_2', name: 'Mid', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_3', name: 'Trebl', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_4', name: 'Vol', min: 0, max: 100, defaultValue: 75),
    ],
  ),
  // AC370_1U.ZD2
  EffectDefinition(
    effectId: '0x04800061',
    name: 'AC 370',
    category: 'Amp',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 27,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Gain', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_1', name: 'Bass', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_2', name: 'Mid', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_3', name: 'Trebl', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_4', name: 'Vol', min: 0, max: 100, defaultValue: 75),
    ],
  ),
  // MINIMARK.ZD2
  EffectDefinition(
    effectId: '0x04800070',
    name: 'Mini MkB',
    category: 'Amp',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 12,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Gain', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_1', name: 'Bass', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_2', name: 'Mid', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_3', name: 'Trebl', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_4', name: 'Vol', min: 0, max: 100, defaultValue: 75),
    ],
  ),
  // EBH3601U.ZD2
  EffectDefinition(
    effectId: '0x04800081',
    name: 'EBH360',
    category: 'Amp',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 22,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Gain', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_1', name: 'Bass', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_2', name: 'Mid', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_3', name: 'Trebl', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_4', name: 'Vol', min: 0, max: 100, defaultValue: 75),
    ],
  ),
  // B15N_1U.ZD2
  EffectDefinition(
    effectId: '0x04800091',
    name: 'FlipTop',
    category: 'Amp',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 18,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Gain', min: 0, max: 100, defaultValue: 45),
      ParameterDescriptor(id: 'param_1', name: 'Bass', min: 0, max: 100, defaultValue: 60),
      ParameterDescriptor(id: 'param_2', name: 'Trebl', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_3', name: 'Vol', min: 0, max: 100, defaultValue: 75),
    ],
  ),
  // SVT_8X10.ZD2
  EffectDefinition(
    effectId: '0x05800010',
    name: 'SVT8x10',
    category: 'Cabinet',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 13,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Mic', min: 0, max: 1, defaultValue: 0, labels: ['DYN', 'COND']),
      ParameterDescriptor(id: 'param_1', name: 'Lo', min: -12, max: 12, defaultValue: 0, unit: 'dB'),
      ParameterDescriptor(id: 'param_2', name: 'Hi', min: -12, max: 12, defaultValue: 0, unit: 'dB'),
      ParameterDescriptor(id: 'param_3', name: 'Vol', min: 0, max: 100, defaultValue: 75),
    ],
  ),
  // SV4X10TW.ZD2
  EffectDefinition(
    effectId: '0x05800018',
    name: 'SVT4x10TW',
    category: 'Cabinet',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 13,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Mic', min: 0, max: 1, defaultValue: 0, labels: ['DYN', 'COND']),
      ParameterDescriptor(id: 'param_1', name: 'Lo', min: -12, max: 12, defaultValue: 0, unit: 'dB'),
      ParameterDescriptor(id: 'param_2', name: 'Hi', min: -12, max: 12, defaultValue: 0, unit: 'dB'),
      ParameterDescriptor(id: 'param_3', name: 'Vol', min: 0, max: 100, defaultValue: 75),
    ],
  ),
  // FD_B4X12.ZD2
  EffectDefinition(
    effectId: '0x05800020',
    name: 'FD-B4x12',
    category: 'Cabinet',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 13,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Mic', min: 0, max: 1, defaultValue: 0, labels: ['DYN', 'COND']),
      ParameterDescriptor(id: 'param_1', name: 'Lo', min: -12, max: 12, defaultValue: 0, unit: 'dB'),
      ParameterDescriptor(id: 'param_2', name: 'Hi', min: -12, max: 12, defaultValue: 0, unit: 'dB'),
      ParameterDescriptor(id: 'param_3', name: 'Vol', min: 0, max: 100, defaultValue: 75),
    ],
  ),
  // SWR_4X10.ZD2
  EffectDefinition(
    effectId: '0x05800030',
    name: 'SMR4x10TW',
    category: 'Cabinet',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 13,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Mic', min: 0, max: 1, defaultValue: 0, labels: ['DYN', 'COND']),
      ParameterDescriptor(id: 'param_1', name: 'Lo', min: -12, max: 12, defaultValue: 0, unit: 'dB'),
      ParameterDescriptor(id: 'param_2', name: 'Hi', min: -12, max: 12, defaultValue: 0, unit: 'dB'),
      ParameterDescriptor(id: 'param_3', name: 'Vol', min: 0, max: 100, defaultValue: 75),
    ],
  ),
  // AG4X10TW.ZD2
  EffectDefinition(
    effectId: '0x05800040',
    name: 'AG4x10TW',
    category: 'Cabinet',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 13,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Mic', min: 0, max: 1, defaultValue: 0, labels: ['DYN', 'COND']),
      ParameterDescriptor(id: 'param_1', name: 'Lo', min: -12, max: 12, defaultValue: 0, unit: 'dB'),
      ParameterDescriptor(id: 'param_2', name: 'Hi', min: -12, max: 12, defaultValue: 0, unit: 'dB'),
      ParameterDescriptor(id: 'param_3', name: 'Vol', min: 0, max: 100, defaultValue: 75),
    ],
  ),
  // TE_4X10.ZD2
  EffectDefinition(
    effectId: '0x05800050',
    name: 'TE4x10',
    category: 'Cabinet',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 13,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Mic', min: 0, max: 1, defaultValue: 0, labels: ['DYN', 'COND']),
      ParameterDescriptor(id: 'param_1', name: 'Lo', min: -12, max: 12, defaultValue: 0, unit: 'dB'),
      ParameterDescriptor(id: 'param_2', name: 'Hi', min: -12, max: 12, defaultValue: 0, unit: 'dB'),
      ParameterDescriptor(id: 'param_3', name: 'Vol', min: 0, max: 100, defaultValue: 75),
    ],
  ),
  // AC_1X18.ZD2
  EffectDefinition(
    effectId: '0x05800060',
    name: 'AC1x18',
    category: 'Cabinet',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 13,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Mic', min: 0, max: 1, defaultValue: 0, labels: ['DYN', 'COND']),
      ParameterDescriptor(id: 'param_1', name: 'Lo', min: -12, max: 12, defaultValue: 0, unit: 'dB'),
      ParameterDescriptor(id: 'param_2', name: 'Hi', min: -12, max: 12, defaultValue: 0, unit: 'dB'),
      ParameterDescriptor(id: 'param_3', name: 'Vol', min: 0, max: 100, defaultValue: 75),
    ],
  ),
  // MKB2X8TW.ZD2
  EffectDefinition(
    effectId: '0x05800070',
    name: 'MkB2x8TW',
    category: 'Cabinet',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 17,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Mic', min: 0, max: 1, defaultValue: 0, labels: ['DYN', 'COND']),
      ParameterDescriptor(id: 'param_1', name: 'Lo', min: -12, max: 12, defaultValue: 0, unit: 'dB'),
      ParameterDescriptor(id: 'param_2', name: 'Hi', min: -12, max: 12, defaultValue: 0, unit: 'dB'),
      ParameterDescriptor(id: 'param_3', name: 'Vol', min: 0, max: 100, defaultValue: 75),
    ],
  ),
  // EB4X10TW.ZD2
  EffectDefinition(
    effectId: '0x05800080',
    name: 'EB4x10TW',
    category: 'Cabinet',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 13,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Mic', min: 0, max: 1, defaultValue: 0, labels: ['DYN', 'COND']),
      ParameterDescriptor(id: 'param_1', name: 'Lo', min: -12, max: 12, defaultValue: 0, unit: 'dB'),
      ParameterDescriptor(id: 'param_2', name: 'Hi', min: -12, max: 12, defaultValue: 0, unit: 'dB'),
      ParameterDescriptor(id: 'param_3', name: 'Vol', min: 0, max: 100, defaultValue: 75),
    ],
  ),
  // AM1X15.ZD2
  EffectDefinition(
    effectId: '0x05800090',
    name: 'AM1x15',
    category: 'Cabinet',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 13,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Mic', min: 0, max: 1, defaultValue: 0, labels: ['DYN', 'COND']),
      ParameterDescriptor(id: 'param_1', name: 'Lo', min: -12, max: 12, defaultValue: 0, unit: 'dB'),
      ParameterDescriptor(id: 'param_2', name: 'Hi', min: -12, max: 12, defaultValue: 0, unit: 'dB'),
      ParameterDescriptor(id: 'param_3', name: 'Vol', min: 0, max: 100, defaultValue: 75),
    ],
  ),
  // TREMOLO.ZD2
  EffectDefinition(
    effectId: '0x06000010',
    name: 'Tremolo',
    category: 'Modulation',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 9,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Depth', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_1', name: 'Rate', min: 0, max: 100, defaultValue: 35),
      ParameterDescriptor(id: 'param_2', name: 'Tone', min: 0, max: 10, defaultValue: 6),
      ParameterDescriptor(id: 'param_3', name: 'Mix', min: 0, max: 100, defaultValue: 50),
    ],
  ),
  // PHASER.ZD2
  EffectDefinition(
    effectId: '0x06000040',
    name: 'Phaser',
    category: 'Modulation',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 7,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Depth', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_1', name: 'Rate', min: 0, max: 100, defaultValue: 35),
      ParameterDescriptor(id: 'param_2', name: 'Tone', min: 0, max: 10, defaultValue: 6),
      ParameterDescriptor(id: 'param_3', name: 'Mix', min: 0, max: 100, defaultValue: 50),
    ],
  ),
  // THEVIBE.ZD2
  EffectDefinition(
    effectId: '0x06000060',
    name: 'TheVibe',
    category: 'Modulation',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 10,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Depth', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_1', name: 'Rate', min: 0, max: 100, defaultValue: 35),
      ParameterDescriptor(id: 'param_2', name: 'Tone', min: 0, max: 10, defaultValue: 6),
      ParameterDescriptor(id: 'param_3', name: 'Mix', min: 0, max: 100, defaultValue: 50),
    ],
  ),
  // PITCHSHF.ZD2
  EffectDefinition(
    effectId: '0x060000b0',
    name: 'PitchSHFT',
    category: 'Modulation',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 7,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Depth', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_1', name: 'Rate', min: 0, max: 100, defaultValue: 35),
      ParameterDescriptor(id: 'param_2', name: 'Tone', min: 0, max: 10, defaultValue: 6),
      ParameterDescriptor(id: 'param_3', name: 'Mix', min: 0, max: 100, defaultValue: 50),
    ],
  ),
  // HPS.ZD2
  EffectDefinition(
    effectId: '0x060000d0',
    name: 'HPS',
    category: 'Modulation',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 7,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Depth', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_1', name: 'Rate', min: 0, max: 100, defaultValue: 35),
      ParameterDescriptor(id: 'param_2', name: 'Tone', min: 0, max: 10, defaultValue: 6),
      ParameterDescriptor(id: 'param_3', name: 'Mix', min: 0, max: 100, defaultValue: 50),
    ],
  ),
  // CLONECHO.ZD2
  EffectDefinition(
    effectId: '0x06000100',
    name: 'CloneCho',
    category: 'Modulation',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 10,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Depth', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_1', name: 'Rate', min: 0, max: 100, defaultValue: 35),
      ParameterDescriptor(id: 'param_2', name: 'Tone', min: 0, max: 10, defaultValue: 6),
      ParameterDescriptor(id: 'param_3', name: 'Mix', min: 0, max: 100, defaultValue: 50),
    ],
  ),
  // SUPERCHO.ZD2
  EffectDefinition(
    effectId: '0x06000110',
    name: 'SuperCho',
    category: 'Modulation',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 8,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Depth', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_1', name: 'Rate', min: 0, max: 100, defaultValue: 35),
      ParameterDescriptor(id: 'param_2', name: 'Tone', min: 0, max: 10, defaultValue: 6),
      ParameterDescriptor(id: 'param_3', name: 'Mix', min: 0, max: 100, defaultValue: 50),
    ],
  ),
  // CRNTRI3S.ZD2
  EffectDefinition(
    effectId: '0x06000131',
    name: 'CoronaTri',
    category: 'Modulation',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 21,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Depth', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_1', name: 'Rate', min: 0, max: 100, defaultValue: 35),
      ParameterDescriptor(id: 'param_2', name: 'Tone', min: 0, max: 10, defaultValue: 6),
      ParameterDescriptor(id: 'param_3', name: 'Mix', min: 0, max: 100, defaultValue: 50),
    ],
  ),
  // B_ST_CHO.ZD2
  EffectDefinition(
    effectId: '0x06800020',
    name: 'BassStCho',
    category: 'Modulation',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 7,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Depth', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_1', name: 'Rate', min: 0, max: 100, defaultValue: 35),
      ParameterDescriptor(id: 'param_2', name: 'Tone', min: 0, max: 10, defaultValue: 6),
      ParameterDescriptor(id: 'param_3', name: 'Mix', min: 0, max: 100, defaultValue: 50),
    ],
  ),
  // B_VFLNG.ZD2
  EffectDefinition(
    effectId: '0x06800040',
    name: 'BaVinFLNG',
    category: 'Modulation',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 7,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Depth', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_1', name: 'Rate', min: 0, max: 100, defaultValue: 35),
      ParameterDescriptor(id: 'param_2', name: 'Tone', min: 0, max: 10, defaultValue: 6),
      ParameterDescriptor(id: 'param_3', name: 'Mix', min: 0, max: 100, defaultValue: 50),
    ],
  ),
  // B_OCTAVE.ZD2
  EffectDefinition(
    effectId: '0x06800050',
    name: 'Ba Octave',
    category: 'Modulation',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 7,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Depth', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_1', name: 'Rate', min: 0, max: 100, defaultValue: 35),
      ParameterDescriptor(id: 'param_2', name: 'Tone', min: 0, max: 10, defaultValue: 6),
      ParameterDescriptor(id: 'param_3', name: 'Mix', min: 0, max: 100, defaultValue: 50),
    ],
  ),
  // B_DETUNE.ZD2
  EffectDefinition(
    effectId: '0x06800060',
    name: 'Ba Detune',
    category: 'Modulation',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 12,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Depth', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_1', name: 'Rate', min: 0, max: 100, defaultValue: 35),
      ParameterDescriptor(id: 'param_2', name: 'Tone', min: 0, max: 10, defaultValue: 6),
      ParameterDescriptor(id: 'param_3', name: 'Mix', min: 0, max: 100, defaultValue: 50),
    ],
  ),
  // B_PITCH.ZD2
  EffectDefinition(
    effectId: '0x06800070',
    name: 'BaMnPitch',
    category: 'Modulation',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 10,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Depth', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_1', name: 'Rate', min: 0, max: 100, defaultValue: 35),
      ParameterDescriptor(id: 'param_2', name: 'Tone', min: 0, max: 10, defaultValue: 6),
      ParameterDescriptor(id: 'param_3', name: 'Mix', min: 0, max: 100, defaultValue: 50),
    ],
  ),
  // BASS_PHA.ZD2
  EffectDefinition(
    effectId: '0x06800080',
    name: 'BassPhase',
    category: 'Modulation',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 10,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Depth', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_1', name: 'Rate', min: 0, max: 100, defaultValue: 35),
      ParameterDescriptor(id: 'param_2', name: 'Tone', min: 0, max: 10, defaultValue: 6),
      ParameterDescriptor(id: 'param_3', name: 'Mix', min: 0, max: 100, defaultValue: 50),
    ],
  ),
  // BOMBER.ZD2
  EffectDefinition(
    effectId: '0x07000010',
    name: 'Bomber',
    category: 'SFX',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 8,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Sens', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_1', name: 'Tone', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_2', name: 'Mix', min: 0, max: 100, defaultValue: 60),
      ParameterDescriptor(id: 'param_3', name: 'Vol', min: 0, max: 100, defaultValue: 75),
    ],
  ),
  // LPROLL3S.ZD2
  EffectDefinition(
    effectId: '0x07000041',
    name: 'LoopRoll',
    category: 'SFX',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 6,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Sens', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_1', name: 'Tone', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_2', name: 'Mix', min: 0, max: 100, defaultValue: 60),
      ParameterDescriptor(id: 'param_3', name: 'Vol', min: 0, max: 100, defaultValue: 75),
    ],
  ),
  // STDSYN.ZD2
  EffectDefinition(
    effectId: '0x07800010',
    name: 'StdSyn',
    category: 'SFX',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 20,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Sens', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_1', name: 'Tone', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_2', name: 'Mix', min: 0, max: 100, defaultValue: 60),
      ParameterDescriptor(id: 'param_3', name: 'Vol', min: 0, max: 100, defaultValue: 75),
    ],
  ),
  // SYNTLK.ZD2
  EffectDefinition(
    effectId: '0x07800020',
    name: 'SynTlk',
    category: 'SFX',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 20,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Sens', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_1', name: 'Tone', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_2', name: 'Mix', min: 0, max: 100, defaultValue: 60),
      ParameterDescriptor(id: 'param_3', name: 'Vol', min: 0, max: 100, defaultValue: 75),
    ],
  ),
  // Z_SYN_1U.ZD2
  EffectDefinition(
    effectId: '0x07800031',
    name: 'Z-Syn',
    category: 'SFX',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 17,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Sens', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_1', name: 'Tone', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_2', name: 'Mix', min: 0, max: 100, defaultValue: 60),
      ParameterDescriptor(id: 'param_3', name: 'Vol', min: 0, max: 100, defaultValue: 75),
    ],
  ),
  // DEFRET.ZD2
  EffectDefinition(
    effectId: '0x07800040',
    name: 'Defret',
    category: 'SFX',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 7,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Sens', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_1', name: 'Tone', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_2', name: 'Mix', min: 0, max: 100, defaultValue: 60),
      ParameterDescriptor(id: 'param_3', name: 'Vol', min: 0, max: 100, defaultValue: 75),
    ],
  ),
  // PH_DIST.ZD2
  EffectDefinition(
    effectId: '0x07800050',
    name: 'PH+Dist',
    category: 'SFX',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 18,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Sens', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_1', name: 'Tone', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_2', name: 'Mix', min: 0, max: 100, defaultValue: 60),
      ParameterDescriptor(id: 'param_3', name: 'Vol', min: 0, max: 100, defaultValue: 75),
    ],
  ),
  // DELAY_3S.ZD2
  EffectDefinition(
    effectId: '0x08000011',
    name: 'Delay',
    category: 'Delay',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 6,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Time', min: 1, max: 3000, defaultValue: 350, unit: 'ms'),
      ParameterDescriptor(id: 'param_1', name: 'F.B', min: 0, max: 100, defaultValue: 30),
      ParameterDescriptor(id: 'param_2', name: 'Mix', min: 0, max: 100, defaultValue: 35),
      ParameterDescriptor(id: 'param_3', name: 'Tail', min: 0, max: 1, defaultValue: 1, labels: ['OFF', 'ON']),
    ],
  ),
  // ANDLY_3S.ZD2
  EffectDefinition(
    effectId: '0x08000021',
    name: 'AnalogDly',
    category: 'Delay',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 6,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Time', min: 1, max: 3000, defaultValue: 350, unit: 'ms'),
      ParameterDescriptor(id: 'param_1', name: 'F.B', min: 0, max: 100, defaultValue: 30),
      ParameterDescriptor(id: 'param_2', name: 'Mix', min: 0, max: 100, defaultValue: 35),
      ParameterDescriptor(id: 'param_3', name: 'Tail', min: 0, max: 1, defaultValue: 1, labels: ['OFF', 'ON']),
    ],
  ),
  // TAPEECHO.ZD2
  EffectDefinition(
    effectId: '0x08000030',
    name: 'TapeEcho',
    category: 'Delay',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 7,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Time', min: 1, max: 3000, defaultValue: 350, unit: 'ms'),
      ParameterDescriptor(id: 'param_1', name: 'F.B', min: 0, max: 100, defaultValue: 30),
      ParameterDescriptor(id: 'param_2', name: 'Mix', min: 0, max: 100, defaultValue: 35),
      ParameterDescriptor(id: 'param_3', name: 'Tail', min: 0, max: 1, defaultValue: 1, labels: ['OFF', 'ON']),
    ],
  ),
  // RVRSDL3S.ZD2
  EffectDefinition(
    effectId: '0x08000041',
    name: 'ReverseDL',
    category: 'Delay',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 6,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Time', min: 1, max: 3000, defaultValue: 350, unit: 'ms'),
      ParameterDescriptor(id: 'param_1', name: 'F.B', min: 0, max: 100, defaultValue: 30),
      ParameterDescriptor(id: 'param_2', name: 'Mix', min: 0, max: 100, defaultValue: 35),
      ParameterDescriptor(id: 'param_3', name: 'Tail', min: 0, max: 1, defaultValue: 1, labels: ['OFF', 'ON']),
    ],
  ),
  // MODDELAY.ZD2
  EffectDefinition(
    effectId: '0x08000050',
    name: 'ModDelay',
    category: 'Delay',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 8,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Time', min: 1, max: 3000, defaultValue: 350, unit: 'ms'),
      ParameterDescriptor(id: 'param_1', name: 'F.B', min: 0, max: 100, defaultValue: 30),
      ParameterDescriptor(id: 'param_2', name: 'Mix', min: 0, max: 100, defaultValue: 35),
      ParameterDescriptor(id: 'param_3', name: 'Tail', min: 0, max: 1, defaultValue: 1, labels: ['OFF', 'ON']),
    ],
  ),
  // DUALDL3S.ZD2
  EffectDefinition(
    effectId: '0x080000a1',
    name: 'Dual DLY',
    category: 'Delay',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 17,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Time', min: 1, max: 3000, defaultValue: 350, unit: 'ms'),
      ParameterDescriptor(id: 'param_1', name: 'F.B', min: 0, max: 100, defaultValue: 30),
      ParameterDescriptor(id: 'param_2', name: 'Mix', min: 0, max: 100, defaultValue: 35),
      ParameterDescriptor(id: 'param_3', name: 'Tail', min: 0, max: 1, defaultValue: 1, labels: ['OFF', 'ON']),
    ],
  ),
  // AIR.ZD2
  EffectDefinition(
    effectId: '0x09000010',
    name: 'Air',
    category: 'Reverb',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 6,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Decay', min: 1, max: 30, defaultValue: 12),
      ParameterDescriptor(id: 'param_1', name: 'Tone', min: 0, max: 10, defaultValue: 6),
      ParameterDescriptor(id: 'param_2', name: 'Mix', min: 0, max: 100, defaultValue: 30),
      ParameterDescriptor(id: 'param_3', name: 'PreD', min: 1, max: 200, defaultValue: 20, unit: 'ms'),
    ],
  ),
  // ROOM.ZD2
  EffectDefinition(
    effectId: '0x09000020',
    name: 'Room',
    category: 'Reverb',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 10,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Decay', min: 1, max: 30, defaultValue: 12),
      ParameterDescriptor(id: 'param_1', name: 'Tone', min: 0, max: 10, defaultValue: 6),
      ParameterDescriptor(id: 'param_2', name: 'Mix', min: 0, max: 100, defaultValue: 30),
      ParameterDescriptor(id: 'param_3', name: 'PreD', min: 1, max: 200, defaultValue: 20, unit: 'ms'),
    ],
  ),
  // HALL.ZD2
  EffectDefinition(
    effectId: '0x09000030',
    name: 'Hall',
    category: 'Reverb',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 11,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Decay', min: 1, max: 30, defaultValue: 12),
      ParameterDescriptor(id: 'param_1', name: 'Tone', min: 0, max: 10, defaultValue: 6),
      ParameterDescriptor(id: 'param_2', name: 'Mix', min: 0, max: 100, defaultValue: 30),
      ParameterDescriptor(id: 'param_3', name: 'PreD', min: 1, max: 200, defaultValue: 20, unit: 'ms'),
    ],
  ),
  // HD_HALL.ZD2
  EffectDefinition(
    effectId: '0x09000040',
    name: 'HD Hall',
    category: 'Reverb',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 26,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Decay', min: 1, max: 30, defaultValue: 12),
      ParameterDescriptor(id: 'param_1', name: 'Tone', min: 0, max: 10, defaultValue: 6),
      ParameterDescriptor(id: 'param_2', name: 'Mix', min: 0, max: 100, defaultValue: 30),
      ParameterDescriptor(id: 'param_3', name: 'PreD', min: 1, max: 200, defaultValue: 20, unit: 'ms'),
    ],
  ),
  // SPRING.ZD2
  EffectDefinition(
    effectId: '0x09000050',
    name: 'Spring',
    category: 'Reverb',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 9,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Decay', min: 1, max: 30, defaultValue: 12),
      ParameterDescriptor(id: 'param_1', name: 'Tone', min: 0, max: 10, defaultValue: 6),
      ParameterDescriptor(id: 'param_2', name: 'Mix', min: 0, max: 100, defaultValue: 30),
      ParameterDescriptor(id: 'param_3', name: 'PreD', min: 1, max: 200, defaultValue: 20, unit: 'ms'),
    ],
  ),
  // PLATEREV.ZD2
  EffectDefinition(
    effectId: '0x09000070',
    name: 'Plate',
    category: 'Reverb',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 21,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Decay', min: 1, max: 30, defaultValue: 12),
      ParameterDescriptor(id: 'param_1', name: 'Tone', min: 0, max: 10, defaultValue: 6),
      ParameterDescriptor(id: 'param_2', name: 'Mix', min: 0, max: 100, defaultValue: 30),
      ParameterDescriptor(id: 'param_3', name: 'PreD', min: 1, max: 200, defaultValue: 20, unit: 'ms'),
    ],
  ),
  // PDL_VOL.ZD2
  EffectDefinition(
    effectId: '0x0b000010',
    name: 'PDL Vol',
    category: 'Pedal',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 4,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Min', min: 0, max: 100, defaultValue: 0),
      ParameterDescriptor(id: 'param_1', name: 'Max', min: 0, max: 100, defaultValue: 100),
      ParameterDescriptor(id: 'param_2', name: 'Curve', min: 0, max: 1, defaultValue: 0, labels: ['Linear', 'Log']),
      ParameterDescriptor(id: 'param_3', name: 'Pedal', min: 0, max: 100, defaultValue: 100),
    ],
  ),
  // BASSWAH.ZD2
  EffectDefinition(
    effectId: '0x0b800010',
    name: 'BassWah',
    category: 'Pedal',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 8,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Freq', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_1', name: 'Reso', min: 0, max: 10, defaultValue: 5),
      ParameterDescriptor(id: 'param_2', name: 'DryMix', min: 0, max: 100, defaultValue: 20),
      ParameterDescriptor(id: 'param_3', name: 'Pedal', min: 0, max: 100, defaultValue: 50),
    ],
  ),
  // PDL_RESO.ZD2
  EffectDefinition(
    effectId: '0x0b800020',
    name: 'PDL Reso',
    category: 'Pedal',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 6,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Freq', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_1', name: 'Reso', min: 0, max: 100, defaultValue: 60),
      ParameterDescriptor(id: 'param_2', name: 'Mix', min: 0, max: 100, defaultValue: 60),
      ParameterDescriptor(id: 'param_3', name: 'Pedal', min: 0, max: 100, defaultValue: 50),
    ],
  ),
  // B_PDLPIT.ZD2
  EffectDefinition(
    effectId: '0x0b800030',
    name: 'Ba PDLPit',
    category: 'Pedal',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 6,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Shift', min: -24, max: 24, defaultValue: 12, unit: 'st'),
      ParameterDescriptor(id: 'param_1', name: 'Tone', min: 0, max: 10, defaultValue: 6),
      ParameterDescriptor(id: 'param_2', name: 'Bal', min: 0, max: 100, defaultValue: 70),
      ParameterDescriptor(id: 'param_3', name: 'Pedal', min: 0, max: 100, defaultValue: 0),
    ],
  ),
  // B_PDLMNP.ZD2
  EffectDefinition(
    effectId: '0x0b800040',
    name: 'Ba PDLMnP',
    category: 'Pedal',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 6,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Mode', min: 0, max: 4, defaultValue: 0, labels: ['Cho', 'Flng', 'Phs', 'Trem', 'Vib']),
      ParameterDescriptor(id: 'param_1', name: 'Depth', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_2', name: 'Mix', min: 0, max: 100, defaultValue: 50),
      ParameterDescriptor(id: 'param_3', name: 'Pedal', min: 0, max: 100, defaultValue: 50),
    ],
  ),
  // OUT_VP.ZD2
  EffectDefinition(
    effectId: '0x0bfffff0',
    name: 'Output VP',
    category: 'Pedal',
    deviceFamily: DeviceFamily.zoomB1xFour,
    dspLoad: 3,
    parameters: [
      ParameterDescriptor(id: 'param_0', name: 'Min', min: 0, max: 100, defaultValue: 0),
      ParameterDescriptor(id: 'param_1', name: 'Max', min: 0, max: 100, defaultValue: 100),
      ParameterDescriptor(id: 'param_2', name: 'Pedal', min: 0, max: 100, defaultValue: 100),
    ],
  ),
];

/// Helper catalog and lookup utilities for the Zoom Four series
/// (`B1X FOUR`, `B1 FOUR`, `G1X FOUR`, `G1 FOUR`).
class ZoomFourCatalog {
  ZoomFourCatalog._();

  static final List<EffectDefinition> _b1FourEffects = _cloneForFamily(
    DeviceFamily.zoomB1Four,
    includePedalEffects: false,
  );
  static final List<EffectDefinition> _g1xFourEffects = _cloneForFamily(
    DeviceFamily.zoomG1xFour,
    includePedalEffects: true,
  );
  static final List<EffectDefinition> _g1FourEffects = _cloneForFamily(
    DeviceFamily.zoomG1Four,
    includePedalEffects: false,
  );

  static List<EffectDefinition> _cloneForFamily(
    DeviceFamily family, {
    required bool includePedalEffects,
  }) {
    return [
      for (final def in zoomB1xFourCatalogData)
        if (includePedalEffects || def.category != 'Pedal')
          EffectDefinition(
            effectId: def.effectId,
            name: def.name,
            category: def.category,
            deviceFamily: family,
            parameters: def.parameters,
            dspLoad: def.dspLoad,
          ),
    ];
  }

  /// Complete B1X FOUR effect catalog (default Four-series bass catalog).
  static List<EffectDefinition> get allB1xFourEffects => zoomB1xFourCatalogData;

  /// All expression-pedal effects supported on `B1X FOUR` and `G1X FOUR`.
  static List<EffectDefinition> get expressionPedalEffects => zoomB1xFourCatalogData
      .where((e) => e.category == 'Pedal')
      .toList(growable: false);

  /// Distinct category names present in the Zoom B1X FOUR catalog.
  static List<String> get categories => zoomB1xFourCatalogData
      .map((e) => e.category)
      .toSet()
      .toList(growable: false);

  /// Returns the catalog entries scoped to [family].
  ///
  /// Non-expression models (`zoomB1Four`, `zoomG1Four`) omit `'Pedal'` effects
  /// from their picker lists to reflect `hasExpressionPedal == false`.
  static List<EffectDefinition> effectsForFamily(DeviceFamily family) {
    switch (family) {
      case DeviceFamily.zoomB1Four:
        return _b1FourEffects;
      case DeviceFamily.zoomG1xFour:
        return _g1xFourEffects;
      case DeviceFamily.zoomG1Four:
        return _g1FourEffects;
      case DeviceFamily.zoomB1xFour:
      case DeviceFamily.zoomMs50gPlus:
      case DeviceFamily.zoomMs60bPlus:
      case DeviceFamily.zoomMs70cdrPlus:
      case DeviceFamily.zoomMs200dPlus:
      case DeviceFamily.line6BassPodPro:
      case DeviceFamily.unknown:
        return zoomB1xFourCatalogData;
    }
  }

  /// Returns the catalog entries scoped to a [ZoomFourProfile].
  static List<EffectDefinition> effectsForProfile(ZoomFourProfile profile) =>
      effectsForFamily(profile.deviceFamily);

  /// Looks up a Zoom Four effect definition by hex ID (e.g. `'0x04800011'`) or
  /// effect name (case-insensitive, e.g. `'AMPG SVT'`).
  static EffectDefinition? getById(
    String effectId, {
    DeviceFamily family = DeviceFamily.zoomB1xFour,
  }) {
    final normalized = effectId.trim().toLowerCase();
    final catalog = effectsForFamily(family);
    for (final def in catalog) {
      if (def.effectId.toLowerCase() == normalized) return def;
    }
    // Fall back to full B1X FOUR definitions so Pedal blocks imported onto B1 FOUR remain readable.
    if (family != DeviceFamily.zoomB1xFour) {
      for (final def in zoomB1xFourCatalogData) {
        if (def.effectId.toLowerCase() == normalized) return def;
      }
    }
    return getByName(effectId, family: family);
  }

  /// Looks up a Zoom Four effect definition by 32-bit hardware effect ID.
  static EffectDefinition? getByIntId(
    int intEffectId, {
    DeviceFamily family = DeviceFamily.zoomB1xFour,
  }) {
    return getById(formatHexId(intEffectId), family: family);
  }

  /// Looks up a Zoom Four effect definition by exact display name (case-insensitive).
  static EffectDefinition? getByName(
    String name, {
    DeviceFamily family = DeviceFamily.zoomB1xFour,
  }) {
    final normalized = name.trim().toLowerCase();
    final catalog = effectsForFamily(family);
    for (final def in catalog) {
      if (def.name.toLowerCase() == normalized) return def;
    }
    if (family != DeviceFamily.zoomB1xFour) {
      for (final def in zoomB1xFourCatalogData) {
        if (def.name.toLowerCase() == normalized) return def;
      }
    }
    return null;
  }

  /// Filters Zoom Four effects by category name (case-insensitive).
  static List<EffectDefinition> getByCategory(
    String category, {
    DeviceFamily family = DeviceFamily.zoomB1xFour,
  }) {
    final normalized = category.trim().toLowerCase();
    return effectsForFamily(family)
        .where((e) => e.category.toLowerCase() == normalized)
        .toList(growable: false);
  }

  /// Formats a 32-bit Zoom effect integer ID as `'0x00000000'`.
  static String formatHexId(int id) =>
      '0x${id.toRadixString(16).padLeft(8, '0').toUpperCase()}';
}
