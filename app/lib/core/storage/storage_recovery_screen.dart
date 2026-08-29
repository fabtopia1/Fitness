import 'package:flutter/material.dart';
import 'package:lifedna/core/config/firebase_config.dart';
import 'package:lifedna/core/storage/storage_mode.dart';
import 'package:lifedna/core/theme/app_theme.dart';
import 'package:lifedna/core/theme/ld_spacing.dart';
import 'package:lifedna/core/widgets/ld_widgets.dart';

/// Shown when local storage cannot be opened at all.
///
/// This screen exists because the alternative is a permanent lockout. The
/// failure it handles — encrypted boxes whose Keystore key did not survive a
/// device transfer — has no fix that preserves the data, so the honest thing
/// is to say what happened, say exactly what resetting costs, and give the
/// user a button that works. A retry that cannot succeed is worse than no
/// button at all.
class StorageRecoveryScreen extends StatefulWidget {
  const StorageRecoveryScreen({
    required this.failure,
    required this.onReset,
    required this.onRetry,
    super.key,
  });

  final StorageUnavailable failure;

  /// Deletes local storage and restarts. Destructive, and the copy says so.
  final Future<void> Function() onReset;

  /// Re-runs startup. Worth offering: a keystore can be briefly unavailable
  /// while the device is still finishing a boot.
  final Future<void> Function() onRetry;

  @override
  State<StorageRecoveryScreen> createState() => _StorageRecoveryScreenState();
}

class _StorageRecoveryScreenState extends State<StorageRecoveryScreen> {
  bool _busy = false;
  bool _confirming = false;

  /// Whether there is an account this device could download from again.
  static bool get _hasCloudBackup => FirebaseConfig.isConfigured;

  @override
  Widget build(BuildContext context) {
    final c = context.ldColors;
    final type = context.ldType;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(LdSpacing.s6),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_outline_rounded, size: 44, color: c.warning),
                  const SizedBox(height: LdSpacing.s5),
                  Text(
                    widget.failure.headline,
                    style: type.displayM.copyWith(color: c.textPrimary),
                  ),
                  const SizedBox(height: LdSpacing.s3),
                  Text(
                    widget.failure.detail,
                    style: type.bodyM.copyWith(color: c.textSecondary),
                  ),
                  const SizedBox(height: LdSpacing.s6),

                  if (!_confirming) ...[
                    LdPrimaryButton(
                      label: 'Try again',
                      size: LdButtonSize.l,
                      loading: _busy,
                      onPressed: _busy ? null : _retry,
                    ),
                    const SizedBox(height: LdSpacing.s3),
                    LdPrimaryButton(
                      label: 'Reset this phone’s data',
                      size: LdButtonSize.l,
                      variant: LdButtonVariant.secondary,
                      onPressed: _busy
                          ? null
                          : () => setState(() => _confirming = true),
                    ),
                  ] else ...[
                    Container(
                      padding: const EdgeInsets.all(LdSpacing.s4),
                      decoration: BoxDecoration(
                        color: Color.lerp(c.surface, c.danger, 0.16),
                        borderRadius: BorderRadius.circular(LdRadius.m),
                      ),
                      child: Text(
                        _hasCloudBackup
                            ? StorageUnavailable.resetWarningSignedIn
                            : StorageUnavailable.resetWarningLocal,
                        style: type.bodyS.copyWith(color: c.textPrimary),
                      ),
                    ),
                    const SizedBox(height: LdSpacing.s4),
                    LdPrimaryButton(
                      label: 'Reset and continue',
                      size: LdButtonSize.l,
                      variant: LdButtonVariant.danger,
                      loading: _busy,
                      onPressed: _busy ? null : _reset,
                    ),
                    const SizedBox(height: LdSpacing.s3),
                    LdPrimaryButton(
                      label: 'Cancel',
                      variant: LdButtonVariant.ghost,
                      onPressed: _busy
                          ? null
                          : () => setState(() => _confirming = false),
                    ),
                  ],

                  const SizedBox(height: LdSpacing.s6),
                  Text(
                    'Reference: ${widget.failure.reason.name}',
                    style: type.caption.copyWith(color: c.textTertiary),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _retry() async {
    setState(() => _busy = true);
    await widget.onRetry();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _reset() async {
    setState(() => _busy = true);
    await widget.onReset();
    if (mounted) setState(() => _busy = false);
  }
}

/// The recovery screen as a standalone app, for use before `runApp` has ever
/// mounted the real one.
class StorageRecoveryApp extends StatelessWidget {
  const StorageRecoveryApp({
    required this.failure,
    required this.onReset,
    required this.onRetry,
    super.key,
  });

  final StorageUnavailable failure;
  final Future<void> Function() onReset;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.dark(),
    home: StorageRecoveryScreen(
      failure: failure,
      onReset: onReset,
      onRetry: onRetry,
    ),
  );
}
