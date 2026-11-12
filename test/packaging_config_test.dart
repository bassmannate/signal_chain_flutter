import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Milestone 9: Platform Packaging & Release Distribution Configurations', () {
    final projectRoot = Directory.current.path;

    test('Linux desktop launcher and icon assets exist and are properly configured', () {
      final desktopFile = File('$projectRoot/linux/packaging/signal-chain.desktop');
      expect(desktopFile.existsSync(), isTrue, reason: 'signal-chain.desktop must exist');

      final desktopContent = desktopFile.readAsStringSync();
      expect(desktopContent, contains('[Desktop Entry]'));
      expect(desktopContent, contains('Name=Signal Chain'));
      expect(desktopContent, contains('Exec=signal-chain %u'));
      expect(desktopContent, contains('Icon=signal-chain'));
      expect(desktopContent, contains('Categories=AudioVideo;Audio;Midi;'));

      final appstreamFile = File('$projectRoot/linux/packaging/io.github.bassmannate.signal_chain.appdata.xml');
      expect(appstreamFile.existsSync(), isTrue, reason: 'AppStream metainfo XML must exist');
      final appstreamContent = appstreamFile.readAsStringSync();
      expect(appstreamContent, contains('<id>io.github.bassmannate.signal_chain</id>'));
      expect(appstreamContent, contains('<metadata_license>FSFAP</metadata_license>'));
      expect(appstreamContent, contains('<project_license>MIT</project_license>'));
      expect(appstreamContent, contains('<name>Signal Chain</name>'));
      expect(appstreamContent, contains('<summary>'));
      expect(appstreamContent, contains('<description>'));
      expect(appstreamContent, contains('<url type="homepage">'));

      final svgIcon = File('$projectRoot/linux/packaging/signal-chain.svg');
      expect(svgIcon.existsSync(), isTrue, reason: 'signal-chain.svg icon must exist');
      expect(svgIcon.readAsStringSync(), contains('<svg'));

      final pngIcon = File('$projectRoot/linux/packaging/signal-chain.png');
      expect(pngIcon.existsSync(), isTrue, reason: 'signal-chain.png icon must exist');
      expect(pngIcon.lengthSync(), greaterThan(1000));
    });

    test('Linux packaging and installation scripts exist and have executable permissions', () {
      final debScript = File('$projectRoot/tool/package_linux_deb.sh');
      expect(debScript.existsSync(), isTrue, reason: 'package_linux_deb.sh must exist');
      final debContent = debScript.readAsStringSync();
      expect(debContent, contains('dpkg-deb --build'));
      expect(debContent, contains('Depends: alsa-utils'));

      final appImageScript = File('$projectRoot/tool/package_linux_appimage.sh');
      expect(appImageScript.existsSync(), isTrue, reason: 'package_linux_appimage.sh must exist');
      final appImageContent = appImageScript.readAsStringSync();
      expect(appImageContent, contains('AppRun'));
      expect(appImageContent, contains('appimagetool'));

      final installScript = File('$projectRoot/tool/install_linux_desktop.sh');
      expect(installScript.existsSync(), isTrue, reason: 'install_linux_desktop.sh must exist');
      final installContent = installScript.readAsStringSync();
      expect(installContent, contains('.local/bin'));
      expect(installContent, contains('.local/share/applications'));

      // Check executable bits on POSIX systems
      if (!Platform.isWindows) {
        expect(debScript.statSync().mode & 0x49, isNonZero, reason: 'package_linux_deb.sh must be executable');
        expect(appImageScript.statSync().mode & 0x49, isNonZero, reason: 'package_linux_appimage.sh must be executable');
        expect(installScript.statSync().mode & 0x49, isNonZero, reason: 'install_linux_desktop.sh must be executable');
      }
    });

    test('Android USB Host and MIDI features are declared in AndroidManifest.xml', () {
      final manifestFile = File('$projectRoot/android/app/src/main/AndroidManifest.xml');
      expect(manifestFile.existsSync(), isTrue, reason: 'AndroidManifest.xml must exist');

      final content = manifestFile.readAsStringSync();
      expect(content, contains('android.hardware.usb.host'));
      expect(content, contains('android.software.midi'));
      expect(content, contains('android.hardware.usb.action.USB_DEVICE_ATTACHED'));
      expect(content, contains('@xml/device_filter'));
    });

    test('Android USB device filter contains Zoom (5766) and Line 6 (3649) vendor IDs', () {
      final filterFile = File('$projectRoot/android/app/src/main/res/xml/device_filter.xml');
      expect(filterFile.existsSync(), isTrue, reason: 'device_filter.xml must exist');

      final content = filterFile.readAsStringSync();
      // Zoom Corporation (0x1686 = 5766)
      expect(content, contains('vendor-id="5766"'));
      // Line 6 (0x0E41 = 3649)
      expect(content, contains('vendor-id="3649"'));
    });

    test('Windows packaging PowerShell script and RC resource metadata are configured', () {
      final psScript = File('$projectRoot/tool/package_windows_zip.ps1');
      expect(psScript.existsSync(), isTrue, reason: 'package_windows_zip.ps1 must exist');
      final psContent = psScript.readAsStringSync();
      expect(psContent, contains('Compress-Archive'));
      expect(psContent, contains('signal-chain-windows-x64'));

      final rcFile = File('$projectRoot/windows/runner/Runner.rc');
      expect(rcFile.existsSync(), isTrue, reason: 'Runner.rc must exist');
      final rcContent = rcFile.readAsStringSync();
      expect(rcContent, contains('Signal Chain'));
      expect(rcContent, contains('Signal Chain Contributors'));
    });
  });
}

