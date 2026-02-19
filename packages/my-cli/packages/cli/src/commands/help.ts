/**
 * Help command - displays interactive TUI for help system
 * Uses Ink/React for rendering the terminal UI
 *
 * CL-4.1: Ink-based interactive help command
 */

import React from 'react';
import { render } from 'ink';
import { loadRegistry, findDotfilesRoot } from '@my-cli/core';
import App from '../tui/App.js';

/**
 * Help command handler
 * Loads registry and displays interactive TUI
 *
 * @returns Exit code (never reached - process.exit called by app)
 */
export async function helpCommand(): Promise<number> {
  try {
    // Get dotfiles root and construct path to help file
    const dotfilesRoot = findDotfilesRoot();
    const helpFilePath = `${dotfilesRoot}/shell-common/functions/my_help.sh`;

    // Load registry - use shell mode for accurate current state
    const registry = await loadRegistry(helpFilePath, 'shell');

    // Render TUI
    render(React.createElement(App, { registry }));

    // Wait for the app to finish (process.exit will be called from quit)
    // This line will never be reached in normal operation
    return 0;
  } catch (error) {
    // eslint-disable-next-line no-console
    console.error(
      'Error loading help:',
      error instanceof Error ? error.message : error,
    );
    return 1;
  }
}
