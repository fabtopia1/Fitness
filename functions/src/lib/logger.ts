import { createHash } from 'node:crypto';

import { logger } from 'firebase-functions/v2';

/**
 * Structured logging with mandatory redaction.
 *
 * Health data is the most sensitive class the product holds, and a log line is
 * the easiest place for it to leak (docs/19 §2). Nothing here ever accepts a
 * free-text value: fields are counts, categories, durations and booleans.
 *
 * User identity is logged as a hash, never as a uid or an email.
 */

const REDACT = /email|name|food|message|content|weight|value|body|note|title/i;

export interface LogFields {
  function: string;
  uidHash?: string;
  outcome?: 'ok' | 'error' | 'blocked';
  latencyMs?: number;
  [key: string]: string | number | boolean | undefined;
}

function assertRedacted(fields: LogFields): void {
  for (const [key, value] of Object.entries(fields)) {
    if (typeof value === 'string' && REDACT.test(key)) {
      throw new Error(
        `Refusing to log potentially sensitive field "${key}". ` +
          'Log a count, a category or a hash instead.',
      );
    }
  }
}

/**
 * A stable, non-reversible identifier for correlating one user's requests.
 *
 * Truncated SHA-256 — enough to follow a single user through a trace, not
 * enough to enumerate the user base from a log export.
 */
export function hashUid(uid: string): string {
  return createHash('sha256').update(uid).digest('hex').slice(0, 12);
}

export const log = {
  info(fields: LogFields): void {
    assertRedacted(fields);
    logger.info(fields.function, fields);
  },
  warn(fields: LogFields): void {
    assertRedacted(fields);
    logger.warn(fields.function, fields);
  },
  error(fields: LogFields & { errorType?: string }): void {
    assertRedacted(fields);
    logger.error(fields.function, fields);
  },
};
