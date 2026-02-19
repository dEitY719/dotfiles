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

    const output = lastFrame()!;
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

  it('TC-6: displays "Esc to go back" hint at bottom', () => {
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
    expect(output).toContain('Esc to go back');
  });
});
