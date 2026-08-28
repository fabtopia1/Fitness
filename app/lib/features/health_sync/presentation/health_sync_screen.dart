import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifedna/core/providers/providers.dart';
import 'package:lifedna/core/theme/app_theme.dart';
import 'package:lifedna/core/theme/ld_spacing.dart';
import 'package:lifedna/core/widgets/ld_widgets.dart';
import 'package:lifedna/features/health_sync/data/health_sync_service.dart';
import 'package:lifedna/features/health_sync/domain/health_entities.dart';

final healthAvailabilityProvider = FutureProvider<HealthAvailability>(
  (ref) => ref.watch(healthSyncServiceProvider).availability(),
);

/// Health sync status and setup.
///
/// Reports the truth about what is connected. When nothing is, it says so and
/// lists the exact steps — it never renders sample step counts to fill space.
class HealthSyncScreen extends ConsumerWidget {
  const HealthSyncScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ldColors;
    final type = context.ldType;
    final async = ref.watch(healthAvailabilityProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Health sync')),
      body: LdAsyncView(
        value: async,
        onRetry: () => ref.invalidate(healthAvailabilityProvider),
        errorContext: 'Health sync',
        data: (availability) => ListView(
          padding: const EdgeInsets.fromLTRB(
            LdSpacing.s4,
            LdSpacing.s3,
            LdSpacing.s4,
            LdSpacing.scrollBottom,
          ),
          children: [
            LdCard(
              accentColor: availability.isUsable ? c.success : c.warning,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        availability.isUsable
                            ? Icons.check_circle_rounded
                            : Icons.info_outline_rounded,
                        color: availability.isUsable ? c.success : c.warning,
                      ),
                      const SizedBox(width: LdSpacing.s2),
                      Expanded(
                        child: Text(
                          availability.title,
                          style: type.titleL.copyWith(color: c.textPrimary),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: LdSpacing.s2),
                  Text(
                    availability.detail,
                    style: type.bodyS.copyWith(color: c.textSecondary),
                  ),
                  if (availability.canRequestPermission) ...[
                    const SizedBox(height: LdSpacing.s4),
                    LdPrimaryButton(
                      label: 'Grant access',
                      size: LdButtonSize.l,
                      onPressed: () async {
                        final result = await ref
                            .read(healthSyncServiceProvider)
                            .requestPermissions();
                        ref.invalidate(healthAvailabilityProvider);
                        if (!context.mounted) return;
                        final failure = result.failureOrNull;
                        if (failure != null) {
                          showFailureSnack(context, failure);
                        }
                      },
                    ),
                  ],
                ],
              ),
            ),
            const LdSectionHeader(title: 'How Samsung Health connects'),
            LdCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Samsung Health shares its data through Health Connect, '
                    "which is Android's official health hub. LifeDNA reads "
                    'Health Connect rather than talking to Samsung Health '
                    'directly, so no partner approval is needed and the same '
                    'code works with other apps you use.',
                    style: type.bodyS.copyWith(color: c.textSecondary),
                  ),
                  const SizedBox(height: LdSpacing.s4),
                  for (
                    var i = 0;
                    i < HealthSyncService.enablementSteps.length;
                    i++
                  )
                    Padding(
                      padding: const EdgeInsets.only(bottom: LdSpacing.s2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 20,
                            height: 20,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: c.surfaceHighest,
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              '${i + 1}',
                              style: type.caption.copyWith(
                                color: c.textSecondary,
                              ),
                            ),
                          ),
                          const SizedBox(width: LdSpacing.s3),
                          Expanded(
                            child: Text(
                              HealthSyncService.enablementSteps[i],
                              style: type.bodyS.copyWith(
                                color: c.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const LdSectionHeader(title: 'What LifeDNA would read'),
            LdCard(
              child: Column(
                children: [
                  for (final metric in HealthSyncService.requestedMetrics)
                    Padding(
                      padding: const EdgeInsets.only(bottom: LdSpacing.s2),
                      child: Row(
                        children: [
                          Icon(Icons.circle, size: 6, color: c.textTertiary),
                          const SizedBox(width: LdSpacing.s3),
                          Expanded(
                            child: Text(
                              metric.label,
                              style: type.bodyM.copyWith(color: c.textPrimary),
                            ),
                          ),
                          Text(
                            metric.unit,
                            style: type.caption.copyWith(color: c.textTertiary),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: LdSpacing.s2),
                  Text(
                    'Only these four. Every extra permission is another reason '
                    'to decline the whole prompt.',
                    style: type.caption.copyWith(color: c.textTertiary),
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
