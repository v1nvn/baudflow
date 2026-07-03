import { access, mkdir, readFile, writeFile } from "node:fs/promises";
import { glob } from "glob";
import { parse } from "node-html-parser";
import { dirname, join, resolve } from "node:path";
import TurndownService from "turndown";
import { fileURLToPath } from "node:url";

// Always stripped before markdown conversion (never useful in an LLM digest).
const BUILT_IN_EXCLUDE_SELECTORS = ["script", "style", "[data-llms-ignore]"];

const defaultConfig = {
  siteUrl: "",
  name: "",
  description: "",
  generateIndividualMd: true,
  generateLlmsTxt: true,
  generateLlmsFullTxt: true,
  titleSelector: "h1",
  contentSelector: "main",
  exclude: ["404", "404.html", "_astro", "**.xml", "**.txt", "node_modules"],
  excludeSelectors: [],
  trailingSlash: "ignore",
  buildFormat: "directory",
  verbose: false,
};

function resolveTrailingSlash(mode, buildFormat) {
  if (mode === "always" || mode === "never") return mode;
  return buildFormat === "file" ? "never" : "always";
}

function applyTrailingSlash(url, mode, buildFormat) {
  const resolved = resolveTrailingSlash(mode, buildFormat);
  if (resolved === "always") return url.endsWith("/") ? url : `${url}/`;
  return url.replace(/\/+$/, "");
}

function getErrorMessage(error) {
  return error instanceof Error ? error.message : String(error);
}

