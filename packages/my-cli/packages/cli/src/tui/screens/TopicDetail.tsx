/**
 * TopicDetail screen component
 * Displays detailed information about a selected help topic
 */

import React from 'react';
import { Box, Text, useInput } from 'ink';
import { HelpTopic } from '@my-cli/core';

interface TopicDetailProps {
  /**
   * Topic to display details for
   */
  topic: HelpTopic;

  /**
   * Callback when user presses Esc to go back to topics list
   */
  onBack: () => void;
}

interface KeyInput {
  escape?: boolean;
}

/**
 * TopicDetail screen showing full topic information
 *
 * @param props Component props
 * @returns Rendered detail screen
 *
 * @example
 * ```tsx
 * <TopicDetail
 *   topic={topic}
 *   onBack={() => setScreen('topics')}
 * />
 * ```
 */
const TopicDetail: React.FC<TopicDetailProps> = ({ topic, onBack }) => {
  // Handle Escape key to go back
  useInput((_input: string, key: KeyInput) => {
    if (key.escape) {
      onBack();
    }
  });

  return (
    <Box flexDirection="column" padding={1}>
      {/* Title */}
      <Box marginBottom={1}>
        <Text bold>{topic.name}</Text>
      </Box>

      {/* Metadata: source and category */}
      <Box marginBottom={1}>
        <Text dimColor>
          Source: {topic.source} | Category: {topic.category}
        </Text>
      </Box>

      {/* Divider */}
      <Box marginBottom={1}>
        <Text dimColor>────────────────────────────────────────</Text>
      </Box>

      {/* Description */}
      <Box marginBottom={1}>
        <Text>{topic.description}</Text>
      </Box>

      {/* Content section */}
      <Box marginBottom={1} flexDirection="column">
        {topic.content ? (
          <Text>{topic.content}</Text>
        ) : (
          <Text dimColor>No content</Text>
        )}
      </Box>

      {/* Examples section (optional) */}
      {topic.examples && topic.examples.length > 0 && (
        <Box marginBottom={1} flexDirection="column">
          <Box marginBottom={0}>
            <Text>Examples:</Text>
          </Box>
          {topic.examples.map((example) => (
            <Box key={example} paddingLeft={2}>
              <Text>{example}</Text>
            </Box>
          ))}
        </Box>
      )}

      {/* Aliases section (optional) */}
      {topic.aliases && topic.aliases.length > 0 && (
        <Box marginBottom={1}>
          <Text>Aliases: {topic.aliases.join(', ')}</Text>
        </Box>
      )}

      {/* Footer hint */}
      <Box marginTop={1}>
        <Text dimColor>Esc to go back</Text>
      </Box>
    </Box>
  );
};

export default TopicDetail;
