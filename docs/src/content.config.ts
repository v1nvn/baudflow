import { defineCollection, z } from 'astro:content';
import { glob } from 'astro/loaders';

// Canonical doc-section order, shared by the sidebar (DocsLayout) and the docs
// index card grid. New pages declare a `section` + an `order` within it.
export const DOC_SECTIONS = [
  'Getting started',
  'Guides',
  'Reference',
  'Project',
] as const;

const docs = defineCollection({
  loader: glob({ base: './src/content/docs', pattern: '**/*.md' }),
  schema: z.object({
    title: z.string(),
    description: z.string().default(''),
    section: z.enum(DOC_SECTIONS).default('Guides'),
    order: z.number().default(0),
  }),
});

export const collections = { docs };
