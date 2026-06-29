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

- [ ] **1. Bundle the emoji font.** Acquire OFL Noto Emoji (monochrome) → `asset/font/NotoEmoji-Regular.ttf` + `NotoEmoji-OFL.txt`. Verify: valid TTF, monochrome, provides U+1F600. *(Sonnet subagent.)* Commit.
- [ ] **2. Emoji font loader.** `_EMOJI_FONT_FILE` (from `_FONT_DIR`) + `_get_emoji_font(size)` that caches into `_font_cache` and returns `C_NULL` on missing/failed load (graceful degradation). Add null-guard to the `quit!` font-close loop. Import `_FONT_DIR` from `FontModule`.
- [ ] **3. Run splitter + compositor.** `_font_runs(text, primary, emoji)` and `_render_runs_blended(runs, color)`; wire into `_render_element!(::GraphicsText)` with the single-run fast path.
- [ ] **4. Measurement.** Update `measure_text` to split runs and sum per-run metrics.
- [ ] **5. Build + verify.** Load the SDL package; render an emoji-bearing string offscreen (`write_image`) and confirm glyphs are not tofu; run the smallest relevant test. Commit steps 2–4.
- [ ] **6.** Move this plan to `plan/done/`.

## Decisions / discoveries (filled in during implementation)

- SDL backend = SDL2 (`SimpleDirectMediaLayer.LibSDL2`); confirmed no fallback API.
- Surface/blit symbols all present in the binding: `SDL_CreateRGBSurfaceWithFormat`,
  `SDL_BlitSurface`, `SDL_SetSurfaceBlendMode`, `SDL_FreeSurface`, `TTF_FontAscent`.
- Texture cache key `(renderer, text, filename, size, color)` is unchanged: emoji
  routing is a deterministic function of `text` + primary font, so the key still
  uniquely identifies the composite.
