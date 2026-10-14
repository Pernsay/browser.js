/**
 * Production server for Browser.js on Render (or any Node host).
 *
 * Serves the built frontend (packages/chrome/dist) AND terminates the Wisp
 * WebSocket proxy on the SAME port / origin.
 *
 *   node render-server.mjs
 *
 * Env vars (all optional except PORT, which Render provides):
 *   PORT                port to bind (Render sets this automatically)
 *   HOST                bind address, must be 0.0.0.0 on Render  (default 0.0.0.0)
 *   STATIC_DIR          built frontend to serve                  (default packages/chrome/dist)
 *   ALLOW_PRIVATE_IPS   "1" to let the proxy reach RFC1918 hosts  (default 0 - keep off!)
 *   ALLOW_LOOPBACK_IPS  "1" to let the proxy reach 127.0.0.1      (default 0 - keep off!)
 *   LOG_WISP            "1" for verbose wisp logging              (default 0)
 */

import http from "node:http";
import fs from "node:fs";
import fsp from "node:fs/promises";
import path from "node:path";
import { createReadStream } from "node:fs";
import { fileURLToPath } from "node:url";

import { server as wisp, logging } from "@mercuryworkshop/wisp-js/server";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const PORT = Number(process.env.PORT || 3000);
const HOST = process.env.HOST || "0.0.0.0";
const STATIC_DIR = path.resolve(
	process.env.STATIC_DIR || path.join(__dirname, "packages/chrome/dist"),
);

// ---- proxy hardening -----------------------------------------------------
// Leaving these off stops visitors from using your deploy to port-scan your
// Render private network / the container itself.
wisp.options.allow_private_ips = process.env.ALLOW_PRIVATE_IPS === "1";
wisp.options.allow_loopback_ips = process.env.ALLOW_LOOPBACK_IPS === "1";

if (process.env.LOG_WISP !== "1") {
	logging.set_level(logging.WARN);
}

// ---- static file serving -------------------------------------------------
const MIME_TYPES = {
	".html": "text/html; charset=utf-8",
	".htm": "text/html; charset=utf-8",
	".js": "text/javascript; charset=utf-8",
	".mjs": "text/javascript; charset=utf-8",
	".css": "text/css; charset=utf-8",
	".json": "application/json; charset=utf-8",
	".map": "application/json; charset=utf-8",
	".wasm": "application/wasm", // REQUIRED: scramjet uses instantiateStreaming()
	".png": "image/png",
	".jpg": "image/jpeg",
	".jpeg": "image/jpeg",
	".gif": "image/gif",
	".svg": "image/svg+xml",
	".ico": "image/x-icon",
	".webp": "image/webp",
	".woff": "font/woff",
	".woff2": "font/woff2",
	".ttf": "font/ttf",
	".txt": "text/plain; charset=utf-8",
	".webmanifest": "application/manifest+json",
};

function getMimeType(filePath) {
	return (
		MIME_TYPES[path.extname(filePath).toLowerCase()] ||
		"application/octet-stream"
	);
}

/** Resolve a URL path to a file inside STATIC_DIR, or null if it escapes. */
async function resolveStatic(pathname) {
	let decoded;
	try {
		decoded = decodeURIComponent(pathname);
	} catch {
		return null;
	}
	const resolved = path.resolve(STATIC_DIR, "." + path.posix.normalize(decoded));
	if (resolved !== STATIC_DIR && !resolved.startsWith(STATIC_DIR + path.sep)) {
		return null; // path traversal attempt
	}
	try {
		const stat = await fsp.stat(resolved);
		if (stat.isDirectory()) {
			const index = path.join(resolved, "index.html");
			await fsp.access(index);
			return index;
		}
		return resolved;
	} catch {
		return null;
	}
}

function sendFile(req, res, filePath) {
	const stat = fs.statSync(filePath);
	res.writeHead(200, {
		"Content-Type": getMimeType(filePath),
		"Content-Length": stat.size,
		// The wasm/JS payloads are content-hashed; the HTML is not.
		"Cache-Control": /index\.html$/.test(filePath)
			? "no-cache"
			: "public, max-age=31536000, immutable",
	});
	if (req.method === "HEAD") {
		res.end();
		return;
	}
	createReadStream(filePath)
		.on("error", () => res.destroy())
		.pipe(res);
}

const server = http.createServer((req, res) => {
	void (async () => {
		try {
			const method = req.method || "GET";
			if (method !== "GET" && method !== "HEAD") {
				res.writeHead(405, { Allow: "GET, HEAD" }).end("Method Not Allowed");
				return;
			}

			const { pathname } = new URL(req.url || "/", "http://localhost");

			if (pathname === "/healthz") {
				res.writeHead(200, { "Content-Type": "text/plain" }).end("ok");
				return;
			}

			const filePath = await resolveStatic(pathname);
			if (filePath) {
				sendFile(req, res, filePath);
				return;
			}

			// SPA fallback - everything else renders the app shell
			const indexPath = path.join(STATIC_DIR, "index.html");
			if (fs.existsSync(indexPath)) {
				sendFile(req, res, indexPath);
				return;
			}

			res.writeHead(404, { "Content-Type": "text/plain" }).end("Not Found");
		} catch (err) {
			console.error("request error", err);
			if (!res.headersSent) res.writeHead(500);
			res.end("Internal Server Error");
		}
	})();
});

// Everything scramjet proxies travels over this WebSocket upgrade.
server.on("upgrade", (req, socket, head) => {
	wisp.routeRequest(req, socket, head);
});

server.listen(PORT, HOST, () => {
	console.log(`Browser.js  listening on http://${HOST}:${PORT}`);
	console.log(`  static: ${STATIC_DIR}`);
	console.log(`  wisp:   ws://${HOST}:${PORT}/`);
});
