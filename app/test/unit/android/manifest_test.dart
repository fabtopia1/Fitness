import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The Android manifest, asserted from Dart.
///
/// These pin facts that no widget or unit test can reach and that only fail on
/// a physical device — usually days later, silently. The receivers below are
/// the case in point: `flutter_local_notifications` 18.0.1 ships a manifest
/// containing PERMISSIONS ONLY, so an app that does not declare them itself
/// schedules reminders that can never be delivered. Nothing throws. The
/// schedule is stored, the alarm fires, and no component exists to receive it.
void main() {
  final raw = File('android/app/src/main/AndroidManifest.xml')
      .readAsStringSync();

  /// Comments stripped. The manifest explains at length why it does NOT ask
  /// for certain permissions, so a raw text search finds the very names those
  /// comments exist to rule out.
  final manifest = raw.replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');

  const plugin = 'com.dexterous.flutterlocalnotifications';

  group('scheduled notifications can actually be delivered', () {
    test('the scheduled-notification receiver is declared', () {
      expect(
        manifest,
        contains('$plugin.ScheduledNotificationReceiver'),
        reason: 'without it no zonedSchedule notification is ever shown',
      );
    });

    test('the boot receiver is declared', () {
      expect(
        manifest,
        contains('$plugin.ScheduledNotificationBootReceiver'),
        reason: 'without it every reminder is lost on reboot',
      );
    });

    test('the boot receiver listens for the four boot actions', () {
      // BOOT_COMPLETED alone misses HTC/quick-boot devices, and
      // MY_PACKAGE_REPLACED is what re-arms reminders after sideloading an
      // update over the top — the normal way this app is installed.
      for (final action in const [
        'android.intent.action.BOOT_COMPLETED',
        'android.intent.action.MY_PACKAGE_REPLACED',
        'android.intent.action.QUICKBOOT_POWERON',
        'com.htc.intent.action.QUICKBOOT_POWERON',
      ]) {
        expect(manifest, contains(action), reason: action);
      }
    });

    test('RECEIVE_BOOT_COMPLETED is granted', () {
      expect(
        manifest,
        contains('android.permission.RECEIVE_BOOT_COMPLETED'),
        reason: 'the boot receiver never fires without it',
      );
    });

    test('the receivers are not exported', () {
      // They are internal to the app. Exporting them lets any app on the
      // phone trigger a notification.
      final receiverBlocks = RegExp(r'<receiver[\s\S]*?(?:/>|</receiver>)')
          .allMatches(manifest)
          .map((m) => m.group(0)!);

      expect(receiverBlocks, isNotEmpty);
      for (final block in receiverBlocks) {
        expect(block, contains('android:exported="false"'));
      }
    });
  });

  group('data safety', () {
    test('cloud backup is off, with rules for both API levels', () {
      // Hive boxes are encrypted with a device-bound Keystore key. Backing
      // them up manufactures the exact unrecoverable state C-1 exists for:
      // files that arrive on a new device without the key that opens them.
      expect(manifest, contains('android:allowBackup="false"'));
      expect(
        manifest,
        contains('android:fullBackupContent="@xml/backup_rules"'),
      );
      expect(
        manifest,
        contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
      );
    });

    test('no exact-alarm permission is requested', () {
      // Reminders use inexactAllowWhileIdle deliberately. SCHEDULE_EXACT_ALARM
      // is restricted on Android 14+ and would add a permission prompt the app
      // does not need.
      expect(manifest, isNot(contains('SCHEDULE_EXACT_ALARM')));
      expect(manifest, isNot(contains('USE_EXACT_ALARM')));
    });

    test('only the permissions the code actually uses are declared', () {
      final declared = RegExp(r'android\.permission\.(\w+)')
          .allMatches(manifest)
          .map((m) => m.group(1)!)
          .toSet();

      expect(declared, {
        'INTERNET',
        'ACCESS_NETWORK_STATE',
        'POST_NOTIFICATIONS',
        'RECEIVE_BOOT_COMPLETED',
        'CAMERA',
      });
    });

    test('no storage permission is needed for backups', () {
      // Backups go to the app's own external directory, which needs none.
      expect(manifest, isNot(contains('WRITE_EXTERNAL_STORAGE')));
      expect(manifest, isNot(contains('MANAGE_EXTERNAL_STORAGE')));
    });
  });

  group('R8 keeps what the manifest names', () {
    final rules = File('android/app/proguard-rules.pro').readAsStringSync();

    test('the notification plugin survives shrinking', () {
      // The receivers are referenced only from XML, so R8 cannot see the
      // reference and would strip them from a release build.
      expect(rules, contains('-keep class com.dexterous.**'));
    });

    test('Gson generic signatures survive', () {
      // The plugin stores schedules as Gson JSON and resolves them through
      // TypeToken in the boot receiver. Without Signature the generic erases
      // and the reboot path throws — release builds only.
      expect(rules, contains('-keepattributes Signature'));
    });
  });
}
