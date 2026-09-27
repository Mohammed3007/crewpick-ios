const MAX_HTML_BYTES = 1_000_000;
const MAX_REDIRECTS = 3;

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json", "cache-control": "no-store" } });

Deno.serve(async (request) => {
  if (request.method !== "POST") return json(405, { error: "POST required" });
  if (!request.headers.get("authorization")) return json(401, { error: "Authentication required" });

  try {
    const body = await request.json() as { url?: string };
    let target = new URL(body.url ?? "");
    let response: Response | undefined;
    for (let redirect = 0; redirect <= MAX_REDIRECTS; redirect += 1) {
      await assertPublicHTTPS(target);
      response = await fetch(target, {
        redirect: "manual",
        signal: AbortSignal.timeout(8_000),
        headers: { "user-agent": "CrewPickPreview/1.0", accept: "text/html,application/xhtml+xml" },
      });
      if (![301, 302, 303, 307, 308].includes(response.status)) break;
      const location = response.headers.get("location");
      if (!location || redirect === MAX_REDIRECTS) throw new Error("Too many redirects");
      target = new URL(location, target);
    }
    if (!response?.ok) return json(422, { error: "The page could not be loaded" });
    if (!(response.headers.get("content-type") ?? "").toLowerCase().includes("text/html")) {
      return json(415, { error: "The URL is not an HTML page" });
    }

    const html = await limitedText(response);
    const metadata = extractMetadata(html);
    const fallbackTitle = target.pathname.split("/").filter(Boolean).at(-1)?.replaceAll(/[-_]+/g, " ") ?? target.hostname;
    return json(200, {
      title: clean(metadata["og:title"] ?? metadata["twitter:title"] ?? pageTitle(html) ?? fallbackTitle).slice(0, 200),
      description: clean(metadata["og:description"] ?? metadata.description ?? "").slice(0, 500),
      site_name: clean(metadata["og:site_name"] ?? target.hostname.replace(/^www\./, "")).slice(0, 100),
      image_url: absoluteURL(metadata["og:image"] ?? metadata["twitter:image"], target),
      canonical_url: target.href,
    });
  } catch (error) {
    console.warn(error);
    return json(400, { error: "CrewPick couldn't preview that URL" });
  }
});

async function assertPublicHTTPS(url: URL) {
  if (url.protocol !== "https:" || (url.port && url.port !== "443") || !url.hostname) throw new Error("HTTPS required");
  const host = url.hostname.toLowerCase().replace(/^\[|\]$/g, "");
  if (host === "localhost" || host.endsWith(".local") || host.endsWith(".internal")) throw new Error("Private host");
  if (host.includes(":")) {
    if (isPrivateIPv6(host)) throw new Error("Private address");
    return;
  }
  if (/^\d+\.\d+\.\d+\.\d+$/.test(host)) {
    if (isPrivateIPv4(host)) throw new Error("Private address");
    return;
  }
  const addresses = await Deno.resolveDns(host, "A").catch(() => []);
  const v6Addresses = await Deno.resolveDns(host, "AAAA").catch(() => []);
  if (addresses.length + v6Addresses.length === 0) throw new Error("Host not found");
  if (addresses.some(isPrivateIPv4) || v6Addresses.some(isPrivateIPv6)) throw new Error("Private address");
}

function isPrivateIPv4(value: string) {
  const octets = value.split(".").map(Number);
  if (octets.length !== 4 || octets.some((part) => !Number.isInteger(part) || part < 0 || part > 255)) return true;
  const [a, b] = octets;
  return a === 0 || a === 10 || a === 127 || a >= 224 || (a === 169 && b === 254) ||
    (a === 172 && b >= 16 && b <= 31) || (a === 192 && b === 168) || (a === 100 && b >= 64 && b <= 127);
}

function isPrivateIPv6(value: string) {
  const host = value.toLowerCase();
  return host === "::" || host === "::1" || host.startsWith("fc") || host.startsWith("fd") ||
    host.startsWith("fe8") || host.startsWith("fe9") || host.startsWith("fea") || host.startsWith("feb") ||
    host.startsWith("::ffff:127.") || host.startsWith("::ffff:10.") || host.startsWith("::ffff:192.168.");
}

async function limitedText(response: Response) {
  const declared = Number(response.headers.get("content-length") ?? 0);
  if (declared > MAX_HTML_BYTES) throw new Error("Page too large");
  const reader = response.body?.getReader();
  if (!reader) return "";
  const chunks: Uint8Array[] = [];
  let size = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.byteLength;
    if (size > MAX_HTML_BYTES) {
      await reader.cancel();
      throw new Error("Page too large");
    }
    chunks.push(value);
  }
  const combined = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) { combined.set(chunk, offset); offset += chunk.length; }
  return new TextDecoder().decode(combined);
}

function extractMetadata(html: string) {
  const result: Record<string, string> = {};
  for (const match of html.matchAll(/<meta\s+[^>]*>/gi)) {
    const attrs: Record<string, string> = {};
    for (const attr of match[0].matchAll(/([\w:-]+)\s*=\s*(["'])(.*?)\2/gi)) attrs[attr[1].toLowerCase()] = attr[3];
    const key = (attrs.property ?? attrs.name)?.toLowerCase();
    if (key && attrs.content && !result[key]) result[key] = attrs.content;
  }
  return result;
}

function pageTitle(html: string) {
  return html.match(/<title[^>]*>([\s\S]*?)<\/title>/i)?.[1];
}

function clean(value: string) {
  return value.replace(/<[^>]+>/g, " ").replace(/&amp;/gi, "&").replace(/&quot;/gi, '"')
    .replace(/&#39;|&apos;/gi, "'").replace(/&lt;/gi, "<").replace(/&gt;/gi, ">")
    .replace(/&#(\d+);/g, (_, code) => String.fromCodePoint(Number(code))).replace(/\s+/g, " ").trim();
}

function absoluteURL(value: string | undefined, base: URL) {
  if (!value) return null;
  try {
    const url = new URL(value, base);
    return url.protocol === "https:" ? url.href : null;
  } catch { return null; }
}
