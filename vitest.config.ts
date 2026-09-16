import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    include: ['packages/**/src/**/*.test.ts', 'apps/**/src/**/*.test.ts'],
    environment: 'node',
    coverage: { include: ['packages/*/src/**'], thresholds: { lines: 80, functions: 80 } },
  },
});
