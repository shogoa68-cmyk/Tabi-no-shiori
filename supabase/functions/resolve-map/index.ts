// resolve-map：Googleマップの短縮リンク（maps.app.goo.gl/…）を、本当の長いURLに戻して返す。
// 使い方：GET /functions/v1/resolve-map?url=https://maps.app.goo.gl/xxxx  →  { "url": "https://www.google.com/maps?q=..." }
// Supabase の管理画面で「Verify JWT」をオフにして使う（ページにキーを書かなくていいように）。

const ALLOW_ORIGINS = ["https://shogoa68-cmyk.github.io", "http://localhost:8000"];
// 短縮リンクとして受けつける相手（これ以外は読みに行かない＝なんでも中継する道具にしない）
const SHORT_HOSTS = ["maps.app.goo.gl", "goo.gl"];
const GOOGLE_HOST = /(^|\.)google\.[a-z.]+$/;

function cors(origin: string | null) {
  return {
    "Access-Control-Allow-Origin": origin && ALLOW_ORIGINS.includes(origin) ? origin : ALLOW_ORIGINS[0],
    "Access-Control-Allow-Methods": "GET, OPTIONS",
    "Access-Control-Allow-Headers": "authorization, apikey, content-type",
    "Vary": "Origin",
  };
}

Deno.serve(async (req) => {
  const headers = { ...cors(req.headers.get("origin")), "Content-Type": "application/json; charset=utf-8" };
  if (req.method === "OPTIONS") return new Response(null, { headers });
  const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers });

  let cur: URL;
  try { cur = new URL(new URL(req.url).searchParams.get("url") ?? ""); } catch { return json({ error: "bad_url" }, 400); }
  if (cur.protocol !== "https:" || !SHORT_HOSTS.includes(cur.hostname)) return json({ error: "not_short_link" }, 400);
  if (cur.hostname === "goo.gl" && !cur.pathname.startsWith("/maps")) return json({ error: "not_short_link" }, 400);

  // 転送先を最大5回までたどる。Google のページに着いたらそこで終わり。
  for (let i = 0; i < 5; i++) {
    let res: Response;
    try {
      res = await fetch(cur, { redirect: "manual", signal: AbortSignal.timeout(5000), headers: { "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)", "Accept-Language": "ja" } });
    } catch { return json({ error: "fetch_failed" }, 502); }
    await res.body?.cancel();
    const loc = res.headers.get("location");
    if (res.status < 300 || res.status >= 400 || !loc) break;
    const next = new URL(loc, cur);
    if (next.protocol !== "https:") break;
    cur = next;
    if (GOOGLE_HOST.test(cur.hostname)) return json({ url: cur.toString() });
    if (!SHORT_HOSTS.includes(cur.hostname)) break;
  }
  return json({ error: "not_resolved" }, 422);
});
