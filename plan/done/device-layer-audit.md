# The audit of the device layer

The owner asked for a review of the whole shape of the device layer
(`source/kernel/device/`) and a re-audit against the rules in
`documentation/rule/`. The layer is five files: the abstract `Device`, and the
`Display`, `Keyboard` and `Mouse` devices. It has no imports and no functions.

The main finding: no code reads what the devices hold. The SDL backend writes the
size and the scale of the display into each `Display`, and no code reads them.
The scale that SDL uses comes from process-global values in the style package.

On 2026-09-25 the owner chose option (b) for item 1, accepted items 2 to 7, and
asked for this plan, to see how large (b) is before the work starts. The owner
then confirmed the decisions D1 to D5 as recommended, and gave permission to
unseal the five files of the layer.

## Items

1. **Option (b): the `Display` of each editor is the source of its scale.** The
   process-global display scale and the process-global zoom go. Part 1 below.
2. The module docstring says "inert marker types" and "no per-device state". Both
   are false. Its link names `Device.jl`, and the file is `DeviceInterface.jl`.
3. The `Display` docstring describes the SDL windows, promises multi-monitor
   support, and uses the passive voice and "HiDPI". The `Mouse` docstring has a
   sentence that is hard to read.
4. `Keyboard` and `Mouse` are `mutable`, and no code writes them. They stay
   mutable, because a backend fills a device in place. The docstrings say so.
5. The export block is one statement for four fragments, and `DeviceModule` is
   in `EXPORT_UNMIGRATED`.
6. The layer has no test file. Its tests are in `HeadlessBackendTest.jl` and call
   the devices "markers". They move to `test/kernel/device/DeviceTest.jl`.
7. False text outside the layer: `devices-and-backends.md` (the `Screen` row, "a
   stateless singleton struct", `Device.jl` in the tree, `read_from_device` and
   `write_to_device`), `naming-rules.md` (`Device.jl` as the example), the SDL
   `write_to_devices` docstring (a check for a `Display` that the code does not
   do), and the `Editor` docstring ("window" as a device).

## Part 1: the scale of each editor comes from its Display

### The facts

The style package holds three process-global values in `source/style/Font.jl`:

| Value | What it is | Written by | Read by |
| --- | --- | --- | --- |
| `_BASE_DISPLAY_SCALE` | the scale of the hardware, found by a probe | the SDL probe, once | only the product below |
| `_USER_ZOOM` | the uniform zoom, Ctrl+= and Ctrl+- | `adjust_user_zoom!` | only the product below |
| `_DISPLAY_SCALE` | the product of the two | `recompute_display_scale!`, and the offscreen render, which swaps it for the time of an export | about 50 lines in `Sdl.jl`, and `font_scaled_size` and `font_device_size` |

`_FONT_ZOOM`, the zoom of Ctrl+Alt+= and Ctrl+Alt+-, is a fourth value. It is not
part of this plan (see "Not in this plan").

All the readers of `_DISPLAY_SCALE` are in the SDL backend:

- The conversion between logical and device pixels: `_to_device` and
  `_to_logical`. The SDL backend uses them for the window sizes, the
  supersampled target, the input coordinates, the resize events and the size
  query.
- The render: the renderer scale in `_render_window!`, the size of the fonts, and
  the size of each text texture.
- The text measure: `measure_text(::SdlBackend, …)` measures at the device size
  and divides by the scale.

The web backend, the console backend, the PDF export and the live layouts do not
read the display scale. A live layout measures with `measure_truetype_text`,
which reads only the font zoom.

This shape gives three faults:

- Two editors in one process share one scale and one zoom. Ctrl+= in one editor
  changes the render scale of the windows of every editor, but only the editor
  that got the key lays its windows out again.
- `write_image` writes the export scale into `_DISPLAY_SCALE` for the time of the
  render. An editor that renders on another thread during that time renders at
  the export scale.
- `configure_devices!` copies `_DISPLAY_SCALE`, which holds the zoom. So the
  `Display` of a second editor gets the zoom of the first editor as its hardware
  scale.

### The design (proposed)

