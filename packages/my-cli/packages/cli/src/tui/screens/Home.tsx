/**
 * Home screen component
 * Displays interactive category list for navigation
 */

import React, { useState } from 'react';
import { Box, Text, useInput } from 'ink';
import { HelpRegistry, HelpCategory } from '@my-cli/core';

interface HomeProps {
  /**
   * Registry containing categories and topics
   */
  registry: HelpRegistry;

  /**
   * Callback when category is selected
   */
  onSelect: (category: HelpCategory) => void;
}

interface KeyInput {
  upArrow?: boolean;
  downArrow?: boolean;
  escape?: boolean;
}

/**
 * Home screen showing category list with arrow navigation
 *
 * @param props Component props
 * @returns Rendered home screen
 *
 * @example
 * ```tsx
 * <Home registry={registry} onSelect={handleSelect} />
 * ```
 */
const Home: React.FC<HomeProps> = ({ registry, onSelect }) => {
  const categories = registry.getCategories();
  const [selectedIndex, setSelectedIndex] = useState(0);

  // Handle arrow key navigation
  useInput((input: string, key: KeyInput) => {
    if (key.upArrow) {
      setSelectedIndex((prev) => Math.max(0, prev - 1));
    } else if (key.downArrow) {
      setSelectedIndex((prev) => Math.min(categories.length - 1, prev + 1));
    } else if (input === '\r' && categories.length > 0) {
      // Enter key
      onSelect(categories[selectedIndex]);
    }
  });

  // Show empty state
  if (categories.length === 0) {
    return (
      <Box flexDirection="column">
        <Text>No categories</Text>
      </Box>
    );
  }

  return (
    <Box flexDirection="column">
      {categories.map((category, index) => {
        const isSelected = index === selectedIndex;
        const prefix = isSelected ? '> ' : '  ';
        const color = isSelected ? 'cyan' : 'white';

        return (
          <Box key={`category-${index}`} flexDirection="row" paddingY={0}>
            <Text color={color} bold={isSelected}>
              {prefix}
              {category.label.padEnd(20)}
              {category.description}
            </Text>
          </Box>
        );
      })}
      <Box marginTop={1}>
        <Text dimColor>↑↓ to navigate, Enter to select, q to quit</Text>
      </Box>
    </Box>
  );
};

export default Home;
