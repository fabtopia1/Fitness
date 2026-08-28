import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lifedna/core/providers/providers.dart';
import 'package:lifedna/core/router/app_router.dart';
import 'package:lifedna/core/theme/app_theme.dart';
import 'package:lifedna/core/theme/ld_spacing.dart';
import 'package:lifedna/core/widgets/ld_widgets.dart';
import 'package:lifedna/features/auth/presentation/auth_controller.dart';

class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ldColors;
    final type = context.ldType;
    final state = ref.watch(authControllerProvider);
    final isCloud = ref.watch(firebaseServiceProvider).isAvailable;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(LdSpacing.s5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: c.primary,
                  borderRadius: BorderRadius.circular(LdRadius.m),
                ),
                child: Icon(
                  Icons.bolt_rounded,
                  color: c.textOnPrimary,
                  size: 32,
                ),
              ),
              const SizedBox(height: LdSpacing.s6),
              Text(
                'LifeDNA OS',
                style: type.displayM.copyWith(color: c.textPrimary),
              ),
              const SizedBox(height: LdSpacing.s2),
              Text(
                'Training, nutrition and recovery in one place.',
                style: type.bodyL.copyWith(color: c.textSecondary),
              ),
              const Spacer(),
              if (state.hasError)
                Padding(
                  padding: const EdgeInsets.only(bottom: LdSpacing.s4),
                  child: _InlineError(error: state.error!),
                ),
              LdPrimaryButton(
                label: 'Create account',
                size: LdButtonSize.l,
                loading: state.isLoading,
                onPressed: () => context.push(Routes.signUp),
              ),
              const SizedBox(height: LdSpacing.s3),
              LdPrimaryButton(
                label: 'Sign in',
                size: LdButtonSize.l,
                variant: LdButtonVariant.secondary,
                onPressed: () => context.push(Routes.signIn),
              ),
              if (!isCloud) ...[
                const SizedBox(height: LdSpacing.s5),
                // Local mode is a real supported path, not a debug hatch, so
                // it is offered plainly rather than hidden.
                Container(
                  padding: const EdgeInsets.all(LdSpacing.s4),
                  decoration: BoxDecoration(
                    color: c.surfaceElevated,
                    borderRadius: BorderRadius.circular(LdRadius.m),
                    border: Border.all(color: c.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.phonelink_lock_rounded,
                            size: 18,
                            color: c.info,
                          ),
                          const SizedBox(width: LdSpacing.s2),
                          // Flexible, not fixed: at a large text scale on a
                          // narrow phone this heading is wider than the card.
                          Flexible(
                            child: Text(
                              'Cloud sync not configured',
                              style: type.titleM.copyWith(color: c.textPrimary),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: LdSpacing.s2),
                      Text(
                        'This build has no Firebase configuration. You can use '
                        'every feature with your data stored on this device.',
                        style: type.bodyS.copyWith(color: c.textSecondary),
                      ),
                      const SizedBox(height: LdSpacing.s3),
                      LdPrimaryButton(
                        label: 'Continue on this device',
                        variant: LdButtonVariant.ghost,
                        loading: state.isLoading,
                        onPressed: () async {
                          final failure = await ref
                              .read(authControllerProvider.notifier)
                              .continueWithoutAccount();
                          if (failure != null && context.mounted) {
                            showFailureSnack(context, failure);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: LdSpacing.s5),
              Text(
                'LifeDNA provides training and nutrition information for '
                'healthy adults. It is not a medical device.',
                style: type.caption.copyWith(color: c.textTertiary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.error});
  final Object error;

  @override
  Widget build(BuildContext context) {
    final c = context.ldColors;
    return Container(
      padding: const EdgeInsets.all(LdSpacing.s3),
      decoration: BoxDecoration(
        color: Color.lerp(c.surface, c.danger, 0.18),
        borderRadius: BorderRadius.circular(LdRadius.s),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, size: 18, color: c.danger),
          const SizedBox(width: LdSpacing.s2),
          Expanded(
            child: Text(
              'Something went wrong. Please try again.',
              style: context.ldType.bodyS.copyWith(color: c.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
