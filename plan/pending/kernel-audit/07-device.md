# Layer 07 — device (`source/kernel/device/`)

Commit 15b40434, 2026-09-27. Seal state: all sealed (5 of 5).

## Verdict

The device layer is five short files with no imports, no global state and one
function, and it matches its audit of 2026-09-25: each editor has its own
`Display`, and the SDL backend draws with its ratio. Two design faults remain.
The zoom of a `Display` changes only through a method that the SDL package adds
to `evaluate_operation` for a kernel operation, so no other backend can take part.
And `Display.width` and `Display.height` have a writer and no reader, while the
code that needs the size asks `get_display_size(backend)`. A `Display` also
accepts a scale or a zoom of zero, which makes the SDL input throw. The
`Display` docstring states a contract that only SDL keeps.

## Shape

- Purpose: the physical properties of the hardware of one editor: the size, the
  scale and the zoom of the display, the layout of the keyboard, the buttons and
  the wheel of the mouse. A device has no behaviour; a backend fills it.
- Files:

  | file | lines | seal | what it holds |
  | --- | ---: | --- | --- |
  | `DeviceModule.jl` | 30 | 🔒 | the docstring, the exports, four includes |
  | `DeviceInterface.jl` | 10 | 🔒 | the abstract `Device` |
  | `Keyboard.jl` | 13 | 🔒 | `Keyboard` (`layout`) |
  | `Mouse.jl` | 16 | 🔒 | `Mouse` (`button_count`, `has_scroll_wheel`) |
  | `Display.jl` | 32 | 🔒 | `Display` (`width`, `height`, `scale`, `zoom`), `get_device_pixel_ratio` |

- Imports: none. Imported by: the `editor/` and `playback/` layers of the kernel;
  `ProjecturedSdl`; `ProjecturedFaultTest`; omnet-julia
  (`CampaignPrecompile.jl` builds `Device[Display(), Keyboard(), Mouse()]`).
- Public surface: 5 exported names: `Device`, `Keyboard`, `Mouse`, `Display`,
  `get_device_pixel_ratio`. All five have users outside the kernel. The fields
  have fewer: `Display.scale` and `Display.zoom` are read by the SDL backend
  only; `Display.width`, `Display.height`, `Keyboard.layout`,
  `Mouse.button_count` and `Mouse.has_scroll_wheel` are read by no code.
- State: each device is a mutable struct. `make_editor` makes a new
  `Device[Display(), Keyboard(), Mouse()]` on each call, and
  `configure_devices!(::SdlBackend, …)` makes the backend draw with the
  `Display` of that list. No state is global.
- Tests: `test/kernel/device/DeviceModuleTest.jl` (55 lines, 16 passes in the
  baseline log): the defaults, the keyword constructors, the ratio with
  `@inferred`. `test/backend/sdl/backend/DeviceConfigTest.jl` tests the SDL half (two
  backends with their own ratio; a zoom of one leaves the other).

## Summary

| category | High | Medium | Low |
| --- | ---: | ---: | ---: |
| Correctness | 0 | 0 | 1 |
| Architecture | 0 | 1 | 0 |
| Shape | 0 | 1 | 0 |
| Documentation | 0 | 0 | 1 |
| Tests | 0 | 0 | 1 |

## Findings

### L07-1 Only a method of the SDL package steps the zoom of a `Display`

