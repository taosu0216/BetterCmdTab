/**
 * Build-time prerender. The app is a client-rendered SPA, so without this the
 * shipped index.html has an empty <div id="root"> and crawlers that don't run
 * JS see no content. This renders the page to static HTML and injects it into
 * the built dist/index.html. main.tsx still uses createRoot, so the client
 * replaces this markup on load — it exists purely so crawlers get real content.
 *
 * Runs under Bun (see Dockerfile) after `vite build`:
 *   bun run scripts/prerender.tsx
 */
import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { renderToString } from "react-dom/server";
import { createElement } from "react";
import { Home } from "../src/routes/index.tsx";

const dist = join(import.meta.dir, "..", "dist", "index.html");
const MARKER = '<div id="root"></div>';

const html = readFileSync(dist, "utf8");
if (!html.includes(MARKER)) {
  throw new Error(`prerender: marker ${MARKER} not found in ${dist}`);
}

const app = renderToString(createElement(Home));
if (!app.trim()) {
  throw new Error("prerender: Home rendered empty markup");
}

writeFileSync(dist, html.replace(MARKER, `<div id="root">${app}</div>`));
console.log(`prerender: injected ${app.length} chars of static HTML into dist/index.html`);
