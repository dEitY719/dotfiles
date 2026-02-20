/**
 * Topics screen component
 * Displays interactive topic list for a selected category
 */

import React, { useMemo, useState } from 'react';
import { Box, Text, useInput } from 'ink';
import { HelpRegistry, HelpCategory, HelpTopic } from '@my-cli/core';
import Fuse from 'fuse.js';

interface TopicsProps {
  /**
   * Registry containing categories and topics
   */
  registry: HelpRegistry;

  /**
   * Selected category to display topics for
   */
  category: HelpCategory;

  /**
   * Callback when user wants to go back to home screen
   */
  onBack: () => void;

  /**
   * Callback when topic is selected (for CL-4.3 detail screen)
   * Can be async to load topic content
   */
  onSelect: (topic: HelpTopic) => void | Promise<void>;
}

interface KeyInput {
  upArrow?: boolean;
  downArrow?: boolean;
  escape?: boolean;
  backspace?: boolean;
}

/**
 * Topics screen showing topic list with arrow navigation
 *
 * @param props Component props
 * @returns Rendered topics screen
 *
 * @example
 * ```tsx
 * <Topics
 *   registry={registry}
 *   category={category}
 *   onBack={() => setScreen('home')}
 *   onSelect={(topic) => setScreen('detail')}
 * />
 * ```
 */
const Topics: React.FC<TopicsProps> = ({
  registry,
  category,
  onBack,
  onSelect,
}) => {
  const topics = registry.getTopicsByCategory(category.key);
  const [selectedIndex, setSelectedIndex] = useState(0);
  const [searchMode, setSearchMode] = useState(false);
  const [query, setQuery] = useState('');

  // Create Fuse instance for fuzzy search
  const fuse = useMemo(
    () =>
      new Fuse(topics, {
        keys: ['name', 'description', 'aliases'],
        threshold: 0.4,
      }),
    [topics],
  );

  // Filter topics based on search query
  const filteredTopics = useMemo(
    () => (query ? fuse.search(query).map((result) => result.item) : topics),
    [query, fuse, topics],
  );

  // Handle arrow key navigation, Enter, and Escape
  useInput((input: string, key: KeyInput) => {
    if (searchMode) {
      // Search mode key handling
      if (key.backspace) {
        setQuery((prev) => prev.slice(0, -1));
      } else if (key.escape) {
        // Exit search or clear query
        if (query) {
          setQuery('');
        } else {
          setSearchMode(false);
        }
      } else if (input === '\r' && filteredTopics.length > 0) {
        // Enter key - select first result
        onSelect(filteredTopics[selectedIndex]);
      } else if (input && input !== '/') {
        // Add character to query
        setQuery((prev) => prev + input);
        setSelectedIndex(0);
      }
    } else {
      // Normal mode key handling
      if (input === '/') {
        // Enter search mode
        setSearchMode(true);
      } else if (key.upArrow) {
        setSelectedIndex((prev) => Math.max(0, prev - 1));
      } else if (key.downArrow) {
        setSelectedIndex((prev) => Math.min(topics.length - 1, prev + 1));
      } else if (input === '\r' && topics.length > 0) {
        // Enter key
        onSelect(topics[selectedIndex]);
      } else if (key.escape) {
        // Escape key
        onBack();
      }
    }
  });

  // Show empty state
  if (topics.length === 0) {
    return (
      <Box flexDirection="column">
        <Box marginBottom={1}>
          <Text bold>{category.label}</Text>
        </Box>
        <Box marginBottom={1}>
          <Text>No topics</Text>
        </Box>
        <Box>
          <Text dimColor>↑↓ navigate, Enter select, / search, Esc back</Text>
        </Box>
      </Box>
    );
  }

  // Use filtered topics if in search mode, otherwise use all topics
  const displayTopics = searchMode ? filteredTopics : topics;

  return (
    <Box flexDirection="column">
      <Box marginBottom={1}>
        <Text bold>{category.label}</Text>
      </Box>

      {/* Search input display */}
      {searchMode && (
        <Box marginBottom={1}>
          <Text>
            / {query}
            <Text dimColor>_</Text>
          </Text>
        </Box>
      )}

      {/* No results state */}
      {searchMode && filteredTopics.length === 0 && (
        <Box marginBottom={1}>
          <Text dimColor>No results</Text>
        </Box>
      )}

      {/* Topics list */}
      {displayTopics.map((topic, index) => {
        const isSelected = index === selectedIndex;
        const prefix = isSelected ? '> ' : '  ';
        const color = isSelected ? 'cyan' : 'white';

        return (
          <Box key={topic.id} flexDirection="row" paddingY={0}>
            <Text color={color} bold={isSelected}>
              {prefix}
              {topic.name.padEnd(20)}
              {topic.description}
            </Text>
          </Box>
        );
      })}

      <Box marginTop={1}>
        <Text dimColor>
          {searchMode
            ? 'Type to search, Esc to clear/exit'
            : '↑↓ navigate, Enter select, / search, Esc back'}
        </Text>
      </Box>
    </Box>
  );
};

export default Topics;
