/**
 * Cross-language rounding.
 *
 * `Math.round` rounds half toward +Infinity; Dart's `num.round()` rounds half
 * AWAY FROM ZERO. They agree on positive halves and disagree on negative ones:
 *
 *     Math.round(-67.5)  === -67
 *     (-67.5).round()    === -68     // Dart
 *
 * `projectedWeeklyChangeKg` is negative for every user in a deficit, so a value
 * landing on a .5 boundary would have produced a different stored target on the
 * server than the client had already shown. The engine-parity fixture suite
 * caught this; this helper removes the class of bug entirely.
 *
 * Every engine rounds through here. Do not call `Math.round` in `src/engines`.
 */
export function roundHalfAwayFromZero(value: number): number {
  return value < 0 ? -Math.round(-value) : Math.round(value);
}

/** Rounds to `decimals` places, half away from zero. */
export function roundTo(value: number, decimals: number): number {
  const factor = 10 ** decimals;
  return roundHalfAwayFromZero(value * factor) / factor;
}