// Markdown filename for a page: matches the file written on disk so llms.txt
// links always resolve. Home ("/") → index.md.
function mdSlug(urlPath) {
  return urlPath === "/" ? "index" : urlPath.replace(/^\//, "");
}

async function discoverHtmlFiles(inputDir, excludePatterns) {
  const files = await glob(`${inputDir}/**/*.html`, {
    ignore: excludePatterns.map((p) => `${inputDir}/${p}`),
    absolute: true,
  });
  return files.sort();
}

function fileToUrlPath(filePath, inputDir) {
  const relativePath = filePath.replace(resolve(inputDir), "");
  let urlPath = relativePath.replace(/\\/g, "/").replace(/^\//, "");
  urlPath = urlPath.replace(/\.html$/, "");
  if (urlPath.endsWith("/index") || urlPath === "index") {
    urlPath = urlPath.replace(/\/index$/, "").replace(/^index$/, "");
  }
  return "/" + urlPath;
}

async function processHtmlFile(filePath, options) {
  const { titleSelector, contentSelector, excludeSelectors } = options;
  const html = await readFile(filePath, "utf8");
  const root = parse(html);

  const titleElement = root.querySelector(titleSelector);
  const title = titleElement?.text?.trim() || "";

  const metaDescription = root.querySelector('meta[name="description"]');
  const description = metaDescription?.getAttribute("content") || "";

  let content = "";
  const contentElement = root.querySelector(contentSelector);
  if (contentElement) {
    const selectors = Array.from(
      new Set([...BUILT_IN_EXCLUDE_SELECTORS, ...excludeSelectors]),
    ).join(", ");
    if (selectors) contentElement.querySelectorAll(selectors).forEach((el) => el.remove());

    const turndownService = new TurndownService({
      headingStyle: "atx",
      codeBlockStyle: "fenced",
    });
    content = turndownService.turndown(contentElement.innerHTML);
  }

  return { title, description, content };
}

// Escape a value for a YAML double-quoted scalar so a title or description
// containing a quote, backslash, or newline can't corrupt the front matter.
function yamlQuote(value) {
  return `"${String(value).replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\r?\n/g, " ")}"`;
}

function generateMarkdownFile(page, config) {
  const { siteUrl, trailingSlash, buildFormat } = config;
  const url = applyTrailingSlash(`${siteUrl}${page.urlPath}`, trailingSlash, buildFormat);
  let md = "---\n";
  md += `title: ${yamlQuote(page.title)}\n`;
  md += `url: ${yamlQuote(url)}\n`;
  if (page.description) md += `description: ${yamlQuote(page.description)}\n`;
  md += "---\n\n";
  md += page.content;
  return md;
}

function generateLlmsTxtContent(pages, config) {
  const { name, description, siteUrl } = config;
  const base = siteUrl.endsWith("/") ? siteUrl : `${siteUrl}/`;

  let content = `# ${name}\n\n`;
  if (description) content += `> ${description}\n\n`;
  content += "This file helps language models discover the most useful content on this site.\n\n";

  const grouped = {};
  pages.forEach((page) => {
    const parts = page.urlPath.split("/").filter(Boolean);
    const group = parts.length > 1 ? parts[0] : "Home";
    (grouped[group] ||= []).push(page);
  });

  Object.keys(grouped)
    .sort()
    .forEach((group) => {
      const groupName = group.charAt(0).toUpperCase() + group.slice(1);
      content += `## ${groupName}\n\n`;
      grouped[group].forEach((page) => {
        const mdUrl = new URL(`${mdSlug(page.urlPath)}.md`, base).href;
        const linkText = page.title || page.urlPath;
        content += page.description
          ? `- [${linkText}](${mdUrl}): ${page.description}\n`
          : `- [${linkText}](${mdUrl})\n`;
      });
      content += "\n";
    });

  return content;
}

function generateLlmsFullTxtContent(pages, config) {
  const { name, siteUrl, trailingSlash, buildFormat } = config;

  let content = `# ${name}\n\n`;
  content += `URL: ${applyTrailingSlash(siteUrl, trailingSlash, buildFormat)}\n\n`;

  pages.forEach((page, index) => {
    const url = applyTrailingSlash(`${siteUrl}${page.urlPath}`, trailingSlash, buildFormat);
    content += `## ${page.title}\n\n`;
    content += `URL: ${url}\n\n`;
    if (page.description) content += `${page.description}\n\n`;
    content += page.content;
    if (index < pages.length - 1) content += "\n\n---\n\n";
  });

  return content;
}

export async function generateLlmsFiles(config) {
  const {
    inputDir,
    outputDir,
    siteUrl,
    name,
    description,
    generateIndividualMd = true,
    generateLlmsTxt = true,
    generateLlmsFullTxt = true,
    titleSelector = "h1",
    contentSelector = "main",
    exclude = defaultConfig.exclude,
    excludeSelectors = defaultConfig.excludeSelectors,
    trailingSlash = defaultConfig.trailingSlash,
    buildFormat = defaultConfig.buildFormat,
    verbose = false,
  } = config;

  const resolvedInputDir = resolve(inputDir);
  const resolvedOutputDir = resolve(outputDir);

  try {
    await access(resolvedOutputDir);
  } catch {
    throw new Error(`Output directory does not exist: ${outputDir}`);
  }

  if (verbose) console.log("🔍 Discovering HTML files...");
  const htmlFiles = await discoverHtmlFiles(resolvedInputDir, exclude);
  if (verbose) console.log(`   Found ${htmlFiles.length} HTML files`);

  const pages = [];
  for (const file of htmlFiles) {
    try {
      const urlPath = fileToUrlPath(file, resolvedInputDir);
      const pageData = await processHtmlFile(file, {
        titleSelector,
        contentSelector,
        excludeSelectors,
      });
      if (!pageData.title) {
        if (verbose) console.log(`   ⚠️  Skipping ${urlPath} (no title found)`);
        continue;
      }
      pages.push({ urlPath, filePath: file, ...pageData });
      if (verbose) console.log(`   ✓ ${urlPath}: "${pageData.title}"`);
    } catch (error) {
      console.error(`   ✗ Error processing ${file}: ${getErrorMessage(error)}`);
    }
  }
  if (verbose) console.log(`   Processed ${pages.length} pages successfully\n`);

  const homePage = pages.find((p) => p.urlPath === "/");
  const formatterConfig = {
    name: name || homePage?.title || "Site",
    description: description || homePage?.description || "",
    siteUrl: siteUrl.replace(/\/$/, ""),
    trailingSlash,
    buildFormat,
  };

  if (generateIndividualMd) {
    if (verbose) console.log("📝 Generating individual .md files...");
    for (const page of pages) {
      const mdPath = join(resolvedOutputDir, `${mdSlug(page.urlPath)}.md`);
      const mdDir = dirname(mdPath);
      try {
        await access(mdDir);
      } catch {
        await mkdir(mdDir, { recursive: true });
      }
      await writeFile(mdPath, generateMarkdownFile(page, formatterConfig), "utf8");
      if (verbose) console.log(`   ✓ ${mdPath}`);
    }
    if (verbose) console.log(`   Created ${pages.length} .md files\n`);
  }

  if (generateLlmsTxt) {
    if (verbose) console.log("📋 Generating llms.txt...");
    await writeFile(
      join(resolvedOutputDir, "llms.txt"),
      generateLlmsTxtContent(pages, formatterConfig),
      "utf8",
    );
    if (verbose) console.log(`   ✓ ${join(resolvedOutputDir, "llms.txt")}\n`);
  }

  if (generateLlmsFullTxt) {
    if (verbose) console.log("📚 Generating llms-full.txt...");
    await writeFile(
      join(resolvedOutputDir, "llms-full.txt"),
      generateLlmsFullTxtContent(pages, formatterConfig),
      "utf8",
    );
    if (verbose) console.log(`   ✓ ${join(resolvedOutputDir, "llms-full.txt")}\n`);
  }

  console.log(`✅ llms: ${pages.length} pages → llms.txt + llms-full.txt + ${pages.length} .md files`);
}

export default function llmsIntegration(options = {}) {
  let astroSiteUrl = "";
  let astroTrailingSlash;
  let astroBuildFormat;

  return {
    name: "astro-llms-md",
    hooks: {
      "astro:config:setup": async ({ config, logger }) => {
        astroSiteUrl = config.site?.toString?.() || "";
        astroTrailingSlash = config.trailingSlash;
        astroBuildFormat = config.build?.format;
        logger.info("llms.txt integration ready");
      },
      "astro:build:done": async ({ dir, logger }) => {
        try {
          const distDir = fileURLToPath(dir);
          const merged = {
            ...defaultConfig,
            trailingSlash: astroTrailingSlash ?? defaultConfig.trailingSlash,
            buildFormat: astroBuildFormat ?? defaultConfig.buildFormat,
            ...options,
          };
          if (!merged.siteUrl && !astroSiteUrl) {
            logger.warn(
              "llms.txt: no site URL; set `site` in astro.config.mjs or pass `siteUrl`",
            );
            return;
          }
          await generateLlmsFiles({
            inputDir: distDir,
            outputDir: distDir,
            siteUrl: merged.siteUrl || astroSiteUrl,
            name: merged.name,
            description: merged.description,
            generateIndividualMd: merged.generateIndividualMd,
            generateLlmsTxt: merged.generateLlmsTxt,
            generateLlmsFullTxt: merged.generateLlmsFullTxt,
            titleSelector: merged.titleSelector,
            contentSelector: merged.contentSelector,
            exclude: merged.exclude,
            excludeSelectors: merged.excludeSelectors,
            trailingSlash: merged.trailingSlash,
            buildFormat: merged.buildFormat,
            verbose: merged.verbose,
          });
        } catch (error) {
          logger.error(`llms.txt: ${getErrorMessage(error)}`);
          if (options.verbose && error instanceof Error) logger.error(error.stack || "");
        }
      },
    },
  };
}
