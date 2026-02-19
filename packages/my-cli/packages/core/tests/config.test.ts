/**
 * Unit tests for configuration and dotfiles root detection
 * CL-1.4: Configuration loader
 */

import { describe, it, expect } from 'vitest';
import * as fs from 'fs';
import * as path from 'path';
import * as os from 'os';
import {
  findDotfilesRoot,
  resolveXDGDirs,
  loadConfigFromFile,
  loadConfig,
  loadConfigContext,
} from '../src/config/dotfiles-root';
import { DEFAULT_CONFIG, Config } from '../src/config/types';
import { InternalError } from '../src/errors';

describe('Configuration Loader', () => {
  describe('findDotfilesRoot', () => {
    it('should return dotfiles root from current project', () => {
      const root = findDotfilesRoot();
      expect(root).toBeTruthy();
      expect(fs.existsSync(root)).toBe(true);
    });

    it('should contain dotfiles path', () => {
      const root = findDotfilesRoot();
      expect(root).toContain('dotfiles');
    });

    it('should return absolute path', () => {
      const root = findDotfilesRoot();
      expect(path.isAbsolute(root)).toBe(true);
    });

    it('should prioritize MY_CLI_DOTFILES_ROOT environment variable', () => {
      const originalEnv = process.env.MY_CLI_DOTFILES_ROOT;
      const currentDir = process.cwd();

      try {
        process.env.MY_CLI_DOTFILES_ROOT = currentDir;
        const root = findDotfilesRoot();
        expect(root).toBe(currentDir);
      } finally {
        process.env.MY_CLI_DOTFILES_ROOT = originalEnv;
      }
    });

    it('should find .git directory in parent directories', () => {
      const root = findDotfilesRoot();
      // Root should exist and be valid
      expect(fs.existsSync(root)).toBe(true);
    });
  });

  describe('resolveXDGDirs', () => {
    it('should return XDG directory structure', () => {
      const dirs = resolveXDGDirs();
      expect(dirs.configHome).toBeTruthy();
      expect(dirs.fallbackHome).toBeTruthy();
      expect(dirs.configFile).toBeTruthy();
    });

    it('should return absolute paths', () => {
      const dirs = resolveXDGDirs();
      expect(path.isAbsolute(dirs.configHome)).toBe(true);
      expect(path.isAbsolute(dirs.fallbackHome)).toBe(true);
      expect(path.isAbsolute(dirs.configFile)).toBe(true);
    });

    it('should include my-cli in config home', () => {
      const dirs = resolveXDGDirs();
      expect(dirs.configHome).toContain('my-cli');
    });

    it('should use XDG_CONFIG_HOME if set', () => {
      const originalXdg = process.env.XDG_CONFIG_HOME;
      const testDir = '/tmp/test-xdg';

      try {
        process.env.XDG_CONFIG_HOME = testDir;
        const dirs = resolveXDGDirs();
        expect(dirs.configHome).toBe(path.join(testDir, 'my-cli'));
      } finally {
        process.env.XDG_CONFIG_HOME = originalXdg;
      }
    });

    it('should default to ~/.config if XDG_CONFIG_HOME not set', () => {
      const originalXdg = process.env.XDG_CONFIG_HOME;

      try {
        delete process.env.XDG_CONFIG_HOME;
        const dirs = resolveXDGDirs();
        const home = os.homedir();
        expect(dirs.configHome).toContain(home);
        expect(dirs.configHome).toContain('.config');
      } finally {
        if (originalXdg) {
          process.env.XDG_CONFIG_HOME = originalXdg;
        }
      }
    });

    it('should include fallback home directory', () => {
      const dirs = resolveXDGDirs();
      const home = os.homedir();
      expect(dirs.fallbackHome).toBe(path.join(home, '.my-cli'));
    });
  });

  describe('loadConfigFromFile', () => {
    it('should return default config if file does not exist', () => {
      const nonExistentPath = '/tmp/non-existent-config-12345.json';
      const config = loadConfigFromFile(nonExistentPath);
      expect(config).toEqual(DEFAULT_CONFIG);
    });

    it('should parse valid JSON config file', () => {
      const testConfig: Config = {
        theme: 'dark',
        pager: 'more',
        shellLoader: true,
      };

      const tempFile = path.join(os.tmpdir(), `test-config-${Date.now()}.json`);

      try {
        fs.writeFileSync(tempFile, JSON.stringify(testConfig), 'utf-8');
        const loaded = loadConfigFromFile(tempFile);

        expect(loaded.theme).toBe('dark');
        expect(loaded.pager).toBe('more');
        expect(loaded.shellLoader).toBe(true);
      } finally {
        if (fs.existsSync(tempFile)) {
          fs.unlinkSync(tempFile);
        }
      }
    });

    it('should merge config with defaults', () => {
      const partialConfig = { theme: 'light' };
      const tempFile = path.join(os.tmpdir(), `test-config-${Date.now()}.json`);

      try {
        fs.writeFileSync(tempFile, JSON.stringify(partialConfig), 'utf-8');
        const loaded = loadConfigFromFile(tempFile);

        expect(loaded.theme).toBe('light');
        expect(loaded.pager).toBe(DEFAULT_CONFIG.pager);
        expect(loaded.logLevel).toBe(DEFAULT_CONFIG.logLevel);
      } finally {
        if (fs.existsSync(tempFile)) {
          fs.unlinkSync(tempFile);
        }
      }
    });

    it('should throw InternalError for invalid JSON', () => {
      const tempFile = path.join(os.tmpdir(), `test-config-${Date.now()}.json`);

      try {
        fs.writeFileSync(tempFile, '{invalid json}', 'utf-8');
        expect(() => loadConfigFromFile(tempFile)).toThrow(InternalError);
      } finally {
        if (fs.existsSync(tempFile)) {
          fs.unlinkSync(tempFile);
        }
      }
    });

    it('should handle empty JSON object', () => {
      const tempFile = path.join(os.tmpdir(), `test-config-${Date.now()}.json`);

      try {
        fs.writeFileSync(tempFile, '{}', 'utf-8');
        const loaded = loadConfigFromFile(tempFile);
        expect(loaded).toEqual(DEFAULT_CONFIG);
      } finally {
        if (fs.existsSync(tempFile)) {
          fs.unlinkSync(tempFile);
        }
      }
    });
  });

  describe('loadConfig', () => {
    it('should return valid config', () => {
      const config = loadConfig();
      expect(config).toBeTruthy();
      expect(config.theme).toBeDefined();
      expect(config.pager).toBeDefined();
    });

    it('should respect MY_CLI_CONFIG environment variable', () => {
      const testConfig: Config = { theme: 'light', pager: 'cat' };
      const tempFile = path.join(os.tmpdir(), `test-config-${Date.now()}.json`);
      const originalEnv = process.env.MY_CLI_CONFIG;

      try {
        fs.writeFileSync(tempFile, JSON.stringify(testConfig), 'utf-8');
        process.env.MY_CLI_CONFIG = tempFile;

        const config = loadConfig();
        expect(config.theme).toBe('light');
        expect(config.pager).toBe('cat');
      } finally {
        process.env.MY_CLI_CONFIG = originalEnv;
        if (fs.existsSync(tempFile)) {
          fs.unlinkSync(tempFile);
        }
      }
    });

    it('should have valid default values', () => {
      const config = loadConfig();
      expect(config.theme).toMatch(/^(light|dark|auto)$/);
      expect(config.pager).toMatch(/less|more|cat/);
      expect(config.logLevel).toMatch(/^(debug|info|warn|error)$/);
      expect(typeof config.interactive).toBe('boolean');
    });
  });

  describe('loadConfigContext', () => {
    it('should return complete context object', () => {
      const context = loadConfigContext();
      expect(context.dotfilesRoot).toBeTruthy();
      expect(context.config).toBeTruthy();
      expect(context.xdgDirs).toBeTruthy();
    });

    it('should include valid dotfiles root', () => {
      const context = loadConfigContext();
      expect(fs.existsSync(context.dotfilesRoot)).toBe(true);
    });

    it('should include valid config', () => {
      const context = loadConfigContext();
      expect(context.config.theme).toBeDefined();
      expect(context.config.pager).toBeDefined();
    });

    it('should include valid XDG directories', () => {
      const context = loadConfigContext();
      expect(path.isAbsolute(context.xdgDirs.configHome)).toBe(true);
      expect(path.isAbsolute(context.xdgDirs.fallbackHome)).toBe(true);
      expect(path.isAbsolute(context.xdgDirs.configFile)).toBe(true);
    });

    it('should be consistent across multiple calls', () => {
      const context1 = loadConfigContext();
      const context2 = loadConfigContext();

      expect(context1.dotfilesRoot).toBe(context2.dotfilesRoot);
      expect(context1.config.theme).toBe(context2.config.theme);
    });
  });

  describe('Default Configuration', () => {
    it('should have valid default values', () => {
      expect(DEFAULT_CONFIG.theme).toBe('auto');
      expect(DEFAULT_CONFIG.pager).toBe('less -R');
      expect(DEFAULT_CONFIG.shellLoader).toBe(false);
      expect(Array.isArray(DEFAULT_CONFIG.registryPaths)).toBe(true);
      expect(DEFAULT_CONFIG.logLevel).toBe('info');
      expect(DEFAULT_CONFIG.interactive).toBe(true);
    });
  });

  describe('Config type validation', () => {
    it('should support all config properties', () => {
      const config: Config = {
        theme: 'dark',
        pager: 'less -R',
        shellLoader: true,
        registryPaths: ['/path/to/registry'],
        logLevel: 'debug',
        interactive: false,
      };

      expect(config.theme).toBe('dark');
      expect(config.pager).toBe('less -R');
      expect(config.shellLoader).toBe(true);
      expect(config.registryPaths).toHaveLength(1);
      expect(config.logLevel).toBe('debug');
      expect(config.interactive).toBe(false);
    });
  });
});
