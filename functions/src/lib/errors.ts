import { FunctionsErrorCode, HttpsError } from 'firebase-functions/v2/https';

/**
 * Stable machine-readable failure reasons.
 *
 * The client switches on `reason`, never on `message`. A reason string is
 * permanent: it is deprecated by ceasing to emit it, never by reusing it for a
 * different meaning (docs/09 §10).
 */
export const Reason = {
  UNAUTHENTICATED: 'UNAUTHENTICATED',
  EMAIL_NOT_VERIFIED: 'EMAIL_NOT_VERIFIED',
  RATE_LIMITED: 'RATE_LIMITED',
  AI_BUDGET_EXCEEDED: 'AI_BUDGET_EXCEEDED',
  VALIDATION_FAILED: 'VALIDATION_FAILED',
  PROVIDER_UNAVAILABLE: 'PROVIDER_UNAVAILABLE',
  PROVIDER_AUTH_EXPIRED: 'PROVIDER_AUTH_EXPIRED',
  SAFETY_BLOCKED: 'SAFETY_BLOCKED',
  NOT_FOUND: 'NOT_FOUND',
  CONFLICT: 'CONFLICT',
  PAYLOAD_TOO_LARGE: 'PAYLOAD_TOO_LARGE',
  INTERNAL: 'INTERNAL',
} as const;

export type ReasonCode = (typeof Reason)[keyof typeof Reason];

interface ErrorDetails {
  reason: ReasonCode;
  retryAfter?: number;
  resetAt?: string;
  [key: string]: unknown;
}

/**
 * Builds an HttpsError carrying the documented envelope.
 *
 * `message` is user-safe copy; anything diagnostic goes to structured logging,
 * never to the client, and never into a message a user might screenshot.
 */
export function fail(
  code: FunctionsErrorCode,
  message: string,
  details: ErrorDetails,
): HttpsError {
  return new HttpsError(code, message, details);
}

export const unauthenticated = (): HttpsError =>
  fail('unauthenticated', 'Sign in to continue.', {
    reason: Reason.UNAUTHENTICATED,
  });

export const rateLimited = (retryAfterSeconds: number): HttpsError =>
  fail('resource-exhausted', 'Too many requests. Try again shortly.', {
    reason: Reason.RATE_LIMITED,
    retryAfter: retryAfterSeconds,
  });

export const budgetExceeded = (resetAt: string): HttpsError =>
  fail(
    'resource-exhausted',
    "You've reached today's AI limit. It resets at midnight.",
    { reason: Reason.AI_BUDGET_EXCEEDED, resetAt },
  );

export const validationFailed = (detail: string): HttpsError =>
  fail('invalid-argument', 'That request looks wrong.', {
    reason: Reason.VALIDATION_FAILED,
    detail,
  });

export const payloadTooLarge = (limit: number, received: number): HttpsError =>
  fail('invalid-argument', 'Too much data in one request.', {
    reason: Reason.PAYLOAD_TOO_LARGE,
    limit,
    received,
  });
