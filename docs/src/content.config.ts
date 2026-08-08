import { defineCollection, z } from 'astro:content';
import { glob } from 'astro/loaders';

// Canonical doc-section order, shared by the sidebar (DocsLayout) and the docs
// index card grid. New pages declare a `section` + an `order` within it.
export const DOC_SECTIONS = [
  'Start',
  'Operate',
  'Integrate',
  'Reference',
  'Project',
] as const;

const docs = defineCollection({
  loader: glob({ base: './src/content/docs', pattern: '**/*.md' }),
  schema: z.object({
    title: z.string(),
    description: z.string().default(''),
    section: z.enum(DOC_SECTIONS).default('Operate'),
    order: z.number().default(0),
    // Narrative/use-case pages opt into TechArticle JSON-LD + og:type=article.
    article: z.boolean().default(false),
    updated: z.string().optional(),
  }),
});

// Editorial / use-case content that lives alongside the docs but outside the
// operator manual — origin stories, comparisons, deep-dive narratives. These
// keep TechArticle semantics for search but are not part of the docs sidebar.
const articles = defineCollection({
  loader: glob({ base: './src/content/articles', pattern: '**/*.md' }),
  schema: z.object({
    title: z.string(),
    description: z.string().default(''),
    order: z.number().default(0),
    updated: z.string().optional(),
  }),
});

export const collections = { docs, articles };