- **The `Display` holds two values.** `scale` is the number of device pixels for
  each logical pixel of the hardware. `zoom` is the uniform zoom of the editor,
  `1.0` by default. `get_device_pixel_ratio(display)` gives their product. The
  term is the one that browsers use for the same product. [D1]
- **The SDL backend holds a `Display`.** The constructor `SdlBackend()` gives
  the backend its own `Display()`. `configure_devices!(backend, devices)` fills
  the first `Display` in `devices` from the probe, and the backend then uses that
  `Display`. So the editor, the backend and the zoom operation all use the same
  object. The backend interface does not change. The calls in omnet-julia stay
  valid. [D2]
- **The probe stays a cache of the process.** The probe finds a fact about the
  machine, not about an editor. The probe runs `xrdb` one time, and it has two
  latches. It moves from the style package into `Sdl.jl`, as
  `_PROBED_DISPLAY_SCALE`. Three places read it: `configure_devices!`,
  `get_sdl_display_size` (which runs before an editor exists), and the probe at
  the first window open. When that last probe finds the scale, it also writes
  the scale into the `Display` of the backend.
- **Each SDL conversion takes the ratio as an argument.** The functions become
  `_to_device(px, ratio)`, `_to_logical(px, ratio)` and
  `font_device_size(font, ratio)`. The render passes `ratio` down from
  `_render_window!` to `_get_font`: about 10 functions and 25 calls in `Sdl.jl`.
  The offscreen render passes its export scale, so it does not change a global
  value. [D3]
- **The measure.** `measure_text(backend::SdlBackend, …)` measures at the ratio
  of the `Display` of the backend. `measure_sdl_text` measures at the ratio
  `1.0`. `write_image` and the tools use this standalone function. So an exported
  image does not depend on the display of the machine that makes it. [D5]
- **The zoom.** `evaluate_operation(editor, ::AdjustZoomOperation)` steps the
  `zoom` of the `Display` of the SDL backend, and lays the windows out again with
  the ratio of the old value to the new value. These names go:
  `adjust_user_zoom!`, `_USER_ZOOM`, `_DISPLAY_SCALE`,
  `recompute_display_scale!`, and `font_scaled_size`, which has no caller. Both
  zooms use `_stepped_zoom`, so it becomes the public `step_zoom(current, delta)`
  in `StyleModule`.
- **Web and console do not change.** Their `configure_devices!` is the default,
  which does nothing, and their `Display` keeps its defaults.

### Decisions (confirmed by the owner on 2026-09-25)

For each decision, the first option is the one that the owner confirmed.

- **D1, where the zoom is.**
  - On the `Display`. The zoom then goes with the editor, and any backend can
    read it.
  - On the `SdlBackend`.
  - On the `Editor`. The kernel editor then holds a value that only SDL reads.
- **D2, how SDL gets the `Display`.**
  - SDL keeps the `Display` that `configure_devices!` gives it.
  - SDL finds the `Display` in `devices` at each call. `open_native_windows!(backend,
    document)` gets no `devices`, so this option needs a change to the sealed
    backend interface.
- **D3, how the render gets the ratio.**
  - As an argument.
  - As a scoped value that the render binds. The performance counters use a
    scoped value. This option changes fewer lines, but the value is not visible
    in the signatures.
- **D4, the font zoom.**
  - A separate plan.
  - Part of this plan.
- **D5, the ratio of the standalone measure.**
  - `1.0`.
  - The ratio of the probe. This is the behaviour now, when the zoom is `1.0`.

### The size

| File | Change | Lines, about |
| --- | --- | --- |
| `source/kernel/device/Display.jl` 🔒 | `zoom`, `get_device_pixel_ratio`, the docstring | 20 |
| `source/style/Font.jl` | remove the block of display-scale values, `font_device_size(font, ratio)`, `step_zoom` | −40, +10 |
| `source/style/StyleModule.jl` | the exports | 3 |
| `source/sdl/Sdl.jl` | the probe moves here, the `display` field, about 50 uses, about 10 render functions, the offscreen render, the zoom operation, the docstrings | 120 |
| `package/ProjecturedSdl/src/ProjecturedSdl.jl` | the imports | 3 |
| tests | `InputCoalescingTest.jl`, `DeviceConfigTest.jl`, a new test with two backends | 80 |
| guides | `style.md`, `sdl.md`, `devices-and-backends.md` | 20 |

