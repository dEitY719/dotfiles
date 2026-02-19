/**
 * Main TUI application component
 * Manages screen state and overall navigation
 */

import React, { useState } from 'react';
import { Box, useInput } from 'ink';
import { HelpRegistry, HelpCategory } from '@my-cli/core';
import Home from './screens/Home.js';

interface AppProps {
  /**
   * Registry containing categories and topics
   */
  registry: HelpRegistry;
}

type ScreenType = 'home' | 'topics';

interface KeyInput {
  escape?: boolean;
  upArrow?: boolean;
  downArrow?: boolean;
}

/**
 * Main app component for TUI
 *
 * @param props Component props
 * @returns Rendered app
 */
const App: React.FC<AppProps> = ({ registry }) => {
  const [currentScreen] = useState<ScreenType>('home');

  // Handle quit key (q or Escape)
  useInput((input: string, key: KeyInput) => {
    if (input === 'q' || key.escape) {
      process.exit(0);
    }
  });

  const handleCategorySelect = (_category: HelpCategory) => {
    // CL-4.2 will implement topics screen navigation
    // setCurrentScreen('topics');
  };

  return (
    <Box flexDirection="column" padding={1}>
      {currentScreen === 'home' && (
        <Home registry={registry} onSelect={handleCategorySelect} />
      )}
      {/* CL-4.2: Topics screen will be added here */}
    </Box>
  );
};

export default App;
