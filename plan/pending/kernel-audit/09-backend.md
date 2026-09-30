# Layer 09 — backend (`source/kernel/backend/`)

Commit 15b40434, 2026-09-27. Seal state: all sealed (3 of 3).

## Verdict

The kernel half of the seam is clean: three short files, no imports, no state,
an interface file with bodiless generics, and legal defaults for the
capabilities that a backend can lack. The faults are in how the five backends
answer the seam, and they reach users. The backends keep separate key tables, so
Ctrl+Z, Ctrl+Y, Ctrl+Shift+D and Ctrl+F never fire in the SDL application, and
Ctrl+S, Ctrl+O, Ctrl+Shift+P, Ctrl+T and Ctrl+W never fire in the browser
(L09-1). A side button of the mouse makes a right click on SDL and a left click
in the browser (L09-2). The four output generics (`write_image`, `record_video`,
`render_canvas`, `decode_image`) dispatch on no type that their implementer
owns, so only one package can ever answer each, and the one answer of
`render_canvas` is a stub. The video backend shows one window of many, the
console backend turns Home into a chord of its reader, and the documents
describe the seam as it was before the wait, the wake and the removal of the
text measure.

## Shape

- Purpose: the seam between the editor and a platform: the life of a backend,
  one input event at a time, the output of each frame, the wait between frames,
  a few queries (display size, pointer), and the output to a file (image,
  video, a raster of a canvas, an image decoder).
- Files:

  | file | lines | seal | what it holds |
  | --- | ---: | --- | --- |
  | `BackendModule.jl` | 34 | 🔒 | the docstring, one export statement of 15 names, two includes |
  | `BackendInterface.jl` | 148 | 🔒 | `Backend` and 14 bodiless generics |
  | `BackendDefaults.jl` | 21 | 🔒 | six default methods |

- Imports: none. Imported by: the `editor/` and `playback/` layers of the kernel;
  `ProjecturedSdl`, `ProjecturedWeb`, `ProjecturedConsole`, `ProjecturedVideo`,
  `ProjecturedScreen`, `ProjecturedKernelExample`; the book, markdown and rst
  domains (`decode_image`); omnet-julia (`get_pointer_position`,
  `decode_image`, the start sequence in `CampaignPrecompile.jl`).
- Public surface: 15 exported names. Every name has a user outside the kernel
  except `render_canvas`, whose one caller passes it to `GraphicsCaching`, which
  ignores it (L09-8).
- The seam, generic by generic (✓ = a method of its own; "default" = the method
  of `BackendDefaults.jl`; — = no method, so a `MethodError`):

  | generic | default | SDL | web | console | video | headless (example) |
  | --- | --- | --- | --- | --- | --- | --- |
  | `initialize_backend!` | — | ✓ | ✓ | ✓ raw mode | ✓ | ✓ no-op |
  | `quit_backend!` | — | ✓ stops SDL | ✓ | ✓ | ✓ | ✓ no-op |
  | `read_from_devices` | — | ✓ coalesced | ✓ | ✓ | ✓ timeline | ✓ queue |
  | `write_to_devices` | — | `ScreenDocument` only | `ScreenDocument`, error else | `TextBlock`, error else | `ScreenDocument`, one window | any value |
  | `wait_for_input` | sleep ≤ 10 ms | ✓ | ✓ | ✓ | ✓ ≤ 1/fps | default |
  | `wake_backend!` | no-op | ✓ | ✓ | ✓ | default | default |
  | `open_native_windows!` | no-op | ✓ | default | default | default | default |
  | `configure_devices!` | no-op | ✓ keeps the `Display` | default | default | default | default |
  | `get_display_size` | `(1280, 800)` | ✓ logical | default | default | ✓ video size | default |
  | `get_pointer_position` | `(-1, -1)` | ✓ screen | default | default | ✓ last pointer | default |
  | `write_image` | — | ✓ | — | — | — | — |
  | `record_video` | — | — | — | — | ✓ (untyped) | — |
  | `render_canvas` | — | stub | — | — | — | — |
  | `decode_image` | — | ✓ `::AbstractString` | — | — | — | — |

- State: none in the layer. The web and console backends keep all state on the
  instance. The SDL backend shares the SDL session, the font cache and the
  texture cache between its instances (deferred, see below).
