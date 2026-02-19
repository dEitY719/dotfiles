/**
 * Tests for ShellFunctionAdapter
 * Tests calling shell functions and parsing output
 */

import { describe, it, expect, beforeEach, vi } from 'vitest';
import { ShellFunctionAdapter } from '../../src/adapters/ShellFunctionAdapter.js';
import {
  ValidationError,
  SecurityError,
  InternalError,
  MyCLIError,
} from '../../src/errors.js';

describe('ShellFunctionAdapter', () => {
  let adapter: ShellFunctionAdapter;
  const helpFilePath = '/home/bwyoon/dotfiles/shell-common/functions/my_help.sh';

  beforeEach(() => {
    adapter = new ShellFunctionAdapter(helpFilePath, 'bash', 5000);
  });

  it('TC-1: getTopic with valid topic returns HelpTopic', async () => {
    const topic = await adapter.getTopic('git');

    expect(topic).toBeDefined();
    expect(topic.id).toBe('git');
    expect(topic.name).toBe('Git');
    expect(topic.source).toBe('shell');
    expect(topic.content).toBeTruthy();
    expect(topic.content?.length).toBeGreaterThan(0);
  });

  it('TC-2: getTopic with empty topic name throws error', async () => {
    // validateTopic should reject empty strings
    await expect(adapter.getTopic('')).rejects.toThrow(MyCLIError);
  });

  it('TC-3: getTopic with dangerous input throws MyCLIError', async () => {
    // Test shell injection attempts (throws SecurityError)
    await expect(adapter.getTopic('; rm -rf /')).rejects.toThrow(
      MyCLIError,
    );

    // Test path traversal (throws SecurityError)
    await expect(adapter.getTopic('../etc/passwd')).rejects.toThrow(
      MyCLIError,
    );

    // Test backtick command substitution (throws SecurityError)
    await expect(adapter.getTopic('`whoami`')).rejects.toThrow(
      MyCLIError,
    );
  });

  it('TC-4: getTopic with git returns consistent data', async () => {
    const topic1 = await adapter.getTopic('git');
    const topic2 = await adapter.getTopic('git');

    expect(topic1.id).toBe(topic2.id);
    expect(topic1.content).toBe(topic2.content);
  });

  it('TC-5: getTopic with empty string throws ValidationError', async () => {
    await expect(adapter.getTopic('')).rejects.toThrow(ValidationError);
  });

  it('TC-6: getTopic content contains topic information', async () => {
    const topic = await adapter.getTopic('git');

    // Content should mention git in some way (case insensitive)
    expect(topic.content?.toLowerCase()).toMatch(/git|distributed|version|control/);
  });
});
