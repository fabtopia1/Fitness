#!/usr/bin/env python3
"""Regenerates the shared engine-parity fixtures.

These fixtures are executed by BOTH the Dart suite
(app/test/unit/core/engines/parity_test.dart) and the TypeScript suite
(functions/test/engines/parity.test.ts). A divergence fails both builds.

This script is a deliberately independent third implementation of the formulas
in docs/01 §6.2 and docs/12. Agreement between three implementations written
against the specification is much stronger evidence than agreement between two.

IMPORTANT — rounding. Dart's `num.round()` and Dart/JS both round half AWAY
FROM ZERO (the TypeScript engines go through `lib/rounding.ts` to guarantee
this). Python's built-in `round()` uses banker's rounding and disagrees on
every .5 boundary, so this script must never call it directly.

Run:  python3 tool/generate_engine_fixtures.py
"""
import json
import math
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "test" / "fixtures" / "engines"

ACTIVITY = {
    "sedentary": 1.2,
    "light": 1.375,
    "moderate": 1.55,
    "active": 1.725,
    "very_active": 1.9,
}
KCAL_PER_KG_BODY_MASS = 7700


def rnd(value: float) -> int:
    """Round half away from zero, matching Dart and the TS rounding helper."""
    return int(math.floor(value + 0.5)) if value >= 0 else -int(math.floor(-value + 0.5))


def round_to(value: float, decimals: int) -> float:
    factor = 10 ** decimals
    return rnd(value * factor) / factor


def clamp(value, lo, hi):
    return min(hi, max(lo, value))


# --------------------------------------------------------------------- macro --

def compute_macros(i):
    warnings, clamped = [], False
    days = clamp(rnd(i.get("trainingDaysPerWeek", 4)), 0, 7)
    lean = i.get("leanMassKg")
    w, h, a = i["weightKg"], i["heightCm"], i["age"]

    base = 10 * w + 6.25 * h - 5 * a
    bmr = base + 5 if i["sex"] == "male" else base - 161 if i["sex"] == "female" else base - 78
    base_tdee = bmr * ACTIVITY[i["activityLevel"]]
    bonus = min(i.get("trainingDayBonusKcal", 300), 500)

    rate = abs(i.get("weeklyRateTargetPct", 0.75))
    if rate > 1.0:
        rate = 1.0
        clamped = True
        warnings.append("RATE_CLAMPED_TO_SAFE_MAXIMUM")

    if i["goalMode"] == "maintain":
        delta = 0.0
    elif i["goalMode"] == "cut":
        delta = -(w * rate / 100 * KCAL_PER_KG_BODY_MASS) / 7
    else:
        delta = (w * min(rate, 0.5) / 100 * KCAL_PER_KG_BODY_MASS) / 7

    weekly_avg_tdee = base_tdee + bonus * (days / 7)
    if delta < 0:
        cap = -(weekly_avg_tdee * 0.25)
        if delta < cap:
            delta = cap
            clamped = True
            warnings.append("DEFICIT_CLAMPED_TO_25_PERCENT")
        if delta < -1000:
            delta = -1000.0
            clamped = True
            warnings.append("DEFICIT_CLAMPED_TO_1000_KCAL")

    train_kcal = base_tdee + bonus + delta
    rest_kcal = base_tdee + delta
    floor_kcal = 1200 if i["sex"] == "female" else 1500
    if rest_kcal < floor_kcal:
        rest_kcal = float(floor_kcal)
        clamped = True
        warnings.append("KCAL_RAISED_TO_ABSOLUTE_FLOOR")
    if train_kcal < floor_kcal:
        train_kcal = float(floor_kcal)
        clamped = True

    per_kg = 2.2 if i["goalMode"] == "cut" else 1.8
    protein_floor = rnd(min(max(per_kg * w, 2.4 * lean if lean else 0), 2.6 * w))

    def distribute(kcal):
        protein_kcal = protein_floor * 4
        fat = max(0.7 * w, kcal * 0.2 / 9)
        carb = kcal - protein_kcal - fat * 9
        if carb < 0:
            fat = max(0.5 * w, (kcal - protein_kcal) / 9 * 0.9)
            carb = max(0, kcal - protein_kcal - fat * 9)
        return {
            "kcal": rnd(kcal),
            "proteinG": protein_floor,
            "carbsG": rnd(carb / 4),
            "fatG": rnd(fat),
            "proteinFloorG": protein_floor,
        }

    water = rnd((w * 35 + 500 * (days / 7)) / 250) * 250
    weekly = (train_kcal - (base_tdee + bonus)) * days + (rest_kcal - base_tdee) * (7 - days)

    return {
        "bmr": rnd(bmr),
        "tdee": rnd(base_tdee),
        "weeklyAverageTdee": rnd(weekly_avg_tdee),
        "trainingDay": distribute(train_kcal),
        "restDay": distribute(rest_kcal),
        "proteinFloorG": protein_floor,
        "waterMl": water,
        "projectedWeeklyChangeKg": round_to(weekly / KCAL_PER_KG_BODY_MASS, 2),
        "clamped": clamped,
        "warnings": warnings,
    }


