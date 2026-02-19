/**
 * Unified registry loader with mode selection
 * Integrates parseStaticRegistry and loadByShell with intelligent routing
 *
 * CL-2.4: Registry Integration and Loader Selection
 */

import { HelpRegistry } from './Registry';
import { parseStaticRegistry } from './parse_static';
import { loadByShell, LoadByShellOptions } from './load_by_shell';
import { ValidationError, InternalError } from '../errors';

/**
 * Loader mode for registry loading strategy
 * - 'static': Use static file parsing (fast, no shell execution)
 * - 'shell': Use dynamic shell execution (accurate current state)
 * - 'auto': Try shell first, fallback to static (default)
 */
export type LoaderMode = 'static' | 'shell' | 'auto';

/**
 * Configuration for registry loader
 */
export interface LoaderConfig {
  /**
   * Mode for loading registry
   * @default 'auto'
   */
  mode?: LoaderMode;

  /**
   * Enable caching of loaded registries
   * @default true
   */
  cacheEnabled?: boolean;

  /**
   * Cache time-to-live in milliseconds
   * @default 3600000 (1 hour)
   */
  cacheTTL?: number;

  /**
   * Timeout for shell execution in milliseconds
   * @default 5000
   */
  shellTimeout?: number;

  /**
   * Enable debug logging
   * @default false
   */
  debug?: boolean;
}

/**
 * Default loader configuration
 */
const DEFAULT_CONFIG: LoaderConfig = {
  mode: 'auto',
  cacheEnabled: true,
  cacheTTL: 3600000, // 1 hour
  shellTimeout: 5000,
  debug: false,
};

/**
 * Cache entry for storing loaded registries
 */
interface CacheEntry {
  registry: HelpRegistry;
  timestamp: number;
}

/**
 * Global cache for loaded registries
 */
const registryCache = new Map<string, CacheEntry>();

/**
 * Creates a loader configuration with defaults
 *
 * @param overrides - Configuration overrides
 * @returns Merged configuration with defaults
 *
 * @example
 * ```typescript
 * const config = createLoaderConfig({ mode: 'shell', cacheEnabled: false });
 * ```
 */
export function createLoaderConfig(overrides?: Partial<LoaderConfig>): LoaderConfig {
  return {
    ...DEFAULT_CONFIG,
    ...overrides,
  };
}

/**
 * Loads help registry using configured mode and fallback strategy
 * Supports static file parsing, shell execution, or automatic selection
 *
 * @param filePath - Path to help file (e.g., my_help.sh)
 * @param mode - Loading mode: 'static', 'shell', or 'auto' (default)
 * @param options - Additional configuration options
 * @returns Promise<HelpRegistry> - Populated registry
 * @throws ValidationError if file not found or invalid mode
 * @throws InternalError if loading fails in all modes
 *
 * @example
 * ```typescript
 * // Auto mode with caching
 * const registry = await loadRegistry('./my_help.sh');
 *
 * // Static mode (file-based parsing)
 * const registry = await loadRegistry('./my_help.sh', 'static');
 *
 * // Shell mode (dynamic execution)
 * const registry = await loadRegistry('./my_help.sh', 'shell', {
 *   shellTimeout: 10000
 * });
 * ```
 */
export async function loadRegistry(
  filePath: string,
  mode: LoaderMode = 'auto',
  options?: LoaderConfig,
): Promise<HelpRegistry> {
  // Merge config
  const config = createLoaderConfig({ mode, ...options });

  // Validate mode
  if (!['static', 'shell', 'auto'].includes(config.mode!)) {
    throw new ValidationError(`Invalid loader mode: ${config.mode}. Must be 'static', 'shell', or 'auto'`);
  }

  // Check cache
  if (config.cacheEnabled) {
    const cacheKey = `${filePath}:${config.mode}`;
    const cached = registryCache.get(cacheKey);
    if (cached) {
      const age = Date.now() - cached.timestamp;
      if (age < (config.cacheTTL || DEFAULT_CONFIG.cacheTTL!)) {
        if (config.debug) {
          // eslint-disable-next-line no-console
          console.debug(`[loader] Returning cached registry for ${filePath} (age: ${age}ms)`);
        }
        return cached.registry;
      } else {
        // Cache expired, remove it
        registryCache.delete(cacheKey);
      }
    }
  }

  if (config.debug) {
    // eslint-disable-next-line no-console
    console.debug(`[loader] Loading registry from ${filePath} using mode: ${config.mode}`);
  }

  let registry: HelpRegistry | null = null;
  let lastError: Error | null = null;

  // Execute based on mode
  if (config.mode === 'static') {
    try {
      registry = await loadStaticRegistry(filePath, config);
    } catch (error) {
      if (error instanceof Error) {
        throw error;
      }
      throw new InternalError(`Failed to load registry: ${error}`);
    }
  } else if (config.mode === 'shell') {
    try {
      registry = await loadShellRegistry(filePath, config);
    } catch (error) {
      if (error instanceof Error) {
        throw error;
      }
      throw new InternalError(`Failed to load registry: ${error}`);
    }
  } else if (config.mode === 'auto') {
    // Try shell first, fallback to static
    try {
      registry = await loadShellRegistry(filePath, config);
    } catch (shellError) {
      if (config.debug) {
        // eslint-disable-next-line no-console
        console.debug(`[loader] Shell loading failed, attempting static fallback: ${shellError}`);
      }
      lastError = shellError as Error;

      try {
        registry = await loadStaticRegistry(filePath, config);
      } catch (staticError) {
        // Both failed, throw the first error
        if (lastError) {
          throw lastError;
        }
        throw staticError;
      }
    }
  }

  if (!registry) {
    throw new InternalError('Failed to load registry: no loader executed');
  }

  // Cache result
  if (config.cacheEnabled) {
    const cacheKey = `${filePath}:${config.mode}`;
    registryCache.set(cacheKey, {
      registry,
      timestamp: Date.now(),
    });
  }

  return registry;
}

/**
 * Loads registry using static file parser
 * @internal
 */
async function loadStaticRegistry(
  filePath: string,
  _config: LoaderConfig,
): Promise<HelpRegistry> {
  try {
    return await parseStaticRegistry(filePath);
  } catch (error) {
    if (error instanceof Error) {
      throw error;
    }
    throw new InternalError(`Failed to parse static registry: ${error}`);
  }
}

/**
 * Loads registry using shell executor
 * @internal
 */
async function loadShellRegistry(
  filePath: string,
  config: LoaderConfig,
): Promise<HelpRegistry> {
  const shellOptions: LoadByShellOptions = {
    timeout: config.shellTimeout || DEFAULT_CONFIG.shellTimeout,
    debug: config.debug || false,
  };

  try {
    return await loadByShell(filePath, 'bash', shellOptions);
  } catch (error) {
    if (error instanceof Error) {
      throw error;
    }
    throw new InternalError(`Failed to load shell registry: ${error}`);
  }
}

/**
 * Clears the loader cache
 * Useful for testing or forcing a reload
 *
 * @example
 * ```typescript
 * clearLoaderCache();
 * ```
 */
export function clearLoaderCache(): void {
  registryCache.clear();
}

/**
 * Gets cache statistics
 * @internal
 */
export function getCacheStats(): { size: number; entries: string[] } {
  return {
    size: registryCache.size,
    entries: Array.from(registryCache.keys()),
  };
}
