// @ts-check
import { defineConfig, fontProviders } from 'astro/config';
import sitemap from '@astrojs/sitemap';
import { satteri } from '@astrojs/markdown-satteri';
import { defineMdastPlugin } from 'satteri';
import llms from './src/integrations/llms-md.mjs';
import { version } from './src/version.ts';

// Resolve `%VERSION%` in rendered Markdown (prose text, inline code, and fenced
// code blocks) to the project version from mix.exs, so the docs quick-start
// snippets stay in lockstep with releases with nothing to hand-edit. Runs as a
// mdast plugin on Astro's default Sätteri processor.
/** @param {string} v */
function versionPlugin(v) {
  /** @param {string} s */
  const sub = (s) => s.split('%VERSION%').join(v);
  return defineMdastPlugin({
    name: 'baudflow-version',
    text(node, ctx) {
      if (node.value.includes('%VERSION%')) ctx.replaceNode(node, { type: 'text', value: sub(node.value) });
    },
    inlineCode(node, ctx) {
      if (node.value.includes('%VERSION%')) ctx.replaceNode(node, { type: 'inlineCode', value: sub(node.value) });
    },
    code(node, ctx) {
      if (node.value.includes('%VERSION%')) {
        ctx.replaceNode(node, { type: 'code', lang: node.lang ?? null, meta: node.meta ?? null, value: sub(node.value) });
      }
    },
  });
}

export default defineConfig({
  site: 'https://baudflow.com',
  build: { inlineStylesheets: 'always' },
  markdown: {
    processor: satteri({ mdastPlugins: version ? [versionPlugin(version)] : [] }),
  },
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
