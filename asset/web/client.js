// ProjecturEd web client.
//
// The editor lives on the server. This client:
//   - loads the server's TTF/OTF fonts so text metrics match server-side layout,
//   - renders the PRIMARY (first) WindowDocument directly in the page it was
//     opened from — the entered browser tab is the main window's paint surface,
//     so the editor appears immediately with no extra click and no popup,
//   - renders any ADDITIONAL WindowDocuments as browser popups (window.open),
//   - paints the JSON draw-list the server sends into each surface's <canvas>,
//   - forwards raw mouse/keyboard/resize events back to the server.
//
// Protocol (JSON over one WebSocket). Server -> client:
//   {type:"update", zoom, full:[win...], patches:[{window,clip,draw}...], close:[id...]}
// A `full` entry carries a window's complete draw-list and a `primary` flag (the
// in-tab window); a `patch` repaints only its clip rectangle over the retained
// canvas (incremental rendering). See package/web/src/ProjecturedWeb.jl.
//
// The server works in logical pixels. `zoom` is the zoom of the editor: the
// client draws each logical pixel as `devicePixelRatio × zoom` pixels, and
// divides each size and each pointer position that it sends by `zoom`.

(() => {
  "use strict";

  const canvasEl = document.getElementById("main");
  const overlayEl = document.getElementById("overlay");

  let ws = null;
  let mainId = null;                    // window id bound to the page canvas
  let mainWired = false;                // page-surface listeners attached once
  const windowsMeta = new Map();        // id -> full window object {id,...,draw}
  const popups = new Map();             // id -> { win, canvas, ctx, dpr }
  const pendingPopups = new Map();      // id -> meta, awaiting a user gesture to open
  let zoom = 1;                         // the zoom of the editor, from the server

  // The page itself is a popup-shaped surface ({win,canvas,ctx,dpr}) so the
  // render/event helpers below are shared between the tab and the popups.
  const pageSurface = {
    win: window, canvas: canvasEl, ctx: canvasEl.getContext("2d"),
    dpr: window.devicePixelRatio || 1,
  };

  function setOverlay(text) {
    if (!overlayEl) return;
    if (text) { overlayEl.textContent = text; overlayEl.style.display = ""; }
    else { overlayEl.style.display = "none"; }
  }

  // The surface for a window id: the page for the primary window, else its own
  // window. A window is a window here as it is everywhere — see PAR-MANY-WINDOWS.
  function surfaceFor(id) {
    return id === mainId ? pageSurface : popups.get(id);
  }

  // ── A window kept in reserve ────────────────────────────────────────────────
  //
  // A browser opens a window only inside a transient user activation. A menu is
  // opened by a click and has one; a tooltip is opened by the pointer resting
  // and has none. **That is the browser's limit to solve, not a reason to draw a
  // second window inside the first**, so one window is opened while an
  // activation is in hand and held empty until a window with no activation needs
  // it. A tooltip then gets a window of its own, at the moment it is asked for.
  let reserved = null;                  // { win, canvas, ctx, dpr }, unbound

  function reserveWindow() {
    if (reserved || !mainWired) return;
    const p = openPopup({ id: "reserved", title: "", w: 320, h: 120, x: -1, y: -1 });
    if (p) { try { p.win.blur(); window.focus(); } catch {} reserved = p; }
  }

  // Give the window in reserve to `meta`, and place it where the server said.
  function takeReserved(meta) {
    if (!reserved) return null;
    const p = reserved;
    reserved = null;
    try {
      p.win.resizeTo(Math.round((meta.w > 0 ? meta.w : 320) * zoom),
                     Math.round((meta.h > 0 ? meta.h : 120) * zoom));
      if (meta.x >= 0 && meta.y >= 0) p.win.moveTo(Math.round(meta.x * zoom), Math.round(meta.y * zoom));
      p.win.document.title = meta.title || "ProjecturEd";
      // A tooltip says something about the window under it; it must not take the
      // keyboard away from it.
      p.win.blur(); window.focus();
    } catch {}
    popups.set(meta.id, p);
    return p;
  }

  // ── Fonts ────────────────────────────────────────────────────────────────

  async function loadFonts() {
    try {
      const resp = await fetch("/fonts.json");
      const { fonts } = await resp.json();
      await Promise.all(fonts.map(async (file) => {
        const family = file.replace(/\.[^.]+$/, "");
        try {
          const face = new FontFace(family, `url("/font/${encodeURIComponent(file)}")`);
          await face.load();
          document.fonts.add(face);
        } catch (e) {
          console.warn("font load failed:", file, e);
        }
      }));
      await document.fonts.ready;
    } catch (e) {
      console.warn("could not load fonts.json:", e);
    }
  }

  // ── WebSocket ──────────────────────────────────────────────────────────────

  function connect() {
    const proto = location.protocol === "https:" ? "wss:" : "ws:";
    ws = new WebSocket(`${proto}//${location.host}/ws`);
    ws.onopen = () => { setOverlay("Connecting…"); };
    ws.onclose = () => { resetClientState(); setOverlay("Disconnected. Reload to reconnect."); };
    ws.onerror = () => { setOverlay("Connection error."); };
    ws.onmessage = (ev) => {
      let msg;
      try { msg = JSON.parse(ev.data); } catch { return; }
      if (msg.type === "update") handleUpdate(msg);
      else if (msg.type === "pointer") setPointerCursor(msg);
      else if (msg.type === "busy") setOverlay("Another client is already connected to this editor.");
    };
  }

  // The time of a browser event in milliseconds since the Unix epoch: the clock
  // of `time()` on the server, times 1000.
  function stamp(ev) { return performance.timeOrigin + ev.timeStamp; }

  // A message with no event of the browser behind it has the time of the send.
  function send(obj) {
    if (obj.t === undefined) obj.t = performance.timeOrigin + performance.now();
    if (ws && ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify(obj));
  }

  // Drop per-connection state so a reconnect rebinds the page canvas cleanly.
  // The page-level listeners persist (they read the live `mainId`).
  function resetClientState() {
    mainId = null;
    windowsMeta.clear();
    for (const p of popups.values()) { try { p.win.close(); } catch {} }
    popups.clear();
    pendingPopups.clear();
    clearSurface(pageSurface);
  }

  function handleUpdate(msg) {
    if (typeof msg.zoom === "number" && msg.zoom > 0 && msg.zoom !== zoom) setZoom(msg.zoom);
    const fulls = msg.full || [];
    // Bind the in-tab window the first time we see a frame: the server-flagged
    // primary, or (older server / no flag) the first window in the batch.
    if (mainId === null && fulls.length) {
      bindMain((fulls.find((f) => f.primary) || fulls[0]).id);
    }
    for (const f of fulls) {
      windowsMeta.set(f.id, f);
      paintFull(f);
    }
    for (const p of msg.patches || []) applyPatch(p);
    for (const id of msg.close || []) {
      if (id === mainId) {
        // The editor closed the main window: blank the tab and show the overlay
        // rather than trying to close the OS tab.
        clearSurface(pageSurface);
        setOverlay("Editor window closed.");
        mainId = null;
      } else {
        closePopup(id);
        pendingPopups.delete(id);
      }
      windowsMeta.delete(id);
    }
  }

  // The shape of the pointer over a window: the server sends the CSS cursor of the
  // shape at the pointer when it changes, and the canvas of the window shows it.
  function setPointerCursor(msg) {
    const surface = surfaceFor(msg.window);
    if (surface && surface.canvas) surface.canvas.style.cursor = msg.cursor;
  }

  // ── Page (in-tab) main window ──────────────────────────────────────────────

  function bindMain(id) {
    mainId = id;
    sizeCanvas(pageSurface);
    if (!mainWired) {
      wireEvents(() => mainId, pageSurface);
      window.addEventListener("resize", onTabResize);
      // Browsers block window.open outside a transient user activation, so any
      // additional window that couldn't open from a server message is opened on
      // the next gesture in the tab.
      const onGesture = () => { flushPendingPopups(); reserveWindow(); };
      canvasEl.addEventListener("mousedown", onGesture);
      window.addEventListener("keydown", onGesture);
      mainWired = true;
    }
    // The server lays out at the WindowDocument's default size (e.g. 2400×1600);
    // tell it the real tab size so it re-lays-out to fit, then ask for fresh
    // full state at that size.
    sendResize(id, window);
    send({ type: "resync" });
  }

  function onTabResize() {
    if (!mainId) return;
    sizeCanvas(pageSurface);
    const m = windowsMeta.get(mainId);
    if (m) paint(pageSurface, m);          // repaint retained state so it isn't blank
    sendResize(mainId, window);
    send({ type: "resync" });              // server relayout -> fresh full state
  }

  // The size of the window `win` in logical pixels, sent as the size of `id`.
  function sendResize(id, win) {
    send({ type: "resize", window: id, w: Math.round(win.innerWidth / zoom),
           h: Math.round(win.innerHeight / zoom) });
  }

  // A new zoom of the editor: each surface draws at the new ratio, shows its last
  // frame at once, and sends its new logical size, so the server lays it out
  // again and sends it in full.
  function setZoom(value) {
    zoom = value;
    let resized = false;
    if (mainId !== null) {
      sizeCanvas(pageSurface);
      const m = windowsMeta.get(mainId);
      if (m) paint(pageSurface, m);
      sendResize(mainId, window);
      resized = true;
    }
    for (const [id, p] of popups) {
      if (!p.win || p.win.closed) continue;
      sizeCanvas(p);
      const m = windowsMeta.get(id);
      if (m) paint(p, m);
      sendResize(id, p.win);
      resized = true;
    }
    if (resized) send({ type: "resync" });
  }

  // ── Popups (additional windows) ─────────────────────────────────────────────

  // Open every queued popup now that we have a user gesture, painting each from
  // its retained state, then ask the server for fresh full state for all windows.
  function flushPendingPopups() {
    if (!pendingPopups.size) return;
    let opened = false;
    for (const meta of pendingPopups.values()) {
      const p = ensurePopup(meta);
      if (!p) continue;                 // still blocked; keep it queued for next gesture
      try { p.win.document.title = meta.title || "ProjecturEd"; } catch {}
      paint(p, windowsMeta.get(meta.id) || meta);
      pendingPopups.delete(meta.id);
      opened = true;
    }
    if (opened) send({ type: "resync" });
  }

  function ensurePopup(meta) {
    let p = popups.get(meta.id);
    if (p && !p.win.closed) return p;
    p = openPopup(meta);
    if (p) popups.set(meta.id, p);
    return p;
  }

  function openPopup(meta) {
    const width = Math.round((meta.w > 0 ? meta.w : 1024) * zoom);
    const height = Math.round((meta.h > 0 ? meta.h : 768) * zoom);
    let features = `width=${width},height=${height}`;
    if (meta.x >= 0) features += `,left=${Math.round(meta.x * zoom)}`;
    if (meta.y >= 0) features += `,top=${Math.round(meta.y * zoom)}`;
    const win = window.open("", meta.id, features);
    if (!win) return null;

    const doc = win.document;
    doc.open();
    doc.write(`<!DOCTYPE html><html><head><meta charset="utf-8"><title>${meta.title || "ProjecturEd"}</title>
      <style>html,body{margin:0;height:100%;overflow:hidden;background:#000}
      canvas{display:block;width:100vw;height:100vh}</style></head>
      <body><canvas id="c"></canvas></body></html>`);
    doc.close();

    const canvas = doc.getElementById("c");
    const ctx = canvas.getContext("2d");
    const p = { win, canvas, ctx, dpr: win.devicePixelRatio || 1 };
    sizeCanvas(p);
    wireEvents(() => meta.id, p);

    win.addEventListener("resize", () => {
      sizeCanvas(p);
      const m = windowsMeta.get(meta.id);
      if (m) paint(p, m);                 // repaint retained state so it isn't blank
      sendResize(meta.id, win);
      send({ type: "resync" });           // server relayout -> fresh full state
    });
    win.addEventListener("beforeunload", () => {
      send({ type: "close", window: meta.id });
      popups.delete(meta.id);
    });
    sendResize(meta.id, win);
    return p;
  }

  function closePopup(id) {
    const p = popups.get(id);
    if (p) { try { p.win.close(); } catch {} }
    popups.delete(id);
  }

  // The canvas has the pixels of the page, and `p.dpr` is the number of them in
  // one logical pixel: the ratio of the browser times the zoom.
  function sizeCanvas(p) {
    const ratio = p.win.devicePixelRatio || 1;
    const w = p.win.innerWidth, h = p.win.innerHeight;
    p.canvas.width = Math.max(1, Math.round(w * ratio));
    p.canvas.height = Math.max(1, Math.round(h * ratio));
    p.dpr = ratio * zoom;
  }

  function clearSurface(p) {
    if (!p.win || p.win.closed) return;
    const ctx = p.ctx;
    ctx.setTransform(p.dpr, 0, 0, p.dpr, 0, 0);
    ctx.clearRect(0, 0, p.win.innerWidth / zoom, p.win.innerHeight / zoom);
  }

  // ── Rendering ──────────────────────────────────────────────────────────────

  function col(c) { return `rgba(${c[0]},${c[1]},${c[2]},${(c[3] / 255).toFixed(4)})`; }

  // Full repaint of a window from its complete draw-list. The primary window
  // paints into the page canvas; any other window into its popup.
  function paintFull(meta) {
    if (meta.id === mainId) {
      try { document.title = meta.title || "ProjecturEd"; } catch {}
      setOverlay(null);
      paint(pageSurface, meta);
      return;
    }
    const p = ensurePopup(meta) || takeReserved(meta);
    if (!p) { pendingPopups.set(meta.id, meta); return; }  // blocked: open on next gesture
    try { p.win.document.title = meta.title || "ProjecturEd"; } catch {}
    paint(p, meta);
  }

  function paint(p, meta) {
    if (!p.win || p.win.closed) return;
    const ctx = p.ctx;
    ctx.setTransform(p.dpr, 0, 0, p.dpr, 0, 0);
    const w = p.win.innerWidth / zoom, h = p.win.innerHeight / zoom;
    if (meta.bg) { ctx.fillStyle = col(meta.bg); ctx.fillRect(0, 0, w, h); }
    else { ctx.clearRect(0, 0, w, h); }
    renderList(ctx, meta.draw || []);
  }

  // Incremental repaint: clip to the patch rectangle, clear it to the window
  // background, then paint the primitives the server sent for that region.
  function applyPatch(patch) {
    const p = surfaceFor(patch.window);
    const meta = windowsMeta.get(patch.window);
    if (!p || (p.win && p.win.closed) || !meta) return;
    const [x, y, w, h] = patch.clip;
    const ctx = p.ctx;
    ctx.setTransform(p.dpr, 0, 0, p.dpr, 0, 0);
    ctx.save();
    ctx.beginPath();
    ctx.rect(x, y, w, h);
    ctx.clip();
    ctx.fillStyle = meta.bg ? col(meta.bg) : "rgba(0,0,0,0)";
    if (meta.bg) ctx.fillRect(x, y, w, h); else ctx.clearRect(x, y, w, h);
    renderList(ctx, patch.draw || []);
    ctx.restore();
  }

  function renderList(ctx, list) { for (const e of list) renderNode(ctx, e); }

  function renderNode(ctx, e) {
    switch (e.t) {
      case "text":   return drawText(ctx, e);
      case "rect":   return drawRect(ctx, e);
      case "line":   return drawLine(ctx, e);
      case "polyline": return drawPolyline(ctx, e);
      case "polygon": return drawPolygon(ctx, e);
      case "circle": return drawCircle(ctx, e);
      case "arc":    return drawArc(ctx, e);
      case "group":  return drawGroup(ctx, e);
      case "clip":   return drawClip(ctx, e);
      case "image":  return drawImage(ctx, e);
    }
  }

  // A text is drawn as the layout measured it: each character at its pen
  // position (e.o, one per code point) on the baseline e.b below the top of the
  // box, with the fallback fonts in the server's order. Drawing each character
  // alone keeps the browser's kerning and ligatures out of the positions.
  function drawText(ctx, e) {
    if (!e.s) return;
    ctx.font = `${e.sz}px ${e.f.map((family) => `"${family}"`).join(", ")}`;
    ctx.textBaseline = "alphabetic";
    ctx.fillStyle = col(e.c);
    const characters = Array.from(e.s);
    const baseline = e.y + e.b;
    for (let i = 0; i < characters.length; i++) {
      const character = characters[i];
      if (character === "\uFE0E" || character === "\uFE0F") continue;
      ctx.fillText(character, e.x + e.o[i], baseline);
    }
  }

  function roundRectPath(ctx, x, y, w, h, rtl, rtr, rbr, rbl) {
    const m = Math.min(w / 2, h / 2);
    rtl = Math.min(rtl, m); rtr = Math.min(rtr, m);
    rbr = Math.min(rbr, m); rbl = Math.min(rbl, m);
    ctx.beginPath();
    ctx.moveTo(x + rtl, y);
    ctx.lineTo(x + w - rtr, y);
    ctx.arcTo(x + w, y, x + w, y + rtr, rtr);
    ctx.lineTo(x + w, y + h - rbr);
    ctx.arcTo(x + w, y + h, x + w - rbr, y + h, rbr);
    ctx.lineTo(x + rbl, y + h);
    ctx.arcTo(x, y + h, x, y + h - rbl, rbl);
    ctx.lineTo(x, y + rtl);
    ctx.arcTo(x, y, x + rtl, y, rtl);
    ctx.closePath();
  }

  function fillRounded(ctx, x, y, w, h, rtl, rtr, rbr, rbl, c) {
    if (w <= 0 || h <= 0) return;
    if ((rtl | rtr | rbr | rbl) === 0) { ctx.fillStyle = c; ctx.fillRect(x, y, w, h); return; }
    roundRectPath(ctx, x, y, w, h, rtl, rtr, rbr, rbl);
    ctx.fillStyle = c; ctx.fill();
  }

  function strokeRounded(ctx, x, y, w, h, rtl, rtr, rbr, rbl, bw, c) {
    if (w <= 0 || h <= 0 || bw <= 0) return;
    roundRectPath(ctx, x, y, w, h, rtl, rtr, rbr, rbl);
    ctx.strokeStyle = c; ctx.lineWidth = bw; ctx.stroke();
  }

  // Mirror Sdl's _render_rect!: an opaque fill paints the border-colored rounded
  // rect with the fill inset over it (radii shrink to stay concentric); a
  // translucent fill paints only the inset and strokes the border as a ring, or
  // the fill would composite against the border colour instead of against
  // whatever is behind the rect.
  function drawRect(ctx, e) {
    const bw = e.bw | 0;
    const inset = () => {
      if (e.c[3] <= 0) return;
      fillRounded(ctx, e.x + bw, e.y + bw, e.w - 2 * bw, e.h - 2 * bw,
        Math.max(0, e.rtl - bw), Math.max(0, e.rtr - bw),
        Math.max(0, e.rbr - bw), Math.max(0, e.rbl - bw), col(e.c));
    };
    if (bw > 0 && e.bc[3] > 0) {
      if (e.c[3] >= 255) {
        fillRounded(ctx, e.x, e.y, e.w, e.h, e.rtl, e.rtr, e.rbr, e.rbl, col(e.bc));
        inset();
      } else {
        inset();
        const hb = bw / 2;
        strokeRounded(ctx, e.x + hb, e.y + hb, e.w - bw, e.h - bw,
          Math.max(0, e.rtl - hb), Math.max(0, e.rtr - hb),
          Math.max(0, e.rbr - hb), Math.max(0, e.rbl - hb), bw, col(e.bc));
      }
    } else {
      fillRounded(ctx, e.x, e.y, e.w, e.h, e.rtl, e.rtr, e.rbr, e.rbl, col(e.c));
    }
  }

  function drawLine(ctx, e) {
    const wdt = Math.max(1, e.w | 0);
    const dash = e.dash;
    if (!dash && e.y1 === e.y2) {
      ctx.fillStyle = col(e.c);
      ctx.fillRect(Math.min(e.x1, e.x2), e.y1 - (wdt >> 1), Math.abs(e.x2 - e.x1) + 1, wdt);
    } else if (!dash && e.x1 === e.x2) {
      ctx.fillStyle = col(e.c);
      ctx.fillRect(e.x1 - (wdt >> 1), Math.min(e.y1, e.y2), wdt, Math.abs(e.y2 - e.y1) + 1);
    } else {
      // Dashed (any orientation) and solid diagonals both stroke a path; the
      // dash pattern is applied via setLineDash and reset afterwards.
      ctx.strokeStyle = col(e.c);
      ctx.lineWidth = wdt;
      ctx.lineCap = dash ? "butt" : "square";
      if (dash) ctx.setLineDash(dash);
      ctx.beginPath();
      ctx.moveTo(e.x1, e.y1);
      ctx.lineTo(e.x2, e.y2);
      ctx.stroke();
      if (dash) ctx.setLineDash([]);
    }
  }

  // A routed connector: a stroked polyline path plus optional filled-triangle
  // arrowheads. Splines are tessellated to a polyline server-side, so this op
  // covers both GraphicsPolyline and GraphicsSpline.
  function drawPolyline(ctx, e) {
    const pts = e.pts || [];
    if (pts.length < 1) return;
    const wdt = Math.max(1, e.w | 0);
    const c = col(e.c);
    const dash = e.dash;
    if (pts.length >= 2) {
      ctx.strokeStyle = c;
      ctx.lineWidth = wdt;
      ctx.lineCap = dash ? "butt" : "round";
      ctx.lineJoin = "round";
      // Same setLineDash dance as drawLine; the path below is one moveTo plus a
      // run of lineTo calls stroked in a single call, so the dash phase carries
      // continuously across vertices with no extra bookkeeping.
      if (dash) ctx.setLineDash(dash);
      ctx.beginPath();
      ctx.moveTo(pts[0][0], pts[0][1]);
      for (let i = 1; i < pts.length; i++) ctx.lineTo(pts[i][0], pts[i][1]);
      ctx.stroke();
      if (dash) ctx.setLineDash([]);
    }
    const sz = e.as | 0;
    const head = (atEnd) => {
      const n = pts.length;
      if (n < 2) return;
      const tip = atEnd ? pts[n - 1] : pts[0];
      const prev = atEnd ? pts[n - 2] : pts[1];
      let dx = tip[0] - prev[0], dy = tip[1] - prev[1];
      const len = Math.hypot(dx, dy);
      if (len === 0) return;
      const ux = dx / len, uy = dy / len, px = -uy, py = ux;
      const bx = tip[0] - ux * sz, by = tip[1] - uy * sz, half = sz / 2;
      ctx.beginPath();
      ctx.moveTo(tip[0], tip[1]);
      ctx.lineTo(bx + px * half, by + py * half);
      ctx.lineTo(bx - px * half, by - py * half);
      ctx.closePath();
      ctx.fillStyle = c;
      ctx.fill();
    };
    if (e.ea) head(true);
    if (e.sa) head(false);
  }

  // A closed filled shape, the filled counterpart of drawPolyline. The canvas
  // fill uses the nonzero winding rule, so a concave outline (a star marker)
  // needs no triangulation here; the border strokes the same path.
  function drawPolygon(ctx, e) {
    const pts = e.pts || [];
    if (pts.length < 3) return;
    ctx.beginPath();
    ctx.moveTo(pts[0][0], pts[0][1]);
    for (let i = 1; i < pts.length; i++) ctx.lineTo(pts[i][0], pts[i][1]);
    ctx.closePath();
    if (e.c[3] > 0) { ctx.fillStyle = col(e.c); ctx.fill(); }
    const bw = e.bw | 0;
    if (bw > 0 && e.bc[3] > 0) {
      ctx.strokeStyle = col(e.bc);
      ctx.lineWidth = bw;
      ctx.lineJoin = "round";
      ctx.stroke();
    }
  }

  function drawCircle(ctx, e) {
    const bw = e.bw | 0;
    const disc = (r, c) => { if (r <= 0) return; ctx.beginPath(); ctx.arc(e.cx, e.cy, r, 0, Math.PI * 2); ctx.fillStyle = c; ctx.fill(); };
    if (bw > 0 && e.bc[3] > 0) {
      if (e.c[3] > 0) {
        disc(e.r, col(e.bc));
        disc(e.r - bw, col(e.c));
      } else {
        // transparent fill: a true hollow ring (outer edge at e.r), centre unpainted
        const rm = Math.max(0, e.r - bw / 2);
        if (rm > 0) {
          ctx.beginPath();
          ctx.arc(e.cx, e.cy, rm, 0, Math.PI * 2);
          ctx.strokeStyle = col(e.bc);
          ctx.lineWidth = bw;
          ctx.stroke();
        }
      }
    } else {
      disc(e.r, col(e.c));
    }
  }

  // A stroke along a part of a circle, inside its outer radius e.r: the angles are
  // degrees from the top, clockwise. The canvas measures from 3 o'clock, so each
  // angle moves back by a quarter turn.
  function drawArc(ctx, e) {
    const w = Math.max(1, Math.min(e.w | 0, e.r));
    const rm = e.r - w / 2;
    if (rm <= 0 || !(e.sweep > 0) || e.c[3] <= 0) return;
    const sweep = Math.min(e.sweep, 360);
    const a0 = (e.start - 90) * Math.PI / 180;
    ctx.beginPath();
    ctx.arc(e.cx, e.cy, rm, a0, a0 + sweep * Math.PI / 180);
    ctx.strokeStyle = col(e.c);
    ctx.lineWidth = w;
    ctx.lineCap = "butt";
    ctx.stroke();
  }

  function drawGroup(ctx, e) {
    ctx.save();
    ctx.translate(e.x, e.y);
    renderList(ctx, e.content || []);
    ctx.restore();
  }

  // Mirror Sdl's _render_viewport!: clip to (x,y,w,h), then render content at the
  // content canvas's own (ox,oy) offset.
  function drawClip(ctx, e) {
    ctx.save();
    ctx.translate(e.x, e.y);
    ctx.beginPath();
    ctx.rect(0, 0, e.w, e.h);
    ctx.clip();
    // Optional viewport affine transform (zoom/pan): [a,b,c,d,e,f], applied
    // after the clip so it magnifies content within the fixed viewport box.
    if (e.m) ctx.transform(e.m[0], e.m[1], e.m[2], e.m[3], e.m[4], e.m[5]);
    ctx.translate(e.ox, e.oy);
    renderList(ctx, e.content || []);
    ctx.restore();
  }

  const imageCache = new Map();   // rgba-base64 -> offscreen canvas

  function drawImage(ctx, e) {
    let off = imageCache.get(e.rgba);
    if (!off) {
      const bin = atob(e.rgba);
      const bytes = new Uint8ClampedArray(bin.length);
      for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
      const img = new ImageData(bytes, e.nw, e.nh);
      off = document.createElement("canvas");
      off.width = e.nw; off.height = e.nh;
      off.getContext("2d").putImageData(img, 0, 0);
      if (imageCache.size > 256) imageCache.clear();
      imageCache.set(e.rgba, off);
    }
    ctx.drawImage(off, e.x, e.y, e.w, e.h);
  }

  // ── Event capture ──────────────────────────────────────────────────────────

  function mods(ev) { return { ctrl: ev.ctrlKey, shift: ev.shiftKey, alt: ev.altKey, meta: ev.metaKey }; }
  // The name of a button, or null for one that the event layer does not name. The
  // side buttons are back and forward.
  function buttonSym(b) {
    return b === 0 ? "left" : b === 1 ? "middle" : b === 2 ? "right" :
           b === 3 ? "back" : b === 4 ? "forward" : null;
  }
  // A side button is the page's own: the browser does not go back or forward.
  function isSideButton(b) { return b === 3 || b === 4; }
  // The place of the pointer in logical pixels.
  function pos(ev, canvas) {
    const r = canvas.getBoundingClientRect();
    return { x: Math.round((ev.clientX - r.left) / zoom), y: Math.round((ev.clientY - r.top) / zoom) };
  }

  const PREVENT_KEYS = new Set([
    "ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown", "Tab", "Backspace",
    "Delete", "Home", "End", "PageUp", "PageDown", "Enter", " ",
  ]);

  // `idFn` returns the current window id, so the page surface (whose binding can
  // change across reconnects) always sends the live `mainId`.
  function wireEvents(idFn, p) {
    const doc = p.win.document;
    const canvas = p.canvas;

    canvas.addEventListener("mousedown", (ev) => {
      const button = buttonSym(ev.button);
      if (button === null) return;
      if (isSideButton(ev.button)) ev.preventDefault();
      const { x, y } = pos(ev, canvas);
      send({ type: "mousedown", window: idFn(), button, x, y, mods: mods(ev),
             t: stamp(ev) });
    });
    // A press captures the pointer: until the release, the canvas gets the moves
    // and the release, and shows its cursor, also outside the window, so a drag
    // goes on and keeps its shape there.
    canvas.addEventListener("pointerdown", (ev) => {
      try { canvas.setPointerCapture(ev.pointerId); } catch {}
    });
    canvas.addEventListener("mouseup", (ev) => {
      const button = buttonSym(ev.button);
      if (button === null) return;
      if (isSideButton(ev.button)) ev.preventDefault();
      const { x, y } = pos(ev, canvas);
      send({ type: "mouseup", window: idFn(), button, x, y, mods: mods(ev),
             t: stamp(ev) });
    });
    // Every move goes, so the part under the pointer lights and a tooltip comes.
    // A move with a button held goes at once, for a drag; a move with no button
    // held goes at most once per animation frame, the last one of the frame.
    let pendingMove = null;
    canvas.addEventListener("mousemove", (ev) => {
      const { x, y } = pos(ev, canvas);
      const move = { type: "mousemove", window: idFn(), x, y, buttons: ev.buttons,
                     mods: mods(ev), t: stamp(ev) };
      if (ev.buttons !== 0) {
        pendingMove = null;
        send(move);
        return;
      }
      const isFirst = pendingMove === null;
      pendingMove = move;
      if (isFirst) {
        p.win.requestAnimationFrame(() => {
          const last = pendingMove;
          pendingMove = null;
          if (last !== null) send(last);
        });
      }
    });
    // The pointer went out of the window: the screen gives the window a move off
    // it, so nothing in it stays lit.
    canvas.addEventListener("mouseleave", (ev) => {
      send({ type: "leave", window: idFn(), t: stamp(ev) });
    });
    canvas.addEventListener("wheel", (ev) => {
      ev.preventDefault();
      const { x, y } = pos(ev, canvas);
      send({
        type: "scroll", window: idFn(),
        dx: Math.sign(ev.deltaX), dy: -Math.sign(ev.deltaY),
        x, y, mods: mods(ev), t: stamp(ev),
      });
    }, { passive: false });
    canvas.addEventListener("contextmenu", (ev) => ev.preventDefault());

    doc.addEventListener("keydown", (ev) => {
      const prevented = PREVENT_KEYS.has(ev.key) || ev.ctrlKey || ev.metaKey;
      if (prevented) ev.preventDefault();
      send({ type: "keydown", window: idFn(), key: ev.key, code: ev.code, repeat: ev.repeat,
             mods: mods(ev), t: stamp(ev) });
      // preventDefault() on keydown suppresses the browser's keypress event, so a
      // printable key we prevented would never deliver its type-in character. In
      // practice this is Space (kept in PREVENT_KEYS so it doesn't scroll/activate
      // the page): synthesize the keypress here for the single-character case so a
      // space inserts like any other typed character. Ctrl/Meta combos are excluded
      // — those are chords, not text input.
      if (prevented && ev.key.length === 1 && !ev.ctrlKey && !ev.metaKey) {
        send({ type: "keypress", window: idFn(), char: ev.key, text: ev.key, mods: mods(ev),
               t: stamp(ev) });
      }
    });
    doc.addEventListener("keyup", (ev) => {
      send({ type: "keyup", window: idFn(), key: ev.key, code: ev.code, mods: mods(ev),
             t: stamp(ev) });
    });
    doc.addEventListener("keypress", (ev) => {
      const ch = ev.key;                       // printable chars only (≈ SDL_TEXTINPUT)
      if (!ch || ch.length !== 1) return;
      send({ type: "keypress", window: idFn(), char: ch, text: ch, mods: mods(ev), t: stamp(ev) });
    });
  }

  // ── Boot ───────────────────────────────────────────────────────────────────

  window.addEventListener("beforeunload", () => {
    for (const p of popups.values()) { try { p.win.close(); } catch {} }
    send({ type: "quit" });
  });

  (async () => {
    setOverlay("Loading fonts…");
    await loadFonts();
    setOverlay("Connecting…");
    connect();
  })();
})();