That is about 300 lines in 10 files, in three packages: the kernel, style and
SDL. No sealed file outside the device layer changes. omnet-julia and inet-julia
do not change.

The risk is the SDL render. The check below compares exported images, and it
opens a live window. The display of this machine has `Xft.dpi` 192, so the probe
finds the scale 2.

## Not in this plan

- **The font zoom, `_FONT_ZOOM`, has the same fault.** Layout reads it
  in 15 places, in 7 files of 6 packages: graphics, text, style, PDF, web and
  SDL. It is a reactive cell. So a value for each editor needs a path into the
  layout, for example `PrinterContext`, which holds the clock. That is a design
  of its own. [D4]
- **Other process-global state in `Sdl.jl`:** `_LAST_HOVER_MOTION`,
  `_PARTIAL_RENDER` and `_DEBUG_DIRTY` (which `initialize_backend!` copies from
  the backend), and `_font_backend`. The caches of fonts and text textures are
  keyed by content, so they stay.
- **The `devices` argument of `read_from_devices`, `write_to_devices` and
  `wait_for_input`.** With D2 as recommended, no code reads it.
- `plan/pending/naming-rule-violations.md` item 29 counts `_DISPLAY_SCALE` and
  `_USER_ZOOM` among the exported names with an underscore. After this plan, the
  count goes down by two.

## Steps

Each step is a commit in a worktree.

0. [x] **The baseline on main.** Done at `25694efb`.
   - `/var/tmp/device-audit/baseline.jl` writes 10 examples with `write_image`,
     at scale 1 and at scale 2, in one process. It writes them one time before
     the probe runs and one time after. The examples have text, viewports,
     images, charts and widgets. It also records `measure_sdl_text` of four
     texts.
   - The images after the probe are the same as the images before it. The
     measures change after the probe, for example from `(150, 23)` to
     `(147, 22)` for `"iiiiiiiiii WWWWW"`, because the probe sets the global
     scale to 2.
   - The counts: `test_kernel()` 2301 pass, 3 fail and 3 error (the 6 known
     failures), `test_sdl()` 117 pass, `test_video()` 34 pass.
1. [x] **The device layer.**
   - Items 2, 3 and 5.
   - The `zoom` field and `get_device_pixel_ratio`.
   - Item 6: `test/kernel/device/DeviceModuleTest.jl` takes the device tests from
     `HeadlessBackendTest.jl`, and adds tests for `zoom` and the ratio. Its
     function is `test_device_module`, as `test_event_module` is for the event
     layer.
2. [x] **SDL uses the ratio of its `Display`, and the zoom is on the
   `Display`.** Steps 2 and 3 of the first version of this plan are one commit.
   When SDL stops reading the global scale, the zoom must move to the `Display`
   at the same time. Otherwise Ctrl+= does nothing in the commit between.
   - The probe moves into `Sdl.jl` as `_PROBED_DISPLAY_SCALE`.
     `_update_display_scale!` answers whether it found the scale. When it does,
     `_open_native_window!` writes the scale into the `Display` of the backend.
   - `SdlBackend` gets a `display` field. The constructor gives it a
     `Display()`. `initialize_backend!` writes the probed scale into it.
     `configure_devices!` fills the first `Display` in `devices` and puts it in
     the field. A list with no `Display` leaves the field as it is.
   - `SdlWindowResources` gets a `ratio` field: the ratio last applied to the
     window, as `width` and `height` are the size last applied. The functions
     that get the window record read it: the SSAA target, the window render,
     the size of the native window and the dirty-rectangle walk.
     `write_to_devices` gives the ratio of the `Display` to
     `_update_window_geometry!`, which resizes the native window when the ratio
     changes.
   - The render chain below the window record takes the ratio as an argument:
     `_render_canvas!`, `_dispatch_render_elem!`, `_render_viewport!`, the
     `_render_element!` of a text, `_get_font`, `_font_runs` and `_glyph_font`.
     `_render_elements!` had no caller, and it is removed.
   - The input reads the ratio of the `Display` of the backend.
   - The dirty-rectangle walk measures a text at the ratio of the window, not
     at the ratio 1 of `measure_sdl_text`. At the scale 2 the two measures
     differ by up to 3 pixels, and a bound that is too narrow leaves old pixels
     on the screen.
   - `_font_backend`, the global backend that `measure_sdl_text` used, is
     removed.
   - `evaluate_operation(editor, ::AdjustZoomOperation)` does nothing for a
     backend that is not an `SdlBackend`. Before, it changed the global scale
     and the window sizes of any editor.
   - The style package loses `_DISPLAY_SCALE`, `_BASE_DISPLAY_SCALE`,
     `_USER_ZOOM`, `recompute_display_scale!`, `adjust_user_zoom!` and
     `font_scaled_size`. `_stepped_zoom` becomes `step_zoom`.