# ------------------------------------------------------------------ recovery --

def sleep_score(s):
    goal = s.get("goalMinutes", 480)
    ratio = s["totalMinutes"] / goal if goal > 0 else 0
    if 0.95 <= ratio <= 1.15:
        duration = 100.0
    elif ratio < 0.95:
        duration = max(0, 100 - (0.95 - ratio) * 220)
    else:
        duration = max(60, 100 - (ratio - 1.15) * 100)

    consistency = None
    if (s.get("nightsOfHistory", 0) >= 7
            and s.get("bedtimeStdDevMinutes") is not None
            and s.get("wakeStdDevMinutes") is not None):
        sigma = (s["bedtimeStdDevMinutes"] + s["wakeStdDevMinutes"]) / 2
        consistency = clamp(100 - (sigma - 20) * 1.6, 0, 100)

    efficiency = None
    if s["timeInBedMinutes"] > 0:
        pct = s["totalMinutes"] / s["timeInBedMinutes"] * 100
        efficiency = 100.0 if pct >= 90 else ((pct - 60) * 3.33 if pct >= 60 else 0.0)

    stages = None
    if (s.get("deepMinutes") is not None and s.get("remMinutes") is not None
            and s["totalMinutes"] > 0):
        deep_pct = s["deepMinutes"] / s["totalMinutes"] * 100
        rem_pct = s["remMinutes"] / s["totalMinutes"] * 100
        stages = (clamp(100 - abs(deep_pct - 18) * 5, 0, 100)
                  + clamp(100 - abs(rem_pct - 22.5) * 5, 0, 100)) / 2

    total, weight = duration * 0.40, 0.40
    if consistency is not None:
        total += consistency * 0.25
        weight += 0.25
    if efficiency is not None:
        total += efficiency * 0.20
        weight += 0.20
    if stages is not None:
        total += stages * 0.15
        weight += 0.15
    return int(clamp(rnd(total / weight), 0, 100))


def training_score(t):
    acwr = t["acwr"]
    base = 75.0
    if acwr is not None:
        base = (70 if acwr < 0.6 else 85 if acwr < 0.8 else 100 if acwr < 1.3
                else 75 if acwr < 1.5 else 50 if acwr < 1.8 else 25)
    adjustment = 0.0
    if t["meanDailyLoad28d"] > 0 and t["yesterdayLoad"] > 1.5 * t["meanDailyLoad28d"]:
        adjustment -= 15
    if (t.get("yesterdaySessionRpe") or 0) >= 9:
        adjustment -= 8
    if t.get("daysSinceLastSession", 0) >= 2 and (acwr is None or acwr >= 0.8):
        adjustment += 10
    return int(clamp(rnd(base + adjustment), 0, 100))


def activity_score(a):
    if a["stepGoal"] <= 0:
        return 0
    ratio = a["steps"] / a["stepGoal"]
    steps = 100.0 if ratio >= 1 else (ratio * 100 if ratio >= 0.5 else ratio * 80)
    active = clamp(a["activeMinutes"] / 45 * 100, 0, 100)
    score = 0.6 * steps + 0.4 * active
    if a["steps"] < 3000 and not a.get("trainedYesterday", False):
        score -= 10
    return int(clamp(rnd(score), 0, 100))


