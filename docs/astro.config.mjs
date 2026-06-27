// @ts-check
import { defineConfig, fontProviders } from 'astro/config';
import sitemap from '@astrojs/sitemap';
import llms from './src/integrations/llms-md.mjs';

export default defineConfig({
  site: 'https://baudflow.com',
  build: { inlineStylesheets: 'always' },
  fonts: [
    {
      provider: fontProviders.fontsource(),
      name: 'DM Sans',
      cssVariable: '--font-sans',
      weights: ['100 900'],
      styles: ['normal'],
      fallbacks: ['system-ui', 'sans-serif'],
    },
    {
      provider: fontProviders.fontsource(),
      name: 'JetBrains Mono',
      cssVariable: '--font-mono',
      weights: ['100 800'],
      styles: ['normal'],
      fallbacks: ['ui-monospace', 'monospace'],
    },
  ],
  image: {
    layout: 'constrained',
    responsiveStyles: true,
  },
  integrations: [
    sitemap(),
    llms({
      name: 'Baudflow',
      description:
        'Baudflow is a self-hosted, open-source speed-test tracker and network monitor built with Elixir, Phoenix LiveView, and PostgreSQL. It runs automated Ookla speed tests and continuous TCP-connect pings on a schedule, streams every run in real time, and turns the results into health verdicts, SLA compliance, and alerts.',
      excludeSelectors: ['nav', 'aside', 'header', 'footer', "[aria-hidden='true']", '[hidden]'],
    }),
  ],
});
