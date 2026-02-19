/**
 * Dotfiles root detection and configuration loader
 * Handles environment variables, path traversal, and XDG Base Directory
 */

import * as fs from 'fs';
import * as path from 'path';
import { homedir } from 'os';
import { InternalError } from '../errors';
import { Config, DEFAULT_CONFIG, XDGDirs } from './types';

/**
 * Finds the dotfiles root directory using multiple strategies
 *
 * Priority order:
 * 1. MY_CLI_DOTFILES_ROOT environment variable
 * 2. Parent directory search (.git directory)
 * 3. Current working directory
 *
 * @returns Absolute path to dotfiles root
 * @throws InternalError if root cannot be determined
 */
export function findDotfilesRoot(): string {
  // Strategy 1: Environment variable (highest priority)
  const envRoot = process.env.MY_CLI_DOTFILES_ROOT;
  if (envRoot && fs.existsSync(envRoot)) {
    return envRoot;
  }

  // Strategy 2: Search parent directories for .git
  const gitMarker = findGitRoot();
  if (gitMarker) {
    return gitMarker;
  }

  // Strategy 3: Current working directory as fallback
  const cwd = process.cwd();
  if (fs.existsSync(cwd)) {
    return cwd;
  }

  throw new InternalError(
    'Unable to find dotfiles root. Set MY_CLI_DOTFILES_ROOT environment variable.'
  );
}

/**
 * Traverses up the directory tree to find .git directory
 * This is commonly used as the marker for dotfiles root
 *
 * @returns Path to directory containing .git, or null if not found
 */
function findGitRoot(): string | null {
  let current = process.cwd();
  const root = path.parse(current).root;

  while (current !== root) {
    const gitPath = path.join(current, '.git');
    if (fs.existsSync(gitPath)) {
      return current;
    }
    current = path.dirname(current);
  }

  return null;
}

/**
 * Resolves XDG Base Directory paths for configuration
 * Follows XDG Base Directory specification
 *
 * @returns Object containing XDG paths
 */
export function resolveXDGDirs(): XDGDirs {
  const home = homedir();

  // Support XDG_CONFIG_HOME or default to ~/.config
  let xdgConfigHome = process.env.XDG_CONFIG_HOME || path.join(home, '.config');

  // Ensure xdgConfigHome is an absolute path
  if (!path.isAbsolute(xdgConfigHome)) {
    xdgConfigHome = path.join(home, xdgConfigHome);
  }

  const configHome = path.join(xdgConfigHome, 'my-cli');

  // Fallback to ~/.my-cli for backward compatibility
  const fallbackHome = path.join(home, '.my-cli');

  // Primary config file location
  let configFile = path.join(configHome, 'config.json');

  // If primary location doesn't exist, check fallback
  if (!fs.existsSync(configFile) && fs.existsSync(fallbackHome)) {
    configFile = path.join(fallbackHome, 'config.json');
  }

  return {
    configHome,
    fallbackHome,
    configFile,
  };
}

/**
 * Loads configuration from JSON file
 * Merges with default configuration
 *
 * @param configPath - Path to config.json file
 * @returns Merged configuration object
 * @throws InternalError if file cannot be read or parsed
 */
export function loadConfigFromFile(configPath: string): Config {
  try {
    if (!fs.existsSync(configPath)) {
      // Config file doesn't exist - use defaults
      return DEFAULT_CONFIG;
    }

    const content = fs.readFileSync(configPath, 'utf-8');
    const userConfig = JSON.parse(content) as Partial<Config>;

    // Merge with defaults
    return {
      ...DEFAULT_CONFIG,
      ...userConfig,
    };
  } catch (error) {
    if (error instanceof SyntaxError) {
      throw new InternalError(
        `Configuration file parsing failed: ${configPath}\n${(error as Error).message}`
      );
    }

    if (error instanceof Error && 'code' in error) {
      const ioError = error as Error & { code?: string };
      if (ioError.code === 'EACCES') {
        throw new InternalError(
          `Configuration file is not readable: ${configPath}`
        );
      }
    }

    throw new InternalError(
      `Failed to load configuration: ${error instanceof Error ? error.message : String(error)}`
    );
  }
}

/**
 * Loads complete configuration from standard locations
 *
 * Checks:
 * 1. Environment variable MY_CLI_CONFIG
 * 2. XDG config directory (~/.config/my-cli/config.json)
 * 3. Fallback directory (~/.my-cli/config.json)
 *
 * @returns Configuration object with user settings merged with defaults
 */
export function loadConfig(): Config {
  // Check for environment variable override
  const envConfigPath = process.env.MY_CLI_CONFIG;
  if (envConfigPath) {
    return loadConfigFromFile(envConfigPath);
  }

  // Resolve XDG paths
  const xdgDirs = resolveXDGDirs();

  // Load from XDG config path
  return loadConfigFromFile(xdgDirs.configFile);
}

/**
 * Returns the full configuration context including dotfiles root
 * Useful for passing around the complete runtime environment
 */
export interface ConfigContext {
  dotfilesRoot: string;
  config: Config;
  xdgDirs: XDGDirs;
}

/**
 * Loads complete configuration context
 *
 * @returns Object containing dotfiles root, config, and XDG paths
 */
export function loadConfigContext(): ConfigContext {
  const dotfilesRoot = findDotfilesRoot();
  const xdgDirs = resolveXDGDirs();
  const config = loadConfig();

  return {
    dotfilesRoot,
    config,
    xdgDirs,
  };
}