- Category: Architecture · Severity: Medium · Confidence: Confirmed
- Decided before: `plan/done/device-layer-audit.md` put this method in `Sdl.jl` and left the web and console backends as they were. This finding asks the owner to reopen that decision, because the owner wants many editors on the web backend.
- Where: [Display.jl:19](../../../source/kernel/device/Display.jl#L19) 🔒,
  [Sdl.jl:3926](../../../source/backend/sdl/SdlBackend.jl#L3926)
- Evidence: the kernel editor turns Ctrl+= into `AdjustZoomOperation`
  (`source/kernel/editor/ReadEvaluatePrint.jl:136`), a kernel type. The one
  method that evaluates it is in `Sdl.jl`:
  `function evaluate_operation(editor, op::AdjustZoomOperation)` with
  `editor.backend isa SdlBackend || return nothing`. The package extends a kernel
  function for a kernel type (type piracy). For the web, console and video
  backends, Ctrl+= does nothing, and none of them can add a method of its own
  without the overwrite of the SDL method. The zoom is a field of the device
  since the device audit, so the step of the zoom is not a matter of one backend.
  `AdjustFontZoomOperation` has the same shape (`Sdl.jl:3936`).
- Rule: PAR-FRAMEWORKS-SINK (the lower layer owns the generic, a higher package
  adds a method for its own type); PAR-BACKEND-SEAM ("the same editor runs
  unchanged across them").
- Fix: the kernel evaluates `AdjustZoomOperation` on the `Display` in
  `editor.devices`, and calls a backend generic (with a no-op default) for the
  work of a backend after a change of ratio, which SDL answers with its
  `_reflow_for_scale!` and its full repaint.
- Reach: `Sdl.jl`; an unsealed kernel file of the `editor/` or `operation/`
  layer; `BackendInterface.jl`, `BackendDefaults.jl`, `BackendModule.jl`
  (sealed) for the new generic. Planned in part:
  plan/pending/font-zoom-per-editor.md (the evaluation of
  `AdjustFontZoomOperation` by the kernel editor, option A).

### L07-2 `Display.width` and `Display.height` have a writer and no reader

- Category: Shape · Severity: Medium · Confidence: Confirmed
- Where: [Display.jl:16](../../../source/kernel/device/Display.jl#L16) 🔒
- Evidence: `configure_devices!(::SdlBackend, …)` writes
  `display.width, display.height = get_sdl_display_size()`
  ([Sdl.jl:4015](../../../source/backend/sdl/SdlBackend.jl#L4015)). No code reads the two
  fields. The code that needs the size of the display asks the backend:
  `get_display_size(backend)` in `source/platform/screen/WindowScene.jl:139` (before
  `make_editor`, so before any `Display` is configured), in the SDL window
  placement (`Sdl.jl:3766`), and in `example/projectured/ValueViewer.jl:88`,
  `FileEditor.jl:168` and `Gallery.jl:225`. So one fact has two sources, and
  the default is written
  three times: `Display()` gives `(1280, 800)`, `BackendDefaults.jl:17` gives
  `(1280, 800)`, and `get_sdl_display_size` falls back to `(1280, 720)`. The
  device audit found "no code reads what the devices hold"; its fix covered the
  scale and the zoom, not the size.
- Rule: design fault (one fact with two sources); PAR-BACKEND-SEAM (the device
  holds the physical properties that `configure_devices!` finds).
- Fix: remove the two fields and their write in `configure_devices!`. The size
  is needed before an editor exists, so the backend query is the one source.
  Keep one default value.
- Reach: `Display.jl` (sealed), `BackendDefaults.jl` (sealed) for the one
  default, `Sdl.jl`, `DeviceModuleTest.jl`, `HeadlessBackendTest.jl`,
  omnet-julia `CampaignPrecompile.jl` (it builds a `Display()` and needs no
  change).

### L07-3 A `Display` accepts a scale or a zoom of zero, and SDL input then throws

- Category: Correctness · Severity: Low · Confidence: Confirmed
- Where: [Display.jl:22](../../../source/kernel/device/Display.jl#L22) 🔒,
  [Display.jl:32](../../../source/kernel/device/Display.jl#L32) 🔒
- Evidence: the constructor converts `scale` and `zoom` to `Float64` and checks
  nothing, and the fields are mutable. With a ratio of `0.0`, the SDL input
  computes `_to_logical(px, ratio) = round(Int, px / ratio)`, which is
  `round(Int, Inf)`: an `InexactError` in `_poll_window_input` for each mouse
  event. A negative or `NaN` value gives wrong or failed conversions in the same
  place. `step_zoom` keeps the zoom inside its table and the SDL probe rejects a
  scale `<= 0`, so only a direct construction or a direct write reaches the
  fault.
- Rule: bug (an invariant of the device that no code states or checks).
- Fix: an inner constructor that requires `scale > 0` and `zoom > 0`, and a
  sentence in the docstring.
- Reach: `Display.jl` (sealed), `DeviceModuleTest.jl`.

### L07-4 The `Display` docstring states a contract that only SDL keeps

- Category: Documentation · Severity: Low · Confidence: Confirmed
- Where: [Display.jl:11](../../../source/kernel/device/Display.jl#L11) 🔒,
  `package/ProjecturedKernel/src/ProjecturedKernel.jl:34` 🔒
- Evidence:
  - "A backend draws each logical pixel as `get_device_pixel_ratio(display)`
    device pixels." The web backend uses the `devicePixelRatio` of the browser,
    the video backend its own field `scale` (`VideoBackend.jl`), and the console
    has no pixels. None of them reads the `Display`, and Ctrl+= changes nothing
    in them (L07-1). devices-and-backends.md:47-48 states the limit correctly.
  - The layer diagram in the sealed package root says "layer 7 — the devices
    events come from". The events come from the backend, not from a device
    (devices-and-backends.md:36 says so).
- Rule: PAR-HONEST-DOCS.
- Fix: "The SDL backend draws …", or keep the general sentence and add the
  limits; "layer 7 — the devices and their physical properties".
- Reach: `Display.jl`, `ProjecturedKernel.jl` (both sealed).

### L07-5 The tests do not check the limits of a `Display`, and one test checks only that a struct is mutable

- Category: Tests · Severity: Low · Confidence: Confirmed
- Where: `test/kernel/device/DeviceModuleTest.jl:38`
- Evidence: no test gives a scale or a zoom of zero or less (L07-3). The test
  "a backend writes the properties in place" writes `display.scale` and
  `display.width` itself and reads them back, so it asserts the mutability of the
  struct and no behaviour of a backend; `DeviceConfigTest.jl` in the SDL suite
  holds the real test.
- Rule: PAR-NEW-CODE-SHIPS-TESTS.
- Fix: a test of the rejected values after L07-3; rename the in-place test to
  "each device is mutable".
- Reach: `DeviceModuleTest.jl`.

## Accepted before, not raised again

- `Keyboard` and `Mouse` stay mutable although no code writes or reads their
  fields (plan/done/device-layer-audit.md, item 4).
- The scale that the SDL probe finds is one value for the process
  (`_PROBED_DISPLAY_SCALE`), because it is a fact of the machine, and
  `configure_devices!` copies it into each `Display` (device audit, the design
  and D1 to D5).
- The font zoom `_FONT_ZOOM` is one value for the process (deferred:
  plan/pending/font-zoom-per-editor.md).
- One `scale` for each editor, not one for each monitor (the device audit
  removed the promise of support for several monitors).

## Checked and clean

- PAR-INTERFACE-DECLARES-ONLY: `DeviceInterface.jl` holds one abstract type, and
  the kernel guard checks it.
- The layer imports nothing (PAR-PACKAGE-CHAIN, the layering guard) and names no
  document, operation or backend type.
- PAR-PER-EDITOR-STATE: no global state; each editor gets new devices from the
  default of `make_editor`; the SDL backend draws with the `Display` of its
  editor (DeviceConfigTest.jl checks that a zoom of one backend leaves the other).
- The export block: one statement for each fragment, in include order
  (`DeviceModule` left `EXPORT_UNMIGRATED` on 2026-09-25).
- PAR-MODULE-DOCSTRING, the fragment headers, the naming rules
  (`get_device_pixel_ratio` reads a value with a trivial computation), keyword
  constructors with the defaults of common hardware; no history comment; no line
  over 90 characters.
- `get_device_pixel_ratio` is type-stable (`@inferred` in the test).
