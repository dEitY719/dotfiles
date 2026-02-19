/**
 * TopicDetail screen component
 * Displays detailed information about a selected help topic
 */

import React, { useState, useMemo } from 'react';
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
  pageUp?: boolean;
  pageDown?: boolean;
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
  const LINES_PER_PAGE = 10;
  const [scrollOffset, setScrollOffset] = useState(0);

  // Split content into lines and calculate pagination
  const contentLines = useMemo(
    () => (topic.content ? topic.content.split('\n') : []),
    [topic.content],
  );

  const totalPages = useMemo(
    () => Math.max(1, Math.ceil(contentLines.length / LINES_PER_PAGE)),
    [contentLines],
  );

  const visibleLines = useMemo(
    () =>
      contentLines.slice(
        scrollOffset * LINES_PER_PAGE,
        (scrollOffset + 1) * LINES_PER_PAGE,
      ),
    [contentLines, scrollOffset],
  );

  // Handle key navigation
  useInput((_input: string, key: KeyInput) => {
    if (key.escape) {
      onBack();
    } else if (key.pageDown) {
      setScrollOffset((prev) => Math.min(totalPages - 1, prev + 1));
    } else if (key.pageUp) {
      setScrollOffset((prev) => Math.max(0, prev - 1));
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

      {/* Content section (paginated) */}
      <Box marginBottom={1} flexDirection="column">
        {topic.content ? (
          <>
            {visibleLines.map((line) => (
              <Text key={line || Math.random()}>{line}</Text>
            ))}
            {scrollOffset < totalPages - 1 && (
              <Text dimColor>▼ more</Text>
            )}
          </>
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
        <Text dimColor>
          {totalPages > 1 ? 'PgUp/PgDn to scroll, ' : ''}Esc to go back
        </Text>
      </Box>
    </Box>
  );
};

export default TopicDetail;
