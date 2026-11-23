import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:signal_chain_flutter/core/midi/linux_alsa_midi_transport.dart';
import 'package:signal_chain_flutter/core/midi/midi_message.dart';
import 'package:signal_chain_flutter/core/midi/midi_port_descriptor.dart';
import 'package:signal_chain_flutter/core/midi/mock_midi_transport.dart';
import 'package:signal_chain_flutter/protocols/zoom_file_transfer_service.dart';

void main() {
  group('ZoomFileTransferService', () {
    const port = MidiPortDescriptor(
      id: 'zoom_port',
      name: 'ZOOM MS-60B+',
      manufacturer: 'Zoom Corporation',
      isInput: true,
      isOutput: true,
    );

    test(
      'executes exact 0x52 -> 0x60 open/read chunks/close -> 0x53 -> 0x50 sequence and round-trips multi-chunk 8-bit data',
      () async {
        // 1,600 bytes spanning 4 chunks (512 + 512 + 512 + 64) with all 0x00..0xFF byte values
        final originalPayload = Uint8List.fromList(
          List<int>.generate(1600, (i) => (i * 37 + 13) & 0xFF),
        );

        final transport = MockMidiTransport(initialPorts: [port]);
        transport.setVirtualZoomFiles({
          'FLST_SEQ.ZT2': originalPayload,
        });
        await transport.connect(port.id);
        addTearDown(() => transport.dispose());

        final suppressionTransitions = <bool>[];
        final service = ZoomFileTransferService(
          transport: transport,
          packetTimeout: const Duration(milliseconds: 200),
          pcModeAckTimeout: const Duration(milliseconds: 100),
          closeAckTimeout: const Duration(milliseconds: 100),
        );

        final downloaded = await service.downloadFile(
          'FLST_SEQ.ZT2',
          onSuppressLiveDispatch: suppressionTransitions.add,
        );

        // Exact byte-for-byte multi-chunk 7-bit unpacking round-trip
        expect(downloaded, equals(originalPayload));
        // Live incoming dispatch was suppressed during the session and restored after
        expect(suppressionTransitions, equals([true, false]));

        // Verify exact outgoing SysEx opcode sequence:
        // 0x52 -> 0x60 0x20 0x02 <9x 00> <ASCII FLST_SEQ.ZT2> 00
        // -> 0x60 0x05 0x00 (single post-open poll)
        // -> [0x60 0x22 ..., 0x60 0x05 0x00] x5 (4 data chunks + 1 EOF probe, NO double-poll!)
        // -> 0x60 0x21 (close handle) -> 0x60 0x09 (finalize close) -> 0x53 -> 0x50
        final sent = transport.sentMessages;
        expect(sent.first.data, equals(ZoomFileTransferService.buildPcModeEnableMessage().data));

        // Verify exact real-hardware 60 20 02 open packet bytes for "FLST_SEQ.ZT2":
        // F0 52 00 6E 60 20 02 <9x 00> 46 4C 53 54 5F 53 45 51 2E 5A 54 32 00 F7
        final openPacket = sent[1].data;
        expect(
          openPacket,
          equals(Uint8List.fromList([
            0xF0, 0x52, 0x00, 0x6E, 0x60, 0x20, 0x02,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x46, 0x4C, 0x53, 0x54, 0x5F, 0x53, 0x45, 0x51, 0x2E, 0x5A, 0x54, 0x32, 0x00,
            0xF7,
          ])),
        );
        expect(
          ZoomFileTransferService.decodeOpenFilename(
            openPacket.sublist(16, openPacket.length - 1),
          ),
          equals('FLST_SEQ.ZT2'),
        );

        // Immediately after open: exactly one 60 05 00 poll, then alternating 60 22 / 60 05,
        // per-file close-handle (0x21), and single session-end finalize (0x09)
        final subCmds = sent
            .where((m) => m.data.length >= 6 && m.data[4] == 0x60)
            .map((m) => m.data[5])
            .toList();
        expect(
          subCmds,
          equals([
            0x20, // open
            0x05, // open-status poll
            0x22, 0x05, // chunk 0 (512B)
            0x22, 0x05, // chunk 1 (512B)
            0x22, 0x05, // chunk 2 (512B)
            0x22, 0x05, // chunk 3 (64B)
            0x22, 0x05, // EOF probe (0B)
            0x21, // per-file close handle
            0x09, // session-end finalize
          ]),
        );

        // Verify tail sequence: 0x60 0x21 -> 0x60 0x09 (session teardown) -> 0x53 -> 0x50
        final tail = sent.sublist(sent.length - 4);
        expect(tail[0].data, equals(ZoomFileTransferService.buildCloseHandleMessage().data));
        expect(tail[1].data, equals(ZoomFileTransferService.buildCloseFinalizeMessage().data));
        expect(tail[2].data, equals(ZoomFileTransferService.buildPcModeDisableMessage().data));
        expect(tail[3].data, equals(ZoomFileTransferService.buildParameterEditEnableMessage().data));
      },
    );

    test('chunk codec matches exact 603-byte real-hardware 60 04 22 01 00 framing and rejects corrupted CRC32', () {
      for (final len in [1, 6, 7, 8, 14, 15, 512]) {
        final raw = Uint8List.fromList(
          List<int>.generate(len, (i) => (0x80 + i * 19) & 0xFF),
        );
        final msg = ZoomFileTransferService.encodeChunkResponseMessage(raw);
        expect(msg.data[4], equals(0x60));
        expect(msg.data[5], equals(0x04));
        expect(msg.data[6], equals(0x22));
        expect(msg.data[7], equals(0x01));
        expect(msg.data[8], equals(0x00));
        if (len == 512) {
          expect(msg.data.length, equals(603));
          expect(msg.data[9], equals(0x00)); // lenLsb
          expect(msg.data[10], equals(0x04)); // lenMsb (4 * 128 = 512)
        }
        final decoded = ZoomFileTransferService.decodeChunkResponseMessage(msg);
        expect(decoded.isEof, isFalse);
        expect(decoded.bytes, equals(raw));
      }

      // Corrupt one payload byte -> must fail CRC32 check with hex summary
      final raw = Uint8List.fromList(List<int>.generate(32, (i) => i + 10));
      final validMsg = ZoomFileTransferService.encodeChunkResponseMessage(raw);
      final corruptedBytes = Uint8List.fromList(validMsg.data);
      corruptedBytes[14] ^= 0x01; // flip 1 bit inside packed payload
      expect(
        () => ZoomFileTransferService.decodeChunkResponseMessage(
          MidiMessage(corruptedBytes),
          filename: 'BAD.ZD2',
        ),
        throwsA(
          isA<ZoomFileTransferException>().having(
            (e) => e.message,
            'message',
            allOf(contains('CRC32 mismatch'), contains('F0 52 00 6E 60 04 22 01 00')),
          ),
        ),
      );
    });

    test('parseStatusReply / parseErrorReply treats 60 03 00 00 00 00 00 as OK and 60 03 7F 7F 7F 7F 0F as error', () {
      final okMsg = MidiMessage(Uint8List.fromList([
        0xF0, 0x52, 0x00, 0x6E, 0x60, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0xF7,
      ]));
      final errMsg = MidiMessage(Uint8List.fromList([
        0xF0, 0x52, 0x00, 0x6E, 0x60, 0x03, 0x7F, 0x7F, 0x7F, 0x7F, 0x0F, 0xF7,
      ]));

      expect(ZoomFileTransferService.buildStatusReplyMessage(code: 0).data, equals(okMsg.data));
      expect(ZoomFileTransferService.buildStatusReplyMessage(code: -1).data, equals(errMsg.data));

      // code == 0 is success -> parseErrorReply MUST return null
      expect(ZoomFileTransferService.parseStatusReply(okMsg), equals(0));
      expect(ZoomFileTransferService.parseErrorReply(okMsg), isNull);

      // code == -1 is error -> parseErrorReply returns error details
      expect(ZoomFileTransferService.parseStatusReply(errMsg), equals(-1));
      final err = ZoomFileTransferService.parseErrorReply(errMsg);
      expect(err, isNotNull);
      expect(err!.code, equals(-1));
      expect(err.description, contains('code -1 / not readable'));
    });

    test(
      'recognizes 60 03 7F 7F 7F 7F 0F (-1) open rejection without issuing chunk reads and closes cleanly',
      () async {
        final transport = MockMidiTransport(initialPorts: [port]);
        transport.setVirtualZoomFiles({
          'OTHER.ZD2': Uint8List.fromList([1, 2, 3, 4]),
        });
        await transport.connect(port.id);
        addTearDown(() => transport.dispose());

        final debugLines = <String>[];
        final service = ZoomFileTransferService(
          transport: transport,
          packetTimeout: const Duration(milliseconds: 200),
          pcModeAckTimeout: const Duration(milliseconds: 100),
          closeAckTimeout: const Duration(milliseconds: 100),
          debugLogger: debugLines.add,
        );

        await expectLater(
          () => service.downloadFile('BPM_MDL.ZD2'),
          throwsA(
            isA<ZoomFileTransferException>().having(
              (e) => e.message,
              'message',
              allOf(
                contains('Pedal rejected open/read (code -1 / not readable)'),
                contains('BPM_MDL.ZD2'),
                contains('F0 52 00 6E 60 03 7F 7F 7F 7F 0F F7'),
              ),
            ),
          ),
        );

        // Must NOT have issued any 0x60 0x22 chunk read requests after 60 03 rejection
        final subCmds = transport.sentMessages
            .where((m) => m.data.length >= 6 && m.data[4] == 0x60)
            .map((m) => m.data[5])
            .toList();
        expect(subCmds, equals([0x20, 0x05, 0x21, 0x09]));
        expect(debugLines.any((l) => l.contains('TX open("BPM_MDL.ZD2")')), isTrue);
        expect(debugLines.any((l) => l.contains('RX open-poll("BPM_MDL.ZD2")')), isTrue);
        expect(debugLines.any((l) => l.contains('TX close-handle("BPM_MDL.ZD2")')), isTrue);
      },
    );

    test(
      'downloads consecutive files cleanly in a single PC-Mode session with close-before-next-open lockstep',
      () async {
        final flstPayload = Uint8List.fromList(
          List<int>.generate(700, (i) => (i * 7 + 1) & 0xFF),
        );
        final zd2Payload = Uint8List.fromList(
          List<int>.generate(600, (i) => (i * 13 + 3) & 0xFF),
        );

        final transport = MockMidiTransport(initialPorts: [port]);
        transport.setVirtualZoomFiles({
          'FLST_SEQ.ZT2': flstPayload,
          'MY_NAM.ZD2': zd2Payload,
        });
        await transport.connect(port.id);
        addTearDown(() => transport.dispose());

        final service = ZoomFileTransferService(
          transport: transport,
          packetTimeout: const Duration(milliseconds: 200),
          pcModeAckTimeout: const Duration(milliseconds: 100),
          closeAckTimeout: const Duration(milliseconds: 100),
        );

        final results = await service.runReadSession((session) async {
          final first = await session.downloadFile('FLST_SEQ.ZT2');
          final second = await session.downloadFile('MY_NAM.ZD2');
          return (first: first, second: second);
        });

        expect(results.first, equals(flstPayload));
        expect(results.second, equals(zd2Payload));
        expect(
          transport.virtualZoomDownloadedFiles,
          equals(['FLST_SEQ.ZT2', 'MY_NAM.ZD2']),
        );

        // Exactly one PC-Mode entry (0x52) and one exit (0x53) + edit enable (0x50)
        final pcOnCount = transport.sentMessages
            .where((m) => m.data.length == 6 && m.data[4] == 0x52)
            .length;
        final pcOffCount = transport.sentMessages
            .where((m) => m.data.length == 6 && m.data[4] == 0x53)
            .length;
        expect(pcOnCount, equals(1));
        expect(pcOffCount, equals(1));

        // Verify exact close-handle (0x21) completes BEFORE the second open (0x20),
        // with NO per-file 0x09 between files — only one session-end 0x09 at teardown!
        final subCmds = transport.sentMessages
            .where((m) => m.data.length >= 6 && m.data[4] == 0x60)
            .map((m) => m.data[5])
            .toList();
        expect(
          subCmds,
          equals([
            // File 1 (700 bytes = 512 + 188 + EOF), closed with 0x21 only
            0x20, 0x05, 0x22, 0x05, 0x22, 0x05, 0x22, 0x05, 0x21,
            // File 2 (600 bytes = 512 + 88 + EOF), closed with 0x21 only
            0x20, 0x05, 0x22, 0x05, 0x22, 0x05, 0x22, 0x05, 0x21,
            // Single session-end finalize (0x09)
            0x09,
          ]),
        );
      },
    );

    test(
      'consecutive multi-file downloads stay in lockstep even when a stray 60 05 00 arrives before openForRead',
      () async {
        final flstPayload = Uint8List.fromList(
          List<int>.generate(200, (i) => (i * 5 + 7) & 0xFF),
        );
        final zd2Payload = Uint8List.fromList(
          List<int>.generate(180, (i) => (i * 9 + 11) & 0xFF),
        );

        final transport = MockMidiTransport(initialPorts: [port]);
        transport.setVirtualZoomFiles({
          'FLST_SEQ.ZT2': flstPayload,
          'MY_NAM.ZD2': zd2Payload,
        });
        await transport.connect(port.id);
        addTearDown(() => transport.dispose());

        // Inject a stray echoed `60 05 00` right after File 1's close-handle (60 21)
        // AND another stray `60 05 00` right when File 2's open (60 20) is sent!
        int closeCount = 0;
        transport.registerResponder(
          (req) =>
              req.isSysEx &&
              req.data.length >= 6 &&
              req.data[4] == 0x60 &&
              req.data[5] == 0x21 &&
              closeCount == 0,
          (_) {
            closeCount++;
            // Schedule a stray 60 05 00 to arrive during the inter-file gap
            Future<void>.delayed(const Duration(milliseconds: 2), () {
              transport.simulateIncomingMessage(
                ZoomFileTransferService.buildPollMessage(),
              );
            });
            return ZoomFileTransferService.buildPollMessage();
          },
        );

        final debugLines = <String>[];
        final service = ZoomFileTransferService(
          transport: transport,
          packetTimeout: const Duration(milliseconds: 200),
          pcModeAckTimeout: const Duration(milliseconds: 100),
          closeAckTimeout: const Duration(milliseconds: 100),
          staleDrainDuration: const Duration(milliseconds: 10),
          debugLogger: debugLines.add,
        );

        final results = await service.runReadSession((session) async {
          final first = await session.downloadFile('FLST_SEQ.ZT2');
          final second = await session.downloadFile('MY_NAM.ZD2');
          return (first: first, second: second);
        });

        expect(results.first, equals(flstPayload));
        expect(results.second, equals(zd2Payload));
        expect(
          debugLines.any((l) => l.contains('DROP')),
          isTrue,
        );
      },
    );

    test(
      'guarantees file close (0x60 0x21 + 0x60 0x09), 0x53 exit, 0x50 edit re-enable, and live-dispatch restore in finally on chunk timeout',
      () async {
        final transport = MockMidiTransport(initialPorts: [port]);
        await transport.connect(port.id);
        addTearDown(() => transport.dispose());

        // Respond to 0x52 and 0x60 0x20 (open), but NEVER respond to 0x60 0x05 (timeout!)
        transport.registerResponder(
          (req) =>
              req.isSysEx &&
              req.data.length >= 5 &&
              req.data[1] == 0x52 &&
              (req.data[4] == 0x52 ||
                  (req.data[4] == 0x60 && req.data.length >= 6 && req.data[5] == 0x20)),
          (_) => MidiMessage.sysEx([0x52, 0x00, 0x6E, 0x60, 0x00]),
        );

        final suppressionTransitions = <bool>[];
        final service = ZoomFileTransferService(
          transport: transport,
          packetTimeout: const Duration(milliseconds: 25),
          pcModeAckTimeout: const Duration(milliseconds: 25),
          closeAckTimeout: const Duration(milliseconds: 15),
        );

        await expectLater(
          () => service.downloadFile(
            'FLST_SEQ.ZT2',
            onSuppressLiveDispatch: suppressionTransitions.add,
          ),
          throwsA(isA<TimeoutException>()),
        );

        // Live dispatch MUST be restored
        expect(suppressionTransitions, equals([true, false]));

        // Must ALWAYS finish with file close (0x60 0x21, 0x60 0x09) + 0x53 + 0x50
        final tail = transport.sentMessages.sublist(transport.sentMessages.length - 4);
        expect(tail[0].data, equals(ZoomFileTransferService.buildCloseHandleMessage().data));
        expect(tail[1].data, equals(ZoomFileTransferService.buildCloseFinalizeMessage().data));
        expect(tail[2].data, equals(ZoomFileTransferService.buildPcModeDisableMessage().data));
        expect(tail[3].data, equals(ZoomFileTransferService.buildParameterEditEnableMessage().data));
      },
    );

    test(
      'LinuxAlsaMidiTransport cleanly reassembles 603-byte 0x60 0x04 chunk response even with interleaved 0xF8 real-time byte',
      () async {
        final rawChunk = Uint8List.fromList(
          List<int>.generate(512, (i) => (i * 11 + 5) & 0xFF),
        );
        final chunkMsg = ZoomFileTransferService.encodeChunkResponseMessage(rawChunk);
        expect(chunkMsg.data.length, equals(603));

        final alsa = LinuxAlsaMidiTransport(isLinux: true);
        final received = <MidiMessage>[];
        final sub = alsa.onMessageReceived.listen(received.add);

        // Inject a MIDI Clock (0xF8) right in the middle of the 603-byte SysEx stream
        final withClock = <int>[
          ...chunkMsg.data.sublist(0, 300),
          0xF8,
          ...chunkMsg.data.sublist(300),
        ];
        final hex = withClock
            .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
            .join(' ');

        // Stream in 100-character slices to exercise fragmentation
        for (int i = 0; i < hex.length; i += 100) {
          final end = (i + 100 < hex.length) ? i + 100 : hex.length;
          alsa.feedHexStream(hex.substring(i, end));
        }
        await Future<void>.delayed(Duration.zero);

        final sysexMsgs = received.where((m) => m.isSysEx).toList();
        expect(sysexMsgs.length, equals(1));
        expect(sysexMsgs.first.data, equals(chunkMsg.data));

        final decoded = ZoomFileTransferService.decodeChunkResponseMessage(sysexMsgs.first);
        expect(decoded.isEof, isFalse);
        expect(decoded.bytes, equals(rawChunk));

        await sub.cancel();
        await alsa.dispose();
      },
    );
  });
}

