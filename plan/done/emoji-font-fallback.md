# Emoji font fallback in the SDL text renderer

## Problem

Emoji in rendered text (notably the assistant/Conversation LLM output) appear as
tofu boxes (□). Root cause:

- Every text span is rasterised through a **single** SDL2_ttf font via
  `TTF_RenderUTF8_Blended` ([package/sdl/src/ProjecturedSdl.jl:644](../../package/sdl/src/ProjecturedSdl.jl)).
- The bundled fonts (`asset/font/`: Ubuntu, UbuntuMono, DejaVu, Liberation) have
  **no emoji glyphs**.
- SDL2 (`SimpleDirectMediaLayer.LibSDL2`) has **no fallback-font API**
  (`TTF_AddFallbackFont` is SDL_ttf 3.x only), so any codepoint the active font
  lacks is drawn as `.notdef` = the box.

## Chosen approach — Option A: per-glyph font fallback

Bundle a **monochrome** emoji font (renders through the existing blended path —
no fragile SDL2 colour-emoji plumbing) and, when a span mixes text + emoji, split
it into maximal same-font runs, rasterise each run with its font, and composite
the run surfaces side-by-side (baseline-aligned) into one surface before upload.
The single-texture-per-span cache model is preserved.

### Font

- **Noto Emoji** (monochrome, SIL OFL 1.1) → `asset/font/NotoEmoji-Regular.ttf`,
  plus `asset/font/NotoEmoji-OFL.txt` for attribution. OFL lets us bundle/redistribute.

### Glyph → font routing (no shaping engine; SDL2_ttf is glyph-by-glyph)

`TTF_GlyphIsProvided` is BMP-only (takes `UInt16`), and the 32-bit variant is not
in the binding, so:

- codepoint `> 0xFFFF` (astral plane — virtually all pictographic emoji): → emoji font.
- codepoint `<= 0xFFFF`: primary font if `TTF_GlyphIsProvided(primary, cp) != 0`,
  else emoji font if it provides it, else primary (box). This keeps symbols the
  text font *does* have (✓ ★ → • box-drawing) in the text font where they look right.
- **Variation selectors** U+FE0E/U+FE0F: stripped (zero-width presentation hints
  that would otherwise route to the emoji font and draw a stray box).
- **ZWJ** U+200D and **skin-tone modifiers** U+1F3FB–U+1F3FF: stick to the current
  run's font (don't start a new run) so they stay with the preceding emoji.

Limitation (documented, acceptable for v1): no glyph shaping, so ZWJ sequences
(👨‍👩‍👧) and skin-tone combinations render as their separate base glyphs, not the
combined emoji.

### Compositing

For each run: `TTF_RenderUTF8_Blended` → surface (`w`, `h`, `ascent = TTF_FontAscent`).
Combined surface = `SDL_CreateRGBSurfaceWithFormat(0, Σw, max_ascent + max_below, 32, ARGB8888)`,
where `max_below = max(h - ascent)`. Blit each run at `x` (running sum) and
`y = max_ascent - ascent` (baseline alignment), with `SDL_BLENDMODE_NONE` (straight
RGBA copy; runs don't overlap). Free run surfaces; return the combined surface,
which the caller treats exactly like the old single surface.

**Fast path:** when there is only one run (the common all-text case) skip
compositing entirely and use the single rendered surface — zero overhead on the
hot path and byte-for-byte identical to current behaviour.

### Measurement

`measure_text` must agree with rendering, so it splits runs the same way and sums
`TTF_SizeUTF8` widths per run, taking `max_ascent + max_below` for height. Single
run → unchanged fast path.

## Steps

- [x] **1. Bundle the emoji font.** Monochrome OFL Noto Emoji → `asset/font/NotoEmoji-Regular.ttf` + `NotoEmoji-OFL.txt`. *(See discovery: first build was an incomplete v2.034 static — missing U+1F916 robot — so swapped for the complete modern monochrome Noto Emoji.)*
- [x] **2. Emoji font loader.** `_EMOJI_FONT_FILE` (from `_FONT_DIR`) + `_get_emoji_font(size)` caching into `_font_cache`, returning `C_NULL` on missing/failed load. `quit!` null-guard added. `_FONT_DIR` imported from `FontModule`.
- [x] **3. Run splitter + compositor.** `_font_runs(text, primary, emoji)` + `_render_runs_blended(runs, color)`; wired into `_render_element!(::GraphicsText)` with the single-run fast path.
- [x] **4. Measurement.** `measure_text` splits runs and sums per-run metrics. **Bug found & fixed:** the single-run fast path measured with `primary`, so an all-emoji span was sized from the text font's `.notdef` box (8px) — now uses the run's own font.
- [x] **5. Build + verify.** Offscreen `write_image` render confirms 😀 ✅ 🎉 🤖 render as glyphs (`✓ ★ →` remain boxes — out of scope, see discoveries). Regression tests `test_write_image`, `test_hover_probe`, `test_hover_probe_pipeline` all pass. Committed steps 1–5.
- [x] **6.** Plan moved to `plan/done/`.

## Decisions / discoveries (filled in during implementation)

- SDL backend = SDL2 (`SimpleDirectMediaLayer.LibSDL2`); confirmed no fallback API.
- Surface/blit symbols all present in the binding: `SDL_CreateRGBSurfaceWithFormat`,
  `SDL_BlitSurface`, `SDL_SetSurfaceBlendMode`, `SDL_FreeSurface`, `TTF_FontAscent`.
- Texture cache key `(renderer, text, filename, size, color)` is unchanged: emoji
  routing is a deterministic function of `text` + primary font, so the key still
  uniquely identifies the composite.
- **Emoji font coverage matters.** The first bundled file (static Noto Emoji
  v2.034) was incomplete — `fc-query` charset showed U+1F916 (🤖 robot) absent,
  rendering as a box even though it routed to the emoji font. Swapped to the
  complete modern monochrome Noto Emoji.
- **Out of scope — text-presentation symbols.** ✓ (U+2713), ★ (U+2605),
  → (U+2192) render as boxes: Ubuntu lacks them (they were boxes before this
  change too) and Noto Emoji intentionally covers only emoji, not text symbols.
  Not a regression. A future improvement could add the already-bundled DejaVu
  Sans as a *second* BMP-symbol fallback ahead of the emoji font — deferred to
  keep this change emoji-scoped.
