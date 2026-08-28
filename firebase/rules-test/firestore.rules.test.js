import { readFileSync } from 'node:fs';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  setDoc,
} from 'firebase/firestore';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';

/**
 * Security-rules suite.
 *
 * These rules are the only thing between one user's training log and another
 * user's account, so they are executed against the real Firestore rules engine
 * rather than reviewed by eye.
 */
let testEnv;

const OWNER = 'user_owner';
const OTHER = 'user_other';

/** An ISO-8601 timestamp of the shape every client write carries. */
const NOW = '2026-03-14T09:00:00.000Z';

function owner() {
  return testEnv.authenticatedContext(OWNER).firestore();
}
function other() {
  return testEnv.authenticatedContext(OTHER).firestore();
}
function anonymous() {
  return testEnv.unauthenticatedContext().firestore();
}

/** A valid document body for a sub-collection record. */
function record(id, extra = {}) {
  return { id, updatedAt: NOW, ...extra };
}

/** A valid user profile. */
function profile(extra = {}) {
  return {
    id: OWNER,
    email: 'someone@example.com',
    displayName: 'Sam',
    heightCm: 180,
    weightKg: 82,
    updatedAt: NOW,
    ...extra,
  };
}

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'lifedna-ci',
    firestore: {
      rules: readFileSync('../firestore.rules', 'utf8'),
      host: '127.0.0.1',
      port: 8080,
    },
  });
});

afterAll(async () => {
  await testEnv?.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
});

describe('ownership', () => {
  it('an anonymous client can read nothing', async () => {
    await assertFails(getDoc(doc(anonymous(), 'users', OWNER)));
    await assertFails(
      getDocs(collection(anonymous(), 'users', OWNER, 'workouts')),
    );
  });

  it('an anonymous client can write nothing', async () => {
    await assertFails(setDoc(doc(anonymous(), 'users', OWNER), profile()));
  });

  it('a user can read and write their own profile', async () => {
    await assertSucceeds(setDoc(doc(owner(), 'users', OWNER), profile()));
    await assertSucceeds(getDoc(doc(owner(), 'users', OWNER)));
  });

  it('a user cannot read or write another account', async () => {
    // The single most important assertion in this file.
    await assertFails(getDoc(doc(other(), 'users', OWNER)));
    await assertFails(setDoc(doc(other(), 'users', OWNER), profile()));
    await assertFails(
      getDocs(collection(other(), 'users', OWNER, 'workout_sessions')),
    );
  });

  it('a user cannot write into another account\'s sub-collection', async () => {
    await assertFails(
      setDoc(
        doc(other(), 'users', OWNER, 'nutrition_logs', 'log1'),
        record('log1'),
      ),
    );
  });
});

describe('the collection allow-list', () => {
  const allowed = [
    'foods',
    'meals',
    'nutrition_logs',
    'supplements',
    'supplement_logs',
    'exercises',
    'workouts',
    'workout_sessions',
    'body_measurements',
    'tasks',
    'calendar_events',
    'notifications',
    'settings',
  ];

  it.each(allowed)('%s accepts a valid write and a read', async (name) => {
    await assertSucceeds(
      setDoc(doc(owner(), 'users', OWNER, name, 'doc1'), record('doc1')),
    );
    await assertSucceeds(getDocs(collection(owner(), 'users', OWNER, name)));
  });

  it('a collection nobody declared is refused', async () => {
    // A client bug that invents a collection would otherwise create an
    // unbudgeted, unindexed tree under every user.
    await assertFails(
      setDoc(
        doc(owner(), 'users', OWNER, 'shadow_data', 'doc1'),
        record('doc1'),
      ),
    );
    await assertFails(
      getDocs(collection(owner(), 'users', OWNER, 'shadow_data')),
    );
  });
});

describe('document shape', () => {
  it('a write with no updatedAt is refused', async () => {
    await assertFails(
      setDoc(doc(owner(), 'users', OWNER, 'tasks', 't1'), { id: 't1' }),
    );
  });

  it('updatedAt must be an ISO string, not a Firestore timestamp', async () => {
    // The offline path serialises to JSON for Hive and replays the identical
    // payload here, so the two stores can never disagree about a type.
    await assertFails(
      setDoc(doc(owner(), 'users', OWNER, 'tasks', 't1'), {
        id: 't1',
        updatedAt: new Date(),
      }),
    );
  });

  it('an id that disagrees with the path is refused', async () => {
    await assertFails(
      setDoc(doc(owner(), 'users', OWNER, 'tasks', 't1'), record('t2')),
    );
  });

  it('a document with no id field is accepted', async () => {
    // Not every payload carries a redundant id; the path is authoritative.
    await assertSucceeds(
      setDoc(doc(owner(), 'users', OWNER, 'tasks', 't1'), {
        updatedAt: NOW,
        title: 'Read chapter 4',
      }),
    );
  });

  it('a tombstone replicates', async () => {
    await assertSucceeds(
      setDoc(
        doc(owner(), 'users', OWNER, 'tasks', 't1'),
        record('t1', { deletedAt: NOW }),
      ),
    );
  });

  it('a deletedAt that is not a date is refused', async () => {
    await assertFails(
      setDoc(
        doc(owner(), 'users', OWNER, 'tasks', 't1'),
        record('t1', { deletedAt: 'yesterday' }),
      ),
    );
  });
});

