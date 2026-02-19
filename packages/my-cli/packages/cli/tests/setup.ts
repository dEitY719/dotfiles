/**
 * Test setup for CLI package
 * Initializes test environment and shared test utilities
 */

import { beforeAll, afterAll } from 'vitest';

// Setup environment variables for testing
beforeAll(() => {
  process.env.NODE_ENV = 'test';
  // Add any test-specific environment setup here
});

// Cleanup after tests
afterAll(() => {
  // Add any cleanup here
});
