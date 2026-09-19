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
//   {type:"update", full:[win...], patches:[{window,clip,draw}...], close:[id...]}
// A `full` entry carries a window's complete draw-list and a `primary` flag (the
// in-tab window); a `patch` repaints only its clip rectangle over the retained
// canvas (incremental rendering). See package/web/src/ProjecturedWeb.jl.

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
  const overlays = new Map();           // id -> { win, canvas, ctx, dpr } drawn IN the page

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

  // The surface for a window id: the page for the primary window, an overlay in
  // the page for a tooltip, else its popup.
  function surfaceFor(id) {
    return id === mainId ? pageSurface : (overlays.get(id) || popups.get(id));
  }

  // ── Tooltips (drawn in the page, never opened as a popup) ───────────────────
  //
  // A browser opens a window only inside a transient user activation. A menu is
  // opened by a click and has one; a tooltip is opened by the pointer resting
  // and has none, so a tooltip asked for as a popup would sit in `pendingPopups`
  // until the next click and appear at the wrong moment. It is drawn in the page
  // instead: the document model is the same everywhere, and only this client
  // draws a `tooltip` window differently.
  function ensureOverlay(meta) {
    let o = overlays.get(meta.id);
    if (!o) {
      const canvas = document.createElement("canvas");
      canvas.style.position = "fixed";
      canvas.style.zIndex = "2147483647";
      // A tooltip says something; it never takes the pointer away from what it
      // says it about.
      canvas.style.pointerEvents = "none";
      document.body.appendChild(canvas);
      o = { win: window, canvas, ctx: canvas.getContext("2d"),
            dpr: window.devicePixelRatio || 1 };
      overlays.set(meta.id, o);
    }
    // The server places a window in screen coordinates; in a page the only
    // coordinates there are are the page's own, so the two agree at the origin
    // of the tab and drift by whatever the browser chrome takes.
    o.canvas.style.left = (meta.x >= 0 ? meta.x : 0) + "px";
    o.canvas.style.top = (meta.y >= 0 ? meta.y : 0) + "px";
    o.canvas.style.width = (meta.w > 0 ? meta.w : 200) + "px";
    o.canvas.style.height = (meta.h > 0 ? meta.h : 60) + "px";
    return o;
  }

  function closeOverlay(id) {
    const o = overlays.get(id);
    if (!o) return;
    try { o.canvas.remove(); } catch {}
    overlays.delete(id);
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
      else if (msg.type === "busy") setOverlay("Another client is already connected to this editor.");
    };
  }

  function send(obj) {
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
        closeOverlay(id);
        closePopup(id);
        pendingPopups.delete(id);
      }
      windowsMeta.delete(id);
    }
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
      canvasEl.addEventListener("mousedown", flushPendingPopups);
      window.addEventListener("keydown", flushPendingPopups);
      mainWired = true;
    }
    // The server lays out at the WindowDocument's default size (e.g. 2400×1600);
    // tell it the real tab size so it re-lays-out to fit, then ask for fresh
    // full state at that size.
    send({ type: "resize", window: id, w: window.innerWidth, h: window.innerHeight });
    send({ type: "resync" });
  }

  function onTabResize() {
    if (!mainId) return;
    sizeCanvas(pageSurface);
    const m = windowsMeta.get(mainId);
    if (m) paint(pageSurface, m);          // repaint retained state so it isn't blank
    send({ type: "resize", window: mainId, w: window.innerWidth, h: window.innerHeight });
    send({ type: "resync" });              // server relayout -> fresh full state
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
    const width = meta.w > 0 ? meta.w : 1024;
    const height = meta.h > 0 ? meta.h : 768;
    let features = `width=${width},height=${height}`;
    if (meta.x >= 0) features += `,left=${meta.x}`;
    if (meta.y >= 0) features += `,top=${meta.y}`;
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
      send({ type: "resize", window: meta.id, w: win.innerWidth, h: win.innerHeight });
      send({ type: "resync" });           // server relayout -> fresh full state
    });
    win.addEventListener("beforeunload", () => {
      send({ type: "close", window: meta.id });
      popups.delete(meta.id);
    });
    send({ type: "resize", window: meta.id, w: win.innerWidth, h: win.innerHeight });
    return p;
  }

  function closePopup(id) {
    const p = popups.get(id);
    if (p) { try { p.win.close(); } catch {} }
    popups.delete(id);
  }

  function sizeCanvas(p) {
    const dpr = p.win.devicePixelRatio || 1;
    const w = p.win.innerWidth, h = p.win.innerHeight;
    p.canvas.width = Math.max(1, Math.round(w * dpr));
    p.canvas.height = Math.max(1, Math.round(h * dpr));
    p.dpr = dpr;
  }

  function clearSurface(p) {
    if (!p.win || p.win.closed) return;
    const ctx = p.ctx;
    ctx.setTransform(p.dpr, 0, 0, p.dpr, 0, 0);
    ctx.clearRect(0, 0, p.win.innerWidth, p.win.innerHeight);
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
    if (meta.style === "tooltip") { paint(ensureOverlay(meta), meta); return; }
    const p = ensurePopup(meta);
    if (!p) { pendingPopups.set(meta.id, meta); return; }  // blocked: open on next gesture
    try { p.win.document.title = meta.title || "ProjecturEd"; } catch {}
    paint(p, meta);
  }

  function paint(p, meta) {
    if (!p.win || p.win.closed) return;
    const ctx = p.ctx;
    ctx.setTransform(p.dpr, 0, 0, p.dpr, 0, 0);
    const w = p.win.innerWidth, h = p.win.innerHeight;
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
      case "group":  return drawGroup(ctx, e);
      case "clip":   return drawClip(ctx, e);
      case "image":  return drawImage(ctx, e);
    }
  }

  function drawText(ctx, e) {
    if (!e.s) return;
    ctx.font = `${e.sz}px "${e.f}"`;
    ctx.textBaseline = "top";
    ctx.fillStyle = col(e.c);
    ctx.fillText(e.s, e.x, e.y);
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
  function buttonSym(b) { return b === 1 ? "middle" : b === 2 ? "right" : "left"; }
  function heldSym(buttons) {
    if (buttons & 1) return "left";
    if (buttons & 2) return "right";
    if (buttons & 4) return "middle";
    return "none";
  }
  function pos(ev, canvas) {
    const r = canvas.getBoundingClientRect();
    return { x: Math.round(ev.clientX - r.left), y: Math.round(ev.clientY - r.top) };
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
      const { x, y } = pos(ev, canvas);
      send({ type: "mousedown", window: idFn(), button: buttonSym(ev.button), x, y, mods: mods(ev) });
    });
    canvas.addEventListener("mouseup", (ev) => {
      const { x, y } = pos(ev, canvas);
      send({ type: "mouseup", window: idFn(), button: buttonSym(ev.button), x, y, mods: mods(ev) });
    });
    canvas.addEventListener("mousemove", (ev) => {
      const held = heldSym(ev.buttons);
      if (held === "none") return;             // only forward motion while held
      const { x, y } = pos(ev, canvas);
      send({ type: "mousemove", window: idFn(), x, y, buttons: held, mods: mods(ev) });
    });
    canvas.addEventListener("wheel", (ev) => {
      ev.preventDefault();
      const { x, y } = pos(ev, canvas);
      send({
        type: "scroll", window: idFn(),
        dx: Math.sign(ev.deltaX), dy: -Math.sign(ev.deltaY),
        x, y, mods: mods(ev),
      });
    }, { passive: false });
    canvas.addEventListener("contextmenu", (ev) => ev.preventDefault());

    doc.addEventListener("keydown", (ev) => {
      const prevented = PREVENT_KEYS.has(ev.key) || ev.ctrlKey || ev.metaKey;
      if (prevented) ev.preventDefault();
      send({ type: "keydown", window: idFn(), key: ev.key, code: ev.code, repeat: ev.repeat, mods: mods(ev) });
      // preventDefault() on keydown suppresses the browser's keypress event, so a
      // printable key we prevented would never deliver its type-in character. In
      // practice this is Space (kept in PREVENT_KEYS so it doesn't scroll/activate
      // the page): synthesize the keypress here for the single-character case so a
      // space inserts like any other typed character. Ctrl/Meta combos are excluded
      // — those are chords, not text input.
      if (prevented && ev.key.length === 1 && !ev.ctrlKey && !ev.metaKey) {
        send({ type: "keypress", window: idFn(), char: ev.key, text: ev.key, mods: mods(ev) });
      }
    });
    doc.addEventListener("keyup", (ev) => {
      send({ type: "keyup", window: idFn(), key: ev.key, code: ev.code, mods: mods(ev) });
    });
    doc.addEventListener("keypress", (ev) => {
      const ch = ev.key;                       // printable chars only (≈ SDL_TEXTINPUT)
      if (!ch || ch.length !== 1) return;
      send({ type: "keypress", window: idFn(), char: ch, text: ch, mods: mods(ev) });
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