describe('input bounds', () => {
  it('free text is capped', async () => {
    await assertFails(
      setDoc(
        doc(owner(), 'users', OWNER, 'tasks', 't1'),
        record('t1', { title: 'x'.repeat(501) }),
      ),
    );
    await assertSucceeds(
      setDoc(
        doc(owner(), 'users', OWNER, 'tasks', 't2'),
        record('t2', { title: 'x'.repeat(500) }),
      ),
    );
  });

  it('a note cannot be used as free storage', async () => {
    await assertFails(
      setDoc(
        doc(owner(), 'users', OWNER, 'body_measurements', 'm1'),
        record('m1', { notes: 'x'.repeat(4001) }),
      ),
    );
  });

  it('an impossible bodyweight is refused', async () => {
    await assertFails(
      setDoc(
        doc(owner(), 'users', OWNER, 'body_measurements', 'm1'),
        record('m1', { weightKg: 900 }),
      ),
    );
    await assertSucceeds(
      setDoc(
        doc(owner(), 'users', OWNER, 'body_measurements', 'm2'),
        record('m2', { weightKg: 82.4 }),
      ),
    );
  });

  it('an impossible energy value is refused', async () => {
    await assertFails(
      setDoc(
        doc(owner(), 'users', OWNER, 'nutrition_logs', 'l1'),
        record('l1', { kcal: 500000 }),
      ),
    );
  });

  it('a reminder hour outside the clock is refused', async () => {
    await assertFails(
      setDoc(
        doc(owner(), 'users', OWNER, 'notifications', 'r1'),
        record('r1', { hour: 25, minute: 0 }),
      ),
    );
    await assertSucceeds(
      setDoc(
        doc(owner(), 'users', OWNER, 'notifications', 'r2'),
        record('r2', { hour: 7, minute: 30 }),
      ),
    );
  });

  it('a document with an absurd number of fields is refused', async () => {
    const wide = record('w1');
    for (let i = 0; i < 80; i += 1) wide[`f${i}`] = i;
    await assertFails(
      setDoc(doc(owner(), 'users', OWNER, 'tasks', 'w1'), wide),
    );
  });
});

describe('the profile document', () => {
  it('an id that is not the uid is refused', async () => {
    await assertFails(
      setDoc(doc(owner(), 'users', OWNER), profile({ id: OTHER })),
    );
  });

  it('an impossible height is refused', async () => {
    await assertFails(
      setDoc(doc(owner(), 'users', OWNER), profile({ heightCm: 900 })),
    );
  });

  it('an impossible calorie override is refused', async () => {
    await assertFails(
      setDoc(doc(owner(), 'users', OWNER), profile({ overrideKcal: 99999 })),
    );
  });

  it('an empty email is accepted, because local mode has none', async () => {
    await assertSucceeds(
      setDoc(doc(owner(), 'users', OWNER), profile({ email: '' })),
    );
  });
});

describe('deletes', () => {
  it('a client cannot hard-delete a record', async () => {
    // A hard delete would come back on another device's next pull. The client
    // tombstones instead.
    await setDoc(doc(owner(), 'users', OWNER, 'tasks', 't1'), record('t1'));
    await assertFails(deleteDoc(doc(owner(), 'users', OWNER, 'tasks', 't1')));
  });

  it('a client cannot delete its own account document', async () => {
    await setDoc(doc(owner(), 'users', OWNER), profile());
    await assertFails(deleteDoc(doc(owner(), 'users', OWNER)));
  });
});

describe('everything outside users/{uid}', () => {
  it('is unreachable', async () => {
    await assertFails(getDoc(doc(owner(), 'catalogue', 'foods')));
    await assertFails(
      setDoc(doc(owner(), 'catalogue', 'foods'), { name: 'Rice' }),
    );
    await assertFails(getDocs(collection(owner(), 'analytics')));
  });
});

describe('the rules file itself', () => {
  it('denies by default', () => {
    const rules = readFileSync('../firestore.rules', 'utf8');
    expect(rules).toContain('match /{document=**}');
    expect(rules).toMatch(/allow read, write: if false;/);
  });
});
