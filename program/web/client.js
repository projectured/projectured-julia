// ProjecturEd web client.
//
// The editor lives on the server. This client:
//   - loads the server's TTF/OTF fonts so text metrics match server-side layout,
//   - opens one browser popup per editor WindowDocument (the final paint surface),
//   - renders the JSON draw-list the server sends into each popup's <canvas>,
//   - forwards raw mouse/keyboard/resize events back to the server.
//
// Transport is JSON over a single WebSocket. See program/src/backend/Web.jl for
// the matching server side and the wire protocol.

(() => {
  "use strict";

  const statusEl = document.getElementById("status");
  const launchBtn = document.getElementById("launch");

  let ws = null;
  let latestFrame = null;            // most recent {type:"frame", windows:[…]}
  let launched = false;              // popups may only open after a user gesture
  const popups = new Map();          // id -> { win, canvas, ctx, draw, bg }

  // ── Fonts ────────────────────────────────────────────────────────────────
  // Load every served font so the browser renders with the same glyphs the
  // server measured. Family name = file basename without extension.

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
    ws.onopen = () => { statusEl.textContent = "Connected. Click Launch to open the editor."; launchBtn.disabled = false; };
    ws.onclose = () => { statusEl.textContent = "Disconnected."; };
    ws.onerror = () => { statusEl.textContent = "Connection error."; };
    ws.onmessage = (ev) => {
      let msg;
      try { msg = JSON.parse(ev.data); } catch { return; }
      if (msg.type === "frame") {
        latestFrame = msg;
        if (launched) reconcile(msg);
      } else if (msg.type === "busy") {
        statusEl.textContent = "Another client is already connected to this editor.";
      }
    };
  }

  function send(obj) {
    if (ws && ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify(obj));
  }

  // ── Popups ───────────────────────────────────────────────────────────────

  function reconcile(frame) {
    const wantIds = new Set(frame.windows.map((w) => w.id));
    // Close popups whose window disappeared.
    for (const id of [...popups.keys()]) {
      if (!wantIds.has(id)) {
        const p = popups.get(id);
        try { p.win.close(); } catch {}
        popups.delete(id);
      }
    }
    // Open / update each window.
    for (const w of frame.windows) {
      let p = popups.get(w.id);
      if (!p || p.win.closed) {
        p = openPopup(w);
        if (!p) continue;          // popup blocked
        popups.set(w.id, p);
      }
      p.draw = w.draw;
      p.bg = w.bg;
      try { p.win.document.title = w.title || "ProjecturEd"; } catch {}
      paint(p);
    }
  }

  function openPopup(w) {
    const width = w.w > 0 ? w.w : 1024;
    const height = w.h > 0 ? w.h : 768;
    let features = `width=${width},height=${height}`;
    if (w.x >= 0) features += `,left=${w.x}`;
    if (w.y >= 0) features += `,top=${w.y}`;
    const win = window.open("", w.id, features);
    if (!win) return null;

    const doc = win.document;
    doc.open();
    doc.write(`<!DOCTYPE html><html><head><meta charset="utf-8"><title>${w.title || "ProjecturEd"}</title>
      <style>html,body{margin:0;height:100%;overflow:hidden;background:#000}
      canvas{display:block;width:100vw;height:100vh}</style></head>
      <body><canvas id="c"></canvas></body></html>`);
    doc.close();

    const canvas = doc.getElementById("c");
    const ctx = canvas.getContext("2d");
    const p = { win, canvas, ctx, draw: w.draw, bg: w.bg };
    sizeCanvas(p);
    wireEvents(w.id, p);

    win.addEventListener("resize", () => {
      sizeCanvas(p);
      send({ type: "resize", window: w.id, w: win.innerWidth, h: win.innerHeight });
      paint(p);
    });
    win.addEventListener("beforeunload", () => {
      send({ type: "close", window: w.id });
      popups.delete(w.id);
    });
    // Report the real popup size once (it may differ from the requested size).
    send({ type: "resize", window: w.id, w: win.innerWidth, h: win.innerHeight });
    return p;
  }

  function sizeCanvas(p) {
    const dpr = p.win.devicePixelRatio || 1;
    const w = p.win.innerWidth, h = p.win.innerHeight;
    p.canvas.width = Math.max(1, Math.round(w * dpr));
    p.canvas.height = Math.max(1, Math.round(h * dpr));
    p.dpr = dpr;
  }

  // ── Rendering ──────────────────────────────────────────────────────────────

  function col(c) { return `rgba(${c[0]},${c[1]},${c[2]},${(c[3] / 255).toFixed(4)})`; }

  function paint(p) {
    if (!p.win || p.win.closed) return;
    const ctx = p.ctx;
    ctx.setTransform(p.dpr, 0, 0, p.dpr, 0, 0);
    const w = p.win.innerWidth, h = p.win.innerHeight;
    if (p.bg) { ctx.fillStyle = col(p.bg); ctx.fillRect(0, 0, w, h); }
    else { ctx.clearRect(0, 0, w, h); }
    renderList(ctx, p.draw || []);
  }

  function renderList(ctx, list) {
    for (const e of list) renderNode(ctx, e);
  }

  function renderNode(ctx, e) {
    switch (e.t) {
      case "text":   return drawText(ctx, e);
      case "rect":   return drawRect(ctx, e);
      case "line":   return drawLine(ctx, e);
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

  // Mirror Sdl's _render_rect!: optional outer border-colored rounded rect, then
  // the fill inset by the border width (radii shrink to stay concentric).
  function drawRect(ctx, e) {
    const bw = e.bw | 0;
    if (bw > 0 && e.bc[3] > 0) {
      fillRounded(ctx, e.x, e.y, e.w, e.h, e.rtl, e.rtr, e.rbr, e.rbl, col(e.bc));
      if (e.c[3] > 0) {
        fillRounded(ctx, e.x + bw, e.y + bw, e.w - 2 * bw, e.h - 2 * bw,
          Math.max(0, e.rtl - bw), Math.max(0, e.rtr - bw),
          Math.max(0, e.rbr - bw), Math.max(0, e.rbl - bw), col(e.c));
      }
    } else {
      fillRounded(ctx, e.x, e.y, e.w, e.h, e.rtl, e.rtr, e.rbr, e.rbl, col(e.c));
    }
  }

  // Axis-aligned lines paint as a crisp filled span (matching Sdl); diagonals
  // stroke with square caps.
  function drawLine(ctx, e) {
    const wdt = Math.max(1, e.w | 0);
    if (e.y1 === e.y2) {
      ctx.fillStyle = col(e.c);
      ctx.fillRect(Math.min(e.x1, e.x2), e.y1 - (wdt >> 1), Math.abs(e.x2 - e.x1) + 1, wdt);
    } else if (e.x1 === e.x2) {
      ctx.fillStyle = col(e.c);
      ctx.fillRect(e.x1 - (wdt >> 1), Math.min(e.y1, e.y2), wdt, Math.abs(e.y2 - e.y1) + 1);
    } else {
      ctx.strokeStyle = col(e.c);
      ctx.lineWidth = wdt;
      ctx.lineCap = "square";
      ctx.beginPath();
      ctx.moveTo(e.x1, e.y1);
      ctx.lineTo(e.x2, e.y2);
      ctx.stroke();
    }
  }

  function drawCircle(ctx, e) {
    const bw = e.bw | 0;
    const disc = (r, c) => { if (r <= 0) return; ctx.beginPath(); ctx.arc(e.cx, e.cy, r, 0, Math.PI * 2); ctx.fillStyle = c; ctx.fill(); };
    if (bw > 0 && e.bc[3] > 0) {
      disc(e.r, col(e.bc));
      if (e.c[3] > 0) disc(e.r - bw, col(e.c));
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

  // Mirror Sdl's _render_viewport!: clip to (x,y,w,h), then render content at
  // the content canvas's own (ox,oy) offset.
  function drawClip(ctx, e) {
    ctx.save();
    ctx.translate(e.x, e.y);
    ctx.beginPath();
    ctx.rect(0, 0, e.w, e.h);
    ctx.clip();
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

  function wireEvents(id, p) {
    const doc = p.win.document;
    const canvas = p.canvas;

    canvas.addEventListener("mousedown", (ev) => {
      const { x, y } = pos(ev, canvas);
      send({ type: "mousedown", window: id, button: buttonSym(ev.button), x, y, mods: mods(ev) });
    });
    canvas.addEventListener("mouseup", (ev) => {
      const { x, y } = pos(ev, canvas);
      send({ type: "mouseup", window: id, button: buttonSym(ev.button), x, y, mods: mods(ev) });
    });
    canvas.addEventListener("mousemove", (ev) => {
      const held = heldSym(ev.buttons);
      if (held === "none") return;             // only forward motion while held
      const { x, y } = pos(ev, canvas);
      send({ type: "mousemove", window: id, x, y, buttons: held, mods: mods(ev) });
    });
    canvas.addEventListener("wheel", (ev) => {
      ev.preventDefault();
      const { x, y } = pos(ev, canvas);
      send({
        type: "scroll", window: id,
        dx: Math.sign(ev.deltaX), dy: -Math.sign(ev.deltaY),
        x, y, mods: mods(ev),
      });
    }, { passive: false });
    canvas.addEventListener("contextmenu", (ev) => ev.preventDefault());

    doc.addEventListener("keydown", (ev) => {
      if (PREVENT_KEYS.has(ev.key) || ev.ctrlKey || ev.metaKey) ev.preventDefault();
      send({ type: "keydown", window: id, key: ev.key, code: ev.code, repeat: ev.repeat, mods: mods(ev) });
    });
    doc.addEventListener("keyup", (ev) => {
      send({ type: "keyup", window: id, key: ev.key, code: ev.code, mods: mods(ev) });
    });
    doc.addEventListener("keypress", (ev) => {
      // Printable characters only (mirrors SDL_TEXTINPUT → KeyPress).
      const ch = ev.key;
      if (!ch || ch.length !== 1) return;
      send({ type: "keypress", window: id, char: ch, text: ch, mods: mods(ev) });
    });
  }

  // ── Boot ───────────────────────────────────────────────────────────────────

  launchBtn.addEventListener("click", () => {
    launched = true;
    launchBtn.disabled = true;
    statusEl.textContent = "Editor running in pop-up window(s).";
    if (latestFrame) reconcile(latestFrame);
  });

  window.addEventListener("beforeunload", () => {
    for (const p of popups.values()) { try { p.win.close(); } catch {} }
    send({ type: "quit" });
  });

  (async () => {
    await loadFonts();
    statusEl.textContent = "Fonts loaded. Connecting…";
    connect();
  })();
})();
