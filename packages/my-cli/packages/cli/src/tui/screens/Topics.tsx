/**
 * Topics screen component
 * Displays interactive topic list for a selected category
 */

import React, { useState } from 'react';
import { Box, Text, useInput } from 'ink';
import { HelpRegistry, HelpCategory, HelpTopic } from '@my-cli/core';

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
   */
  onSelect: (topic: HelpTopic) => void;
}

interface KeyInput {
  upArrow?: boolean;
  downArrow?: boolean;
  escape?: boolean;
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

  // Handle arrow key navigation, Enter, and Escape
  useInput((input: string, key: KeyInput) => {
    if (key.upArrow) {
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
          <Text dimColor>↑↓ to navigate, Enter to select, Esc to go back, q to quit</Text>
        </Box>
      </Box>
    );
  }

  return (
    <Box flexDirection="column">
      <Box marginBottom={1}>
        <Text bold>{category.label}</Text>
      </Box>
      {topics.map((topic, index) => {
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
        <Text dimColor>↑↓ to navigate, Enter to select, Esc to go back, q to quit</Text>
      </Box>
    </Box>
  );
};

export default Topics;
