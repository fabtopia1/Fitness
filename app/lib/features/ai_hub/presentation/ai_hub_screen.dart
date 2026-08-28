import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifedna/core/theme/app_theme.dart';
import 'package:lifedna/core/theme/ld_spacing.dart';
import 'package:lifedna/core/widgets/ld_widgets.dart';
import 'package:lifedna/features/ai_hub/domain/ai_coach.dart';
import 'package:lifedna/features/ai_hub/presentation/ai_providers.dart';
import 'package:url_launcher/url_launcher.dart';

/// The AI Hub.
///
/// Two distinct things, deliberately not blurred together:
///
///  1. **Coach** — deterministic, on-device analysis of the user's own
///     numbers. No model, no network, no key. Every statement cites a value
///     the user can verify elsewhere in the app.
///  2. **Shortcuts** — the app composes a brief from those same numbers, shows
///     it in full, and hands it to Claude or Copilot. It never calls an
///     assistant API on the user's behalf, because shipping a key inside an
///     APK is a security incident waiting to happen.
class AiHubScreen extends ConsumerWidget {
  const AiHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ldColors;
    final type = context.ldType;
    final insights = ref.watch(coachInsightsProvider);
    final coachContext = ref.watch(coachContextProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('AI Hub')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          LdSpacing.s4,
          LdSpacing.s3,
          LdSpacing.s4,
          LdSpacing.scrollBottom,
        ),
        children: [
          Text(
            'Coach',
            style: type.headlineM.copyWith(color: c.textPrimary),
          ),
          const SizedBox(height: LdSpacing.s1),
          Text(
            'Runs on this device from your own logged numbers. No account, no '
            'network, nothing sent anywhere.',
            style: type.bodyS.copyWith(color: c.textSecondary),
          ),
          const SizedBox(height: LdSpacing.s4),
          for (final insight in insights)
            Padding(
              padding: const EdgeInsets.only(bottom: LdSpacing.s3),
              child: _InsightCard(insight: insight),
            ),
          const LdSectionHeader(title: 'Ask an assistant'),
          Text(
            'LifeDNA builds a summary of your numbers. You choose whether to '
            'share it.',
            style: type.bodyS.copyWith(color: c.textSecondary),
          ),
          const SizedBox(height: LdSpacing.s3),
          for (final prompt in LocalCoach.prompts)
            Padding(
              padding: const EdgeInsets.only(bottom: LdSpacing.s2),
              child: LdCard(
                padding: const EdgeInsets.all(LdSpacing.s3),
                onTap: () => _openPrompt(context, prompt, coachContext),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            prompt.title,
                            style:
                                type.titleM.copyWith(color: c.textPrimary),
                          ),
                          const SizedBox(height: LdSpacing.s1),
                          Text(
                            prompt.category.label,
                            style: type.caption
                                .copyWith(color: c.textTertiary),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: c.textTertiary),
                  ],
                ),
              ),
            ),
          const SizedBox(height: LdSpacing.s4),
          LdCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.privacy_tip_rounded, size: 18, color: c.info),
                    const SizedBox(width: LdSpacing.s2),
                    Text(
                      'What gets shared',
                      style: type.titleM.copyWith(color: c.textPrimary),
                    ),
                  ],
                ),
                const SizedBox(height: LdSpacing.s2),
                Text(
                  'Nothing leaves this app unless you tap through to an '
                  'assistant, and you see the exact text first. Your name, '
                  'email and photos are never included.',
                  style: type.bodyS.copyWith(color: c.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Future<void> _openPrompt(
    BuildContext context,
    CoachPrompt prompt,
    CoachContext coachContext,
  ) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => _PromptSheet(
          prompt: prompt,
          text: prompt.compose(coachContext),
        ),
      );
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({required this.insight});
  final CoachInsight insight;

  @override
  Widget build(BuildContext context) {
    final c = context.ldColors;
    final type = context.ldType;

    return LdCard(
      eyebrow: insight.category.label,
      accentColor: switch (insight.category) {
        CoachCategory.nutrition => c.protein,
        CoachCategory.training => c.primary,
        CoachCategory.recovery => c.secondary,
        CoachCategory.habits => c.accent,
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            insight.headline,
            style: type.titleL.copyWith(color: c.textPrimary),
          ),
          const SizedBox(height: LdSpacing.s2),
          Text(
            insight.detail,
            style: type.bodyS.copyWith(color: c.textSecondary),
          ),
          if (insight.evidence.isNotEmpty) ...[
            const SizedBox(height: LdSpacing.s3),
            Wrap(
              spacing: LdSpacing.s2,
              runSpacing: LdSpacing.s2,
              children: [
                for (final item in insight.evidence)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: LdSpacing.s3,
                      vertical: LdSpacing.s1,
                    ),
                    decoration: BoxDecoration(
                      color: c.surfaceHighest,
                      borderRadius: BorderRadius.circular(LdRadius.full),
                    ),
                    child: Text(
                      '${item.label}: ${item.value}',
                      style: type.caption.copyWith(color: c.textSecondary),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _PromptSheet extends StatelessWidget {
  const _PromptSheet({required this.prompt, required this.text});
  final CoachPrompt prompt;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.ldColors;
    final type = context.ldType;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          LdSpacing.s4,
          0,
          LdSpacing.s4,
          LdSpacing.s5,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              prompt.title,
              style: type.headlineM.copyWith(color: c.textPrimary),
            ),
            const SizedBox(height: LdSpacing.s3),
            Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.4,
              ),
              width: double.infinity,
              padding: const EdgeInsets.all(LdSpacing.s3),
              decoration: BoxDecoration(
                color: c.surfaceElevated,
                borderRadius: BorderRadius.circular(LdRadius.m),
                border: Border.all(color: c.border),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  text,
                  style: type.bodyS.copyWith(color: c.textSecondary),
                ),
              ),
            ),
            const SizedBox(height: LdSpacing.s4),
            LdPrimaryButton(
              label: 'Copy to clipboard',
              icon: Icons.copy_rounded,
              variant: LdButtonVariant.secondary,
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: text));
                if (context.mounted) {
                  showSuccessSnack(context, 'Copied — paste it anywhere.');
                }
              },
            ),
            const SizedBox(height: LdSpacing.s3),
            for (final assistant in ExternalAssistant.values)
              Padding(
                padding: const EdgeInsets.only(bottom: LdSpacing.s2),
                child: LdPrimaryButton(
                  label: 'Copy and open ${assistant.label}',
                  icon: Icons.open_in_new_rounded,
                  onPressed: () => _open(context, assistant, text),
                ),
              ),
            const SizedBox(height: LdSpacing.s2),
            Text(
              'The summary is copied to your clipboard, then the assistant '
              'opens in your browser. Paste it there.',
              style: type.caption.copyWith(color: c.textTertiary),
            ),
          ],
        ),
      ),
    );
  }

  static Future<void> _open(
    BuildContext context,
    ExternalAssistant assistant,
    String text,
  ) async {
    // Copy first: if the launch fails, the user still has the brief.
    await Clipboard.setData(ClipboardData(text: text));
    final uri = Uri.parse(assistant.url);
    try {
      final launched =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && context.mounted) {
        showSuccessSnack(
          context,
          'Copied. Open ${assistant.label} to paste it.',
        );
      }
    } on Object {
      if (context.mounted) {
        showSuccessSnack(
          context,
          'Copied. Open ${assistant.label} to paste it.',
        );
      }
    }
  }
}
