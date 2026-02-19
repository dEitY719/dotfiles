#!/usr/bin/env node

/**
 * esbuild bundling script for my-cli
 * Creates a production bundle with optimizations
 *
 * CL-6.2: esbuild Bundling
 */

import esbuild from 'esbuild';
import path from 'path';
import fs from 'fs';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const entryPoint = path.join(__dirname, '../dist/index.js');
const outFile = path.join(__dirname, '../dist/my-cli.js');
const outDir = path.dirname(outFile);

// Ensure output directory exists
if (!fs.existsSync(outDir)) {
  fs.mkdirSync(outDir, { recursive: true });
}

console.log('🔨 Building production bundle with esbuild...');
console.log(`   Entry: ${entryPoint}`);
console.log(`   Output: ${outFile}`);

esbuild
  .build({
    entryPoints: [entryPoint],
    outfile: outFile,
    bundle: false, // Don't bundle - just transform
    platform: 'node',
    target: 'node18',
    format: 'esm',
    minify: true,
    sourcemap: false,
    logLevel: 'info',
    define: {
      'process.env.NODE_ENV': '"production"',
    },
  })
  .then(async (result) => {
    // Check bundle size
    const stats = fs.statSync(outFile);
    const sizeInMB = (stats.size / (1024 * 1024)).toFixed(2);

    console.log(`✅ Bundle created successfully!`);
    console.log(`   Size: ${sizeInMB} MB (${stats.size} bytes)`);

    // Check against threshold
    const maxSizeBytes = 15 * 1024 * 1024;
    if (stats.size > maxSizeBytes) {
      console.warn(
        `⚠️  Warning: Bundle exceeds 15MB threshold (${sizeInMB}MB)`,
      );
      process.exit(1);
    }

    console.log('✨ Bundle meets size requirements!');
    process.exit(0);
  })
  .catch((error) => {
    console.error('❌ Bundle failed:', error);
    process.exit(1);
  });
