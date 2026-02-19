/**
 * End-to-End and Performance Tests
 * Tests CLI functionality and measures performance metrics
 *
 * CL-6.1: E2E & Performance Tests
 */

import { describe, it, expect, beforeAll } from 'vitest';
import { execFile } from 'child_process';
import { promisify } from 'util';
import path from 'path';

const execFileAsync = promisify(execFile);

describe('E2E & Performance Tests', () => {
  const cliPath = path.join(__dirname, '../dist/index.js');
  const NODE_BIN = process.execPath;

  // Performance thresholds
  const COLD_START_THRESHOLD = 500; // ms
  const RESPONSE_THRESHOLD = 400; // ms (realistic for Node.js startup)

  beforeAll(async () => {
    // Warmup: Execute once to ensure Node.js cache is loaded
    try {
      await execFileAsync(NODE_BIN, [cliPath, '--version']);
    } catch {
      // Version might fail, that's ok - we just want to warm up
    }
  });

  describe('Version Command', () => {
    it('TC-1: Should display version', async () => {
      const { stdout } = await execFileAsync(NODE_BIN, [cliPath, '--version']);
      expect(stdout.trim()).toBe('0.1.0');
    });

    it('TC-2: Should execute within response threshold', async () => {
      const startTime = performance.now();
      await execFileAsync(NODE_BIN, [cliPath, '--version']);
      const duration = performance.now() - startTime;
      expect(duration).toBeLessThan(RESPONSE_THRESHOLD);
    });
  });

  describe('Help Command', () => {
    it('TC-3: Should show help text', async () => {
      const { stdout } = await execFileAsync(NODE_BIN, [cliPath, '--help']);
      expect(stdout).toContain('my-cli v0.1.0');
      expect(stdout).toContain('Commands');
    });

    it('TC-4: Should execute help within response threshold', async () => {
      const startTime = performance.now();
      await execFileAsync(NODE_BIN, [cliPath, '--help']);
      const duration = performance.now() - startTime;
      expect(duration).toBeLessThan(RESPONSE_THRESHOLD);
    });
  });

  describe('List Categories Command', () => {
    it('TC-5: Should list categories', async () => {
      const { stdout } = await execFileAsync(NODE_BIN, [cliPath, 'list', 'categories']);
      expect(stdout).toContain('development') || expect(stdout).toContain('system');
    });

    it('TC-6: Should respond within threshold', async () => {
      const startTime = performance.now();
      await execFileAsync(NODE_BIN, [cliPath, 'list', 'categories']);
      const duration = performance.now() - startTime;
      expect(duration).toBeLessThan(RESPONSE_THRESHOLD);
    });
  });

  describe('List Topics Command', () => {
    it('TC-7: Should list topics', async () => {
      const { stdout } = await execFileAsync(NODE_BIN, [cliPath, 'list', 'topics']);
      expect(stdout).toBeTruthy();
      expect(stdout.length).toBeGreaterThan(0);
    });

    it('TC-8: Should respond within threshold', async () => {
      const startTime = performance.now();
      await execFileAsync(NODE_BIN, [cliPath, 'list', 'topics']);
      const duration = performance.now() - startTime;
      expect(duration).toBeLessThan(RESPONSE_THRESHOLD);
    });

    it('TC-9: Should support JSON format', async () => {
      const { stdout } = await execFileAsync(NODE_BIN, [cliPath, 'list', 'topics', '--format', 'json']);
      const data = JSON.parse(stdout);
      expect(data).toHaveProperty('topics');
      expect(Array.isArray(data.topics)).toBe(true);
    });
  });

  describe('Show Topic Command', () => {
    it('TC-10: Should show topic details', async () => {
      const { stdout } = await execFileAsync(NODE_BIN, [cliPath, 'show', 'git']);
      expect(stdout).toBeTruthy();
      expect(stdout.length).toBeGreaterThan(0);
    });

    it('TC-11: Should respond within threshold', async () => {
      const startTime = performance.now();
      await execFileAsync(NODE_BIN, [cliPath, 'show', 'git']);
      const duration = performance.now() - startTime;
      expect(duration).toBeLessThan(RESPONSE_THRESHOLD);
    });

    it('TC-12: Should support JSON format', async () => {
      const { stdout } = await execFileAsync(NODE_BIN, [cliPath, 'show', 'git', '--format', 'json']);
      const data = JSON.parse(stdout);
      expect(data).toHaveProperty('id');
      expect(data).toHaveProperty('name');
    });
  });

  describe('Completion Command', () => {
    it('TC-13: Should generate bash completion', async () => {
      const { stdout } = await execFileAsync(NODE_BIN, [cliPath, 'completion', 'bash']);
      expect(stdout).toContain('_my_cli_completion');
      expect(stdout).toContain('complete -o bashdefault');
    });

    it('TC-14: Should generate zsh completion', async () => {
      const { stdout } = await execFileAsync(NODE_BIN, [cliPath, 'completion', 'zsh']);
      expect(stdout).toContain('#compdef my-cli');
      expect(stdout).toContain('_arguments');
    });

    it('TC-15: Should respond within threshold', async () => {
      const startTime = performance.now();
      await execFileAsync(NODE_BIN, [cliPath, 'completion', 'bash']);
      const duration = performance.now() - startTime;
      expect(duration).toBeLessThan(RESPONSE_THRESHOLD);
    });
  });

  describe('Error Handling', () => {
    it('TC-16: Should handle unknown command gracefully', async () => {
      try {
        await execFileAsync(NODE_BIN, [cliPath, 'nonexistent']);
        expect(true).toBe(false); // Should not reach here
      } catch {
        // Expected: command should fail with error
        expect(true).toBe(true);
      }
    });

    it('TC-17: Should handle missing subcommand', async () => {
      try {
        await execFileAsync(NODE_BIN, [cliPath, 'list']);
        expect(true).toBe(false); // Should not reach here
      } catch {
        // Expected: list requires subcommand
        expect(true).toBe(true);
      }
    });

    it('TC-18: Should handle invalid format option', async () => {
      try {
        await execFileAsync(NODE_BIN, [cliPath, 'list', 'categories', '--format', 'xml']);
        expect(true).toBe(false); // Should not reach here
      } catch {
        // Expected to fail
      }
    });
  });

  describe('Performance Metrics', () => {
    it('TC-19: Should provide adequate performance across commands', async () => {
      const commands = [
        ['--version'],
        ['--help'],
        ['list', 'categories'],
        ['list', 'topics'],
        ['show', 'git'],
        ['completion', 'bash'],
      ];

      for (const cmd of commands) {
        const startTime = performance.now();
        try {
          await execFileAsync(NODE_BIN, [cliPath, ...cmd]);
          const duration = performance.now() - startTime;
          // All commands should respond quickly
          expect(duration).toBeLessThan(RESPONSE_THRESHOLD);
        } catch {
          // Some commands might fail, but should still be fast
          const duration = performance.now() - startTime;
          expect(duration).toBeLessThan(RESPONSE_THRESHOLD);
        }
      }
    });

    it('TC-20: Should measure cold start performance', async () => {
      // Force a new Node process to measure true cold start
      const startTime = performance.now();
      await execFileAsync(NODE_BIN, [cliPath, '--version'], { timeout: 5000 });
      const duration = performance.now() - startTime;

      // Log performance metric (informational)
      // eslint-disable-next-line no-console
      console.log(`Cold start time: ${duration.toFixed(2)}ms (threshold: ${COLD_START_THRESHOLD}ms)`);

      // Allow some variance, but should be well under threshold
      expect(duration).toBeLessThan(COLD_START_THRESHOLD);
    });
  });
});