def physiology_adjustment(p):
    adjustment = 0.0
    rhr, rhr_base = p.get("restingHrBpm"), p.get("baselineRestingHrBpm")
    if rhr is not None and rhr_base is not None:
        delta = rhr - rhr_base
        if delta <= -3:
            adjustment += 3
        elif 3 <= delta <= 5:
            adjustment -= 4
        elif delta > 5:
            adjustment -= 8
    hrv, hrv_base = p.get("hrvMs"), p.get("baselineHrvMs")
    if hrv is not None and hrv_base is not None and hrv_base > 0:
        delta_pct = (hrv - hrv_base) / hrv_base * 100
        if delta_pct >= 10:
            adjustment += 4
        elif delta_pct <= -20:
            adjustment -= 9
        elif delta_pct <= -10:
            adjustment -= 5
    return clamp(adjustment, -10, 10)


def compute_recovery(args):
    sleep = args.get("sleep")
    training = args.get("training")
    activity = args.get("activity")
    physiology = args.get("physiology", {})
    planned = args.get("plannedSession")

    ss = sleep_score(sleep) if sleep else None
    ts = training_score(training) if training else None
    a_s = activity_score(activity) if activity else None

    missing = [n for n, v in (("sleep", ss), ("training", ts), ("activity", a_s)) if v is None]
    available = sum(1 for v in (ss, ts, a_s) if v is not None)

    if available < 2:
        if "sleep" in missing:
            detail = "Recovery needs sleep data from at least 2 of the last 3 nights."
        else:
            labels = {"sleep": "sleep", "training": "training history",
                      "activity": "daily activity"}
            detail = ("Recovery needs at least two data sources. Still missing: "
                      + " and ".join(labels[m] for m in missing) + ".")
        return {"recoveryScore": None, "band": "insufficient_data",
                "readinessScore": None, "sleepScore": ss, "components": [],
                "missingInputs": missing, "action": None, "detail": detail}

    weight_total = ((0.4 if ss is not None else 0)
                    + (0.4 if ts is not None else 0)
                    + (0.2 if a_s is not None else 0))
    norms = {
        "sleep": 0.4 / weight_total if ss is not None else 0,
        "training": 0.4 / weight_total if ts is not None else 0,
        "activity": 0.2 / weight_total if a_s is not None else 0,
    }

    def component(name, score):
        w = rnd(norms[name] * 100) / 100
        return {"name": name, "score": score or 0, "weight": w,
                "contribution": (rnd((score or 0) * w * 10) / 10 if score is not None else 0),
                "available": score is not None}

    components = [component("sleep", ss), component("training", ts),
                  component("activity", a_s)]

    composite = ((ss or 0) * norms["sleep"] + (ts or 0) * norms["training"]
                 + (a_s or 0) * norms["activity"] + physiology_adjustment(physiology))
    recovery = int(clamp(rnd(composite), 0, 100))
    band = "low" if recovery <= 33 else "moderate" if recovery <= 66 else "high"

    mean28 = training["meanDailyLoad28d"] if training else 0
    if planned is None or mean28 <= 0:
        readiness = recovery
    else:
        demand = clamp(planned["rpe"] * planned["durationMinutes"] / mean28, 0, 2.5)
        readiness = int(clamp(rnd(recovery - (demand - 1) * 18), 0, 100))

    acwr = training["acwr"] if training else None
    if readiness < 40 or (acwr is not None and acwr >= 1.8):
        action = "rest"
    elif readiness < 65:
        action = "reduce"
    elif readiness >= 80 and (acwr is None or acwr < 1.3):
        action = "push"
    else:
        action = "proceed"

    return {"recoveryScore": recovery, "band": band, "readinessScore": readiness,
            "sleepScore": ss, "components": components, "missingInputs": missing,
            "action": action}


# ------------------------------------------------------------------- cases --

