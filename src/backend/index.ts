import {
	readFile,
	serveFile,
} from "https://esm.town/v/std/utils@85-main/index.ts";
import { Hono } from "npm:hono";
import favicon from "../frontend/favicon.http.tsx";

const app = new Hono();

// Unwrap Hono errors to see original error details
app.onError((err, _c) => {
	throw err;
});

// Serve static files
app.get("/src/frontend/*", (c) => serveFile(c.req.path, import.meta.url));
app.get("/src/shared/*", (c) => serveFile(c.req.path, import.meta.url));

// Serve the main app
app.get("/", async (c) => {
	const html = await readFile("/src/frontend/index.html", import.meta.url);
	return c.html(html);
});

// Health check endpoint
app.get("/health", (c) => {
	return c.json({ status: "ok", timestamp: new Date().toISOString() });
});

app.get("/favicon.svg", (c) => {
	return favicon();
});
export default app.fetch;
