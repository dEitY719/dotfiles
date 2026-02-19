import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    globals: true,
    environment: 'node',
    include: ['packages/*/tests/**/*.test.ts'],
    exclude: ['node_modules', 'dist'],
    reporters: ['verbose'],
    coverage: {
      provider: 'v8',
      reporter: ['text', 'json', 'html', 'lcov'],
      include: ['packages/*/src/**/*.ts'],
      exclude: [
        'packages/*/src/**/*.d.ts',
        'packages/*/src/**/index.ts',
      ],
      // Coverage thresholds - minimum acceptable coverage percentages
      statements: 80,
      branches: 75,
      functions: 80,
      lines: 80,
      // Per-file thresholds can be stricter
      perFile: true,
      // Skip coverage for specific patterns
      skipFull: false,
      all: true,
    },
  },
});
