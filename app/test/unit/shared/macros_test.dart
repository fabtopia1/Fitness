import 'package:flutter_test/flutter_test.dart';
import 'package:lifedna/shared/value_objects/macros.dart';

void main() {
  group('Macros', () {
    test('adds componentwise', () {
      const a = Macros(kcal: 500, proteinG: 40, carbsG: 50, fatG: 15);
      const b = Macros(kcal: 300, proteinG: 25, carbsG: 30, fatG: 8);
      final sum = a + b;
      expect(sum.kcal, 800);
      expect(sum.proteinG, 65);
      expect(sum.carbsG, 80);
      expect(sum.fatG, 23);
    });

    test('scales a per-100 g food to a portion', () {
      // Chicken breast per 100 g → 200 g portion
      const per100 = Macros(kcal: 165, proteinG: 31, carbsG: 0, fatG: 3.6);
      final portion = per100.scaled(2);
      expect(portion.kcal, 330);
      expect(portion.proteinG, 62);
      expect(portion.fatG, closeTo(7.2, 0.001));
    });

    test('reconstructs energy with Atwater factors', () {
      const m = Macros(kcal: 400, proteinG: 30, carbsG: 40, fatG: 12);
      // 120 + 160 + 108 = 388
      expect(m.derivedKcal, 388);
    });

    test('flags energy-inconsistent source data', () {
      // Community food databases frequently contain values like this. We
      // surface the inconsistency rather than silently trusting it.
      const bad = Macros(kcal: 100, proteinG: 30, carbsG: 40, fatG: 12);
      expect(bad.isEnergyInconsistent(), isTrue);

      const good = Macros(kcal: 388, proteinG: 30, carbsG: 40, fatG: 12);
      expect(good.isEnergyInconsistent(), isFalse);
    });

    test('an empty entry is not flagged as inconsistent', () {
      expect(Macros.zero.isEnergyInconsistent(), isFalse);
    });

    test('computes the energy split', () {
      const m = Macros(kcal: 400, proteinG: 30, carbsG: 40, fatG: 12);
      final split = m.energySplit;
      expect(split.protein + split.carbs + split.fat, closeTo(100, 0.01));
      expect(split.protein, closeTo(30.93, 0.01));
    });

    test('an empty split is zeros, not NaN', () {
      final split = Macros.zero.energySplit;
      expect(split.protein, 0);
      expect(split.carbs, 0);
      expect(split.fat, 0);
    });

    test('round-trips through JSON', () {
      const m = Macros(kcal: 248, proteinG: 46.5, carbsG: 0, fatG: 5.4);
      expect(Macros.fromJson(m.toJson()), m);
    });

    test('tolerates missing JSON fields', () {
      final m = Macros.fromJson(const {'kcal': 100});
      expect(m.kcal, 100);
      expect(m.proteinG, 0);
    });
  });

  group('MacroTargets', () {
    const targets = MacroTargets(
      kcal: 2350,
      proteinG: 200,
      carbsG: 210,
      fatG: 70,
      proteinFloorG: 200,
    );

    test('remaining clamps at zero rather than going negative', () {
      const consumed = Macros(kcal: 2412, proteinG: 168, carbsG: 268, fatG: 66);
      final remaining = targets.remaining(consumed);
      expect(remaining.kcal, 0); // over target
      expect(remaining.proteinG, 32);
      expect(remaining.carbsG, 0); // over target
      expect(remaining.fatG, 4);
    });

    test('proteinDebt is measured against the floor, not the target', () {
      const consumed = Macros(proteinG: 168);
      expect(targets.proteinDebt(consumed), 32);
    });

    test('proteinDebt is zero once the floor is met', () {
      expect(targets.proteinDebt(const Macros(proteinG: 210)), 0);
    });

    test('progress may exceed 1.0 — being over target is information', () {
      const consumed = Macros(kcal: 2412, proteinG: 168, carbsG: 268, fatG: 66);
      final p = targets.progress(consumed);
      expect(p.kcal, greaterThan(1.0));
      expect(p.protein, closeTo(0.84, 0.01));
      expect(p.carbs, greaterThan(1.0));
    });

    test('adherence penalizes deviation in either direction', () {
      const under = Macros(kcal: 2115); // −10 %
      const over = Macros(kcal: 2585); // +10 %
      expect(targets.adherencePct(under), closeTo(90, 0.01));
      expect(targets.adherencePct(over), closeTo(90, 0.01));
    });

    test('adherence never goes negative', () {
      expect(targets.adherencePct(const Macros(kcal: 9000)), 0);
    });

    test('round-trips through JSON', () {
      expect(MacroTargets.fromJson(targets.toJson()), targets);
    });
  });
}
