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

0. [ ] **The baseline on main.**
   - Write a fixed set of canvases with `write_image`, at scale 1 and at scale 2.
     Include text, a viewport and an image.
   - Record the counts of `test_sdl()`, `test_substrate()` and the kernel tests of
     the backend and the device.
1. [ ] **The device layer.**
   - Items 2, 3 and 5.
   - The `zoom` field and `get_device_pixel_ratio`.
   - Item 6: `DeviceTest.jl` takes the device tests from `HeadlessBackendTest.jl`,
     and adds tests for `zoom` and the ratio.
2. [ ] **SDL uses the ratio of its `Display`.**
   - The probe moves into `Sdl.jl`.
   - The backend gets its `display` field, and `configure_devices!` sets it.
   - The conversions and the render chain take the ratio.
   - The offscreen render passes its scale, and the swap goes.
   - The measure changes as the design says.
3. [ ] **The zoom is on the `Display`.**
   - The zoom operation uses the `Display`.
   - Add `step_zoom`.
   - The display-scale values go from the style package.
4. [ ] **Tests.**
   - Two backends with `Display(scale = 1.0)` and `Display(scale = 2.0)`
     convert and measure each at its own ratio.
   - A zoom on one backend leaves the other at its ratio.
   - `write_image` at scale 2 leaves the ratio of a backend as it is.
   - `configure_devices!` puts the hardware scale in `scale` and leaves `zoom`
     as it is.
5. [ ] **Guides.**
   - Item 7.
   - `style.md` and `sdl.md` on the scale.
   - The devices section of `devices-and-backends.md`.
6. [ ] **The check.**
   - The exported images of step 0 must be the same, byte for byte, at scale 1
     and at scale 2.
   - The suite counts must be the same as the baseline, plus the new tests.
   - The naming guard, the export guard and the layering guard must pass.
   - omnet-julia must precompile in a scratch environment.
   - A live window at the probed scale 2 must look as it does on main, and
     Ctrl+= and Ctrl+- must zoom it.
   - Then report the result, seal the five device files with the approval of the
     owner, and land.