MACRO_CASES = [
    ("reference_persona_cut", {
        "weightKg": 90.1, "heightCm": 174.5, "age": 21, "sex": "male",
        "activityLevel": "moderate", "goalMode": "cut", "trainingDaysPerWeek": 6,
        "leanMassKg": 61.9, "weeklyRateTargetPct": 0.75}),
    ("reference_persona_current_weight", {
        "weightKg": 89.4, "heightCm": 174.5, "age": 21, "sex": "male",
        "activityLevel": "moderate", "goalMode": "cut", "trainingDaysPerWeek": 6,
        "leanMassKg": 61.9, "weeklyRateTargetPct": 0.75}),
    ("maintain_no_delta", {
        "weightKg": 80, "heightCm": 178, "age": 30, "sex": "male",
        "activityLevel": "moderate", "goalMode": "maintain", "trainingDaysPerWeek": 4}),
    ("bulk_surplus", {
        "weightKg": 80, "heightCm": 178, "age": 30, "sex": "male",
        "activityLevel": "moderate", "goalMode": "bulk", "trainingDaysPerWeek": 4}),
    ("female_cut", {
        "weightKg": 65, "heightCm": 165, "age": 30, "sex": "female",
        "activityLevel": "moderate", "goalMode": "cut", "trainingDaysPerWeek": 4}),
    ("unspecified_sex_midpoint", {
        "weightKg": 65, "heightCm": 165, "age": 30, "sex": "unspecified",
        "activityLevel": "moderate", "goalMode": "maintain", "trainingDaysPerWeek": 4}),
    ("rate_above_ceiling_is_clamped", {
        "weightKg": 90.1, "heightCm": 174.5, "age": 21, "sex": "male",
        "activityLevel": "moderate", "goalMode": "cut", "trainingDaysPerWeek": 6,
        "weeklyRateTargetPct": 2.0}),
    ("deficit_clamped_to_25_percent", {
        "weightKg": 140, "heightCm": 180, "age": 30, "sex": "male",
        "activityLevel": "sedentary", "goalMode": "cut", "trainingDaysPerWeek": 0,
        "weeklyRateTargetPct": 1.0}),
    ("deficit_clamped_to_1000_kcal", {
        "weightKg": 200, "heightCm": 190, "age": 25, "sex": "male",
        "activityLevel": "very_active", "goalMode": "cut", "trainingDaysPerWeek": 6,
        "weeklyRateTargetPct": 1.0}),
    ("absolute_floor_male", {
        "weightKg": 48, "heightCm": 160, "age": 60, "sex": "male",
        "activityLevel": "sedentary", "goalMode": "cut", "trainingDaysPerWeek": 0,
        "weeklyRateTargetPct": 1.0}),
    ("absolute_floor_female", {
        "weightKg": 45, "heightCm": 155, "age": 55, "sex": "female",
        "activityLevel": "sedentary", "goalMode": "cut", "trainingDaysPerWeek": 0,
        "weeklyRateTargetPct": 1.0}),
    ("lean_mass_raises_floor", {
        "weightKg": 70, "heightCm": 175, "age": 28, "sex": "male",
        "activityLevel": "moderate", "goalMode": "cut", "trainingDaysPerWeek": 4,
        "leanMassKg": 68}),
    ("ceiling_binds_protein_floor", {
        "weightKg": 60, "heightCm": 170, "age": 25, "sex": "male",
        "activityLevel": "active", "goalMode": "cut", "trainingDaysPerWeek": 4,
        "leanMassKg": 66}),
    ("half_boundary_bmr", {
        "weightKg": 60, "heightCm": 170, "age": 25, "sex": "male",
        "activityLevel": "moderate", "goalMode": "maintain", "trainingDaysPerWeek": 3}),
]

REF_SLEEP = {"totalMinutes": 431, "timeInBedMinutes": 468, "deepMinutes": 78,
             "remMinutes": 96, "bedtimeStdDevMinutes": 24, "wakeStdDevMinutes": 19,
             "nightsOfHistory": 14}
REF_TRAINING = {"acwr": 1.073, "yesterdayLoad": 584, "meanDailyLoad28d": 334,
                "yesterdaySessionRpe": 8}
REF_ACTIVITY = {"steps": 8432, "stepGoal": 12000, "activeMinutes": 62,
                "trainedYesterday": True}
BASIC_SLEEP = {"totalMinutes": 450, "timeInBedMinutes": 480}
BASIC_TRAINING = {"acwr": 1.0, "yesterdayLoad": 300, "meanDailyLoad28d": 320}

