import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    include: ['test/**/*.test.ts'],
    environment: 'node',
    // The parity suite reads fixtures from the repository root, one level
    // above this package.
    root: __dirname,
  },
});
