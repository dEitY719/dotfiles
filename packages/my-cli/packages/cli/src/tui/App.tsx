/**
 * Main TUI application component
 * Manages screen state and overall navigation
 */

import React, { useState } from 'react';
import { Box, useInput } from 'ink';
import { HelpRegistry, HelpCategory, HelpTopic, ShellFunctionAdapter } from '@my-cli/core';
import Home from './screens/Home.js';
import Topics from './screens/Topics.js';
import TopicDetail from './screens/TopicDetail.js';

interface AppProps {
  /**
   * Registry containing categories and topics
   */
  registry: HelpRegistry;
}

type ScreenType = 'home' | 'topics' | 'detail';

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
  const [currentScreen, setCurrentScreen] = useState<ScreenType>('home');
  const [selectedCategory, setSelectedCategory] = useState<HelpCategory | null>(null);
  const [selectedTopic, setSelectedTopic] = useState<HelpTopic | null>(null);

  // Handle quit key (q or Escape) - only on home screen
  useInput((input: string, key: KeyInput) => {
    if (currentScreen === 'home' && (input === 'q' || key.escape)) {
      process.exit(0);
    }
  });

  const handleCategorySelect = (category: HelpCategory) => {
    setSelectedCategory(category);
    setCurrentScreen('topics');
  };

  const handleTopicSelect = async (topic: HelpTopic) => {
    // Try to load live content from shell first
    try {
      const adapter = new ShellFunctionAdapter('/home/bwyoon/dotfiles/shell-common/functions/my_help.sh');
      const liveContent = await adapter.getTopic(topic.id);
      setSelectedTopic(liveContent);
    } catch {
      // Fall back to the topic from registry (which may have static content)
      setSelectedTopic(topic);
    }
    setCurrentScreen('detail');
  };

  return (
    <Box flexDirection="column" padding={1}>
      {currentScreen === 'home' && (
        <Home registry={registry} onSelect={handleCategorySelect} />
      )}
      {currentScreen === 'topics' && selectedCategory && (
        <Topics
          registry={registry}
          category={selectedCategory}
          onBack={() => setCurrentScreen('home')}
          onSelect={handleTopicSelect}
        />
      )}
      {currentScreen === 'detail' && selectedTopic && (
        <TopicDetail
          topic={selectedTopic}
          onBack={() => setCurrentScreen('topics')}
        />
      )}
    </Box>
  );
};

export default App;