RECOVERY_CASES = [
    ("docs12_worked_example", {
        "sleep": REF_SLEEP, "training": REF_TRAINING, "activity": REF_ACTIVITY,
        "physiology": {"restingHrBpm": 58, "baselineRestingHrBpm": 59,
                       "hrvMs": 42, "baselineHrvMs": 40.8},
        "plannedSession": {"rpe": 8, "durationMinutes": 75}}),
    ("no_planned_session", {
        "sleep": REF_SLEEP, "training": REF_TRAINING, "activity": REF_ACTIVITY}),
    ("two_components_renormalize", {
        "sleep": BASIC_SLEEP, "training": BASIC_TRAINING}),
    ("one_component_insufficient", {"sleep": BASIC_SLEEP}),
    ("no_components_insufficient", {}),
    ("missing_sleep_only", {"training": BASIC_TRAINING}),
    ("acwr_danger_forces_rest", {
        "sleep": {"totalMinutes": 490, "timeInBedMinutes": 530},
        "training": {"acwr": 1.9, "yesterdayLoad": 200, "meanDailyLoad28d": 400},
        "activity": {"steps": 10000, "stepGoal": 10000, "activeMinutes": 45},
        "plannedSession": {"rpe": 6, "durationMinutes": 60}}),
    ("rested_gets_push", {
        "sleep": {"totalMinutes": 490, "timeInBedMinutes": 530},
        "training": {"acwr": 1.0, "yesterdayLoad": 200, "meanDailyLoad28d": 400},
        "activity": {"steps": 10000, "stepGoal": 10000, "activeMinutes": 45},
        "plannedSession": {"rpe": 6, "durationMinutes": 60}}),
    ("sleep_loss_reduces_session", {
        "sleep": {"totalMinutes": 240, "timeInBedMinutes": 280},
        "training": {"acwr": 1.4, "yesterdayLoad": 200, "meanDailyLoad28d": 400},
        "activity": {"steps": 10000, "stepGoal": 10000, "activeMinutes": 45},
        "plannedSession": {"rpe": 9, "durationMinutes": 60}}),
    ("unknown_acwr_is_neutral", {
        "sleep": BASIC_SLEEP,
        "training": {"acwr": None, "yesterdayLoad": 0, "meanDailyLoad28d": 0}}),
    ("elevated_resting_hr_penalty", {
        "sleep": BASIC_SLEEP, "training": BASIC_TRAINING,
        "physiology": {"restingHrBpm": 68, "baselineRestingHrBpm": 58}}),
    ("physiology_adjustment_capped", {
        "sleep": BASIC_SLEEP, "training": BASIC_TRAINING,
        "physiology": {"restingHrBpm": 80, "baselineRestingHrBpm": 55,
                       "hrvMs": 10, "baselineHrvMs": 50}}),
    ("incomplete_physiology_ignored", {
        "sleep": BASIC_SLEEP, "training": BASIC_TRAINING,
        "physiology": {"restingHrBpm": 80}}),
    ("consistency_gated_below_7_nights", {
        "sleep": {**BASIC_SLEEP, "bedtimeStdDevMinutes": 90,
                  "wakeStdDevMinutes": 90, "nightsOfHistory": 3},
        "training": BASIC_TRAINING}),
    ("irregular_schedule_penalised", {
        "sleep": {**BASIC_SLEEP, "bedtimeStdDevMinutes": 90,
                  "wakeStdDevMinutes": 90, "nightsOfHistory": 14},
        "training": BASIC_TRAINING}),
    ("zero_sleep_boundary", {
        "sleep": {"totalMinutes": 0, "timeInBedMinutes": 40},
        "training": BASIC_TRAINING,
        "activity": {"steps": 0, "stepGoal": 10000, "activeMinutes": 0}}),
    ("oversleep_boundary", {
        "sleep": {"totalMinutes": 900, "timeInBedMinutes": 930},
        "training": BASIC_TRAINING}),
]


def main() -> None:
    for name, cases, engine_version, fn in (
        ("macro", MACRO_CASES, "macro-1.0.0", compute_macros),
        ("recovery", RECOVERY_CASES, "recovery-1.2.0", compute_recovery),
    ):
        directory = OUT / name
        directory.mkdir(parents=True, exist_ok=True)
        for case_id, payload in cases:
            document = {
                "id": case_id,
                "engineVersion": engine_version,
                "input": payload,
                "expected": fn(payload),
            }
            (directory / f"{case_id}.json").write_text(
                json.dumps(document, indent=2) + "\n"
            )
        print(f"{name}: wrote {len(cases)} fixtures to {directory.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
