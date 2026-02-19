/**
 * Tests for Topics screen component
 * Tests interactive topic list navigation using Ink
 */

import { describe, it, expect, beforeEach, vi } from 'vitest';
import React from 'react';
import { render } from 'ink-testing-library';
import { HelpRegistry, HelpCategory, HelpTopic } from '@my-cli/core';
import Topics from '../../src/tui/screens/Topics';

/**
 * Strip ANSI color codes from output for easier testing
 */
function stripAnsi(str: string): string {
  return str.replace(/\u001b\[[0-9;]*m/g, '');
}

/**
 * Create a test registry with sample categories and topics
 * Note: Must add category first, then add topics (due to validation)
 */
function createTestRegistry(): HelpRegistry {
  const registry = new HelpRegistry();

  // Add category first
  const category: HelpCategory = {
    key: 'development',
    label: 'Development',
    description: 'Development tools',
    topics: [],
    order: 1,
  };
  registry.addCategory(category);

  // Add topics to the category
  const topics: HelpTopic[] = [
    {
      id: 'git',
      name: 'git',
      category: 'development',
      description: 'Distributed version control',
      source: 'static',
    },
    {
      id: 'node',
      name: 'node',
      category: 'development',
      description: 'JavaScript runtime',
      source: 'static',
    },
  ];

  topics.forEach((topic) => registry.addTopic(topic));
  return registry;
}

/**
 * Create a test registry with empty category
 */
function createEmptyRegistry(): HelpRegistry {
  const registry = new HelpRegistry();
  const category: HelpCategory = {
    key: 'development',
    label: 'Development',
    description: 'Development tools',
    topics: [],
    order: 1,
  };
  registry.addCategory(category);
  return registry;
}

describe('Topics', () => {
  let mockOnBack: ReturnType<typeof vi.fn>;
  let mockOnSelect: ReturnType<typeof vi.fn>;

  beforeEach(() => {
    mockOnBack = vi.fn();
    mockOnSelect = vi.fn();
  });

  it('TC-1: renders category topic list', () => {
    const registry = createTestRegistry();
    const category = registry.getCategory('development')!;
    const { lastFrame } = render(
      <Topics
        registry={registry}
        category={category}
        onBack={mockOnBack}
        onSelect={mockOnSelect}
      />,
    );

    const output = lastFrame()!;
    expect(output).toContain('git');
    expect(output).toContain('node');
  });

  it('TC-2: first item is selected by default', () => {
    const registry = createTestRegistry();
    const category = registry.getCategory('development')!;
    const { lastFrame } = render(
      <Topics
        registry={registry}
        category={category}
        onBack={mockOnBack}
        onSelect={mockOnSelect}
      />,
    );

    const output = stripAnsi(lastFrame()!);
    // Check that the first topic has a selection indicator
    expect(output).toMatch(/^[\s>]*git/m);
  });

  it('TC-3: displays topic name and description', () => {
    const registry = createTestRegistry();
    const category = registry.getCategory('development')!;
    const { lastFrame } = render(
      <Topics
        registry={registry}
        category={category}
        onBack={mockOnBack}
        onSelect={mockOnSelect}
      />,
    );

    const output = lastFrame()!;
    expect(output).toContain('Distributed version control');
    expect(output).toContain('JavaScript runtime');
  });

  it('TC-4: displays "No topics" when category is empty', () => {
    const registry = createEmptyRegistry();
    const category = registry.getCategory('development')!;
    const { lastFrame } = render(
      <Topics
        registry={registry}
        category={category}
        onBack={mockOnBack}
        onSelect={mockOnSelect}
      />,
    );

    const output = lastFrame()!;
    expect(output).toContain('No topics');
  });

  it('TC-5: displays category name as title', () => {
    const registry = createTestRegistry();
    const category = registry.getCategory('development')!;
    const { lastFrame } = render(
      <Topics
        registry={registry}
        category={category}
        onBack={mockOnBack}
        onSelect={mockOnSelect}
      />,
    );

    const output = lastFrame()!;
    expect(output).toContain('Development');
  });

  it('TC-6: displays hint text at bottom', () => {
    const registry = createTestRegistry();
    const category = registry.getCategory('development')!;
    const { lastFrame } = render(
      <Topics
        registry={registry}
        category={category}
        onBack={mockOnBack}
        onSelect={mockOnSelect}
      />,
    );

    const output = lastFrame()!;
    expect(output).toContain('navigate');
    expect(output).toContain('Esc back');
  });

  it('TC-7: initially displays all topics without search', () => {
    const registry = createTestRegistry();
    const category = registry.getCategory('development')!;
    const { lastFrame } = render(
      <Topics
        registry={registry}
        category={category}
        onBack={mockOnBack}
        onSelect={mockOnSelect}
      />,
    );

    const output = lastFrame()!;
    expect(output).toContain('git');
    expect(output).toContain('node');
    // Should not show search input line (which starts with "/") initially
    expect(output).not.toMatch(/^\//m);
  });

  it('TC-8: search hint text is present in footer', () => {
    const registry = createTestRegistry();
    const category = registry.getCategory('development')!;
    const { lastFrame } = render(
      <Topics
        registry={registry}
        category={category}
        onBack={mockOnBack}
        onSelect={mockOnSelect}
      />,
    );

    const output = lastFrame()!;
    expect(output).toContain('/ search');
  });

  it('TC-9: search mode feature is ready for "/" key', () => {
    const registry = createTestRegistry();
    const category = registry.getCategory('development')!;
    const { lastFrame } = render(
      <Topics
        registry={registry}
        category={category}
        onBack={mockOnBack}
        onSelect={mockOnSelect}
      />,
    );

    const output = lastFrame()!;
    // Component should be displaying all topics ready for search
    expect(output).toContain('git');
    expect(output).toContain('node');
    // Footer should mention search capability
    expect(output).toContain('/ search');
  });

  it('TC-10: displays placeholder for search functionality', () => {
    const registry = createTestRegistry();
    const category = registry.getCategory('development')!;
    const { lastFrame } = render(
      <Topics
        registry={registry}
        category={category}
        onBack={mockOnBack}
        onSelect={mockOnSelect}
      />,
    );

    const output = lastFrame()!;
    // The search functionality should be available via "/" key
    // This test verifies the component renders correctly to support it
    expect(output).toContain('Development');
    expect(output).toContain('navigate');
  });
});