- Tests: `test/kernel/backend/HeadlessBackendTest.jl` (58 lines, 13 passes)
  tests the example double and, through it, two defaults (`get_display_size`,
  `configure_devices!`). `test/kernel/editor/WaitTest.jl` tests the default
  wait and wake. The backends have their own suites:
  `test/sdl/backend/` (9 files), `test/projectured/backend/WebTest.jl` and
  `ConsoleBackendTest.jl`, and the video suite. The gaps are in L09-18.

## Summary

| category | High | Medium | Low |
| --- | ---: | ---: | ---: |
| Correctness | 2 | 0 | 2 |
| Architecture | 0 | 5 | 0 |
| Shape | 0 | 1 | 4 |
| Naming | 0 | 0 | 1 |
| Documentation | 0 | 0 | 2 |
| Tests | 0 | 0 | 1 |

## Findings

### L09-1 The backends name different letter keys, so letter shortcuts fail on SDL, on the web and in the console

- Category: Correctness · Severity: High · Confidence: Confirmed
- Checked by the lead on 2026-09-27: Read the code: `sdl_keysym_to_symbol` has no `:z`, and the undo binding is `KeyDownPattern(:z; modifiers = [:ctrl])` at `UndoBufferToAny.jl:94`.
- Where: [Sdl.jl:324](../../../source/sdl/Sdl.jl#L324),
  [Sdl.jl:390](../../../source/sdl/Sdl.jl#L390),
  [Web.jl:139](../../../source/web/Web.jl#L139),
  [Console.jl:341](../../../source/console/Console.jl#L341)
- Evidence: a `KeyDown` of a letter has the name of the letter only when the
  backend lists it; any other letter becomes `:char`.
  - SDL (`sdl_keysym_to_symbol`) names `t w c x v n p s o`, and ends in
    `return :char`. `KeysymTest.jl:27` asserts `'q'` → `:char`.
  - The web backend (`convert_web_key_to_symbol`) names `c x v n` only.
  - The console makes a `KeyPress` for a printable byte. Of the Ctrl bytes
    0x01–0x1A it reads Ctrl+C as a quit and 0x08, 0x09, 0x0A and 0x0D as
    Backspace, Tab and Return, and drops the rest
    (`return nothing # other C0 control byte`).
  - Rules of gesture tables bind other letters: Ctrl+Z, Ctrl+Y and Ctrl+Shift+Z (undo and
    redo, `source/undo/UndoBufferToAny.jl:94-99`, installed by the application),
    Ctrl+Shift+D (duplicate a tab, `source/pane/PaneGestures.jl:155`), Ctrl+F
    (`source/widget/ProjectionConfiguring.jl:138`). None of them can fire on
    SDL. On the web, Ctrl+S, Ctrl+O (`DocumentFile.jl:219-220`), Ctrl+Shift+P
    (the command palette), Ctrl+T, Ctrl+W and Ctrl+\\ fail too.
  - The tests of these rules make `KeyDown(:z, …)` directly
    (`test/undo/UndoBufferTest.jl`), so they pass while the key fails.
  PAR-BACKEND-SEAM says "A single source of truth governs any cross-backend
  mapping (e.g. `convert_web_key_to_symbol` mirrors `sdl_keysym_to_symbol`)",
  and devices-and-backends.md:250-252 says the same. The two tables do not
  mirror each other.
- Rule: PAR-BACKEND-SEAM.
- Fix: one rule in the event layer that names every letter and digit (L06-1);
  SDL names each printable keysym by its character, the web backend by the
  lower case of `key`, the console by the Ctrl byte (0x01 is Ctrl+A). Add a test
  that sends the same key through each backend.
- Reach: `Sdl.jl`, `Web.jl`, `Console.jl`, `KeyboardEvent.jl` (sealed, for the
  rule), `KeysymTest.jl`, `WebTest.jl`, `ConsoleBackendTest.jl`.

### L09-2 A side button of the mouse makes a right click on SDL and a left click in the browser

- Category: Correctness · Severity: High · Confidence: Confirmed
- Checked by the lead on 2026-09-27: Read the code: `_sdl_button_sym` at `Sdl.jl:451` gives `:right` for every button other than 1 and 2.
- Where: [Sdl.jl:451](../../../source/sdl/Sdl.jl#L451), `asset/web/client.js:585`
- Evidence: SDL: `_sdl_button_sym(b::UInt8) = b == 0x01 ? :left : b == 0x02 ?
  :middle : :right`, so the buttons X1 and X2 (4 and 5, the "back" and "forward"
  buttons) become `:right`, and a right click opens the context menu
  (`source/widget/ContextMenuProbe.jl:60`). The web page: `buttonSym(b) {
  return b === 1 ? "middle" : b === 2 ? "right" : "left"; }`, so the buttons 3
  and 4 become `"left"`, which selects and activates. The event layer names three
  buttons (`MouseDown`: "`button` is `:left`, `:middle` or `:right`") and says
  nothing about another button.
- Rule: PAR-BACKEND-SEAM (each backend converts to the same vocabulary); bug.
- Fix: a backend drops a button that the vocabulary does not name, or the event
  layer names `:x1` and `:x2`. State the rule in the `MouseDown` docstring.
- Reach: `Sdl.jl`, `client.js`, `MouseEvent.jl` (sealed, the docstring).

### L09-3 The output generics dispatch on no type that their implementer owns

- Category: Architecture · Severity: Medium · Confidence: Confirmed
- Where: [BackendInterface.jl:117](../../../source/kernel/backend/BackendInterface.jl#L117) 🔒,
  [Sdl.jl:2905](../../../source/sdl/Sdl.jl#L2905),
  [Sdl.jl:4000](../../../source/sdl/Sdl.jl#L4000),
  `source/video/Video.jl:69`
- Evidence: SDL adds `write_image(::GraphicsCanvas, ::AbstractString; …)`,
  `write_image(document, projection, ::AbstractString; …)`,
  `render_canvas(::GraphicsCanvas)` and `decode_image(::AbstractString)`.
  ProjecturedVideo adds `record_video(document, projection; …)` with no types.
  `GraphicsCanvas` belongs to ProjecturedGraphics and `AbstractString` to Base,
  so each method is type piracy, and a second implementer overwrites the first.
  plan/pending/cairo-glfw-backend.md:259 plans exactly that ("Offscreen Cairo
  could also back `render_canvas`/`write_image`"). PAR-OPT-IN-DEPENDENCY says a
  seam is "either a symbol-keyed `Val` factory (… the `record_video` seam) or a
  subtype-dispatched generic"; these four are neither. A caller also cannot ask
  whether a decoder is loaded, so each caller catches every exception:
  `try decode_image(path) catch; nothing end` in `MarkdownToSyntax.jl:442`,
  `BookToSyntax.jl:563` and `RstToSyntax.jl:1138`, which hides a decoder
  that is not loaded and a broken file in the same way.
- Rule: PAR-OPT-IN-DEPENDENCY.
- Fix: dispatch each generic on a renderer or decoder value that the package
  owns (`write_image(::SdlRaster, …)`), or on a `Val` key, with a default that
  names the package to load.
- Reach: `BackendInterface.jl`, `BackendDefaults.jl`, `BackendModule.jl`
  (sealed); `Sdl.jl`; `Video.jl`; three domain call sites; omnet-julia
  `ModuleAppearanceToGraphics.jl` (`decode_image`); 15 files of omnet-julia and
  inet-julia that name `write_image`.

### L09-4 The video backend shows one window of the `ScreenDocument`

- Category: Architecture · Severity: Medium · Confidence: Confirmed
- Where: `source/video/VideoBackend.jl:325`, `source/video/VideoBackend.jl:381`
- Evidence: `write_to_devices(::VideoBackend, …)` renders the window that
  `_select_window` finds: the one named `backend.window_id`, or else the first.
  Every other window of the list (a tooltip, a popup, a dialog of its own) never
  reaches a frame, so a take of a session with a tooltip shows no tooltip. The
  docstring says which window it renders, but not that it drops the others.
- Rule: PAR-MANY-WINDOWS ("Every backend must open all of them … or saying
  plainly that it cannot").
- Fix: compose every window at its `x` and `y` onto the frame (the frame is the
  screen), or state the limit where PAR-MANY-WINDOWS allows it.
- Reach: `VideoBackend.jl`, the video suite.

### L09-5 The console backend turns Home into the chord of a reader

- Category: Architecture · Severity: Medium · Confidence: Confirmed
- Where: [Console.jl:440](../../../source/console/Console.jl#L440),
  [Console.jl:455](../../../source/console/Console.jl#L455)
- Evidence: "The terminal Home key maps to the reader's 'select the root node'
  chord (Ctrl+Alt+Home)": `_make_key_event` answers
  `KeyDown(:home, ModifierKeys(ctrl=true, alt=true); …)` for a plain Home. The
  backend chooses what a key means for one reader, and a reader that binds a
  plain Home never sees it in the console. The contract says: "a device reports
  only what happened, never a gesture derived from several events"
  (`read_from_devices`), and the editor loop treats Escape the same way for the
  same reason (devices-and-backends.md:77-80).
- Rule: PAR-BACKEND-SEAM ("Convert platform events to the backend-agnostic
  device vocabulary").
- Fix: the console sends `KeyDown(:home)`, and the console pipeline binds a plain
  Home to the selection of the root.
- Reach: `Console.jl`, the reader of the console pipeline, `ConsoleBackendTest.jl`.

### L09-6 `get_display_size` takes a 0-based display index under the name `display`

- Category: Architecture · Severity: Medium · Confidence: Confirmed
- Where: [BackendInterface.jl:100](../../../source/kernel/backend/BackendInterface.jl#L100) 🔒,
  [BackendDefaults.jl:17](../../../source/kernel/backend/BackendDefaults.jl#L17) 🔒
- Evidence: `get_display_size(backend; display=0)` passes the SDL index through
  (`SDL_GetDisplayUsableBounds(Int32(display), rect)`), so the first display is
  0. The keyword `display` is an `Integer` here, and the device layer uses the
  same word for a `Display` object (`get_device_pixel_ratio(display)`). The
  docstring says "The pixel size", and the SDL answer is in logical pixels. No
  caller passes the keyword; only `HeadlessBackendTest.jl` does
  (`display=2`).
- Rule: PAR-ONE-BASED-INDEXING; writing-rules.md ("Use one word for one thing").
- Fix: remove the keyword, which no caller uses; say "logical pixels".
- Reach: `BackendInterface.jl`, `BackendDefaults.jl` (sealed), `Sdl.jl`,
  `VideoBackend.jl`, `FaultExamples.jl`, `HeadlessBackendTest.jl`.

### L09-7 The backend packages reach private names across module boundaries

- Category: Architecture · Severity: Medium · Confidence: Confirmed
- Where: `package/ProjecturedVideo/src/ProjecturedVideo.jl:49`,
  `package/ProjecturedSdl/src/ProjecturedSdl.jl:39`, [Sdl.jl:4](../../../source/sdl/Sdl.jl#L4),
  `source/video/Video.jl:1`
- Evidence: ProjecturedVideo imports `_emit_frames!`,
  `_make_offscreen_paint_state`, `_render_canvas_offscreen_partial!` and
  `_emit_frame_with_overlay!`, which ProjecturedSdl does not export.
  ProjecturedSdl exports `_open_offscreen_renderer` and
  `_close_offscreen_renderer`, names that start with an underscore, and imports
  `_bounds_elem!` and `_bounds_extend!`, which `GraphicsModule` does not
  export. `Video.jl` exports `_encode_frames_to_video!`. The offscreen renderer
  is a seam between two packages with no declared contract. ProjecturedVideo
  also imports types that it only uses (`WindowInput`, `WindowQuit`,
  `MouseDown`, …) and names `using ProjecturedGraphics` and
  `using ProjecturedSdl` three times each. `test_sdl_layering()` passes with
  these imports (plan/pending/sdl-per-editor-state.md, step 2), so no guard
  sees them.
- Rule: PAR-MODULE-BOUNDARY-IS-API; PAR-QUALIFIED-EXTENSION.
- Fix: export the offscreen renderer from ProjecturedSdl under public names (or
  move it behind a declared seam), export the bounds helpers of graphics or copy
  what SDL needs, and reduce the import lists to the names that each package
  extends.
- Reach: `ProjecturedVideo.jl`, `ProjecturedSdl.jl`, `Sdl.jl`, `Video.jl`,
  `VideoBackend.jl`, `GraphicsModule.jl`.

### L09-8 `render_canvas` has one implementation, and it is a stub that returns an empty image

- Category: Shape · Severity: Medium · Confidence: Confirmed
- Where: [BackendInterface.jl:134](../../../source/kernel/backend/BackendInterface.jl#L134) 🔒,
  [Sdl.jl:2779](../../../source/sdl/Sdl.jl#L2779)
- Evidence: `render_sdl_canvas(canvas)` is
  `GraphicsImage(Int32(0), Int32(0), Int32(0), Int32(0), nothing)`, and its
  docstring says that it renders to an offscreen texture. `BackendModule.render_canvas`
  delegates to it. The one caller, `make_graphics_caching(projection;
  render=render_canvas)`, hands it to `GraphicsCaching`, whose docstring says
  "nothing reads it yet". `BackendDefaults.jl` gives the rule for the output
  generics: "an unimplemented `write_image` must raise a `MethodError`, not
  fabricate a result". The stub fabricates one.
- Rule: PAR-NO-TEST-DOUBLES-IN-MAIN ("Production code that finds no real backend
  fails loudly rather than fabricating a fake"); architecture-rules.md (no
  orphan shapes the structure).
- Fix: remove `render_canvas`, the stub and the `render` keyword of
  `GraphicsCaching`, or implement the render.
- Reach: `BackendInterface.jl`, `BackendModule.jl` (sealed), `Sdl.jl`,
  `GraphicsCaching.jl`, `GalleryWrapperProjectionExample.jl`.

### L09-9 The SDL backend reads the modifiers and the held buttons at the time of the poll, not of the event

- Category: Correctness · Severity: Low · Confidence: Suspected (the code is confirmed; the effect needs a queue that holds a release)
- Where: [Sdl.jl:3505](../../../source/sdl/Sdl.jl#L3505),
  [Sdl.jl:3521](../../../source/sdl/Sdl.jl#L3521)
- Evidence: a `MouseDown`, `MouseUp`, `MouseScroll` and `KeyPress` take
  `_current_modifiers()` (the keyboard state after the pump), and a `MouseMove`
  takes `SDL_GetMouseState` (the buttons now), not `evt.motion.state`. When the
  queue holds a motion and then a release, the motion reads "no button", so the
  last motion of a drag is taken as idle and falls under the rate limit of idle
  motion. A Ctrl+click whose Ctrl goes up before the poll reads as a plain
  click.
- Rule: bug (an event reports what happened at its time).
- Fix: read `evt.motion.state` for the buttons; for the modifiers, keep the
  state from the last key event in the queue order.
- Reach: `Sdl.jl`, `InputCoalescingTest.jl`.

### L09-10 The default pointer position `(-1, -1)` is also a real position

- Category: Correctness · Severity: Low · Confidence: Suspected (on Windows and macOS; X11 gives no negative root coordinates)
- Where: [BackendDefaults.jl:16](../../../source/kernel/backend/BackendDefaults.jl#L16) 🔒,
  [BackendInterface.jl:89](../../../source/kernel/backend/BackendInterface.jl#L89) 🔒
- Evidence: "`(-1, -1)` when the backend cannot report it — a legal answer". The
  callers do not test it: the tooltip and hover probes compute
  `x = Int(x) + p.offset[1]` from the answer (`TooltipProbe.jl:152`,
  `HoverProbe.jl:109`). A monitor left of or above the primary one has
  negative global coordinates, and a `WindowDocument` with `x < 0` is centered
  by SDL (`px = w.x < 0 ? SDL_WINDOWPOS_CENTERED : …`). So a tooltip there opens in
  the center of the screen.
- Rule: bug (an in-band sentinel).
- Fix: answer `nothing` when the position is not known, and let the callers
  test it.
- Reach: `BackendInterface.jl`, `BackendDefaults.jl` (sealed), `VideoBackend.jl`,
  the two probes, `Sdl.jl` (`compute_window_place`).

### L09-11 No backend reads the `devices` argument, and the backends type it differently

- Category: Shape · Severity: Low · Confidence: Confirmed
- Where: [BackendInterface.jl:29](../../../source/kernel/backend/BackendInterface.jl#L29) 🔒,
  [Sdl.jl:3682](../../../source/sdl/Sdl.jl#L3682)
- Evidence: `read_from_devices`, `write_to_devices` and `wait_for_input` take
  `devices`, and no method of the five backends reads it (the SDL docstring:
  "The reconciler does not read `devices`"). SDL types it `devices::Vector{Device}`,
  the others leave it untyped, and `HeadlessBackendTest.jl` passes `Any[]`. The
  `Display` reaches SDL through `configure_devices!` instead. The device audit
  listed the argument under "Not in this plan".
- Rule: design fault (a parameter of a contract that no implementer reads).
- Fix: remove the argument from the three generics, or state what a backend
  must do with it.
- Reach: `BackendInterface.jl`, `BackendDefaults.jl` (sealed), the five
  backends, the editor, the fault example, the tests, omnet-julia test backends.

### L09-12 The backends answer the same situation in different ways

- Category: Shape · Severity: Low · Confidence: Confirmed
- Where: [Sdl.jl:3682](../../../source/sdl/Sdl.jl#L3682),
  [Web.jl:550](../../../source/web/Web.jl#L550),
  [Console.jl:291](../../../source/console/Console.jl#L291),
  [Web.jl:832](../../../source/web/Web.jl#L832)
- Evidence:
  - An output of the wrong type: the web and console backends raise an error
    that names the fix; SDL and video have no method, so a `MethodError` comes
    each frame. The `run_editor!` docstring says that such output goes
    "unrendered" (`EditorLoop.jl:269`).
  - An input with no window: SDL and the web use the id `:none`, the console
    `:console`. The event layer defines no id for "no window", and a window of
    the document can have either name.
  - `_wait_for_gate` is the same function, word for word, in `Console.jl:119`
    and `Web.jl:832`.
- Rule: PAR-BACKEND-SEAM (one contract for all backends); design fault (the same
  function in two packages).
- Fix: one error method in the kernel defaults for an output that a backend
  does not take; one exported constant for "no window" in the event layer; one
  exported helper for the gated wait.
- Reach: `BackendDefaults.jl`, `WindowInput.jl` (sealed); `Sdl.jl`, `Web.jl`,
  `Console.jl`, `VideoBackend.jl`, `EditorLoop.jl`.

### L09-13 The contract does not state the order of the calls, and one caller skips a step

- Category: Shape · Severity: Low · Confidence: Confirmed
- Where: [BackendInterface.jl:114](../../../source/kernel/backend/BackendInterface.jl#L114) 🔒,
  [BackendInterface.jl:17](../../../source/kernel/backend/BackendInterface.jl#L17) 🔒
- Evidence: `make_editor` calls `initialize_backend!`, `configure_devices!` and
  `open_native_windows!`, in that order (`EditorLoop.jl:246-249`), and
  omnet-julia `CampaignPrecompile.jl` copies the order. `play_live!` calls no
  `configure_devices!` (`source/kernel/playback/Playback.jl:117-121`), so its
  editor holds a `Display` at the defaults while the SDL backend draws with a
  `Display` of its own. The docstring of `configure_devices!` says only "Fill in
  the physical properties"; it does not say that SDL then draws with that
  `Display`. The docstring of `initialize_backend!` says "(create windows, load
  libraries, …)"; no backend creates a window there, `open_native_windows!` does.
- Rule: PAR-MODULE-DOCSTRING (the docstring states the contract).
- Fix: state the sequence in the `Backend` docstring and what
  `configure_devices!` promises; call it in `play_live!`.
- Reach: `BackendInterface.jl` (sealed), `Playback.jl`.

### L09-14 The export statement of `BackendModule` is not in the order of the definitions

- Category: Shape · Severity: Low · Confidence: Confirmed
- Where: [BackendModule.jl:26](../../../source/kernel/backend/BackendModule.jl#L26) 🔒
- Evidence: the statement lists `write_to_devices, read_from_devices,
  get_display_size, configure_devices!, open_native_windows!, …,
  get_pointer_position`; `BackendInterface.jl` defines `write_to_devices,
  open_native_windows!, read_from_devices, wait_for_input, wake_backend!,
  get_pointer_position, get_display_size, …`. The two include lines carry
  comments that repeat the docstring. `BackendModule.jl` is in
  `EXPORT_UNMIGRATED` (`test/suite/exports.jl:53`).
- Rule: code-quality-rules.md §1 ("in the order that the fragment defines it");
  PAR-TIGHT-COMMENTS.
- Fix: order the statement as the interface file; remove the two comments.
- Reach: `BackendModule.jl` (sealed), `exports.jl`. Planned:
  plan/pending/export-block-rule.md.

### L09-15 Four generics with an external effect have no `!`

- Category: Naming · Severity: Low · Confidence: Confirmed
- Where: [BackendInterface.jl:36](../../../source/kernel/backend/BackendInterface.jl#L36) 🔒,
  [BackendInterface.jl:66](../../../source/kernel/backend/BackendInterface.jl#L66) 🔒,
  [BackendInterface.jl:123](../../../source/kernel/backend/BackendInterface.jl#L123) 🔒,
  [BackendInterface.jl:132](../../../source/kernel/backend/BackendInterface.jl#L132) 🔒
- Evidence: `read_from_devices` takes the event out of the queue of the backend
  (SDL clears `pending_input`, the web backend calls `take!`, the headless
  backend `popfirst!`). `write_to_devices` draws on a screen or sends on a
  socket. `write_image` and `record_video` write files. None ends in `!`.
- Rule: naming-rules.md ("An external side effect takes `!`"; "a 'mutating
  getter' like consuming a queue is a `pop_`/`take_`").
- Fix: `take_from_devices!` (or `pop_device_input!`), `write_to_devices!`,
  `write_image!`, `record_video!`; the owner decides, because PAR-BACKEND-SEAM
  names two of them.
- Reach: `BackendInterface.jl`, `BackendModule.jl` (sealed), the five backends,
  the editor, the tests, architecture-invariants.md, omnet-julia and inet-julia
  (about 20 files).

### L09-16 The docstrings of the layer hold stale and loose text

- Category: Documentation · Severity: Low · Confidence: Confirmed
- Where: [BackendModule.jl:10](../../../source/kernel/backend/BackendModule.jl#L10) 🔒,
  [BackendInterface.jl:44](../../../source/kernel/backend/BackendInterface.jl#L44) 🔒,
  [BackendInterface.jl:71](../../../source/kernel/backend/BackendInterface.jl#L71) 🔒,
  [BackendDefaults.jl:20](../../../source/kernel/backend/BackendDefaults.jl#L20) 🔒
- Evidence:
  - `BackendModule`: "so generic code can name a capability (measure text, …)";
    `measure_text` left the contract in acde9278. "isn't" twice; "initialise";
    "live in **opt-in backend packages**", but the console backend is a package
    of the substrate and the headless backend lives in an example package.
  - `BackendInterface.jl`: "may" for a possibility (lines 5, 74), "e.g." (93,
    111), "HiDPI" (111), objects that act as persons ("A window system is free
    to refuse the size it is asked for", "the nearest deadline it knows").
  - Names of callers in the seam: "The editor loop calls it between frames" and
    "a feed's flush" (`wait_for_input`), "to place a follower window near the
    cursor … closes over this behind a `pointer` callback"
    (`get_pointer_position`).
  - `wait_for_input` says "`Inf` is legal" and does not say that the timeout
    must be above zero. The default `sleep(min(timeout_seconds, 0.01))` throws
    an `ArgumentError` for a negative value, and the `Timer` of the web and
    console waits does too. The editor guards with `timeout > 0`
    (`EditorLoop.jl:167`).
- Rule: writing-rules.md; PAR-NO-CONSUMER-DOCS (the seam carve-out allows the
  concepts on each side, not the callers); PAR-MODULE-DOCSTRING.
- Fix: correct the lines above; state "`timeout_seconds > 0`".
- Reach: `BackendModule.jl`, `BackendInterface.jl` (sealed).

### L09-17 The design documents describe an older seam

- Category: Documentation · Severity: Low · Confidence: Confirmed
- Where: `documentation/package/kernel/devices-and-backends.md`,
  `documentation/package/kernel/editor.md`,
  `documentation/design/system-anatomy.md`,
  `documentation/rule/architecture-invariants.md`
- Evidence:
  - devices-and-backends.md:15 and :107 "There are three backends"; the
    `VideoBackend` is a fourth. :104 "There is no `open_window!`/`close_window!`:
    native windows are reconciled on demand inside `write_to_devices`";
    `open_native_windows!` opens them before the first print. :250-252 "mirroring
    `sdl_keysym_to_symbol` … a single source of truth" (false, L09-1).
    :498-501 lists the generics without `wait_for_input` and `wake_backend!`,
    and :514-517 lists the defaults without them. :502 "Concrete backends (SDL,
    Web, Console, Headless, …) live in opt-in packages". :196-201 describes a
    tooltip window in the browser, and web.md:89 says that a tooltip does not
    happen there. :83 places `read!` in `editor/EditorModule.jl`; it is in
    `ReadEvaluatePrint.jl`.
  - editor.md:404-407: "There are two implementations: `SdlBackend` (graphics)
    and `ConsoleBackend` (terminal)".
  - system-anatomy.md:374: layer 9 holds "(lifecycle, text, …)"; :320-322 and
    :495-498 give `backend/Console.jl`, `backend/Pdf.jl`, `backend/Sdl.jl` and
    `backend/Web.jl`, which do not exist.
  - architecture-invariants.md, PAR-BACKEND-SEAM: the example
    "`convert_web_key_to_symbol` mirrors `sdl_keysym_to_symbol`" is false.
  - `ProjecturedVideo.jl:18`: "`record_video(doc, proj, gestures, "out.mp4")`";
    the method takes `gestures` and `filename` as keywords.
    `ProjecturedSdl.jl:12` says that `record_video` "reaches the unexported
    `_emit_frames!` through the qualified name"; it imports it.
  - `ProjecturedKernel.jl:36` 🔒: "layer 9 — rendering-target seam"; the layer
    also holds the input.
- Rule: PAR-UPDATE-THE-GUIDE; PAR-HONEST-DOCS.
- Fix: write the backend part of devices-and-backends.md again from the table
  in the Shape section of this report; correct the other lines.
- Reach: four documents, two package roots, `ProjecturedKernel.jl` (sealed).

### L09-18 No test holds the backends to one vocabulary, and the kernel defaults are half tested

- Category: Tests · Severity: Low · Confidence: Confirmed
- Where: `test/kernel/backend/HeadlessBackendTest.jl`, `test/sdl/backend/KeysymTest.jl:27`
- Evidence:
  - No test sends one input through two backends and compares the events: the
    key names (L09-1), the buttons (L09-2), the sign of the wheel (L06-2).
    `KeysymTest.jl:27` asserts `'q'` → `:char`, so it keeps the gap of L09-1.
  - The defaults of `get_pointer_position` and `open_native_windows!` have no
    test in the kernel.
  - `HeadlessBackendTest.jl` says that it tests "the write/read/measure I/O
    paths"; the measure left in acde9278. The file is named for
    `HeadlessBackend`, and the file that it tests is
    `example/kernel/BackendHeadless.jl`.
- Rule: PAR-NEW-CODE-SHIPS-TESTS; naming-rules.md ("`<Thing>Test.jl` —
  `<Thing>` is the file it tests"; a file is named for what it defines).
- Fix: a conformance test in the umbrella test package that decodes the same
  keys, buttons and wheel turns with SDL (`sdl_to_keydown`), the web
  (`_decode_and_enqueue!`) and the console (`_next_event!`); tests of the two
  defaults; the docstring; rename `BackendHeadless.jl` to `HeadlessBackend.jl`.
- Reach: test files, `example/kernel/BackendHeadless.jl`,
  `ProjecturedKernelExample.jl` (the include).

## Accepted before, not raised again

- The SDL session, its event queue, its font cache and its texture cache are one
  for each process, so a second SDL editor shares them (deferred:
  plan/pending/sdl-per-editor-state.md, Part 2). The font and texture caches
  keyed by content, and `_PROBED_DISPLAY_SCALE`, stay by the exception of
  PAR-PER-EDITOR-STATE (Part 1 of the same plan).
- The font zoom `_FONT_ZOOM` is one value for the process (deferred:
  plan/pending/font-zoom-per-editor.md).
- The web backend sends no motion without a held button, so hover and tooltips
  do not work in the browser; web.md:89 states the limit (PAR-MANY-WINDOWS
  allows a limit that the backend states).
- The console backend renders the Text domain and has one window
  (devices-and-backends.md, "ConsoleBackend", states it).
- The event time comes from each backend on the clock of `time()`
  (plan/done/gesture-layer-audit.md, D2).

## Checked and clean

- PAR-INTERFACE-DECLARES-ONLY: `BackendInterface.jl` holds `Backend` and 14
  bodiless generics; the six defaults are in `BackendDefaults.jl`; the kernel
  guard checks the file.
- The layer imports nothing and names no document, projection or editor type in
  code; a document and a projection appear only as arguments of bodiless
  generics (PAR-FRAMEWORKS-SINK).
- PAR-NO-TEST-DOUBLES-IN-MAIN: `HeadlessBackend` lives in
  `ProjecturedKernelExample`, and no main code makes it.
- PAR-PER-EDITOR-STATE in the layer: no state. The web and console backends keep
  their state on the instance.
- `wake_backend!` is safe from any thread in every backend that answers it
  (`SDL_PushEvent`, `notify` on a `Base.Event`), as the contract requires.
- Every backend gives each event the time of its input (SDL ticks, the `t` of the
  web page, the time of the console read, the schedule of the video), and makes
  no `MousePress` of its own; Escape is an ordinary key in SDL, the web and the
  console.
- PAR-QUALIFIED-EXTENSION at the seam: SDL, web and console extend by
  qualification (`BackendModule.f`), the video backend by an import list.
- PAR-MODULE-DOCSTRING; no history comment; no line over 90 characters.
