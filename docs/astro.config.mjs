// @ts-check
import { defineConfig } from 'astro/config';
import sitemap from '@astrojs/sitemap';

export default defineConfig({
  site: 'https://baudflow.com',
  image: {
    // Responsive by default for every <Image/>/<Picture/> and markdown `![]()`.
    // `responsiveStyles` injects :where([data-astro-image]) rules at specificity 0,
    // so existing .shot img / .prose img rules still win.
    layout: 'constrained',
    responsiveStyles: true,
  },
  integrations: [sitemap()],
});
