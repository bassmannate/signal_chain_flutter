import 'dart:io';
import 'dart:typed_data';
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

    test('Android launcher branding, adaptive icons, and mipmap PNGs are configured', () {
      final manifestFile = File('$projectRoot/android/app/src/main/AndroidManifest.xml');
      final manifestContent = manifestFile.readAsStringSync();
      expect(manifestContent, contains('android:label="Signal Chain"'));
      expect(manifestContent, contains('android:icon="@mipmap/ic_launcher"'));
      expect(manifestContent, contains('android:roundIcon="@mipmap/ic_launcher_round"'));

      final colorsFile = File('$projectRoot/android/app/src/main/res/values/colors.xml');
      expect(colorsFile.existsSync(), isTrue);
      expect(colorsFile.readAsStringSync(), contains('#121318'));

      final fgFile = File('$projectRoot/android/app/src/main/res/drawable/ic_launcher_foreground.xml');
      expect(fgFile.existsSync(), isTrue);
      expect(fgFile.readAsStringSync(), contains('<vector'));

      for (final xmlName in ['ic_launcher.xml', 'ic_launcher_round.xml']) {
        final adaptiveFile = File('$projectRoot/android/app/src/main/res/mipmap-anydpi-v26/$xmlName');
        expect(adaptiveFile.existsSync(), isTrue, reason: '$xmlName must exist');
        final content = adaptiveFile.readAsStringSync();
        expect(content, contains('<adaptive-icon'));
        expect(content, contains('@color/ic_launcher_background'));
        expect(content, contains('@drawable/ic_launcher_foreground'));
      }

      const expectedSizes = {
        'mdpi': 48,
        'hdpi': 72,
        'xhdpi': 96,
        'xxhdpi': 144,
        'xxxhdpi': 192,
      };
      for (final entry in expectedSizes.entries) {
        for (final iconName in ['ic_launcher.png', 'ic_launcher_round.png']) {
          final pngFile = File(
            '$projectRoot/android/app/src/main/res/mipmap-${entry.key}/$iconName',
          );
          expect(pngFile.existsSync(), isTrue, reason: '${entry.key}/$iconName must exist');
          final bytes = pngFile.readAsBytesSync();
          expect(bytes.length, greaterThan(24));
          // Verify PNG signature
          expect(
            bytes.sublist(0, 8),
            equals([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
          );
          // Verify IHDR pixel dimensions
          final data = ByteData.sublistView(bytes);
          final width = data.getUint32(16);
          final height = data.getUint32(20);
          expect(width, equals(entry.value), reason: '${entry.key}/$iconName width');
          expect(height, equals(entry.value), reason: '${entry.key}/$iconName height');
        }
      }
    });

    test('Android Gradle signing, F-Droid metadata, and release APK naming are configured', () {
      final gradleFile = File('$projectRoot/android/app/build.gradle.kts');
      final gradleContent = gradleFile.readAsStringSync();
      expect(gradleContent, contains('dependenciesInfo'));
      expect(gradleContent, contains('includeInApk = false'));
      expect(gradleContent, contains('includeInBundle = false'));
      expect(gradleContent, contains('ANDROID_KEYSTORE_PATH'));
      expect(gradleContent, contains('signingConfigs.getByName("debug")'));

      final releaseYml = File('$projectRoot/.github/workflows/release.yml');
      final releaseContent = releaseYml.readAsStringSync();
      expect(releaseContent, contains('signal-chain-\${VERSION}-android.apk'));
      expect(releaseContent, contains('ANDROID_KEYSTORE_BASE64'));

      final fastlaneDir = '$projectRoot/fastlane/metadata/android/en-US';
      final titleFile = File('$fastlaneDir/title.txt');
      expect(titleFile.existsSync(), isTrue);
      expect(titleFile.readAsStringSync().trim(), equals('Signal Chain'));
      expect(titleFile.readAsStringSync().trim().length, lessThanOrEqualTo(30));

      final shortDescFile = File('$fastlaneDir/short_description.txt');
      expect(shortDescFile.existsSync(), isTrue);
      expect(shortDescFile.readAsStringSync().trim().length, lessThanOrEqualTo(80));

      final fullDescFile = File('$fastlaneDir/full_description.txt');
      expect(fullDescFile.existsSync(), isTrue);
      expect(fullDescFile.readAsStringSync().trim().length, lessThanOrEqualTo(4000));

      expect(File('$fastlaneDir/changelogs/1.txt').existsSync(), isTrue);
      expect(File('$fastlaneDir/changelogs/2.txt').existsSync(), isTrue);

      final fastlaneIcon = File('$fastlaneDir/images/icon.png');
      expect(fastlaneIcon.existsSync(), isTrue);
      final iconData = ByteData.sublistView(fastlaneIcon.readAsBytesSync());
      expect(iconData.getUint32(16), equals(512));
      expect(iconData.getUint32(20), equals(512));
    });
  });
}

