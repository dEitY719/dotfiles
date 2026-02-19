#!/usr/bin/env node

/**
 * CLI entry point
 * Routes commands and handles global options
 */

import { parseArgs, createCommandRouter, listCommand, showCommand, helpCommand } from './commands/index.js';

/**
 * Main entry point
 */
async function main(): Promise<void> {
  try {
    // Parse command-line arguments
    const argv = await parseArgs(process.argv.slice(2));

    // Handle version flag
    if (argv.version) {
      // eslint-disable-next-line no-console
      console.log('0.1.0');
      process.exit(0);
    }

    // Handle help flag
    if (argv.help) {
      // eslint-disable-next-line no-console
      console.log(`my-cli v0.1.0 - Personal CLI tool suite

Usage: my-cli [command] [options]

Global Options:
  --json, -j              Output in JSON format
  --text, -t              Output in text format
  --format <type>         Output format (json, text)
  --search, -s <term>     Search term for filtering
  --filter, -f <category> Filter by category
  --raw, -r               Raw output without formatting
  --version, -v           Show version
  --help, -h              Show help

Commands:
  list                    List categories or topics
  show                    Show topic details

Examples:
  my-cli list categories
  my-cli list topics --search git
  my-cli show git --json
  my-cli show git --raw
`);
      process.exit(0);
    }

    // Get command from first positional argument
    const command = argv._[0];

    // Handle help command - interactive TUI mode
    if (command === 'help' || (!command && process.stdin.isTTY)) {
      const exitCode = await helpCommand();
      process.exit(exitCode);
    }

    if (!command) {
      // eslint-disable-next-line no-console
      console.log('my-cli v0.1.0 - Personal CLI tool suite');
      // eslint-disable-next-line no-console
      console.log('Use "my-cli --help" for usage information');
      process.exit(0);
    }

    // Create router and register commands
    const router = createCommandRouter();
    router.registerCommand('list', 'List categories or topics', listCommand);
    router.registerCommand('show', 'Show topic details', showCommand);
    router.registerCommand('help', 'Interactive help (TUI)', helpCommand);

    // Route to command
    try {
      const exitCode = await router.execute(command, argv);
      process.exit(exitCode);
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error(`Error: Unknown command "${command}"`);
      // eslint-disable-next-line no-console
      console.error('Use "my-cli --help" for usage information');
      process.exit(1);
    }
  } catch (error) {
    // eslint-disable-next-line no-console
    console.error('Error:', error instanceof Error ? error.message : error);
    process.exit(1);
  }
}

main();
