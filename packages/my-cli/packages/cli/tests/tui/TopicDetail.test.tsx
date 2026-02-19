/**
 * Tests for TopicDetail screen component
 * Tests detailed topic display with content, examples, and aliases
 */

import { describe, it, expect, beforeEach, vi } from 'vitest';
import React from 'react';
import { render } from 'ink-testing-library';
import { HelpTopic } from '@my-cli/core';
import TopicDetail from '../../src/tui/screens/TopicDetail';

/**
 * Create a test topic with rich data
 */
function createTestTopic(overrides?: Partial<HelpTopic>): HelpTopic {
  return {
    id: 'git',
    name: 'git',
    category: 'development',
    description: 'Distributed version control',
    content: 'Git is a distributed version control system...',
    examples: ['git init', 'git clone <url>'],
    aliases: ['g'],
    source: 'static',
    ...overrides,
  };
}

describe('TopicDetail', () => {
  let mockOnBack: ReturnType<typeof vi.fn>;

  beforeEach(() => {
    mockOnBack = vi.fn();
  });

  it('TC-1: displays topic name as title', () => {
    const topic = createTestTopic();
    const { lastFrame } = render(
      <TopicDetail topic={topic} onBack={mockOnBack} />,
    );

    const output = lastFrame()!;
    expect(output).toContain('git');
  });

  it('TC-2: displays topic description', () => {
    const topic = createTestTopic();
    const { lastFrame } = render(
      <TopicDetail topic={topic} onBack={mockOnBack} />,
    );

    const output = lastFrame()!;
    expect(output).toContain('Distributed version control');
  });

  it('TC-3: displays topic content when available', () => {
    const topic = createTestTopic({
      content: 'Git is a distributed version control system...',
    });
    const { lastFrame } = render(
      <TopicDetail topic={topic} onBack={mockOnBack} />,
    );

    const output = lastFrame()!;
    expect(output).toContain('Git is a distributed version control system');
  });

  it('TC-4: displays examples when available', () => {
    const topic = createTestTopic({
      examples: ['git init', 'git clone <url>'],
    });
    const { lastFrame } = render(
      <TopicDetail topic={topic} onBack={mockOnBack} />,
    );

    const output = lastFrame()!;
    expect(output).toContain('Examples:');
    expect(output).toContain('git init');
    expect(output).toContain('git clone');
  });

  it('TC-5: displays "No content" when content is missing', () => {
    const topic = createTestTopic({ content: undefined });
    const { lastFrame } = render(
      <TopicDetail topic={topic} onBack={mockOnBack} />,
    );

    const output = lastFrame()!;
    expect(output).toContain('No content');
  });

  it('TC-6: displays "Esc to go back" hint at bottom', () => {
    const topic = createTestTopic();
    const { lastFrame } = render(
      <TopicDetail topic={topic} onBack={mockOnBack} />,
    );

    const output = lastFrame()!;
    expect(output).toContain('Esc to go back');
  });

  it('TC-7: displays aliases when available', () => {
    const topic = createTestTopic({ aliases: ['g', 'git-flow'] });
    const { lastFrame } = render(
      <TopicDetail topic={topic} onBack={mockOnBack} />,
    );

    const output = lastFrame()!;
    expect(output).toContain('Aliases:');
    expect(output).toContain('g');
    expect(output).toContain('git-flow');
  });

  it('TC-8: displays source and category metadata', () => {
    const topic = createTestTopic({
      source: 'static',
      category: 'development',
    });
    const { lastFrame } = render(
      <TopicDetail topic={topic} onBack={mockOnBack} />,
    );

    const output = lastFrame()!;
    expect(output).toContain('static');
    expect(output).toContain('development');
  });
});
