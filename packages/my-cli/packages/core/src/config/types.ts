/**
 * Configuration types for my-cli
 */

export interface Config {
  /**
   * Theme for TUI output (e.g., 'light', 'dark', 'auto')
   */
  theme?: 'light' | 'dark' | 'auto';

  /**
   * Default pager command (e.g., 'less -R', 'more', 'cat')
   */
  pager?: string;

  /**
   * Enable shell loader for dynamic registry loading
   */
  shellLoader?: boolean;

  /**
   * Custom registry paths (optional, for future extensibility)
   */
  registryPaths?: string[];

  /**
   * Logging level
   */
  logLevel?: 'debug' | 'info' | 'warn' | 'error';

  /**
   * Whether to use interactive mode by default
   */
  interactive?: boolean;
}

/**
 * Default configuration values
 */
export const DEFAULT_CONFIG: Config = {
  theme: 'auto',
  pager: 'less -R',
  shellLoader: false,
  registryPaths: [],
  logLevel: 'info',
  interactive: true,
};

/**
 * XDG Base Directory specification paths
 */
export interface XDGDirs {
  /** ~/.config/my-cli */
  configHome: string;
  /** ~/.my-cli (fallback) */
  fallbackHome: string;
  /** Config file path */
  configFile: string;
}
