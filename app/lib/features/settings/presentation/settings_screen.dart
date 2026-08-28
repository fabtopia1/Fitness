import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lifedna/core/config/env.dart';
import 'package:lifedna/core/providers/providers.dart';
import 'package:lifedna/core/router/app_router.dart';
import 'package:lifedna/core/sync/sync_engine.dart';
import 'package:lifedna/core/theme/app_theme.dart';
import 'package:lifedna/core/theme/ld_spacing.dart';
import 'package:lifedna/core/widgets/ld_widgets.dart';
import 'package:lifedna/features/auth/domain/user_profile.dart';
import 'package:lifedna/features/auth/presentation/auth_controller.dart';
import 'package:lifedna/features/settings/domain/app_settings.dart';
import 'package:lifedna/features/settings/presentation/goals_editor_sheet.dart';
import 'package:lifedna/features/settings/presentation/settings_providers.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Build identity, read once from the platform.
final packageInfoProvider = FutureProvider<PackageInfo>(
  (ref) => PackageInfo.fromPlatform(),
);

/// The "Me" tab: profile, targets, integrations, privacy and data control.
///
/// Every switch on this screen changes behaviour when it moves. Nothing here
/// is decorative, and where a capability is unavailable the screen says why
/// instead of showing a control that does nothing.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).valueOrNull;
    final settings = ref.watch(currentSettingsProvider);
    final sync = ref.watch(syncStateProvider).valueOrNull ?? const SyncState();
    final cloud = ref.watch(firebaseServiceProvider).isAvailable;

    return Scaffold(
      appBar: AppBar(title: const Text('Me')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          LdSpacing.screenH,
          0,
          LdSpacing.screenH,
          LdSpacing.scrollBottom,
        ),
        children: [
          if (profile != null) _AccountCard(profile: profile, cloud: cloud),
          if (profile != null) ...[
            const LdSectionHeader(title: 'Targets'),
            _TargetsCard(profile: profile),
          ],

          const LdSectionHeader(title: 'Modules'),
          _NavCard(
            icon: Icons.medication_rounded,
            title: 'Supplements',
            subtitle: 'Stack, doses and reminders',
            onTap: () => context.push(Routes.supplements),
          ),
          _NavCard(
            icon: Icons.calendar_month_rounded,
            title: 'Plan',
            subtitle: 'Tasks, events and Google Calendar',
            onTap: () => context.push(Routes.plan),
          ),
          _NavCard(
            icon: Icons.psychology_rounded,
            title: 'AI Hub',
            subtitle: 'On-device coach and assistant shortcuts',
            onTap: () => context.push(Routes.aiHub),
          ),
          _NavCard(
            icon: Icons.favorite_rounded,
            title: 'Health sync',
            subtitle: 'Samsung Health via Health Connect',
            onTap: () => context.push(Routes.healthSync),
          ),
          _NavCard(
            icon: Icons.list_alt_rounded,
            title: 'Exercise library',
            subtitle: 'Your movements and their history',
            onTap: () => context.push(Routes.exerciseLibrary),
          ),

          const LdSectionHeader(title: 'Reminders'),
          _RemindersCard(settings: settings),

          const LdSectionHeader(title: 'Appearance'),
          _ThemeCard(settings: settings),

          const LdSectionHeader(title: 'Data and sync'),
          _SyncCard(sync: sync, cloud: cloud),

          const LdSectionHeader(title: 'Privacy'),
          _PrivacyCard(settings: settings, cloud: cloud),

          const LdSectionHeader(title: 'About'),
          const _AboutCard(),

          const SizedBox(height: LdSpacing.s5),
          LdPrimaryButton(
            label: 'Sign out',
            variant: LdButtonVariant.secondary,
            size: LdButtonSize.l,
            onPressed: () => _confirmSignOut(context, ref, sync),
          ),
          const SizedBox(height: LdSpacing.s3),
          LdPrimaryButton(
            label: 'Erase data on this device',
            variant: LdButtonVariant.ghost,
            onPressed: () => _confirmErase(context, ref, cloud: cloud),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmSignOut(
    BuildContext context,
    WidgetRef ref,
    SyncState sync,
  ) async {
    final unsynced = sync.pending;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sign out?'),
        content: Text(
          unsynced > 0
              ? '$unsynced change${unsynced == 1 ? '' : 's'} has not reached '
                  'the cloud yet. Signing out now keeps it on this device but '
                  'it will not appear on your other devices until you sign '
                  'back in here.'
              : 'Your data stays on this device and in your account.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final failure = await ref.read(authControllerProvider.notifier).signOut();
    if (failure != null && context.mounted) showFailureSnack(context, failure);
  }

  /// Destructive and irreversible in local mode, so the copy says exactly what
  /// is lost before the button is offered.
  Future<void> _confirmErase(
    BuildContext context,
    WidgetRef ref, {
    required bool cloud,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Erase local data?'),
        content: Text(
          cloud
              ? 'Everything stored on this phone is deleted, including changes '
                  'that have not synced yet. Data already in your account is '
                  'downloaded again the next time you sign in.'
              : 'This build has no cloud backup. Every meal, workout, '
                  'measurement and note on this device is deleted permanently.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Erase'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await ref.read(notificationServiceProvider).cancelAll();
    await ref.read(hiveStoreProvider).clearAll();
    final failure = await ref.read(authControllerProvider.notifier).signOut();
    if (failure != null && context.mounted) showFailureSnack(context, failure);
  }
}

// ----------------------------------------------------------------- account --

class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.profile, required this.cloud});
  final UserProfile profile;
  final bool cloud;

  @override
  Widget build(BuildContext context) {
    final c = context.ldColors;
    final type = context.ldType;
    final initials = profile.displayName.trim().isEmpty
        ? '?'
        : profile.displayName
            .trim()
            .split(RegExp(r'\s+'))
            .take(2)
            .map((part) => part[0].toUpperCase())
            .join();

    return Padding(
      padding: const EdgeInsets.only(top: LdSpacing.s4),
      child: LdCard(
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: c.primaryMuted,
                shape: BoxShape.circle,
              ),
              child: Text(
                initials,
                style: type.titleL.copyWith(color: c.primary),
              ),
            ),
            const SizedBox(width: LdSpacing.s4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    profile.displayName.isEmpty ? 'You' : profile.displayName,
                    style: type.titleL.copyWith(color: c.textPrimary),
                  ),
                  Text(
                    profile.email.isEmpty
                        ? 'On this device only'
                        : profile.email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: type.bodyS.copyWith(color: c.textSecondary),
                  ),
                  const SizedBox(height: LdSpacing.s1),
                  Text(
                    cloud ? 'Synced account' : 'Local mode',
                    style: type.labelMono.copyWith(
                      color: cloud ? c.success : c.info,
                    ),
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

class _TargetsCard extends ConsumerWidget {
  const _TargetsCard({required this.profile});
  final UserProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ldColors;
    final type = context.ldType;
    final targets = profile.computedTargets;

    return LdCard(
      onTap: () => GoalsEditorSheet.show(context, profile),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (targets == null)
            Text(
              'Add your height, weight and date of birth to calculate targets.',
              style: type.bodyM.copyWith(color: c.textSecondary),
            )
          else ...[
            Text(
              '${targets.trainingDay.kcal.round()} kcal · '
              '${targets.trainingDay.proteinG.round()} g protein',
              style: type.titleL.copyWith(color: c.textPrimary),
            ),
            const SizedBox(height: LdSpacing.s1),
            Text(
              'Training day. Rest day ${targets.restDay.kcal.round()} kcal. '
              'Water ${targets.waterMl} ml.',
              style: type.bodyS.copyWith(color: c.textSecondary),
            ),
          ],
          const SizedBox(height: LdSpacing.s3),
          Row(
            children: [
              Icon(Icons.tune_rounded, size: 16, color: c.primary),
              const SizedBox(width: LdSpacing.s2),
              Text(
                'Edit goals and measurements',
                style: type.bodyS.copyWith(color: c.primary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------- reminders --

class _RemindersCard extends ConsumerStatefulWidget {
  const _RemindersCard({required this.settings});
  final AppSettings settings;

  @override
  ConsumerState<_RemindersCard> createState() => _RemindersCardState();
}

class _RemindersCardState extends ConsumerState<_RemindersCard> {
  bool _requesting = false;

  @override
  Widget build(BuildContext context) {
    final c = context.ldColors;
    final type = context.ldType;
    final notifications = ref.watch(notificationServiceProvider);
    final granted = notifications.hasPermission;

    return LdCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: widget.settings.remindersEnabled,
            title: Text(
              'Scheduled reminders',
              style: type.titleM.copyWith(color: c.textPrimary),
            ),
            subtitle: Text(
              'Supplement doses, task due times and rest-timer alerts.',
              style: type.bodyS.copyWith(color: c.textSecondary),
            ),
            onChanged: (value) => ref
                .read(settingsControllerProvider.notifier)
                .setRemindersEnabled(value),
          ),
          if (widget.settings.remindersEnabled && !granted) ...[
            const Divider(),
            const SizedBox(height: LdSpacing.s2),
            Text(
              'Android has not granted notification permission, so nothing '
              'can be delivered.',
              style: type.bodyS.copyWith(color: c.warning),
            ),
            const SizedBox(height: LdSpacing.s3),
            LdPrimaryButton(
              label: 'Allow notifications',
              size: LdButtonSize.s,
              variant: LdButtonVariant.secondary,
              expand: false,
              loading: _requesting,
              onPressed: _request,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _request() async {
    setState(() => _requesting = true);
    final granted =
        await ref.read(notificationServiceProvider).requestPermission();
    if (!mounted) return;
    setState(() => _requesting = false);
    if (granted) {
      await ref.read(supplementRepositoryProvider).rescheduleAll();
      await ref.read(calendarRepositoryProvider).rescheduleAllReminders();
      if (mounted) showSuccessSnack(context, 'Reminders scheduled.');
    } else if (mounted) {
      showSuccessSnack(
        context,
        'Notifications are off. Turn them on in Android settings.',
      );
    }
  }
}

// -------------------------------------------------------------- appearance --

class _ThemeCard extends ConsumerWidget {
  const _ThemeCard({required this.settings});
  final AppSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LdCard(
      child: Wrap(
        spacing: LdSpacing.s2,
        children: [
          for (final option in ThemePreference.values)
            ChoiceChip(
              label: Text(option.label),
              selected: settings.theme == option,
              onSelected: (_) => ref
                  .read(settingsControllerProvider.notifier)
                  .setTheme(option),
            ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------------- sync --

class _SyncCard extends ConsumerWidget {
  const _SyncCard({required this.sync, required this.cloud});
  final SyncState sync;
  final bool cloud;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ldColors;
    final type = context.ldType;
    final encrypted = ref.watch(hiveStoreProvider).isEncrypted;

    final (statusText, statusColor) = switch (sync.phase) {
      SyncPhase.localOnly => ('On this device only', c.info),
      SyncPhase.offline => ('Offline — queued', c.warning),
      SyncPhase.syncing => ('Syncing…', c.primary),
      SyncPhase.error => ('Last sync failed', c.danger),
      SyncPhase.idle => ('Up to date', c.success),
    };

    return LdCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.circle, size: 10, color: statusColor),
              const SizedBox(width: LdSpacing.s2),
              Text(statusText, style: type.titleM.copyWith(color: c.textPrimary)),
            ],
          ),
          const SizedBox(height: LdSpacing.s2),
          Text(
            sync.pending == 0
                ? 'Nothing waiting to upload.'
                : '${sync.pending} change${sync.pending == 1 ? '' : 's'} '
                    'waiting to upload.',
            style: type.bodyS.copyWith(color: c.textSecondary),
          ),
          if (sync.parked > 0)
            Text(
              '${sync.parked} could not be uploaded after repeated attempts.',
              style: type.bodyS.copyWith(color: c.danger),
            ),
          const SizedBox(height: LdSpacing.s2),
          Text(
            encrypted
                ? 'Local database encrypted with a key held in the Android '
                    'keystore.'
                : 'Local database is not encrypted on this device — the '
                    'keystore was unavailable at startup.',
            style: type.bodyS.copyWith(
              color: encrypted ? c.textTertiary : c.warning,
            ),
          ),
          if (cloud) ...[
            const SizedBox(height: LdSpacing.s4),
            Row(
              children: [
                LdPrimaryButton(
                  label: 'Sync now',
                  size: LdButtonSize.s,
                  variant: LdButtonVariant.secondary,
                  expand: false,
                  onPressed: () => ref.read(syncEngineProvider).drain(),
                ),
                if (sync.parked > 0) ...[
                  const SizedBox(width: LdSpacing.s3),
                  LdPrimaryButton(
                    label: 'Retry failed',
                    size: LdButtonSize.s,
                    variant: LdButtonVariant.ghost,
                    expand: false,
                    onPressed: () => ref.read(syncEngineProvider).retryParked(),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------- privacy --

class _PrivacyCard extends ConsumerWidget {
  const _PrivacyCard({required this.settings, required this.cloud});
  final AppSettings settings;
  final bool cloud;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ldColors;
    final type = context.ldType;
    final controller = ref.read(settingsControllerProvider.notifier);

    return LdCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: settings.analyticsConsent,
            title: Text(
              'Usage analytics',
              style: type.titleM.copyWith(color: c.textPrimary),
            ),
            subtitle: Text(
              'Screen names and counts only. Off by default.',
              style: type.bodyS.copyWith(color: c.textSecondary),
            ),
            onChanged: controller.setAnalyticsConsent,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: settings.crashReportsConsent,
            title: Text(
              'Crash reports',
              style: type.titleM.copyWith(color: c.textPrimary),
            ),
            subtitle: Text(
              'Stack traces when the app fails.',
              style: type.bodyS.copyWith(color: c.textSecondary),
            ),
            onChanged: controller.setCrashReportsConsent,
          ),
          const SizedBox(height: LdSpacing.s2),
          Text(
            cloud
                ? 'Food names, weights, measurements, photos and notes are '
                    'never included in analytics or crash reports. Photos '
                    'never leave this device.'
                : 'This build sends nothing anywhere. Analytics and crash '
                    'reporting have no destination configured.',
            style: type.bodyS.copyWith(color: c.textTertiary),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------- about --

class _AboutCard extends ConsumerWidget {
  const _AboutCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ldColors;
    final type = context.ldType;
    final info = ref.watch(packageInfoProvider);

    return LdCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            Env.flavor.appName,
            style: type.titleM.copyWith(color: c.textPrimary),
          ),
          const SizedBox(height: LdSpacing.s1),
          Text(
            switch (info) {
              AsyncData(:final value) =>
                'Version ${value.version} (${value.buildNumber}) · '
                    '${Env.flavor.key}',
              AsyncError() => 'Build ${Env.flavor.key}',
              _ => 'Reading build information…',
            },
            style: type.bodyS.copyWith(color: c.textSecondary),
          ),
          const SizedBox(height: LdSpacing.s3),
          Text(
            'LifeDNA provides training and nutrition information for healthy '
            'adults. It is not a medical device and does not diagnose, treat '
            'or prevent any condition.',
            style: type.caption.copyWith(color: c.textTertiary),
          ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------------- nav --

class _NavCard extends StatelessWidget {
  const _NavCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ldColors;
    final type = context.ldType;

    return Padding(
      padding: const EdgeInsets.only(bottom: LdSpacing.cardGap),
      child: LdCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(
          horizontal: LdSpacing.s4,
          vertical: LdSpacing.s3,
        ),
        child: Row(
          children: [
            Icon(icon, size: 22, color: c.textSecondary),
            const SizedBox(width: LdSpacing.s4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: type.titleM.copyWith(color: c.textPrimary)),
                  Text(
                    subtitle,
                    style: type.bodyS.copyWith(color: c.textTertiary),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: c.textTertiary),
          ],
        ),
      ),
    );
  }
}
