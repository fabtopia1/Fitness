import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lifedna/core/providers/providers.dart';
import 'package:lifedna/core/theme/app_theme.dart';
import 'package:lifedna/core/theme/ld_spacing.dart';
import 'package:lifedna/core/widgets/ld_widgets.dart';

/// Records a body measurement. Every field is optional except that at least
/// one value must be present.
class BodyEditorSheet extends ConsumerStatefulWidget {
  const BodyEditorSheet({super.key});

  @override
  ConsumerState<BodyEditorSheet> createState() => _BodyEditorSheetState();
}

class _BodyEditorSheetState extends ConsumerState<BodyEditorSheet> {
  final _weight = TextEditingController();
  final _bodyFat = TextEditingController();
  final _waist = TextEditingController();
  final _chest = TextEditingController();
  final _leftArm = TextEditingController();
  final _rightArm = TextEditingController();
  final _leftLeg = TextEditingController();
  final _rightLeg = TextEditingController();

  String? _photoPath;
  bool _saving = false;
  bool _showAll = false;

  @override
  void dispose() {
    for (final controller in [
      _weight,
      _bodyFat,
      _waist,
      _chest,
      _leftArm,
      _rightArm,
      _leftLeg,
      _rightLeg,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ldColors;
    final type = context.ldType;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          LdSpacing.s4,
          0,
          LdSpacing.s4,
          MediaQuery.of(context).viewInsets.bottom + LdSpacing.s5,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Log measurement',
                style: type.headlineM.copyWith(color: c.textPrimary),
              ),
              const SizedBox(height: LdSpacing.s4),
              Row(
                children: [
                  Expanded(
                    child: _Field(
                      controller: _weight,
                      label: 'Weight',
                      suffix: 'kg',
                    ),
                  ),
                  const SizedBox(width: LdSpacing.s3),
                  Expanded(
                    child: _Field(
                      controller: _bodyFat,
                      label: 'Body fat',
                      suffix: '%',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: LdSpacing.s3),
              Row(
                children: [
                  Expanded(
                    child: _Field(
                      controller: _waist,
                      label: 'Waist',
                      suffix: 'cm',
                    ),
                  ),
                  const SizedBox(width: LdSpacing.s3),
                  Expanded(
                    child: _Field(
                      controller: _chest,
                      label: 'Chest',
                      suffix: 'cm',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: LdSpacing.s3),
              if (!_showAll)
                LdPrimaryButton(
                  label: 'Add arms and legs',
                  variant: LdButtonVariant.ghost,
                  onPressed: () => setState(() => _showAll = true),
                )
              else ...[
                Row(
                  children: [
                    Expanded(
                      child: _Field(
                        controller: _leftArm,
                        label: 'Left arm',
                        suffix: 'cm',
                      ),
                    ),
                    const SizedBox(width: LdSpacing.s3),
                    Expanded(
                      child: _Field(
                        controller: _rightArm,
                        label: 'Right arm',
                        suffix: 'cm',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: LdSpacing.s3),
                Row(
                  children: [
                    Expanded(
                      child: _Field(
                        controller: _leftLeg,
                        label: 'Left leg',
                        suffix: 'cm',
                      ),
                    ),
                    const SizedBox(width: LdSpacing.s3),
                    Expanded(
                      child: _Field(
                        controller: _rightLeg,
                        label: 'Right leg',
                        suffix: 'cm',
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: LdSpacing.s4),
              Row(
                children: [
                  Expanded(
                    child: LdPrimaryButton(
                      label: _photoPath == null
                          ? 'Add progress photo'
                          : 'Photo attached',
                      icon: Icons.photo_camera_rounded,
                      variant: LdButtonVariant.secondary,
                      onPressed: _pickPhoto,
                    ),
                  ),
                  if (_photoPath != null)
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => setState(() => _photoPath = null),
                    ),
                ],
              ),
              const SizedBox(height: LdSpacing.s2),
              Text(
                'Photos stay on this device and are never uploaded.',
                style: type.caption.copyWith(color: c.textTertiary),
              ),
              const SizedBox(height: LdSpacing.s5),
              LdPrimaryButton(
                label: 'Save',
                size: LdButtonSize.l,
                loading: _saving,
                onPressed: _save,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickPhoto() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.camera,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (picked != null && mounted) {
        setState(() => _photoPath = picked.path);
      }
    } on Object {
      if (mounted) {
        showSuccessSnack(context, 'Camera unavailable on this device.');
      }
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final repository = ref.read(bodyRepositoryProvider);

    final measurement = repository.create(
      weightKg: _parse(_weight),
      bodyFatPct: _parse(_bodyFat),
      waistCm: _parse(_waist),
      chestCm: _parse(_chest),
      leftArmCm: _parse(_leftArm),
      rightArmCm: _parse(_rightArm),
      leftLegCm: _parse(_leftLeg),
      rightLegCm: _parse(_rightLeg),
      photoPath: _photoPath,
    );

    final result = await repository.save(measurement);
    if (!mounted) return;

    result.when(
      ok: (_) {
        // Keeping the profile weight current matters: macro targets are
        // derived from it, so a stale value quietly skews every goal.
        final weight = _parse(_weight);
        if (weight != null) unawaited(_syncProfileWeight(weight));
        Navigator.of(context).pop();
      },
      err: (failure) {
        setState(() => _saving = false);
        showFailureSnack(context, failure);
      },
    );
  }

  Future<void> _syncProfileWeight(double weightKg) async {
    final repository = ref.read(profileRepositoryProvider);
    final profile = repository.read();
    if (profile == null) return;
    await repository.save(profile.copyWith(weightKg: weightKg));
  }

  double? _parse(TextEditingController controller) =>
      double.tryParse(controller.text.trim());
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    required this.suffix,
  });

  final TextEditingController controller;
  final String label;
  final String suffix;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
        ],
        decoration: InputDecoration(labelText: label, suffixText: suffix),
      );
}