3. [x] **Tests.** In `test/sdl/backend/DeviceConfigTest.jl`:
   - `configure_devices!` puts the scale of the hardware in `scale`, leaves
     `zoom` as it is, and makes the backend draw with that `Display`. A second
     `Display` gets the scale and not the zoom of the first.
   - Two backends with `Display(scale = 1.0)` and `Display(scale = 2.0)` each
     measure at their own ratio. `measure_sdl_text` measures at the ratio 1.
   - A zoom on one backend leaves the other.
   - `step_zoom` walks the table.
   - `write_image` at scale 2 leaves the ratio of a backend as it is.
   - `InputCoalescingTest.jl` gives its backend a `Display` with the scale 2,
     so it also tests the conversion of the input.
4. [x] **Guides.**
   - Item 7. `naming-rules.md` also names `DeviceInterface.jl` among the
     contract files with a prefix.
   - `style.md` and `sdl.md` on the scale.
   - The devices section of `devices-and-backends.md`, with a section on the
     device pixel ratio.
   - Three comments that named `_DISPLAY_SCALE`: `TrueType.jl`,
     `WidgetToGraphics.jl` and `WidgetDocumentExample.jl`.
5. [x] **The check.**
   - [x] The exported images are the same as on main, byte for byte: 10
     examples, at scale 1 and at scale 2, before and after the probe, 40 images.
     `measure_sdl_text` gives the same values before and after the probe, which
     are the values of main before the probe.
   - [x] The suite counts are the baseline plus the new tests, with the same 11
     known failures at the same lines:
     - `test_kernel()`: 2311 pass (+10, the device test), 3 fail, 3 error.
     - `test_sdl()`: 138 pass (+21).
     - `test_video()`: 34 pass.
     - `test_substrate()`: 80850 pass, 3 fail, 2 error, 1 broken.
   - [x] The naming guard passes. The export guard shows only the two known
     violations of `HelpModule.jl`. The argument guard shows the same two
     violations as main: `start_application!` and `Tool`. The layering guard of
     the kernel runs inside `test_kernel()`, and passes.
   - [x] `test_sdl()` does not call `test_sdl_layering()`, so it runs on its own:
     7 pass.
   - [x] omnet-julia precompiles in a scratch environment whose projectured
     paths point at the worktree. `OmnetRepl` warns that 8711 of its 16008
     recorded precompile statements are stale. The list is 10 days old, and only
     24 of its statements name code that this branch changes, so the list was
     stale before.
   - [x] Live windows at the probed scale 2 are the same as on main.
     `/var/tmp/device-audit/live.jl` opens four examples in real SDL windows,
     runs frames, zooms in with `AdjustZoomOperation(1)` and resets with
     `AdjustZoomOperation(0)`. After each of the three, it records the logical
     size, the native size and the size of the render target of each window,
     and a hash of the pixels of the render target. The records on main and on
     the branch are the same. The check uses the operation, not a key press;
     the key path that makes the operation does not change.
   - [x] No open branch of another session adds a use of a changed name.
     `feature-videos` and `videos-on-main` have 11 conflicts with main already,
     and the branch adds none.
   - [x] Then report the result, seal the five device files with the approval of
     the owner, and land. The owner approved the seal and the landing on
     2026-09-25.
