import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    // The emulator is a single shared process: parallel files would race on
    // the same documents and produce failures that look like rule bugs.
    fileParallelism: false,
    testTimeout: 20000,
    hookTimeout: 30000,
  },
});
