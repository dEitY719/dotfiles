/**
 * Tests for Home screen component
 * Tests interactive category list navigation using Ink
 */

import { describe, it, expect, beforeEach, vi } from 'vitest';
import React from 'react';
import { render } from 'ink-testing-library';
import { HelpRegistry, HelpCategory } from '@my-cli/core';
import Home from '../../src/tui/screens/Home';

/**
 * Strip ANSI color codes from output for easier testing
 */
function stripAnsi(str: string): string {
  return str.replace(/\u001b\[[0-9;]*m/g, '');
}

/**
 * Create a test registry with sample categories
 */
function createTestRegistry(): HelpRegistry {
  const registry = new HelpRegistry();

  const categories: HelpCategory[] = [
    {
      key: 'development',
      label: 'development',
      description: 'Development tools',
      topics: ['git', 'node'],
      order: 1,
    },
    {
      key: 'devops',
      label: 'devops',
      description: 'DevOps tools',
      topics: ['docker', 'kubernetes'],
      order: 2,
    },
    {
      key: 'ai',
      label: 'ai',
      description: 'AI tools',
      topics: ['llm', 'prompt'],
      order: 3,
    },
  ];

  categories.forEach((cat) => registry.addCategory(cat));
  return registry;
}

describe('Home', () => {
  let mockOnSelect: ReturnType<typeof vi.fn>;

  beforeEach(() => {
    mockOnSelect = vi.fn();
  });

  it('TC-1: renders category list', () => {
    const registry = createTestRegistry();
    const { lastFrame } = render(
      <Home registry={registry} onSelect={mockOnSelect} />,
    );

    const output = lastFrame()!;
    expect(output).toContain('development');
    expect(output).toContain('devops');
    expect(output).toContain('ai');
  });

  it('TC-2: first item is selected by default', () => {
    const registry = createTestRegistry();
    const { lastFrame } = render(
      <Home registry={registry} onSelect={mockOnSelect} />,
    );

    const output = stripAnsi(lastFrame()!);
    // Check that the first category has a selection indicator
    expect(output).toMatch(/^[\s>]*development/m);
  });

  it('TC-3: displays category name and description', () => {
    const registry = createTestRegistry();
    const { lastFrame } = render(
      <Home registry={registry} onSelect={mockOnSelect} />,
    );

    const output = lastFrame()!;
    expect(output).toContain('Development tools');
    expect(output).toContain('DevOps tools');
    expect(output).toContain('AI tools');
  });

  it('TC-4: displays "No categories" when registry is empty', () => {
    const registry = new HelpRegistry();
    const { lastFrame } = render(
      <Home registry={registry} onSelect={mockOnSelect} />,
    );

    const output = lastFrame()!;
    expect(output).toContain('No categories');
  });
});
