import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: './tests/ui', fullyParallel: false, workers: 1,
  timeout: 20000,
  reporter: 'list',
  use: {
    baseURL: 'http://127.0.0.1:3187',
    browserName: 'chromium',
    channel: process.env.PLAYWRIGHT_CHANNEL || undefined,
    viewport: { width: 1440, height: 1100 },
    trace: 'retain-on-failure',
  },
  webServer: {
    command: 'node server.js', url: 'http://127.0.0.1:3187',
    env: { HOST: '127.0.0.1', PORT: '3187', OPTIMIZER_MODE: 'mock' },
    reuseExistingServer: false,
  },
});
