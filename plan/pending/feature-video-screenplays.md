# Feature videos: one screenplay for each feature

> **Status:** pending. No step is started. Written 2026-09-22.

A set of short videos. Each video shows one feature of ProjecturEd, live, in the
running application. The main video is the M/M/1/K study, where the real
assistant builds a simulation study. The videos go into the forum posts
(`documentation-rewrite-discourse-post.md`), the README and the web site.

## 1. The request

> create a plan for writing screenplays that will be recorded as videos for
> various feature demonstrations
> each screenplay should focus on one interesting feature and should show it live
>  - evaluator (typing the reactive rotating vector example)
>  - assistant manipulating the user interface
> I don't know how many additional we should have, you decide. see what features
> does projectured already have
>
> the main feature video should be the omnet mm1k study video
>
> the mm1k assistant demo should not be scripted anymore, the assistant should be
> the real ollama qwen model

The second request, on the same day, after the first draft of this plan:

> update the repl screenplay: rebuild the rotating vector example
> add a new screenplay: create widgets, start with a push button, add other widgets
>
> remove Tier 3, not needed

## 2. What exists

### 2.1 The recording tools

- `record_video(document, projection, gestures, filename; fps, width, height, initial_hold, final_hold, wait_for, supersample, clock)` in `source/video/Video.jl:69`. It renders each frame with the offscreen software renderer and encodes with `ffmpeg`. No window is necessary. The package is `ProjecturedVideo`.
- A gesture is `(event = …, hold = …)`, `(operation = …, hold = …)` or `(await = predicate, hold = …)`. `hold` is video time, so a recording is the same on each run.
- `LiveExample`, `record_live_example` and `play_live_example` in `example/sdl/LiveExamples.jl`. `timed_event`, `timed_operation` and `timed_await` make the timeline entries.
- `make_typein_gestures(text; hold, jitter)` in `example/kernel/Harness.jl:118` makes one key press for each character, with a human rhythm.
- `json_build_live` (`example/sdl/LiveExamples.jl:222`) builds a JSON document from nothing by typing. It made `/home/projectured/json_build.mp4` (760×1000, 43.5 s) on 2026-06-24.
- `FakeLlm` and `ScriptedLlm` (`example/kernel/`) give an assistant with a fixed reply. This plan does not use them in a video (D3).
- `OllamaLlm` takes `temperature` and `seed` (`source/ollama/Ollama.jl:68`). The default model is `qwen3.8:27b` (`source/ollama/Ollama.jl:4`), and the Ollama server of this machine has it (17 GB).
- `bin/projectured` has no option to record. A recording is a library call.

### 2.2 The M/M/1/K study

`plan/done/mm1k-assistant-study-demo.md` in omnet-julia. One window, split in two: the study book on the left (`WorkbenchEditor` on a `BookBook`) and the assistant on the right. In six turns the assistant writes the background, a NED model, an INI configuration, runs the real OMNeT++ `queuenet` simulation, plots the blocking probability, and finds the smallest buffer K for a blocking below 1 %. `record_mm1k_demo(path)` and `play_mm1k_demo()` are in `demo/recording/Mm1kLive.jl:265`.

Today the assistant of the study is a `ScriptedLlm` with fixed replies. The Julia code in the replies runs for real, and so do the simulations. `_warm_up_mm1k_demo` loads `Main.OmnetLegacyExample` into the scratch module of the assistant before the recording, so the replies can call the study functions without a `using` line. The last change to these files is from 2026-09-09. No test runs the recording, so the renames since then can have broken it.

### 2.3 The speed of the real model

On 2026-09-16 `qwen3.8:27b` solved 5 of 8 problems of the omnet-julia application. One turn took from 13 s to 143 s (`plan/done/assistant-finds-the-api.md`, the baseline table). Later work raised the result to 29 of 33 turns on eleven problems (`documentation/requirement/delivery-roadmap.md`). This machine has 32 cores and 61 GB of memory, and no NVIDIA GPU, so the model runs on the CPU.

### 2.4 The faults found while recording

Four faults of the editor, and one thing that is not proven, came out of the work on S3 and S4 on 2026-09-22. The owner said not to fix a fault that the video work finds, so each one is written here and left alone. Each was found with a headless replay of the gestures through `read_intent` and `evaluate_operation`, over a real `Editor` with a `ConsoleBackend`.

**F1. A file tab of the application takes no character.** Open `person.json` in `bin/projectured`, with content or empty. The pane focus is on the tab, the JSON draws, and no key reaches the document: `x`, `,` and `{` each answer no operation. `Alt+Down`, `Tab` and `Alt+click` answer a `ReplaceSelectionOperation`, so the selection moves, but a key after them still answers nothing. A plain click on the text answers nothing at all. The evaluator tab is the control: in the same window `Ctrl+T`, `Insert`, `repl`, Enter and then `1+2` Enter draw `= 3`. So the window, the reader and the loop work, and what fails is the seat of the selection inside a file tab.

What F1 blocks: every screenplay whose keys go into a file tab, which is S5 to S8. S3 stays a single-document take by the owner's decision (2026-09-25). It does not block S1, S2 and S4, which type into a tool tab: the evaluator and the assistant.

**F2. After a string value, `Right` then `,` inserts nothing.** This is the rule the `json_build` live example is built on. A replay of its timeline today: 192 of its 210 keys answer no operation, and the document stops at `{"name": "Alice"}`. `Alt+Up` in place of the `Right` works, and the same build then runs with no dead key.

**F3. A nested container is never left.** Inside `"address": { … }`, an `Alt+Up` once, twice or three times does not bring the caret back to the root object. The next entry lands inside the nested object again. The live example uses `Alt+Up` four times for exactly this, so F3 is the other half of what broke it.

**F4. A callback made in the evaluator can not be called.** A button built in the evaluator with `action = () -> presses[] += 1` lights up under the pointer, and its press routes: the reader answers an operation. The action never runs. Called by hand, the callback says:

```
MethodError: no method matching (::Main.ToolScratch.var"#2#3")()
  (method too new to be called from this world context.)
```

The closure belongs to the world of the evaluator, and `evaluate_operation(::InvokeActionOperation)` (`source/widget/WidgetDocument.jl:2811`) runs in a world compiled before it. It first asks `applicable(callback, editor)` and `applicable(callback)`, and from that older world both answer false, so the callback is skipped with no error at all. The error above comes only from a direct call. The same closure works in a plain session: the label follows the cell, and `callback()` counts. So a widget that a person builds in the evaluator, or that the assistant builds with `execute_julia_code`, can draw and can not act.

**F6. The assistant is told about functions it can not call.** The application declares a narrow API (`make_application_api`), and `execute_julia_code` runs in a scratch namespace that binds only what that declaration names. The guides and `search_api` answer with names outside it, and the model spends its rounds on them:

```
UndefVarError: `search_documents` not defined in `Main.ToolScratch`
  Hint: a global variable of this name also exists in ProjecturedKernel.DocumentModule.
Module 'PaneModule' not found.        # from list_functions("PaneModule"), a module the system prompt names
```

`list_functions` and `list_types` call `_find_module(name)` with no API argument (`source/kernel/tool/Documentation.jl:497` and `:514`), so a declared module is invisible to them. `list_modules` takes the API, and the tool set passes it. A round spent this way is a round the model does not spend on the task, and the agent stops at 8 rounds.

**F7. The caret can not leave a container whose last value is a bool.** A bool is typed with `t` or `f` and is whole-selected, because it has no text. On a structural selection the text layer declines a plain arrow, and the syntax layer navigates the tree, so `Right` on the last entry stays where it is. `End` answers nothing. In `{"meta": {…, "draft": false}}` no caret key reaches the closing `}`, and only `Alt+Up` leaves the object. The `json_build` live example types the bool before the number of `"meta"` for this reason. Found 2026-09-23 in Step 4 of `plan/done/structural-keys-from-the-caret.md`; recorded, not fixed.

**F8. Not proven: after a slow start, the recorder loses the holds of the next keys.** In the probe takes of 2026-09-24 (`build/video/probe_wrap_app.jl`), the first keys waited for compilation, and `F2` reached the window at 26.8 s of video where the timeline schedules it at about 10 s. After it, the four characters of the name and `Escape` reached the window within 0.2 s of video, although the timeline holds 2 s after the last character. The first probe also ended while its last form was still being typed. Recorded, not fixed; the real takes type slowly and hold long, so they can hide it.

**F9. `measure_truetype_text` and the SDL renderer disagree for a font with a fractional advance.** `measure_truetype_text` reads the advances of the font file; SDL draws with hinted advances of whole pixels. DejaVu Sans Mono at 16 px measures 9.63 px for each character and draws 10 px, so a line of 86 characters draws about 30 px wider than it measures. Ubuntu Mono at 20 px measures 10 px exactly, so the JSON and the evaluator do not drift. The gesture panel of the S3 take showed it: its long lines ran past the panel. The take gives the panel `measure_sdl_text`. Found 2026-09-24; recorded, not fixed.

**F10. While a form is typed, the animation of S1 stutters.** The owner saw it on 2026-09-24: "when no type-in occurs the video shows very smooth movement of the circle and lines, but during type-in its laggish". The video backend takes one frame for each 1/30 s of wall clock, and when the work between two frames takes longer, it copies the last frame into the missed slots (`_backfill_frames!`). A key makes that work large: the evaluator handles it, the text is laid out again, and the frame is drawn at 2 and written to disk. Measured on `rotating_vector_v4.mp4`, the picture pane gets about 7 new frames a second while a form is typed and about 16 while the take holds still. F8 has the same cause. The fix proposed to the owner: the recorder keeps video time, not wall-clock time. Each frame is exactly 1/30 s after the one before; the timeline fires by video time; the editor loop takes the time of its clock from the backend, so the editor's clock (`editor.clock`) moves 1/30 s a frame; and the forms of S1 read `editor.clock` in place of `get_wall_clock()`. **Fixed 2026-09-24** (`plan/done/video-time-for-an-animated-take.md`). The owner agreed, and asked that the other takes keep the wall clock: a take that does not move, or that waits for a model, does not need it. So video time is an option of the recorder, off by default, and S1 turns it on. The take `build/video/rotating_vector_v5.mp4` is 114.3 s, exactly its schedule. From 51 s to the end, the picture pane gets 30 new frames a second, while a form is typed and while the take holds still.

**F5. A real drag does not move the slider, and a click leaves its knob held.** In the harness neither a drag nor a character changed the document, but the coordinates there were computed and not read from a frame. The probe of 2026-09-24 (`build/suites/s4/probe_drag.jl`) sends real mouse events to the slider of S4 in its own pane, and reads `slider.value` and `presses` from the scratch module of the evaluator after each gesture:

- The slider takes the knob only on a `MousePress`. The gesture recognizer makes a `MousePress` after the `MouseUp`, and only when the up is less than 5 px and 0.3 s from the down. So a real drag (down on the knob, moves with the left button, up at 0.8) leaves the value at 0.3.
- A real click on the track sets the value (0.5125 at x = 900) and then takes the knob, after the button is already up. The knob stays held (`dragging = true`): a move with no button moves it to 0.93, until the next `MouseUp`.
- A press that the script makes (`MousePress`, moves, `MouseUp`) works, and that is why the old take could press the button.
- A real click on the button counts, except the first one of the probe. The recognizer measures a click with the wall clock, and the first down in the pane took longer than 0.3 s, which is the time of the compilation. A warm-up before the take compiles that path. A live window can lose its first click in the same way; recorded, not fixed.
- Not checked: a character in the text field. The owner keeps the write of the name from the evaluator (2026-09-24).
- Not fixed: a layout (`_route_layout_event`, `source/layout/LayoutToGraphics.jl`) routes a `MouseDown`, a `MouseMove` and a `MouseUp` only to the child under the pointer. A drag that leaves the slider loses its moves, and an up off the slider leaves the knob held. A composite offers a drag event to each child when none is under the pointer; a layout does not.

**Fixed 2026-09-24** (`plan/done/slider-drag-and-real-presses-in-s4.md`, commit b4466777): the slider takes the knob on `MouseDown`, moves while it is held, and lets go on `MouseUp`. A `MousePress` sets the value and takes nothing.

The `json_build` recording of Step 0 produced a file of the right length, which is why the baseline called it good. The file shows a document that stops after one entry. §7 Step 0 says so now.

### 2.5 The gaps

| Gap | What is missing |
| --- | --- |
| G1 | No recording shows the full application window: the menu bar, the toolbar, the tabs, the navigator and the assistant pane. `LiveExample` wraps one editor in one window. `make_application_document` (`example/projectured/Application.jl:78`) is not recorded anywhere. |
| G2 | An `await` entry emits one frame for each pass of its loop, and a pass takes `1/fps` plus the render time. So a wait runs in the video at a speed that the render time decides, and not at the speed of the real wait, which D7 asks for. |
| G3 | A recording shows no pointer and no key names. A viewer can not see what was pressed or clicked. |
| G4 | The M/M/1/K study uses a `ScriptedLlm`, and it loads its functions silently before the run. |
| G5 | The web page shows a Julia function whose body is an XML table (`assets/examples/mixed-julia-xml.jpg`, 2026-07-16), but no code in the repository makes that document now. |
| G6 | S9 shows a terminal and a window side by side, which are two programs. `record_application_video` records one editor, so S9 needs a capture of the screen. The shell of this session is a tty, so the capture runs in the desktop session of the owner. The machine has `ffmpeg`; the tool and the display server are chosen in the step of S9. |

## 3. Decisions

| # | Decision | Who |
| --- | --- | --- |
| D1 | The main video is the M/M/1/K study. | owner, 2026-09-22 |
| D2 | In the M/M/1/K study the assistant is the real `qwen3.8:27b` through Ollama, not a `ScriptedLlm`. | owner, 2026-09-22 |
| D3 | Every video that shows the assistant uses a real model. The post says that the assistant is real, and a scripted reply in a video would contradict that. | my choice |
| D4 | The user side of a screenplay stays scripted: the key presses, the clicks and the typed prompts. Only the assistant is live. | my choice |
| D5 | A feature video shows one feature and lasts 30 s to 90 s. A video that types its code (S1, S4) lasts at most 3 min. The main video lasts as long as the real session takes, because nothing is made faster (D12). | my choice, and D12 |
| D6 | There is no voice. A caption bar that ProjecturEd draws itself says what happens. A key name appears on the screen when a key is pressed, and the pointer is visible. | my choice |
| D7 | A wait for the model runs in the video at the speed of the real wait. It is never cut, and a reply is never replaced. | my choice, and D12 |
| D8 | The model gets no hidden help. It has the system prompt and the tools that every user of the application has. A function that it must find gets a docstring, and a study gets a guide that `search_guides` finds. The first caption names the model and says that it runs on the CPU of this machine. | my choice |
| D9 | Before a recording, the screenplay is rehearsed with a fixed `seed` and `temperature`. The take that goes into the video is one run, and nothing in it is edited (D12). The plan records the model, the seed and the turn log of each take. | my choice |
| D10 | Short videos are 1280×720 at 30 fps, so the 20 px text stays legible in a forum post. The main video is 1920×1080, as the study demo is now. | my choice |
| D11 | The main video can show the M/M/1/K study of the omnet-julia application in a public post (answer to Q1). The caption does not name the private product, and the post says that the code of the study is not in the public repository. | owner, 2026-09-22 |
| D12 | No part of a video is made faster. There is no time lapse and no speed marker (answer to Q3). A wait for the model stays as long as it is. The main video is then as long as the six turns take, which the measurement of §2.3 puts between about 10 min and 25 min. If a take is longer than that, the plan asks the owner again before it is published. | owner, 2026-09-22 |
| D13 | A video types with the rhythm of `make_typein_gestures` itself: `hold = 0.15` on average and `jitter = 0.6`, which reads as a person typing. A faster rhythm is what the first take of S1 used, and the owner asked for the human one. | owner, 2026-09-22 |

## 4. Open questions for the owner

| # | Question | My recommendation |
| --- | --- | --- |
| Q1 | **Answered on 2026-09-22: yes.** See D11. The study runs in the omnet-julia application. Decision D9 of `documentation-rewrite.md` keeps that application out of every public document, and the old hero video of the web site was removed for that reason. Can the main video of a public post show it? | Show it. The caption says that the study runs in an application built on ProjecturEd, with the OMNeT++ simulator, and it does not name the private product. The post must then say that the code of the study is not in the public repository. |
| Q2 | **Deferred by the owner on 2026-09-22: decide it when the takes exist and their length is known.** Partly answered on 2026-09-24: "the last video is good enough to be added to the projectured.github.io, this will be one of the several videos, the hero will be the MM1K when it's ready". S3 is in `projectured.github.io/assets/videos/` (548 KB), shown in a new Videos section of the page (commit `f024f46` there, not pushed). The hero of the page becomes S0 when it exists. Where do the videos live? | The short ones go in `projectured.github.io/assets/video/`, and the web site and the README link them. A long main video goes to YouTube, because a forum shows a YouTube link as a player and a file of that length is too large to upload. |
| Q3 | **Answered on 2026-09-22: no time lapse.** See D12. On the CPU a turn takes minutes. Is a time lapse acceptable, or is there a faster machine for the takes? | Superseded by D12. Every wait runs at its real speed, and the main video is as long as the session. |
| Q4 | Which videos come before the post? | Tier 1 (§5): S0 to S4. Tier 2 can follow the post. |

## 5. The screenplays

Every screenplay has the same parts: the feature, the claim of the post that it shows, the setup, the beats, and the acceptance. The code that a beat types is a target. The step of the screenplay tests it in the real evaluator before any recording, and records here what worked.

### Tier 1

#### S0. The assistant builds a simulation study (main video)

- **Feature:** a local model develops a study end to end. It writes prose, a model, a configuration, runs real simulations, plots the results and changes its own earlier text.
- **Claim:** the assistant works on the same data as you, with the same operations, and runs Julia in the program.
- **Setup:** the study window of `mm1k-assistant-study-demo.md`, 1920×1080. The assistant is `OllamaLlm(model = "qwen3.8:27b", seed = …, temperature = …)`. The study is empty at the start.
- **Beats:** the six prompts of §1 of `mm1k-assistant-study-demo.md`, typed by the scripted user. After each prompt the recording holds while the real turn streams, at the speed of the real turn (D7, D12). The caption names the turn: "1/6 the background", "2/6 the model", and so on.
- **Acceptance:** each turn makes the change to the study that §1 of the demo plan lists, in the take that is kept. The study ends with the chosen K, and the simulated result agrees with the closed form of M/M/1/K. The turn log (rounds, tool calls, seconds) is saved with the take.

#### S1. The evaluator: rebuild the rotating vector

- **Feature:** the evaluator runs Julia in the program. A graphics document that it returns draws as itself and stays live, and a `push!` into it from a later form changes the picture that is already on the screen.
- **Claim:** every field is a reactive cell; a write computes again only what reads it.
- **Setup:** `bin/projectured` with no file, 1280×720. The target is the picture of `run_example("rotating_vector")` (`example/substrate/RotatingVectorDocumentExample.jl`): a dot on a ring, a sine trace to its right, a cosine trace under it, their axes, and two dashed links from the dot to the traces.
- **Beats:** each form is typed, with Shift+Enter between its lines, and runs on Enter. From beat 3 on, each form adds one part to the canvas of beat 3, and that canvas changes where it is.

| # | Action | On the screen | Caption |
| --- | --- | --- | --- |
| 1 | Type `repl` into the empty tab, Enter. | The tab becomes the evaluator. | Type the name of a tool into an empty tab. |
| 2 | `clock = editor.clock` | A `=` row shows the clock of the editor. The take keeps video time, so this clock moves 1/30 s a frame. | |
| 3 | `canvas = GraphicsCanvas([GraphicsRect(0, 0, 600, 600, color_solarized_background_lighter)]; w = 600, h = 600)` | An empty square draws in the result row. | The result is a graphics document. It draws as itself. |
| 4 | `push!(canvas.elements, GraphicsCircle(170, 170, 110, StyleColor(0.0, 0.0, 0.0, 0.0); border_width = 2, border_color = color_solarized_content_darker))` | The ring appears in the square above. | A `push!` changes the picture that is on the screen. |
| 5 | `phase() = -0.5 * get_reactive_clock_time(clock)`, then a `push!` of the dot, whose two coordinates are `ComputedCell`s that read `phase()`. | The dot appears and circles the ring. | Each coordinate is a cell that reads the clock. |
| 6 | A `push!` of the sine trace: a `GraphicsPolyline` whose points are a `ComputedCell` that reads `phase()`. | A blue sine trace scrolls to the right of the ring, level with the dot. | |
| 7 | The same for the cosine trace. | A green cosine trace scrolls down under the ring. | |
| 8 | A `push!` of the two axes of each trace, and of the two dashed links whose ends read `dot.cx` and `dot.cy`. | The picture is complete, and it is the same as the example. | A link reads the dot, not the clock. |
| 9 | Hold 3 s. | | |

- **One video, many forms.** The owner said on 2026-09-22 that the picture grows form by form in one video: "It simply makes it more interesting for the viewer." So each form of the table adds one part to the drawing, and the viewer watches the picture become the example. The video is not cut into parts, and no beat is left out.

- **The first take, 2026-09-22.** Recorded: 1280×720, 3144 frames, 104.8 s, 1.1 MB, with `record_application_video`. The window opens `notes.json`, `Ctrl+T` and `repl` open the evaluator, and thirteen forms build the picture. Each form that changes the picture ends with `; canvas`, so the newest row shows the whole picture above the prompt. The canvas is 300×300, because a canvas of 420×420 and the prompt under it do not both fit in the pane, and the view follows the caret.

  The forms that work, in order: `clock = get_wall_clock()`; the `GraphicsCanvas` with a `GraphicsRect` background; `ring = GraphicsCircle(90, 90, 60, …)`; `push!` of the ring; `phase() = -0.5 * get_reactive_clock_time(clock)`; `dot = GraphicsCircle(ComputedCell(…), ComputedCell(…), 5, …)`; `push!` of the dot; the sine `GraphicsPolyline`; its `push!`; the cosine `GraphicsPolyline`; its `push!`; and the two dashed `GraphicsLine`s, each in its own `push!`.

- **The take of 2026-09-24, for the web site.** Recorded on the branch rebased on `main` at d4fc522c: 1280×720, 256.6 s, 4.5 MB, `build/video/rotating_vector_v2.mp4`. The forms wrap inside the left pane, and the tab name shows its caret while `F2` names the pane. Not yet good enough for the page:
  - **A frozen start.** For 11 s the window shows the README, then the Evaluator button stays pressed for 5 s while the evaluator compiles. The keys that fall due in that pause arrive in one burst, so the first form is half typed when the tab appears (F8).
  - **The length.** 256.6 s, where D5 allows 3 min and the section of the page says "short sessions". The long positional constructors of the graphics are most of it.
  - **Internal text in two results.** `phase()` shows `Main.ToolScratch.var"#phase"()`, and `clock` shows the raw fields of the clock.
  - **A frame in the paste.** While the pasted canvas becomes the tab `untitled`, one frame draws its close button and the new-tab button over each other.

  **The fixes proposed on 2026-09-24, waiting for the owner.** The owner said: "write all the findings up in the plan, we will get back to it".
  1. **A warm-up before the recording (F8, the start).** The script runs the first steps once without recording, in the same process, so the evaluator is compiled before the first frame. Only the script changes.
  2. **The recorder times each key from the previous one (F8, every take).** Each hold is measured from the moment the previous key was handled and drawn, not from the start of the timeline, so a pause of the program no longer fires the waiting keys in one burst. It changes `VideoBackend`, so it is a mechanism change for the owner.
  3. **Shorter forms (A1, the length).** The graphics constructors take a cell or a function by keyword. It is an API change for the owner. It cuts the typing and makes the forms easier to read. A smaller way: leave out a part of the picture, such as the dashed links, which saves about 40 s.
  4. **Readable results (V6).** The evaluator prints a function as the Julia REPL does, `phase (generic function with 1 method)`, and a clock by its type.

- **The refinements the owner asked for, to do before the video is published:**
  - **The typing rhythm.** The take typed with `hold = 0.045` and `jitter = 0.5`, which is faster than a person. Use the rhythm of `make_typein_gestures` itself (`hold = 0.15`, `jitter = 0.6`, `example/kernel/Harness.jl:118`), which is what the owner means by the human one. The forms hold about 1200 characters, so this rhythm adds about two minutes, and the forms must get shorter to stay inside D5.
  - **The forms are long**, because a `GraphicsCircle`, a `GraphicsPolyline` and a `GraphicsLine` with a cell in a field take every positional field. A constructor that takes a function or a cell by keyword would cut the typing in half. It is an API change, and the owner approves it before it is made.
  - **G3 is missing** from this take: no caption bar, no pointer, no key names.
  - **The assistant pane is off** in this take (`assistant = :none`), so the window is narrower than the real one.
  - The holds are 3 s after a form that changes the picture and 1.2 s after the others.

- **Acceptance:**
  - The step writes the real forms of beats 5 to 8 into this table. They come from the example. `phase` replaces the local `angle` of the example, because `angle` is a function of `Base`.
  - The canvas of beat 3 changes in its result row after each `push!`. If the result row shows a copy that does not change, the forms end with `canvas`, so each one shows the canvas again, and this table records that.
  - The reactive `GraphicsCircle`, `GraphicsPolyline` and `GraphicsLine` need every positional field (`example/substrate/RotatingVectorDocumentExample.jl:74`). If a form is too long to type in the video, a shorter constructor that takes a cell or a function is an API change. The owner approves it before Step 2 goes on.
  - The video lasts at most 3 min (D5), and nothing in it is made faster (D12). If the typing is longer than that, the forms get shorter: a shorter constructor, or fewer parts of the picture.

#### S2. The assistant edits a file and arranges the window

- **Feature:** the assistant works in the documents of the person and in the window: it adds a record to a file, and it opens a tab with a table built from the file.
- **Claim:** the assistant works on the same window as you, and `Ctrl+Z` takes its change back.
- **Setup:** `bin/projectured people.json`, 1280×720, with the assistant pane on the right and the panel of the gesture and operation log at the bottom left, over the lower part of the navigator. `people.json` holds five people with a name, an age and a city:

  ```json
  [{"name": "Cleo", "age": 29, "city": "Lyon"}, {"name": "Ada", "age": 36, "city": "London"},
   {"name": "Bob", "age": 41, "city": "Oslo"}, {"name": "Eve", "age": 25, "city": "Rome"},
   {"name": "Dan", "age": 33, "city": "Madrid"}]
  ```
- **Beats:**

| # | Action | On the screen | Caption |
| --- | --- | --- | --- |
| 1 | Hold 2 s. | The file in a tab, the assistant on the right, the log panel at the bottom left. | The assistant: qwen3.8:27b through Ollama, on the GPU of this machine. |
| 2 | Type the prompt "Add Frank, 30, from Paris to people.json." Enter. | The tool calls stream into the conversation, at the speed of the real turn. A record for Frank appears at the end of `people.json`, and the log shows the insert. | It edits your document, as you would. |
| 3 | Click in the tab of `people.json`, and press Ctrl+Z. | Frank goes away, and the log shows the undo. | A change of the assistant is taken back like one of yours. |
| 4 | Click in the input of the assistant. Type the prompt "Open a second tab beside the first one with a table of the people in people.json, sorted by name." Enter. | The tool calls stream in. A second tab opens with the table of the five people, sorted by name, and the log shows the open. The video ends. | It searches the API, writes Julia and runs it. |

- **The owner's decision, 2026-09-26, the order of the beats above:** the assistant first adds a person to the file, the person takes it back with `Ctrl+Z`, and then the assistant builds the table. The owner proposed it, and it replaces the ending "Ada moved to Paris" of the bullet below. For the viewer: the edit of the assistant and the undo of the person sit next to each other; a new record is a larger change to see than one word; the video ends on the table, which shows the five people of the file, so the question whether the table follows the file does not come up. Also decided: the log panel is at the bottom left, where it covers only the lower part of the navigator; and an edit of the assistant inside a file goes into the history of that file, as an edit of the person does, so the person undoes it in the tab of the file. Open for the owner: the text of a log line of such an edit. Today it is "Replace" and the path from the pane tree, cut to 60 characters (`Replace .root.elements[2].tabs[1].content.content.content[2]…`); a short form names the tab and the path inside its document (`Insert people.json › [6]`).
- **The owner's decision, 2026-09-26 (replaced by the bullet above):** the step "Under the two tabs, add a card with a table of the names and the ages." is gone: it "barely adds anything to this video and is not really meaningful", and it was not clear which place "the two tabs" names. In its place the assistant changes the data, the step that shows the claim most directly: it edits the document you edit, and your undo takes the edit back. The video ends after the `Ctrl+Z`. Open for the owner: whether the table of beat 2 follows the file, so it shows "Paris" too.
- **The take of 2026-09-26** (`tool/video/record_assistant_window.jl`, `/var/tmp/s2/assistant_window.mp4`, 188.5 s, 1280×720): qwen3.8:27b on the GPU, context 32768, seed 1, the system prompt unchanged. A warm-up with a scripted model runs the same steps first and is deleted, and the session's gesture log is emptied before the take, so the take fires no burst and its log starts at 1. The session's log is a pane below `people.json` with 20% of the height (the owner, 2026-09-26: a normal pane, not an overlay; the window's own log folds a typed run into one line), and `people.json` is in a scroll pane (`a-file-tab-scrolls.md`). What the video shows, read at one frame per second:
  - 0–63 s: the prompt is typed; the model reads the orientation guide, prints the JSON, and runs `insert_elements!(editor, people_1, length(people_1) + 1, [frank_1])`; the log shows `Insert 1 into people.json`.
  - 66 s: the answer "Added Frank, age 30, from Paris to people.json."
  - 69–74 s: the pointer moves over the file, the wheel scrolls it, and Frank, 30, Paris is the last record for three seconds.
  - 75 s: a click in the file and `Ctrl+Z`: Frank is gone, the log shows `Ctrl+Z` → `Undo`.
  - Then the table prompt; the model reads the docstring of `get_parent`, writes `sort(… for person in people_1; by = first)` once (an error: a generator), corrects it, and opens "People by name" with `target = get_parent(editor, people_tab_1), side = :right`: a pane to the right of `people.json`, with Ada 36 London, Bob 41 Oslo, Cleo 29 Lyon, Dan 33 Madrid, Eve 25 Rome; the log shows `Open the pane People by name`. The video ends on the table.
  Open for the owner: the log line of the scroll (`compound(2): set .scroll_position = …`), the thinking blocks in the conversation, and the length of the second turn.
- **Take 2 of 2026-09-26** (`/var/tmp/s2/assistant_window.mp4`, 226.6 s), after the owner's answers to take 1: the log leaves out a scroll by default (a write of view state, as the history already does); the Files tab is closed, so the file has the left 780 px and the assistant the rest; the thinking of the model is shown open (`collapse_thinking = false` in the take's `prepare_window!`); the table stays a second pane. The first turn is as in take 1, with its thinking open; Frank shows after the scroll at about 66–69 s, and `Ctrl+Z` takes him back at about 70 s. In the second turn the model again wrote `sort(… for person in people_1; by = first)`, a generator, and this time spent three more rounds to find the cause with `collect` before it opened "People by name" with the five people.
- **Take 3 of 2026-09-26** (`/var/tmp/s2/assistant_window.mp4`, 215.2 s), after the owner asked to read the evaluated code: the take waits 4 s before each call of the model (`PacedLlm` in the take script, which forwards the five functions of the model interface and sleeps in `stream_turn`); the window is drawn at 85% of a logical 1506×847, so the video stays 1280×720 with smaller text; the assistant pane has 45% of the width. The five people fit the file pane without a scroll; with Frank the file scrolls again. The code of an `eval` block reads with its colours; two limits remain: a long code line is cut at the right edge of the pane, not wrapped, and the answer of a call that fails shows closed ("› error"), while a call that succeeds shows its answer open. The model made the generator error again and corrected it in one round with `collect`.
- **Take 4 of 2026-09-26** (`/var/tmp/s2/assistant_window.mp4`, 271.4 s), after the owner's note that the code of a call that works was hidden by its answer ("the take should show result as collapsed by default then it can open after some wait"): before each call of the model, the take's `PacedLlm` closes the answer (`result_collapsed`) of each new `EvaluatorForm` of the conversation for 3 s, so the viewer reads the code, then opens it for 3 s, so the viewer sees what the code returned; `prepare_window!` gives it the assistant. Checked at full size: at about 59 s the first block shows its three lines of code with "› result", and then the whole JSON. The model repeated the generator error twice in the second turn this time, with the same seed; the answers of the model are not the same from take to take.
- **The owner's decision after take 4, 2026-09-26:** "can we avoid the error completely?", then "It should go away, let's change the documentation. The doc is a bit specific for the example though". In every take the second turn wrote `sort([…] for person in people_1; by = first)`, a comprehension without its brackets, which gives `sort` a generator; the orientation guide showed the rows and the sort on two lines, and the model merged them. The guide now shows the one call, `rows_1 = sort([[item["name"].value, item["price"].value] for item in items_1]; by = first)`, and says that `sort` takes a vector, not a generator. The guide, the variables paragraph of the `execute_julia_code` descriptions and the docstrings of `find_pane`, `DocumentLocator`, `get_parent`, `describe_reference`, `JsonArray` and `JsonObject` use a neutral example, `items.json` with a name and a price, in place of the data of S2.
- **Take 5 of 2026-09-26** failed: the model followed the system text of the application, `print_natural_text(tab.content)`, which the scroll pane of a file tab broke ("no natural text for WidgetScrollPane"), never read the guide, and spent twenty rounds on the structure by hand; no Frank, no table. Fixed on `file-tab-scrolls` (`print_natural_text` and `get_file_content` see through the scroll pane), and the owner agreed to rewrite the paragraph of the system text (D18 of `the-assistant-reaches-a-referenced-document.md`).
- **Take 6 of 2026-09-26** (`/var/tmp/s2/assistant_window.mp4`, 130.8 s), after the rewrite of the system text: the guide first, `find_pane`, `get_edited_document`, the verbs, `open_pane!` with `target`, `get_parent`, and no data file. Three calls of the model and no error. Read at one frame per second and at full size, every beat is there: the model reads the guide, reads the file (the code closed at about 51–53 s, then the JSON), and adds Frank with `insert_elements!` (the log: "Insert 1 into people.json"); the wheel shows Frank at about 81 s; the click and `Ctrl+Z` take him back at about 85 s (the log: "Ctrl+Z Undo"); the second prompt opens "People" beside the file with the five people sorted by name, and the video ends on the table. Four faults remain:
  1. **The last answer of the model is wrong.** It says "a table of all six records", and its thinking lists "Ada, Bob, Cleo, Dan, Eve, Frank". The table shows five, because the code read the live array. The model did not read the file again after the person's undo, and nothing tells it that the person can edit between its turns.
  2. **The code view writes a pair as a call.** The model wrote `"name" => JsonString("Frank")`, and the block shows `=>("name", JsonString("Frank"))`. `BINARY_OPERATORS` in `source/julia/JuliaParser.jl` holds no `=>`, so the parser makes a `JuliaCall`.
  3. **A long code line is cut at the right edge of the block** (as in take 3), so the ends of the `insert_elements!` and `open_pane!` lines do not show.
  4. The answer of the last call is the whole layout of the window (`show_layout(editor)`), 30 lines that the viewer can not use. Small.
- **The owner's decision after take 6, 2026-09-26:** "Skip fix 3, do 1 and 2". Fault 1: the system text of every assistant (`DEFAULT_ASSISTANT_SYSTEM`, beside the paragraph that says a variable stays bound) now says that the person edits the window between the turns of the model, so a variable of an earlier turn can show something else, and that the model reads a document again before it tells the person what the document holds. Fault 2: at the rebase onto `main` (2026-09-27), `main` already had the same fix from another session (2a6da0f6: a list of the infix operators, `=>`, `in`, `isa`, `%`, `|>` and the broadcast ones among them, and the order of precedence of the Julia manual); that version is kept, and the branch adds that a call of an infix operator with more than two operands, as `a + b + c`, folds to the left and prints as it is written. Fault 3 stays.
- **Take 7 of 2026-09-26** failed, and the recorder hung; no video. Same model, context and seed, with the system text of fix 1. In the first turn the model did not read the guide. It built the new record from `CellVector` and `Cell` by hand, got two errors, and then gave `insert_elements!` a `JsonObject` whose positional constructor put the given `CellVector` inside a second one, so the object held a `CellVector` as an entry. The verb took it. From then on each frame of the file failed ("TypeDispatchingProjection: no projection registered for type CellVector{Cell, Cell}"), and the turn ended at the cap of 8 rounds. Then the recorder stopped: `take_from_devices!` answers nothing while `awaiting_render` is true, a render that fails never clears it, so no frame is written, no entry fires and the cap of the `await` never runs out. The process slept for 18 minutes until it was stopped. Three faults, one in each layer:
  1. **The recorder hangs on a render that fails.** It must go on with the fault on the frame, as a live window does, so a take always ends.
  2. **A document takes an entry of the wrong type.** `JsonObject(CellVector([...]), false)` is accepted, and so is the insert of it; neither says that an entry of a JSON object is a `JsonObjectEntry`.
  3. **The model did not read the guide**, which the system text calls mandatory. With the same seed, a small change of the system text changed the path of the model.
- **The owner's decision after take 7, 2026-09-26:** "Fix a but not b". The recorder now holds the picture when the editor paints nothing (`VideoBackend.jl`). A read that starts after a frame that painted nothing, which it sees in the count of reads that answered nothing since the last paint, holds the last painted picture for that frame: in wall-clock time a copy for each `1/fps` slot up to now, in video time one copy. An entry that waits for its frame takes the held picture as that frame, so the timeline goes on and the take ends with its `WindowQuit`. After a failed paint, the held picture carries a red band across the bottom with the first line of the fault ("The window can not paint: …"), drawn once for each fault over the last painted frame (`_save_picture_with_overlay!` in `Sdl.jl`), or on the background of the window when no paint has worked yet. This covers the three ways a frame paints nothing: a paint that throws, the editor that stops calling `write_to_devices!` after eight failed paints in a row, and a screen with no window. Fault b stays: the JSON object still takes an entry of the wrong type. Found on the way, not in the scope: the pipelines of the application have no `FaultCatchingProjection`, so a printer fault in one file tab reaches the device write and stops the painting of the whole window, in a live window as well.
- **Take 8 of 2026-09-26** (`/var/tmp/s2/assistant_window.mp4`, 768.3 s, recorded in 832.0 s), with the held picture of the recorder and the same model, seed and system text as take 7: the model took the path of take 7 again, call for call, to the same malformed insert, the same failed paint and the cap of 8 rounds. The click in the file was lost, because its reader failed too, so `Ctrl+Z` went to the history of the window and not to the file's. The second prompt was sent: in its turn the model found the broken record, deleted it with `delete_elements!`, tried to insert Frank again in another wrong form, and hit the cap of 8 rounds again. The wait for the second turn then ran to its cap of 600 s, probably because the undo of the window changed the conversation, so the count of turns that the take waits for was not reached. The recorder ended the take: its frames hold the last painted picture with the red band "The window can not paint: TypeDispatchingProjection: no projection registered for type CellVector{Cell, Cell}". The video is not usable. The owner asked for the plan of the fault handling as a separate plan: `plan/pending/a-fault-is-easy-to-see-and-stays-small.md` on `main`.
- **Take 9 of 2026-09-27** (`/var/tmp/s2/assistant_window.mp4`, 108.7 s, recorded in 121.7 s), with the system text that carries the section "Reach what a tab holds" of the orientation guide (`make_application_system`, measured in `plan/pending/a-fast-loop-for-the-assistant.md`), the soft scope of the REPL, and the pair shown as a pair. Seed 1, which failed takes 7 and 8, made three calls, the fewest the screenplay allows: it read the file, made Frank with `JsonObject("name" => …)` and inserted him with `insert_elements!`; in the second turn it read the file again, as the system text says, and built the sorted rows and opened "People" to the right of the file in one call. No fault, no cap. Every beat shows: the insert, the scroll to Frank, `Ctrl+Z` in the log, the five people sorted. One fault remains: the last sentence says "showing all six people sorted by name". The model did not print what it built, and took the count from its first turn ("The array now has 6 entries"). The answer of `open_pane!` it read is the whole tab in the internal form, trimmed, which says nothing of the rows.
- **Take 10 of 2026-09-27: the take that is kept** (`/var/tmp/s2/s2_take10.mp4`, 136.8 s, recorded in 147.9 s), after the owner chose to fix the cause of the wrong count ("Option 2"): the REPL and the answer of a call show a tab by its title and a table by its rows and columns (`PaneTab("People", WidgetTable(5 rows × 3 columns: name, age, city))`, a2ad3898; measured in `plan/pending/a-fast-loop-for-the-assistant.md`). Seed 1 made four calls: it read the file, inserted Frank, then read the file again, built the sorted rows and opened "People" beside the file in one call, and printed the file once more to check it. Its thinking cites the new display ("The table shows 5 rows × 3 columns, which matches the current 5 people"), and its last message says "The \"People\" table is open beside people.json, showing the 5 people sorted by name (Ada, Bob, Cleo, Dan, Eve)", with a note that Frank's addition was undone. Every beat shows: the prompt, the code closed then open, Frank at the end of the file after the scroll, `Ctrl+Z` in the log and Frank gone, the second prompt, the table of five sorted by name. What stays as it is: a long code line is cut at the right edge of its block (the owner: skip), and the answer of the insert is the array in its internal form.
- **The owner's decision, 2026-09-26: the take shows the gesture and operation log as an overlay,** as the take of the JSON type-in does (`--gestures`, the panel of the newest lines first), "so the user who watches the video understands". The viewer reads in it the keys of the person with the operation each made, the operations of the assistant (the open of the tab, the write of "Paris"), and the undo that `Ctrl+Z` makes, so the log shows that an edit of the assistant is an operation like one of the person's. An edit written straight into the document makes no operation and so no line; that is one more reason for D22 of `the-assistant-reaches-a-referenced-document.md`. The panel is at the bottom left (bullet above).

- **The rehearsals of 2026-09-23, with `qwen3.8:27b` on the CPU.** Four turns, none of them opened a tab. The model reads the guides, prints the pane tree with `show_layout`, searches the API, and then spends its rounds on names it can not call (F6) and on field names it guesses wrong.

| The prompt of the user | Seconds | The end |
| --- | --- | --- |
| Open people.json sorted by name in a second tab, beside the first one. | 130 | no tab |
| The same, with the transcript printed | 308 | no tab |
| Show the names and ages from people.json as a table in a new tab. | 103 | no tab |
| Use `open_pane!` to open a tab titled People that holds a `WidgetTable` with the names and the ages. | 160 | no tab |

  The take of the timeline (two prompts, 169 s) shows the same: the model searches, and the window does not change. The harness for a rehearsal is `tool/video/rehearse_assistant.jl`, and it prints every tool call and its answer.

- **The choice this needs:** a model that finishes the task. The owner decides between the local `qwen3.8:27b`, Claude through `ANTHROPIC_API_KEY` (not set in this session), a task small enough for the local model, and waiting until F6 is fixed.

- **The owner's answer, 2026-09-23:** keep qwen, and extend the API of the application so that qwen can do it. What the rehearsals after that showed, and what changed:
  - Every turn ended at the round cap of the agent, which is 8 (`source/kernel/agent/Agent.jl`), and the assistant builds its agent with that default (`source/assistant/AssistantTurn.jl:678`). The model spends the rounds on discovery.
  - `make_application_api` now also declares `DocumentModule => (:search_documents, :get_wrapped_document)`, `FileFormatModule => (:get_file_content,)` and `NaturalModule => (:print_natural_text, :parse_natural_text)`, so a model can read what a tab holds.
  - `APPLICATION_SYSTEM` names the shortest path to a tab's text, and says that the program `show_layout` prints runs whole, because a model copied one line of it without the line that defines `window`.
  - The model called `print_natural_text` on the file document itself, which has no natural text. `print_natural_text(::FileDocument)` in `source/fileformat/DocumentFile.jl` now answers the text of what the file holds, through its history.
  - **Not yet tested.** The rehearsal after the last change was stopped, see the next point.
- **The whole computer crashed during a rehearsal on 2026-09-23.** The model needs 17 GB outside the memory cap of Julia, and the VS Code language server (9 GB) and other sessions' Julia runs were active. A rehearsal starts only when `free -g` shows at least 47 GB available: 20 GB for the capped Julia, 17 GB for the model, and 10 GB of margin. The check runs before each rehearsal, not once.

- **Acceptance:** both prompts succeed in the kept take. Beat 4 needs the window history to hold a change that the assistant makes to the panes. Step 6 checks that first. If the history does not hold it, beat 4 changes to an edit of the data, and this plan records why.

#### S3. JSON from nothing

- **Feature:** a structural editor. A key makes a typed element, not a character: `{`, `[`, `"`, `,` and Tab.
- **Claim:** edits are typed operations on the data, and F1 and the command palette list what works where you are.
- **Setup:** the single-document recorder (`record_live_example`), 900×720, with no menu bar, no toolbar and no tabs. The owner keeps it so (2026-09-25): the take shows the editor called with one document and one projection.
- **The take of 2026-09-22.** Recorded: 900×720, 767 frames, 25.6 s, 92 KB, with the human rhythm of D13. The build is `{"name": "Alice", "age": 30, "city": "Wonderland", "address": {"street": "12 Rabbit Lane", "zip": "12345"}}`, and every one of its 84 keys answers an operation, which the script checks headless before it records.

  **The take of 2026-09-23, caret only.** With F2 and F3 fixed (`plan/done/structural-keys-from-the-caret.md`), on the branch rebased on `main` at cc041a4f: 900×720, 1014 frames, 33.8 s, 134 KB, `build/video/json_from_nothing_caret.mp4`. The build is `{"name": "Alice", "age": 30, "city": "Wonderland", "address": {"street": "12 Rabbit Lane", "zip": "12345"}, "tags": ["admin", "editor"], "active": true}`, and all 123 keys answer an operation. No key selects structure: `Right` leaves a string, a `,` after a number adds the next entry at once, and five presses of `Right` carry the caret from the last string of `"address"` and of `"tags"` past the closing `}` or `]`, where the `,` adds the next root entry. A bool comes last, because the caret can not leave a bool (F7).

  **The take of 2026-09-24, with the gesture panel.** The owner asked for the caret-only take with a gesture overlay, and chose option A: each key with the operation it made. `record_json_from_nothing.jl <output> --gestures`: 1280×720, 32.2 s, `build/video/json_from_nothing_gestures.mp4`, 115 keys, none dead. On the owner's word, one `Down` leaves a nested container where five presses of `Right` did: the line of the closing `}` or `]` holds nothing else, so `Down` puts the caret after the brace. `json_build_live` does the same. Also on the owner's word, the take starts from `JsonNothing`, which draws `empty json`, and not from a whole-selected `JsonInsertion`, whose name buffer drew `insert a new  here` with no caret; `{` on the placeholder makes the object (31.9 s). The value of a fresh entry is still a `JsonInsertion` (`@insertion JsonObjectEntry`), so `insert a new  here` shows after each `{` and `,` until the value is typed. The recorder of the gesture log sits at the root and the panel at the bottom right, eight lines, newest first; a selection move is kept and drawn muted, so the presses of `Right` show. Two display faults of the log were fixed for it: a caret on a delimiter printed the raw data of its projection step, and now prints short (`select .entries[4].value‹.close{0}›`); and a line can be cut to a number of characters (`operation_width`, 60 here), so the panel stays beside the JSON. The panel measures its text with `measure_sdl_text` (F9).

- **Beats that wait for F1:** the three below need the window of the application, so they are not in this take.

| # | Action | On the screen | Caption |
| --- | --- | --- | --- |
| 1 | Press F1. | The keys that work at the selection. | F1 lists the keys that work here, from the projections in use. |
| 2 | Press Ctrl+Shift+P, type `sort`, Enter. | The entries of the object sort by key. | A rule with no key is found by its name. |
| 3 | Press Ctrl+Z. | The old order comes back. | |

- **Acceptance:** the video lasts at most 60 s, and every key of the timeline answers an operation. The script replays the timeline headless first, and it records only when no key did nothing. Where `json_build_live` is long, the typed values are shortened.

#### S4. A tool window from widgets

- **Feature:** a widget is a document. The evaluator makes one, a tab shows it, and each `push!` adds a widget to the tab while it runs. A widget that reads a cell follows it with no callback.
- **Claim:** you can design a tool window without a GUI toolkit.
- **Setup:** `bin/projectured notes.json`, 1280×720. The file gives the window a wide pane, and the evaluator opens beside it with `Ctrl+T`, `Insert`, `repl`. With no file, a new tab lands in the narrow column of the navigator.
- **Beats, as the take of 2026-09-22 runs them.** Each form is typed and runs on Enter. A form that changes the tool ends with `tool`, so the newest result row shows the whole tool, as S1 does with its canvas.

| # | The form | On the screen |
| --- | --- | --- |
| 1 | `presses = Cell(0)` | a `=` row |
| 2 | `live(text) = set_cell_function!(WidgetLabel(Point2D(0, 0), ""), text)` | the helper that makes a label follow a thunk |
| 3 | `button = WidgetButton(Point2D(0, 0), Point2D(160, 36), "Press me"; action = () -> presses[] += 1)` | the button draws in the result row |
| 4 | `tool = VerticalLayout(Any[button]; gap = 12)` | the tool, with one widget |
| 5 | `push!(tool.children, live(() -> "Pressed $(presses[]) times")); tool` | the label under the button |
| 6 | `slider = WidgetSlider(Point2D(0, 0), 0.3); push!(tool.children, slider); tool` | the slider |
| 7 | `push!(tool.children, live(() -> "Slider at $(round(slider.value; digits = 2))")); tool` | the label that reads the slider |
| 8 | `name = WidgetText(Point2D(0, 0), "Ada"); push!(tool.children, name); tool` | the text field |
| 9 | `push!(tool.children, WidgetTable(Point2D(0, 0), ["what", "value"], [["presses", live(…)], ["slider", live(…)], ["name", live(…)]])); tool` | the table, whose value cells are live labels |
| 10 | `presses[] = 3; tool` | the label and the table say 3 |
| 11 | `slider.value = 0.8; tool` | the knob moves, and the label and the table say 0.8 |
| 12 | `name.content = "Ada Lovelace"; tool` | the field and the table say the new name |
| 13 | `open_pane!(editor, tool; title = "My tool")` | the tool takes a tab of its own |

- **The take of 2026-09-22.** 1280×720, 166 s, 1.3 MB. The script is `tool/video/record_widget_tool.jl`.

  What the work settled: a `WidgetComposite` puts every element at one place, so the table covers the rest; the column is `VerticalLayout(Any[…]; gap)`, and its field is `children`. A thunk passed to `WidgetLabel` is drawn as the function, so a live label is made with `set_cell_function!`. `WidgetProgressBar` takes a number and no function, so the video uses a second live label in its place. `open_pane!` moves the focus to the new tab, so it comes last, after the typing is done.

- **The pointer beats wait for F4.** Beats 6, 8 and 10 of the first draft (three presses of the button, a drag of the slider, a character in the field) are not in this take. The button lights up under the pointer, and its action never runs, because the closure belongs to the world of the evaluator (F4 of §2.4). The take shows the same reactivity with a write from the evaluator, which is beats 10 to 12.

- **Acceptance:**
  - Every form runs with no error, which a headless replay checks before the recording.
  - The video lasts at most 3 min (D5).
  - When F4 is fixed, the pointer beats come back, and the writes of beats 10 to 12 make way for them.

### Tier 2

#### S5. A sorted view that takes edits

- **Feature:** a sort is one more projection in the chain, and an edit in the sorted view goes back through it.
- **Setup:** one list in two tabs side by side: the left one in the order of the data, the right one through a `SortingProjection`. The `sorting` example has the projection. Step 8 finds how the application opens the second view.
- **Beats:** change a value in the right tab so that its element moves to a new sorted place. The left tab shows the new value in the old place. Remove the sorted view: the data kept its order.
- **Acceptance:** the edit in the sorted view works in the application today. If it does not, the video waits and the post changes its claim.

#### S6. The same object in two places

- **Feature:** Ctrl+N notes a part, and a paste puts the same object in a second place. Ctrl+Shift+V pastes a copy.
- **Setup:** a JSON document with two people, one of them with an `address` object.
- **Beats:** note the address, paste it as the address of the second person, change the city in one place: both places change. Paste a copy with Ctrl+Shift+V into a third place, change it: only that one changes.
- **Acceptance:** both pastes work with the keys of the application. Save and load of the shared object is not in this video.

#### S7. The editor is reflective

- **Feature:** the window is a value. The evaluator walks from `editor` to the parts of the window and shows each part as itself. A part that the evaluator shows still works: the toolbar opens a tool, the explorer opens a file, and an edit of a document in one view shows in the other view.
- **Claim:** the editor is made of documents, and the evaluator reaches all of them, the editor itself too.
- **The screenplay of the owner, 2026-09-26:** evaluate `typeof(editor.document)`, go down with the properties and `typeof` to the toolbar, and evaluate it: the toolbar appears in the evaluator, and a click on it works. Search for the files pane and evaluate it, and open a JSON file from it. Find the document of the JSON file, move the JSON tab so that the evaluator and the JSON tab are both visible, and edit a string: both views change. On the same day the owner accepted these changes:
  - `propertynames` shows the fields on the way down.
  - The press is on a toolbar button that has an effect that the viewer can see.
  - The tab is dragged before the search for its document.
  - The edit goes in both directions, and a `Ctrl+Z` ends it.
  - A form adds a button to the toolbar, and the real toolbar and its copy change together.

  This screenplay takes the place of the reflection view that S7 held before.
- **Do not evaluate a container of the evaluator.** The evaluator draws a `Document` result as itself (`source/conversation/Evaluator.jl`, `evaluate_operation`). `editor.document` and `editor.document.content` both hold the evaluator, so their result would draw the window inside itself. That is why the way down uses `typeof` and `propertynames`.
- **Setup:** `bin/projectured` over a folder that holds `people.json`, 1280×720, with no assistant. The Files pane is on the left.
- **Beats:**

| # | Action | On the screen | What the viewer learns |
| --- | --- | --- | --- |
| 1 | Hold, then click the Evaluator button of the toolbar. | The evaluator opens in a tab. | |
| 2 | `typeof(editor.document)`, then `typeof(editor.document.content)` | `WidgetShell` | `editor` is this window, and it is a value. |
| 3 | `propertynames(editor.document.content)` | `(:content, :menu_bar, :toolbar, :status_bar, :context_menu)` | The parts of the window are fields. |
| 4 | `toolbar = editor.document.content.toolbar` | The toolbar draws in the result row. | |
| 5 | Click "Gesture log" in the copy. | The gesture log opens in the window, with the click on the copy as its newest gesture. | It is the real toolbar. |
| 6 | `push!(toolbar.elements, WidgetToolbarItem("Hello"))` | A "Hello" button appears in the toolbar of the window and in its copy. | Code changes the editor itself. |
| 7 | `files = first(search_documents(editor.document, d -> d isa Workspace))` | The explorer draws in the result row. | A search finds a part of the window. |
| 8 | Double-click `people.json` in the copy of the explorer. | A tab opens. | It is the real explorer. |
| 9 | Drag the new tab to the right edge. | The evaluator on the left, `people.json` on the right. | |
| 10 | `json = first(search_documents(editor.document, d -> d isa JsonFile))` | The JSON document draws in the result row. | |
| 11 | Edit a name in the tab, then another name in the result row. | Each edit shows in both views. | One document, two views. |
| 12 | `Ctrl+Z` in the tab, then hold. | Both views go back. | |

- **The rehearsal of 2026-09-26**, ten takes in video time in one warm session, typed fast; the checks print from `await` entries. Every beat works in the program as it is:
  - `editor.document` is a `ScreenDocument` (`windows`, `selection`), so the walk goes through `windows[1]`: `ScreenDocument` → `WindowDocument` → `ClipboardSlice` → `WidgetShell` → `toolbar`. The toolbar is `editor.document.windows[1].content.content.toolbar`, and its result row is the same object (`===`).
  - The copy of the toolbar is live: a press on Frame plot opens a real Frame plot tab in the group of the evaluator, which then covers the evaluator, so the take presses the Evaluator tab to go back. `push!(toolbar.elements, WidgetToolbarItem("Hello"))` adds a "Hello" button to the toolbar of the window and to its copy.
  - The search finds the explorer of the Files pane (`===`), and a double-click on `people.json` in the copy opens a real tab. The double-click also selects that row in both views, because they show one document; a press on the Evaluator tab then brings that selection back, and an Enter would open the file a second time. So the take clicks the prompt line before it types.
  - A drag of the tab to the right edge splits the window; the left group then shows `README.md`, and the take presses the Evaluator tab again. The JSON search finds the document of the tab (`===`).
  - An edit in the tab and an edit in the result row each show in both views, and the caret shows in both. Each edit is one entry of the `UndoBuffer` inside `JsonFile`, and the window buffer records it too; two presses of `Ctrl+Z` in the tab take both edits back in both views.
  - A count with `search_documents` after an undo is wrong: it also finds the old text in `redo_entries`. Check an undo on a frame.
  - `people.json` holds three people, because five do not fit in the result row of a pane that is 512 px wide.
- **Decided by the owner after the rehearsal, 2026-09-26:**
  - A type result showed its cell parameters: `WindowDocument{Cell, Cell, …}` held the word `Cell` 14 times. The forms use `nameof(typeof(…))`, so the results read `:ScreenDocument`, `:WindowDocument` and `:WidgetShell`.
  - The result of `push!` is the `CellVector` of the buttons, which drew as a column of nine icons, 300 px high. The form ends with `;`, and the evaluator hides the value of such a form, as the Julia REPL does (`plan/pending/evaluator-semicolon-and-infix-operators.md`). The same plan makes the two forms with `d -> d isa …` Julia documents, so every form of the take draws in the colors of the Julia notation.
- **The take of 2026-09-27**: `tool/video/record_reflective_editor.jl`, 1280×720, 136.8 s, 1.7 MB, recorded in video time in a warm session after a fast run of the same script (`PROJECTURED_TAKE_FAST=1`), so no step compiles during the take. It was recorded on the branch rebased on `main` at 15b40434, where a file tab shows its file in a scroll pane. It is `build/video/s7/s7_reflective_editor.mp4` of the main checkout, and `assets/videos/reflective-editor.mp4` of the web page. The code is typed in short runs (a name, a call up to its `(`, an argument up to its `,`), 0.13 s a key with a jitter of 0.4 and 0.25 s between the runs. The folder is named `team`, because both explorers show its name.
  - Beat 5 presses Gesture log, not Frame plot. The Frame plot of a take showed frames of 25 to 120 ms, and that time includes the work of the recorder, which draws each frame at twice the size and saves it; the owner chose the other tool on 2026-09-27. The gesture log lists the click on the copy of the toolbar as a gesture like any other.
- **Acceptance:**
  - Beats 5 and 8 work from the copy in the evaluator. No test did this before this video. If a click fails, it is a product gap to fix, not a reason to change the beat.
  - `search_documents` also walks the undo buffer. The rehearsal checks with `===` that each search finds the object that the window shows.
  - The video lasts at most 3 min (D5), and it types with the rhythm of D13.

#### S9. The editor from a plain Julia REPL

- **Feature:** ProjecturEd is a library. A person opens a window on a value from their own REPL, edits it, closes the window, and the value is there in the session, richer than before.
- **Claim:** it is also a generic user interface for your own Julia program.
- **The owner's words, 2026-09-22:** "demonstrate how to use the editor from the original Julia repl. Start from a text document, then syntax, then json, then widget warp, then add XML, each time exit to repl and start over."
- **Setup:** a terminal with `julia --project=environment/all` beside the window that each round opens. One REPL session holds all five rounds, so each round builds on the value of the round before it. This video needs a capture of the screen (G6), because the terminal and the window are two programs.
- **Beats:** five rounds. Each round is: type a few lines in the REPL, a window opens, edit in the window, close the window, and the REPL prompt is back.

| Round | In the REPL | In the window |
| --- | --- | --- |
| 1 | a text document, and `run_window_editor(document, NaturalToGraphics(measure = measure_truetype_text), "Text"; backend = SdlBackend())` | type a word into the prose, then close the window |
| 2 | a syntax tree of the same content | walk the tree, open and close a node |
| 3 | `parse_natural_text(:json, "{\"name\": \"Alice\"}")` | edit a value, add an entry |
| 4 | wrap the JSON of round 3 in a widget: a card with a title, and the JSON as its content | the card holds the live JSON, and an edit in it still works |
| 5 | put an XML element in the document of round 4 | the caret crosses from the widget into the XML and back |

- **Acceptance:**
  - Each round runs from a REPL that the viewer sees, with no file of the repository and no helper of the examples: only the public API.
  - After each round the REPL prompt is back and the value of that round is still bound, so the next round builds on it.
  - The step writes the real lines of each round here, after it has run them.

#### S8. Two domains in one document

- **Feature:** a document of one domain holds a document of another, and navigation and editing cross the boundary.
- **Setup:** the `mixed` example: a JSON object that holds an XML article (`example/xml/MixedDocumentExample.jl`).
- **Beats:** the arrow keys move the caret from a JSON string into the XML text and back. Type a word in an XML paragraph. Press F1 inside the XML and inside the JSON: the lists of keys differ.
- **Acceptance:** the caret crosses the boundary in both directions. A second take can use the Julia function with an XML body of the web page, after Step 8 makes that document again as an example (G5).

#### S10. Only what changes is drawn again

- **The owner's words, 2026-09-25:** "show the partial render and the dirty rectangle for navigation only causes a small box to be re-rendered and for editing text only causes the edited paragraph to be re-rendered, this is a demonstration of reactivity and laziness/incrementality".
- **Feature:** a change computes again only the cells that depend on it, and the backend repaints only the region that changed.
- **Claim:** the editor is reactive and incremental. A move of the caret repaints a small box, and a typed character repaints only the paragraph that holds it.
- **Setup:** a text of several paragraphs, with `partial_render` and `debug_dirty` on: the SDL backend has both (`source/sdl/Sdl.jl`), and `debug_dirty` outlines the repainted region in red. `VideoBackend` has neither, so the recorder must first repaint partially and draw the outline, or the take records the SDL window from the screen (G6, as S9 needs).
- **Beats:** the arrow keys move the caret through a paragraph: a small red box at the old and at the new place of the caret. A word is typed into the second paragraph: the red box covers that paragraph and nothing else.
- **Acceptance:** in each frame of the take, the outline covers only the two caret boxes on a move, and only the edited paragraph on a key.
- **The take of 2026-09-26**: recorded with `record_application_video(...; partial_render = true, debug_dirty = true, debug_dirty_hold = 0.6)` over `example/markdown/paragraphs.md`, 30.4 s, `build/video/s10/s10_partial_render.mp4` of the worktree `projectured-julia-paragraph-partial-render`, recorded by `build/video/s10/take.jl` there. Each key outlines the edited paragraph and the status line, which shows where the caret is; the key that makes the paragraph one line taller, or shorter, outlines the paragraphs below it too. How it was made to work is in `plan/done/paragraph-partial-render.md`. On the web page it is `assets/videos/partial-render.mp4`, the fourth video of the Videos section (commit `364adfb` of `projectured.github.io`).
- **The owner's words for a second take, 2026-09-26:** "can we remove the status line for this video? some move over the toolbar to show highlights, some move over the navigator to show highlights, we need a bit of a clicking in the navigator collapse/expand to show how the change is drawn, some up/down navigation in the text, some ctrl+left/right, some more idea to show how partial render works? the typing should come at the end, the text should explain some details how it works".
- **The second take** (on the branch `partial-render-video`):
  - [x] `make_application_window` and `record_application_video` take `status_bar = false`, which leaves out the status bar. It changes with every move of the caret, so it added a red box at the bottom of each frame.
  - [x] The page in the video explains how the repaint works: the cells, the hover cell of a button, the walk and its three kinds of change, the set of rectangles, the container that does not read the size of its children, the caret, and the chain of each paragraph.
  - [x] The navigator lists `example/`, so a folder in the middle of the list can open and close.
  - [x] The beats, in this order: the pointer moves over the toolbar, then over the rows of the navigator; a folder opens and closes; a click puts the caret in the text; Up and Down move it by a line, and Ctrl+Left and Ctrl+Right by a word; the typing comes last. The script is `build/video/s10/take2.jl` of the worktree `projectured-julia-partial-render-video`; the first take of it is 54 s.
  - [x] **A hover in the toolbar painted the whole window again** (found in a draft take). A toolbar item drew its hover layer in the cell that also computes its size and its element list, so a hover made the toolbar lay out its items again, and the shell computed again the height that it offers to the content. Fixed: the hover layer of a toolbar item, a menu item and a button is always there, and its size and color are cells of their own, as the focus ring reads the selection; the toolbar and the menu compute their extent from the sizes their items state. The list widget keeps its hover in its build cell, because its hover is a row index.
  - [x] **The outline of a click stayed through the pause after it.** With `debug_dirty_hold`, the outline of the last repaint stayed until the next repaint. It now ends with its hold.
  - [x] **A folder that opens or closes paints the whole navigator again.** The tree made new row graphics for every row on a toggle, every folder row read the set of open folders for its chevron, and the walk painted a container whole when its element list changed. The owner chose on 2026-09-27 to fix it, and to add a scroll step: `plan/done/folder-toggle-repaint.md`. A toggle now paints the chevron and the rows from the folder down.
  - [x] **The final take**: `build/video/s10/take4.mp4`, 59.3 s, with the wheel over the navigator after the folders, recorded on the branch rebased onto `main`. A take with a full repaint and one with the partial repaint of the same timeline draw the same 684 frames (`build/video/s10/check2.jl`). On the web page it replaces the first take (commit `cee5b5e` of `projectured.github.io`).
  - Found in the draft, and not in the take: in a Markdown file, Down on the last line of a paragraph does not go to the next paragraph, Shift+Ctrl+Right does not extend a selection, and Enter in a paragraph makes no operation.

#### S11. Only what you look at is computed

- **Feature:** a document can be infinite. The view asks only for the rows that it shows, and the list computes only the rows that the view asks for. A list made from a lazy list is lazy too.
- **Claim:** laziness is visible. A count beside each list says how many of its nodes exist, and it grows only when the view reaches new rows.
- **The owner's idea, 2026-09-27:** the sieve of Eratosthenes of the examples, made in the evaluator and shown in a scroll pane; first a list that is infinite in one direction, then one that is infinite in both; a list that skips its first N elements, or a subsequence made by a filter. "The goal is to demonstrate the laziness." On the same day the owner accepted this proposal:
  - A count of the computed nodes is the proof on the screen. Without it, a lazy list and a list that was computed before the take look the same.
  - The evaluator holds the forms, and each list opens in a scroll pane of its own beside the evaluator, as the results of S1, S4 and S7 do. A result row is narrow, it scrolls inside the scroll pane of the evaluator, and the evaluator follows its end.
  - The sieve is the first list. Programmers know it, and one form defines all the primes.
  - The far jump and the list that is infinite in both directions are the primes around one trillion, not the negative primes of `make_lazy_bidirectional_document_example`. Each prime of the sieve depends on all the primes before it, so a skip of N primes computes N primes; and the negative primes are a mirror that means nothing, whose node chaining the test file says has faults. A prime around one trillion is found by a test of that number alone, so the list starts in the middle and costs only the rows on the screen, in both directions.
  - The filter is in: the primes that end in 7 are a lazy list made from the lazy sieve, and when it scrolls, both counts grow.
- **Setup:** `bin/projectured`, 1280×720, with no assistant, and the evaluator open in a tab. The lists open to its right.
- **Beats:**

| # | Action | On the screen | What the viewer learns |
| --- | --- | --- | --- |
| 1 | `primes = sieve(integers_from(2));` | The form runs, and no result row shows. | One line defines all the primes. |
| 2 | A form opens `primes` in a pane to the right of the evaluator. | A card with the title "Primes, computed: N" over a scroll pane of 2, 3, 5, …; N is about the number of rows that fill the pane. | Only what the pane shows is computed. |
| 3 | Scroll down three screens, then back to the top. | N grows while the pane shows new rows, and stays the same on the way back. | The count follows the view, and a node is computed once. |
| 4 | `sevens = lazy_filter(primes, p -> p.value % 10 == 7);`, and a form opens it under the first pane. Scroll it. | 7, 17, 37, 47, …; the counts of both cards grow. | A lazy list made from a lazy list pulls only what its view needs. |
| 5 | `around = make_primes_around(10^12);`, and a form opens it. Scroll up, then down. | The first prime after one trillion, with the smaller primes above it and the larger ones below; its count stays small. | A far start costs only the rows on the screen, in both directions. |
| 6 | Hold on the three cards. | | |

- **Acceptance:**
  - The count never computes a node: it walks only the nodes whose cells are up to date. Check it with a count taken before and after the take draws a frame without a scroll.
  - The sieve scrolls a few hundred primes at most. Each prime adds one filter to the chain of the stream, so a far scroll makes the chain deep and slow.
  - The video lasts at most 3 min (D5), and it types with the rhythm of the S7 take.
  - The product work is in `plan/done/lazy-list-video.md`.
- **The take of 2026-09-27**: `tool/video/record_lazy_primes.jl`, 1280×720, 92.2 s, recorded in video time in a warm session after a fast run of the same script. The forms, as typed: `using ProjecturedSubstrateExample;`, `primes = sieve(integers_from(2));`, `show_lazy_list!(editor, primes, "Primes");`, `sevens = lazy_filter(primes, p -> p.value % 10 == 7);`, `show_lazy_list!(editor, sevens, "Sevens");`, `around = make_primes_around(10^12);`, `show_lazy_list!(editor, around, "Around one trillion");`. The counts in the take: Primes 31 when it opens, 126 after thirty steps of the wheel and the same after the way back, 251 after Sevens scrolls; Sevens 15, then 62; Around one trillion 17, 26 after three steps up, which show the crossing of one trillion, and 64 after fifteen steps down. The take is `build/video/s11/s11_lazy_primes.mp4` of the main checkout, and `assets/videos/lazy-primes.mp4` of the web page, after the S7 article.
  - **Open for the owner:** a form whose value is a list with no end, with no `;`, gets a result row one line high, and the rest of the list draws over the next prompt. A result whose graphics have no end needs a bounded window, such as a scroll pane of a fixed height, and that changes how a `result` path maps through the result row. See `plan/done/lazy-list-video.md`.

#### S12. A setting takes effect at once

**Accepted by the owner on 2026-10-03.** The owner reviews each take before the next one starts. S12 came first; after its review the owner said "do S14 first", so S14 comes before S13. The owner asked for a settings video, and said that it does not have to be complicated.

- **Feature:** the settings page of the editor. Each setting says what it sets, and a change takes effect while you look.
- **Claim:** a setting is a value with its own text, and the window follows it at once; `Ctrl+Z` takes a setting back like an edit.
- **Setup:** `bin/projectured` over a folder with `README.md` open, 1280×720, with no assistant.
- **Beats:**

| # | Action | On the screen | What the viewer learns |
| --- | --- | --- | --- |
| 1 | Click the Settings button of the toolbar. | The Settings tab: a card for each group (Fault, History, Pointer, Render, Start), and the text of each setting under its row. | Each setting says what it sets. |
| 2 | In the Render card, turn on "Partial render", then "Repaint outline". | | |
| 3 | Move the pointer over the toolbar, the tabs and the switches. | A red outline around each part that the window paints again. | The change takes effect at once. |
| 4 | Press `Ctrl+Z` twice, and move the pointer again. | Both switches are off, and no outline shows. | A setting is taken back like an edit. |
| 5 | Hold. | | |

- **What exists** (found on 2026-10-03): the toolbar button and the View menu open the settings of the running editor; the cards come from the `@settings` declarations and their docstrings; a switch writes the setting and applies it to the backend at once; a history around the tab takes back a change (`plan/done/editor-settings.md`, D14).
- **Checks before the take:**
  - Open the page from the toolbar, not by typing `settings` into an empty tab: a typed name makes a new `Settings()` that the editor does not read, so a change there does nothing.
  - The repaint outline holds 0 s by default, so an outline lasts one frame. "Outline hold" can give it 0.6 s, as in S10, or the take sets it in the same beat.
- **The owner's review of the first take, 2026-10-03:** "looks good, add gesture overlay, do less movement on the toolbar for showing the refresh, it's a bit too much". The second take rests on three buttons with the outline on and on two after the undo, and shows the panel of the newest gestures at the bottom right.
  - The application window had no way to show the existing `GestureLogOverlayProjection`: its `gesture_log` wrapper only records into the log of the session, and the recorder lost its hook to wrap the projection when the window came to be built from the wrappers of `build_editor`. So the `gesture_log` wrapper takes `(; overlay = true, anchor, lines, measure, operation_width, background)`: it puts the existing overlay over the content, with a log of its own of `lines` entries, and `record_application_video` takes `gesture_overlay = true`. Test: `test_window_wrappers()`, 43 pass.
  - The overlay is black at 72% by default, and the text of the Settings page showed through its lines, so the panel of the wrapper is an opaque gray of the same shade by default.
- **The second take of 2026-10-03**, accepted by the owner the same day: 26.7 s, the same file. It is on the web page as `assets/videos/settings.mp4`, after the S10 article. **The first take of 2026-10-03**: `tool/video/record_settings.jl`, 1280×720, 36.5 s, recorded in video time in a warm session. It is `build/video/s12/s12_settings.mp4` of the worktree `projectured-julia-s12-settings-video`. What the rehearsal settled:
  - The Settings button is the tenth of the toolbar, after Appearance. The page opens in the group of the file, and twelve steps of the wheel bring the Render card into view.
  - One press on the `+` of "Outline hold" gives 0.5 s, so the take sets the hold in beat 2.
  - A hover is drawn, and so outlined, only when the pointer rests on a button: a glide of 0.04 s a step draws no hover. The take rests 0.5 s on each button and on each tab.
  - Three presses of `Ctrl+Z` take back the hold, the outline and the partial repaint, in that order; the focus stays in the Settings tab while the pointer rests on the toolbar.
  - Seen in the take, for the owner: the cards are not all as wide as the pane (Fault and History are narrower than Pointer and Render); and a press on a switch outlines the Start card too, under the Render card.

#### S13. The look of every part is a value

**Accepted by the owner on 2026-10-03.** The owner reviews each take before the next one starts. S12 came first; after its review the owner said "do S14 first", so S14 comes before S13. The owner asked for an appearance video, and said that it does not have to be complicated.

- **Feature:** the appearance page. Every color, font and size of the editor is a value of a theme, and a change shows in the open documents while you look.
- **Claim:** the look is data. The page is made from the themes themselves, so each style has its text, and an edit of a style is an edit like any other.
- **Setup:** `bin/projectured` over a folder with `people.json`, 1280×720, with no assistant. The file is on the left, and the Appearance tab opens on the right.
- **Beats:**

| # | Action | On the screen | What the viewer learns |
| --- | --- | --- | --- |
| 1 | Press `Ctrl+,`. | The Appearance tab: the rows Zoom, Text, Icons, Spacing, Controls, Corners and Lines, and a card for each theme. | |
| 2 | Press `Ctrl+Alt+=` twice, then `Ctrl+Alt+0`. | All text grows, the Text row reads 125%, and then it is back. | One step changes every text of the window. |
| 3 | Open the Json card. | A row for each style of JSON, with its text under it, for example "The key of an object member, with its quotes." | The page is made from the theme. |
| 4 | Type a new color into the field of "Key text". | The keys of `people.json` change color at once. | A style is a value, and the document follows it. |
| 5 | In the Widget card, choose the preset "Slate dark". | The whole window turns dark. | |
| 6 | Press `Ctrl+Z` twice. | The dark preset and the key color go back. | A change of the look is a step of undo. |

- **What exists** (found on 2026-10-03): `Ctrl+,`, the toolbar and the View menu open the tab; the cards come from the 29 `@theme` declarations and their field docstrings; a color is a swatch and a field of hex text; the presets "Slate light", "Slate dark", "Light" and "Dark" exist for the Widget theme only; a theme edit is a step of undo, and a zoom or scale step is not (`plan/done/zoom-and-theme-controls.md`).
- **Checks before the take:**
  - Beat 5: only the Widget theme has a dark preset, so the colors of JSON stay the colors of a light page. If the document looks wrong on a dark window, that is a product gap to show to the owner, and beat 5 waits.
  - Beat 2: a scale step is not undone by `Ctrl+Z`, so the beat resets it with `Ctrl+Alt+0`.
  - The tab opens in the group of the file. The take drags it to the right edge, as in S7, or the window is prepared with the split.
- **The first take, 2026-10-03:** `tool/video/record_appearance.jl`, 1280×720, 49.4 s, recorded in video time in a warm session after a fast run of the same script (`PROJECTURED_TAKE_FAST=1`). It is `build/video/s13/s13_appearance.mp4` of the worktree `projectured-julia-s13-appearance-video`, branch `s13-appearance-video`, from `main` at c01c21bff. The branch `default-look` (37 commits, not on `main`) changes the default fonts and spacing; the take shows the look of `main`, and the owner wrote in that plan that the videos do not have to match the new look exactly. Each check of the take prints the look after its beat, and all four pass: text 125%; keys `#dc322fff`; background `#020617ff`; after two undos the keys `#268bd2ff` and the background `#f1f5f9ff`. What the rehearsals settled:
  - **Fault fixed, with a test:** `record_application_video` gave no appearance to the projection, to `build_editor`, to the windows that it opens, nor to the wrappers, so each made an `Appearance` of its own. The tab and the keys changed one that no view drew with: the text did not grow, and the tab had no Widget and no Json card (its appearance held only the Gesture help, Syntax and Text themes). The recorder now gives one default `Appearance` to each place, as `run_application` does (`appearance` keyword; `test_application_video`, the new test set passes; the fault band test fails as on `main` since 2026-10-01).
  - `Ctrl+,` opens the tab in the group of the file; a drag of the tab from (207, 95) to (1240, 400) puts it in the right half. `Ctrl+Alt+=` gives 110% and then 125%, every text of the window grows, and `Ctrl+Alt+0` gives 100% again. A scale step makes no line in the gesture panel.
  - The cards: Editor (Widget, Text, Syntax, Reference), Tools (Fault, File system, Frame statistics, Gesture help, Gesture log, Help, Inspector, Message log), Documents (Book, Chart, Graph, Json, Julia, Markdown, Math, Rst, Sql, Xml, Yaml). A wheel step of 6 scrolls the tab 138 px, the same in each run and with any time between the steps; 17 steps put the chevron of the Json card at (686, 235).
  - The row of a colour is a swatch and a hex text that overtypes: a typed digit replaces the digit after the caret and writes the theme when the text names a colour, and Backspace changes nothing. The digits typed after one click are one step of undo. The take types `dc322f` after the `#` of "key text" (888, 517): the keys turn pink at the first digit and red at the last.
  - "Slate dark" (765, 414) turns the whole window dark, and the colours of JSON stay readable on it, so the check of beat 5 passes. The preset is one step of undo, so two presses of `Ctrl+Z` take back the preset and then the colour. The presets show no chosen button, because a choice writes the preset and keeps no state.
  - In one rehearsal the last frames showed "Slate dark" at y = 361, but a click there right after the wheel hit the summary of the card; the frame at the moment of the click showed it at y = 414, and a click there hits. The checks of the take are what tell that each click hit.
- **The owner's review of the first take, 2026-10-03:** "looks good, but there are issues: the zoom at the beginning cannot be understood, you should click on the buttons instead, and show the different scales and their effect. Retake."
- **The second take, 2026-10-03:** the same script, 1280×720, 100.2 s, `build/video/s13/s13_appearance_take2.mp4` of the worktree (the first take stays beside it). Beat 2 is now clicks on the buttons of the tab: the Widget card opens first, so its four presets show what a control is; then for each scale some clicks on its "+", a rest of 2 s on the largest value, and its "Reset". Text to 150% and Spacing to 150% grow the whole window, the file too; Icons to 175% grows the toolbar and the chevrons; Controls to 175% grows the radio buttons of the presets; Corners to 250% makes the buttons round; Lines to 300% makes every border thick. The gesture panel is at the bottom left, so it covers no button of the tab, and the status bar is off. Ten checks print the look after each step, and all pass. What the rehearsals settled:
  - A step of Text, Spacing or Lines moves the buttons of its own row and of the rows below, so each click has its own place, read from the drawn texts of the window (a probe walks the graphics of the last print). The places are in `SCALE_CLICKS` of the script.
  - The Zoom row is not in the take: the video backend draws every frame at one density, so a step of the zoom changes the percent and nothing else. In a window the SDL backend draws at the density times the zoom.
  - One step of the wheel before Controls brings the presets into view and moves the rows up by 69 px; one step after Lines takes the tab back to its top.
- **The third take, 2026-10-03:** the owner asked for the zoom too ("yes, do the zoom too"). `build/video/s13/s13_appearance_take3.mp4` of the worktree, 1280×720, 106.7 s. The scale beat starts with the Zoom row: three clicks on its "+" give 110%, 125% and 150%, and the whole window grows, the toolbar, the menu and the gesture panel too, as in a live window; "Reset" gives 100% again. Then Text, which grows only the text, so the two differ on the screen. Eleven checks print the look after each step, and all pass.
  - **The recorder change** (595a63fa6, with a test): the video backend keeps the `Display` of the editor in `configure_devices!`, as `SdlBackend` does. At a new zoom the window gets the size of the frame over the zoom, and the offscreen renderer draws its content at the density times the zoom (`with_offscreen_zoom` of `ProjecturedSDL`), so the frame shows it larger. A point of the timeline is a point of the frame: an event reaches the part that the frame shows there, and the pointer is an overlay at the size of the frame. Test: `test_application_video`, a click at the frame place of the Evaluator button opens it at 150% and not at 100%, and the menu text is half as tall again (4 pass); `test_video` 79 pass and 1 fail, the fault band test that fails on `main` since 2026-10-01; `test_tree_render`, `test_laid_out_canvas` and `test_paint_fault` pass.
  - The frame places of the Zoom row: "+" at (872, 149), (895, 164) and (930, 186), and "Reset" at (1088, 224) at 150%: the place in the window times the zoom.
  - A zoom step that does not pass the reader of the window, such as `post_operation!` in a probe, changes the zoom but not the percent in the tab, because only the `appearance` wrapper prints the tab again. A click and a key pass it.
- **The owner accepted the third take on 2026-10-03** ("very good"), and asked to land it and to put it on the web page as the last video. The branch landed on `main` at 9a13ed3b8 after a rebase; the tests after it: `test_video` 79 pass and the fault band fail of `main`, `test_tree_render`, `test_laid_out_canvas` and `test_paint_fault` pass. The take is `assets/videos/appearance.mp4` of projectured.github.io, the last article of the Videos section, with the poster at 97.5 s (the window in Slate dark with the red keys), commit 14604e0, not pushed. The three takes are in `build/video/s13/` of the main checkout.

#### S14. A data frame as a table that you edit

**Accepted by the owner on 2026-10-03.** The owner reviews each take before the next one starts. S12 came first; after its review the owner said "do S14 first", so S14 comes before S13.

- **Feature:** a `DataFrame` of DataFrames.jl shown as a table that filters, sorts, finds and edits, where each edit writes into the frame itself, and where only the rows on the screen are read.
- **Claim:** the table is a view of the frame, not a copy. An edit in the table is a write into `df`, the evaluator sees it at once, and `Ctrl+Z` takes it back. A frame of ten million rows opens as fast as one of a thousand.
- **Setup:** `bin/projectured`, 1280×720, with no assistant, the evaluator open, and the Files pane closed so that the table has room. The data is `make_data_frame_example()`: 1000 products with `id`, `name`, `price`, `quantity`, `in_stock` and `discount`.
- **Beats:**

| # | Action | On the screen | What the viewer learns |
| --- | --- | --- | --- |
| 1 | `using DataFrames, ProjecturedDataFramesExample;` and `df = make_data_frame_example();` | | A plain `DataFrame`. |
| 2 | A form opens `DataFrameView(df)` in a pane to the right of the evaluator. | The table: each header with the name and the type of its column, the row numbers, a filter field under each header, and the bar "Rows where" with a find field. | |
| 3 | Scroll the table with the wheel. | The rows move, and the row numbers count up. | |
| 4 | Type `> 50` in the filter field of `price`. | Only the rows with a price over 50; the corner says how many rows are kept. | A filter is a condition typed where the column is. |
| 5 | Type `in_stock && quantity < 10` in the bar "Rows where". | Fewer rows: the products that are in stock and almost gone. | A condition can be Julia over the columns. |
| 6 | Click the sort arrow of `price` twice. | The rows go from the highest price down. | |
| 7 | `Ctrl+F`, type a part of a name, then `F3` twice. | The table jumps to each row that holds the name. | |
| 8 | Click a price, type a new one, press Enter. | The cell shows the new price. | |
| 9 | In the evaluator, `df[row, :price]` for that row. | The result is the new price. | The table writes into the frame itself. |
| 10 | Press `Ctrl+Z` in the table, and evaluate the form again. | The old price, in the table and in the result. | An edit of the frame is a step of undo. |
| 11 | `big = DataFrame(n = 1:10^7, square = (1:10^7) .^ 2);`, and a form opens its view. Scroll it far. | Ten million rows open at once and scroll without a pause. | Only the rows on the screen are read. |
| 12 | Hold. | | |

- **What exists** (found on 2026-10-03): `ProjecturedDataFrames` loads by itself when `Projectured` and `DataFrames` are both loaded; `DataFrameView(df)` is a document, so a form that returns it draws the live table; filtering, sorting, finding and editing are the first release of `plan/pending/view-and-edit-a-data-frame.md`; an edit is `SetDataFrameValueOperation`, which writes into `df`; the rows are a lazy list, and a test reads only a screenful of a frame of ten million rows.
- **Checks before the take:**
  - `display_in_editor(df)` opens a second window outside the recording, so the take uses `DataFrameView(df)` in a pane of the recorded window. A form that opens a pane beside the evaluator is long (`open_pane!` with `target` and `side`); the step finds the shortest honest form, as `show_lazy_list!` was for S11.
  - The table of six columns needs more width than half of the window. The step checks the widths, and gives the table pane more of the window if it needs it.
  - Beat 11 sorts nothing: a sort of ten million rows runs at once and shows no progress.
  - Not in the video, because they are not in the first release: the rename of a column, the drag of a column, a range selection, and the copy and paste of cells.
  - Beat 9 reads the row number of the edited cell from the row header of the table, so the form names the row that the viewer saw.
- **State of the work, 2026-10-03:** branch `s14-dataframe-video` in the worktree `projectured-julia-s12-settings-video` (it holds S12 too). The rehearsals are in `/var/tmp/projectured-s12/` (helpers `lib/take_common.jl`; the probes of the second session are `out/e05.jl` to `out/e13.jl`).
  - **The owner chose B:** the take loads `DataFrames, ProjecturedDataFrames, ProjecturedDataFramesExample, ProjecturedPlatformExample` before the window, and binds their names in the namespace of the evaluator from the first entry of the timeline (`bind_startup_names!`); without that binding `make_data_frame_example` is not defined in the evaluator. The first visible form is `df = make_data_frame_example();`. The owner said to skip a plan for the faults below.
  - **Faults found and not fixed:** (1) a package loaded from the evaluator does not add its view to the open window, because `NaturalToGraphics` builds its table once; (2) the object fallback faults with `UndefRefError` on a `DataFrameView`; (3) in video time a gesture timer fires late. `VideoBackend` stamps an event with `start_time` plus the video time, and `_pop_due_timer!` compares the due time with the wall clock `time()`. When the video runs ahead of the wall clock, a press and release of the button waits for its timer (`gesture_tracking_waiting`), and the keys after it go to the field that had the focus. A live window stamps events with the wall clock, so it does not show this. A fix needs a clock of the backend for the timers, which is a new mechanism, so it waits for the owner. A `MouseClick` does not wait, so the take opens the cell with a click.
  - **Faults fixed, each with a test:** `DataFrameViewRow` had no `length`, so the history faulted when keys emptied a number into a type-in (`test_data_frame_cells()` 173 pass). A drag of the scroll bar moved the thumb and not the rows: the move with the button held writes the value in a compound with the mouse target, which the view did not convert (`test_data_frame_view()` 52 pass). The discounts of the example printed as `0.15000000000000002` (`test_data_frame_example()` 5 pass). The gesture log folded a typed run across a click or F3 that it does not record, so the take showed `typed "item 9big = DataFram"` (`test_gesture_log()` 63 pass).
  - **Retests after the length fix:** a click on a cell after a find opens the cell. An `UndoBuffer` around the view still does not take the edit in a rehearsal, but for another reason: the press of the cell waited for its gesture timer (fault 3). It is not retested with a click.
  - **Layout:** `show_beside!(editor, DataFrameView(df), "Products"; side = :above, share = 0.68)` (`example/platform/ShowBesideExample.jl`): the table across the full width, the evaluator under it; the Files pane closed in `prepare`; `gesture_overlay = (; lines = 6, operation_width = 32)` at the bottom right. The six columns are about 22 px wider than the window, so the discount column is cut at the right edge: each column is as wide as its header at least, and the row numbers are as wide as the field of the column pattern in the corner.
  - **Coordinates:** filter field of `price` (535, 208); bar "Rows where" (380, 133); sort arrow of `price` (629, 176); the right edge of the last digit of the top price (640, 261), which opens the cell with the caret at its end; rows from y = 260 every 42 px; prompt of the evaluator (300, 626), then (300, 655). The scroll bar of the big frame: the middle of the thumb at the top is (1265, 162), and the bar ends at y = 484; a press at y = 166 already jumps to row 127389, and a move below the bar is not read.
  - **Data:** `> 50` keeps 509 rows; `in_stock && quantity < 10` keeps 34; two clicks on the arrow sort by price down, top row 457 (99.3). Find `item 9` with Enter and F3 jumps to 964, 989, 917. A drag of the thumb to y = 480 shows rows 9999995 to 10000000.
  - **The undo of the edit, as the owner decided it (option (a) of 4.6):** the first `Ctrl+Z` after Enter puts 99.3 back into `df` and opens the cell again with the text "129.9"; the next five take back the typed keys, and the cell stays open on "99.3". So after one `Ctrl+Z` the table shows "129.9" in an open cell, and the viewer does not see the old price. Escape then closes the cell on 99.3, but it is a step of undo, so `Ctrl+Y` after it does nothing. The view shares the history of the window: after `df[457, :price]` in the evaluator, `Ctrl+Z` takes back the evaluation and then the typed form key by key, and an Escape with no open cell closes the window.
- **The first take, 2026-10-03:** `tool/video/record_data_frame.jl`, 1280×720, 103.4 s, recorded in video time in a warm session after a fast run of the same script (`PROJECTURED_TAKE_FAST=1`). It is `build/video/s14/s14_data_frame.mp4` of the worktree. The order is the one of the handover: filter, condition, sort, edit, `Ctrl+Z`, `Ctrl+Y`, `df[457, :price]` (`= 129.9`), find, the big frame. Read at two frames a second:
  - The table opens above the evaluator, the wheel moves the rows, the filter keeps 509 and the condition 34 rows, the sort puts 457 on top, the edit writes 129.9, and the evaluator reads `129.9`. The find jumps to 964, 989 and 917. The big frame opens as a tab with 10000000 in the corner, and the drag goes to the last row at once.
  - `Ctrl+Z` opens the cell on "129.9" and `Ctrl+Y` closes it on 129.9, so the price 99.3 does not show between them (see the undo above).
  - The discount column is cut at the right edge in the whole Products part.
  - **The owner accepted this take as it is on 2026-10-03** ("well done, beautiful"), and asked to land it and to put it on the web page. It is `assets/videos/data-frame.mp4` of projectured.github.io, after the S12 article, with the poster at 60.75 s (the table with 129.9 on top and `= 129.9` in the evaluator), and the form of the README for a data frame under it (commit 0d66e9a, which the owner pushed). The owner then asked to put it first in the list of videos, before "The assistant edits a file", and said that `display_in_editor` needs `using SimpleDirectMediaLayer` to open a window, so the form of the article loads it (commit 764b353, not pushed). The branch landed on `main` at 582c8cc64 with S12, after two rebases; the tests after the second one: `test_dataframes()` 542, `test_window_wrappers()` 43 and `test_gesture_log()` 63 pass. The questions of the undo beat, the cut column and the clock of the timers in video time got no answer yet.

### Considered, and not chosen now

| Feature | Why not now |
| --- | --- |
| A fault stays where it happened | It works (`example/fault/FaultExamples.jl`), but a red frame in place of a view is weak in a video. It fits a later video for developers. |
| An external client over MCP, the same window in a browser and a terminal | The owner removed tier 3 on 2026-09-22. These videos show more than one program, so they also need a capture of the screen, which `record_video` can not do. |
| Charts with a selected data point, a graph with automatic layout | They work, but a still picture shows them as well as a video. The web page and the README have the pictures. |
| A state machine that makes Julia, a process flowchart with breakpoints | A breakpoint has no click yet (`documentation/package/process/process.md`), so the video would be code. |
| A table with formulas | A formula in a table cell does not take an edit yet (`plan/pending/excel-julia-formulas.md`). |

## 6. Constraints

- Run every Julia process of a recording with a memory cap and a timeout, and write its output to a file. The cap is 8 GB by default (`systemd-run --user --scope -p MemoryMax=8G`) with `-t 2`. A larger cap is only for a run that needs it, and the caps of everything that runs at once stay below half of the memory `free -g` shows as available. The takes of 2026-09-22 ran with 20 GB caps, before this rule.
- The model needs 17 GB and runs in the Ollama server, outside the cap of Julia. Before EACH run that loads it, `free -g` must show at least 47 GB available. Count the VS Code language server and the Julia runs of other sessions. Run one Julia process at a time. Do not unload a model that another session uses. The whole computer crashed on 2026-09-23 when this was not checked.
- A video and every other output of a take goes to `build/video/` of the worktree, never to `/tmp`: `/tmp` is a RAM disk, and the crash of 2026-09-23 took the first takes with it.
- A take with the real model is not a measurement of time, so it needs no idle machine. But the video shows every wait at its real length (D12), so another heavy process on the machine makes the video longer.
- Do the work in a worktree beside the main checkout, in `workspace/`. Commit each step.

## 7. Steps

### Step 0: the worktree and the baseline

- [x] Make the worktree: `workspace/projectured-julia-feature-videos`, branch `feature-videos`, from `main` at 47790c4f.
- [x] Record `json_build_live` as it is today. **The recorder works; the example does not.** `record_live_example("json_build", path)` made an MP4 of 760×1000, 1257 frames, 41.9 s, 73 KB, so the machinery of the recording survived the renames. The document in those frames stops at `{"name": "Alice"}`: F2 and F3 of §2.4 break the rest of the timeline. A baseline that counts frames and not content says nothing about the content.

      The run also showed this: `ProjecturedSdlExample` exports `LiveExample`, `live_examples`, `play_live_example`, `record_live_example`, `timed_event`, `timed_operation` and `timed_await`, but not the constant of one example. A caller names an example by its string, which the second method of `record_live_example` takes.
- [ ] The baseline of the scripted `record_mm1k_demo` moves to Step 7, where the work on that video happens. It needs the omnet-julia environment and a built OMNeT++, and minutes of compilation that Step 0 does not need.

### Step 1: the recording tools (G1, G2, G3)

**The design.** `record_video` drives a document and a projection by hand: it has no `Editor`, so it has no tools for the assistant, no feeds, no tooltip and no menu. Every screenplay of tier 1 needs the real application. So the recording becomes a **backend**, and the editor loop runs as it runs in a window.

`VideoBackend <: Backend` in the video slice (`source/video/`, package `ProjecturedVideo`) holds the frame size, the frame rate, the directory of the frames, the index of the next frame, the position of the pointer, the timeline with a fire time for each entry, and the offscreen renderer of `ProjecturedSdl`. It answers the interface of `source/kernel/backend/BackendInterface.jl`:

| Function | What it does |
| --- | --- |
| `initialize_backend!` | opens the offscreen renderer of the video size |
| `take_from_devices!` | answers the next timeline entry whose fire time passed, as a `WindowInput`, and moves the pointer for a mouse event |
| `write_to_devices!` | renders the canvas of the screen, writes the PNG of the frame, and first repeats the last frame for each frame slot that passed with no repaint (G2) |
| `wait_for_input` | sleeps at most `1/fps`, so the loop keeps a frame rate |
| `get_pointer_position` | the pointer of the timeline (G3) |
| `get_display_size`, `open_native_windows!`, `configure_devices!` | the video size, and no native window |
| `measure_text`, `render_canvas`, `decode_image`, `quit_backend!`, `wake_backend!` | as `ProjecturedSdl` does |

The number of the frames follows the wall clock, so one second of the session is one second of the video (D12), and the clock of the editor stays the wall clock, so an animation runs at its real speed. The overlay of G3 (the pointer, the name of the last key, the caption bar) is drawn over the canvas of the screen in `write_to_devices!`, so nothing of it enters the document of the application.

`record_application_video(paths, timeline, filename; …)` builds the document and the projection with `make_application_window`, runs `run_with_window_tools` and `run_editor!` with a `VideoBackend`, stops the loop after the last entry and the final hold, and encodes the frames with the `ffmpeg` call of `record_video`.

- [x] G1: `VideoBackend` and `record_application_video` (commit 5b2b0cc6). The clip of 5 s shows the menu bar, the toolbar, the two tabs and the evaluator with its prompt. `test_video()` passes 15/15, `test_video_layering()` 7/7.

      Two faults of the first cut, both found and fixed in that commit: an entry that fires before the first print is dropped, because `run_read_stage!` has no IO map yet, so the clock of the timeline starts when the first frame is on disk; and `run_frame!` batches up to 32 operations into one repaint, so the backend holds the next entry until the frame of the one before it is rendered. `ProjecturedVideo` now also depends on `ProjecturedScreen`, and the table of `package-rules.md` says so.
- [x] G2: the frames follow the wall clock. The clip of 5 s scripted 5.0 s and recorded 4.93 s, which is one frame.
- [ ] G3: the pointer, the name of each pressed key for about one second, and the caption bar of the timeline.
- [x] `record_video` stays as it is. Only the `ffmpeg` call moved into `_encode_frames_to_video!`, which both recorders use.

### Step 2: S1, the evaluator rebuilds the rotating vector

- [x] Write the real forms, test each one in the evaluator of the application, and record them in §5. All thirteen run, and the dot moves with the clock.
- [x] Check that the canvas changes in its result row after a `push!`. It does, and each form that changes the picture ends with `; canvas`, so the newest row shows the whole picture.
- [x] Write the timeline, record, and give the video to the owner. The first take is 104.8 s (2026-09-22).
- [ ] Record again with the refinements of §5: the human rhythm of D13, shorter forms, and G3.

### Step 3: S3, JSON from nothing

- [x] Find a build that works today, and check it headless before recording. F2 and F3 rule the shape: `Alt+Up` leaves a value, and a nested object comes last.
- [x] Record it: 25.6 s, 900×720, 84 keys, none of them dead (2026-09-22).
- [x] Record it again with the caret only, after F2 and F3: 33.8 s, 900×720, 123 keys, none of them dead (2026-09-23).
- ~~[ ] When F1 is fixed, move the video into the application window and add the beats of F1, the command palette and Ctrl+Z.~~
  **Dropped (2026-09-25, the owner's decision):** S3 stays a single-document take. It also shows how to call the editor with a simple document and a projection, which the page gives under the video (`run_example` with a `JsonNothing` and a chain of projections).

### Step 4: S4, a tool window from widgets

- [x] Write the real forms of the beats, test each one in the evaluator of the application, and record them in §5.
- [x] Check the click, the drag and the type-in. The click routes and the action never runs (F4), so the take writes the cells from the evaluator instead.
- [x] Write the timeline, record, and give the video to the owner: 166 s, 2026-09-22.
- [x] When F4 is fixed, record again with the pointer beats. Done 2026-09-24 (`plan/done/slider-drag-and-real-presses-in-s4.md`): `build/video/widget_tool_v2.mp4`, 91.2 s. Every click is a real mouse down and up, three presses of the button count, a real drag moves the slider from 0.3 to 0.8, and the form `slider.value = 0.8` is gone. The name is still written from the evaluator, as the owner decided.

### Step 5: the real model in a take

- [x] Start the assistant of a take as `OllamaLlm` with a `seed` and a `temperature` of the screenplay. Done for S2: the `llm` keyword of `record_application_video`, `OllamaLlm(context = 32768, seed = 1)` in `tool/video/record_assistant_window.jl`.
- [ ] Save the turn log of a take beside the video: the model, the seed, the rounds, the tool calls, the tokens and the seconds of each turn.
- [x] A rehearsal runs the screenplay without a video, turn by turn, until each turn succeeds. Record the seed of the rehearsal that works. Done (2026-09-27): `tool/assistant/rehearsal.jl` in a warm session (`plan/pending/a-fast-loop-for-the-assistant.md`) runs S2 on many seeds with checks of each step and of the last message; seed 1 is the seed of the take that is kept.

### Step 6: S2, the assistant arranges the window

- [x] Check that `Ctrl+Z` takes back a change of the panes that the assistant made. Record the result in §5.
  **Yes (2026-09-26).** `tool/video/check_assistant_undo.jl` records a take in which a scripted model (`ScriptedLlm`, through the new `llm` keyword of `record_application_video` and `make_application_assistant`) makes the tool call of S2: `open_pane!` with a card that holds a table. The tab "People" opens beside the assistant with the table, and one `Ctrl+Z` removes it and selects the assistant again. A second `Ctrl+Z` takes nothing back: the newest step is then the submission of the prompt. Two traps of the check, recorded so the next one does not fall in them: a take with no warm-up fires its entries in a burst after the slow start, so a frame read at a guessed time can show the window before a change; and `search_documents` from the root also finds the tabs that the undo buffer holds for a redo, so the check counts the tabs inside the pane tree.
- [x] Rehearse (Step 5), record, and give the video to the owner. Done (2026-09-27): take 10, `/var/tmp/s2/s2_take10.mp4`, 136.8 s; on the owner's word ("Land it and add the video to the web page") it is the first video of the Videos section of `projectured.github.io`, "The assistant edits a file".

### Step 7: S0, the M/M/1/K study with the real model (in omnet-julia)

- [x] Q1 is answered: yes (D11).
- [ ] Replace the `ScriptedLlm` of `mm1k_demo_live` with the `OllamaLlm` of Step 5. Keep the typed prompts.
- [ ] Remove the silent `using Main.OmnetLegacyExample` of `_warm_up_mm1k_demo`. The model finds the study functions itself (D8): each one has a docstring, and a guide says how a study is written. The warm-up keeps only the compilation.
- [ ] Rehearse turn by turn. Where the model fails, improve the docstrings, the guide or the prompt of the user. Do not give the model a reply. Record each change and its reason here.
- [ ] Record the take and give the video to the owner.

### Step 8: tier 2

- [ ] S5, S6, S8, each with the checks of its acceptance. S7 is done: it landed and is on the web page (2026-09-27).
- [ ] S9, the editor from a plain Julia REPL. It needs G6 first: choose the tool that captures the screen of the desktop session, and check that the terminal and the window are both legible at 1920×1080.

### Step 9: publish and close

- [ ] Give the owner the length and the size of each take, and ask Q2 then. Put the videos where the answer says.
  - [x] S3, the take with the gesture panel (31.9 s, 548 KB): the Videos section of `projectured.github.io` (2026-09-24), one of several videos. The hero stays the picture of the assistant until S0 is ready.
- [ ] Put the videos in place of the placeholder of the post, and link them from the README and the web site.
- [ ] Mark the video item of Step 9 of `documentation-rewrite.md` as moved to this plan.
- [ ] Move this plan to `plan/done/`.

## 8. The open issues, in stages

Everything the three recorded videos still lack, and everything the work on them found, rated two ways and put in stages. The owner asked for this list on 2026-09-23.

**Importance.**

- **A:** the owner named it, a video can not be made without it, or a claim of the post is false while it stands.
- **B:** a video is visibly weaker.
- **C:** polish.

**Difficulty.** These are estimates from what the code shows, not measurements.

- **S:** one function or one script, and the cause is known.
- **M:** one slice, or a design choice for the owner.
- **L:** the cause is not known, so a diagnosis comes first.

### 8.1 The issues

| Id | Issue | Where it shows | Importance | Difficulty |
| --- | --- | --- | --- | --- |
| G3 | No pointer, no mark for a click, no key names, no caption bar | all videos | A | M |
| V1 | A form changes every earlier result row, because each row holds the same live object | S1, S4 | A | S |
| V2 | The typing is faster than a person (`hold = 0.045`), against D13 | S1 | A | S |
| V3 | The evaluator opens by typing `repl` into a new tab, not from the toolbar button | S1, S4 | A | S |
| F4 | A callback made in the evaluator is skipped, because `applicable` answers false from the older world (§2.4) | S4, and every widget the assistant builds | A | S |
| F6 | The assistant is told about names it can not call, and `list_functions` does not see the declared API (§2.4) | S2 | A | S |
| X1 | The wider application API for qwen is written and not tested (§5, S2) | S2 | A | S |
| F2 | After a string value, `Right` then `,` inserts nothing | S3, the `json_build` example | A | M |
| F3 | `Alt+Up` never leaves a nested container | S3, the `json_build` example | A | M |
| F1 | A file tab of the application takes no character | S3 in the window, S5 to S8, and the post's claim that the application edits files | A | L |
| F5 | A real drag does not move the slider, and a click leaves its knob held (§2.4); a character in the text field is not checked | S4 | A | S |
| F7 | The caret can not leave a container whose last value is a bool (§2.4) | S3, the `json_build` example | B | M |
| A1 | A moving `GraphicsCircle`, `GraphicsPolyline` or `GraphicsLine` needs every positional field, so the forms are long | S1 | B | M |
| A2 | A thunk given to `WidgetLabel` draws as the function, so the video types a `live(...)` helper | S4 | B | M |
| A3 | `open_pane!` takes the focus and has no keyword to keep it, so the tool gets its tab only at the end | S4 | B | M |
| A4 | The agent ends a turn at 8 rounds, and every S2 rehearsal ended there | S2 | B | S |
| A5 | `WidgetProgressBar` takes a number and no function | S4 | C | S |
| A6 | `WidgetComposite` puts every child at one place | S4 | C | S |
| A7 | A new tab in a window with no file lands in the narrow column of the navigator, so S1 and S4 open `notes.json` for no reason the viewer sees | S1, S4 | C | M |
| A8 | `ProjecturedSdlExample` does not export the constant of one live example | the scripts | C | S |
| V4 | The assistant pane is off, so the window is narrower than the real one | S1, S3, S4 | C | S |
| V5 | S4 lasts 163 s, near the limit of 3 min (D5) | S4 | C | S |
| P1 | The post names a Julia function with an XML body, and no example makes that document now (G5) | the post | B | M |
| F8 | After a slow start the recorder fires the keys that fell due in one burst, and the holds after it are lost; S1 opens frozen for 16 s (§2.4) | S1, every take of the application | A | M |
| V6 | Two results of S1 show internal text: `Main.ToolScratch.var"#phase"()`, and the raw fields of the clock | S1 | B | S |
| V7 | S1 lasts 256.6 s, over D5 (3 min), and the page calls its videos short sessions | S1 on the web site | A | M, through A1 |
| F9 | The truetype measure and the SDL renderer disagree for a font with a fractional advance (§2.4) | the gesture panel | C | M |

### 8.2 The stages

Important before less important, and within the same importance, easy before hard. A video is recorded again at the end of the stage that changes it, so the owner sees each improvement.

**Stage 1: important and small (A, S).** Each item is one function or one script.

- [x] F4: call the action's callback with `Base.invokelatest`, for the `applicable` check and for the call, in `evaluate_operation(::InvokeActionOperation)` (`source/widget/WidgetDocument.jl`, not sealed). A test builds a button in a newer world than the editor and presses it. Commit 93241b99. The test failed 2 of 2 before the change; `test_widget_action()` passes 45 of 45 after it, and the button tests pass.
- [x] F6: `list_functions` and `list_types` take the API, as `list_modules` does, list only the declared names, and are bound in a declared scratch namespace with the declaration applied. Commit e563e9d6. `test_declared_api()` passes 117 of 117, and the listing tests of the MCP suite pass.
- [x] X1, the code: the application declares `search_documents`, `get_wrapped_document`, `get_file_content`, `print_natural_text` and `parse_natural_text`, its system prompt names the path to a tab's text, and `print_natural_text(::FileDocument)` answers the text of what a file holds. Commit 90f63b5c. `test_application()` passes 139 of 139. One of its checks used `print_document` as a name the declared surface refuses; `print_natural_text` names it in its docstring, so the check now uses `read_intent`.
- [ ] X1, the test with qwen: only when 47 GB is available (§6). The machine had 43 GB on 2026-09-23.
- [x] The recorder starts the application as the application does. `record_application_video` ran the start of the window tools and not the start of the application, so a recorded assistant had no declared API and no undo tools; the take of S2 on 2026-09-22 ran that way. The start is public as `start_application!`, and the recorder calls it. Commits 90f63b5c and ef3a45b8.
- [x] V3: the timeline presses the Evaluator button of the toolbar, at (50, 38) of a window with no assistant pane. With no file open, the evaluator lands in the narrow column of the navigator, so the takes still open `notes.json` (A7).
- [x] V1: the object gets a pane of its own with existing keys, and every later form returns nothing. `Alt+click` selects the object in its result row (for the tool, `Alt+Up` then selects the layout around the button), `Ctrl+N` notes it, `Ctrl+\` splits the window, `Ctrl+V` pastes the same object into the new pane, `F2` names the pane, `Ctrl+Alt+Left` brings the focus back, and `Down` moves the caret from the selected object into the fresh prompt. A plain click on the prompt does nothing, because a click selects only where a projection wires it, and without the `Down` the next Enter evaluates the selected form again. A form that returns `nothing` shows `= Done.`.
- [x] V2: the forms type with the rhythm of D13. S1 then lasts about 4 min 15 s, which is over D5. Only a shorter constructor (A1) or fewer parts bring it under 3 min.
- [x] S4 gets its pointer beats back: with F4 fixed, three presses of the button in the tool's own pane count, and the label and the table follow. The slider and the name are still written from the evaluator, because F5 is not proven.
- [x] Record S1 and S4 again, and give them to the owner (2026-09-23). S1: 254.9 s, 3.9 MB, thirteen forms, each run once, and the picture grows in a pane named "Picture". S4: 166.9 s, 1.6 MB, eleven forms, then three presses of the button in the pane "My tool"; the label says "Pressed 3 times" and the table follows. The files are `build/video/rotating_vector.mp4` and `build/video/widget_tool.mp4`.

  A new small finding (C): in S4 the tab strip draws the `+` of the group above the `×` of the tab "My tool", in a narrow group. In S1 the strip of the pane "Picture" draws them side by side.

**Stage 2: important, one slice each (A, M).**

- [ ] G3: the overlay of the recording: the pointer, a ring at each press, the name of each key for about one second, and the caption bar of the timeline. It is drawn over the frame in `write_to_devices!`, so nothing of it enters the document of the application.
- [ ] F5: with the pointer visible, check the drag of a slider and a character in a text field. The item becomes a fault or goes away.
- [x] F2 and F3: the structural navigation of JSON. The `json_build` live example is the test, and it builds its whole document again. Done in `plan/done/structural-keys-from-the-caret.md` (2026-09-23): a claim that no stage can carry is no claim, an introduced position stands at the innermost node, and a container leaves a `,` on its closing delimiter to its parent. `json_build_live` builds with `Right` and no `Alt+Up`; F7 came out of it.
- [ ] Record S1 and S4 again with the overlay, and S4 with its pointer beats back.

**Stage 3: important, the cause not known (A, L).**

- [ ] F1: a diagnosis first. Where does the selection of a file tab stop, and why does no key reach the document? The probes of §2.4 are the starting point.
- [ ] F1: the fix, in the size the diagnosis shows.
- [ ] Record S3 in the application window, with the beats of F1, the command palette and `Ctrl+Z`.
- [ ] The post: its claim about editing files holds, or the post states the limit.

**Stage 4: less important, and each one an API choice for the owner (B and C).** Each item changes a public API or a default, so the owner approves each one before it is made.

- [ ] A1: a shorter constructor for a moving graphics element, one that takes a function or a cell by keyword.
- [ ] A2: a function given as the content of a `WidgetLabel` is computed, not drawn.
- [ ] A3: a keyword of `open_pane!` that keeps the focus where it is.
- [ ] A4: the round cap of the agent, as a default or as a setting of the application.
- [ ] A5, A6, A7, A8: the small ones.
- [ ] P1: the example of the web page, a Julia function with an XML body, made again.
- [ ] V4, V5: the assistant pane in the takes, and a shorter S4.

**Stage 4b: S1 on the web site (2026-09-24).** The take of 2026-09-24 is not yet good enough for the page. The four fixes proposed under S1 (§5) wait for the owner's choice.

- [x] F8: a warm-up in the script; the recorder change was skipped by the owner.
- [x] V7 through A1: the live graphics constructors, and faster typing.
- [x] V6: readable results of a function and of a clock.
- [x] Record S1 again and give it to the owner for the page. Done in
      `plan/done/rotating-vector-video-for-the-page.md`: 113.8 s, drawn at 2,
      on the web page since 2026-09-24.

**Stage 5: the videos that wait for the stages before.**

- [x] S2, the assistant arranges the window, with qwen: on the web page (2026-09-27), take 10.
- [ ] S0, the M/M/1/K study with qwen, in omnet-julia.
- [ ] Tier 2, S5 to S8: after F1.
- [ ] S10, a new screenplay the owner proposed on 2026-09-23: an edit reaches every earlier result that shows the same object, and copy and paste shows the same thing, for example a widget pasted into the evaluator as the argument of a function call that changes it. A check comes first: whether a widget noted with `Ctrl+N` pastes into a form of the evaluator. The select-and-paste work pastes into a tab.
- [ ] S9, the editor from a plain Julia REPL: needs a capture of the screen in the owner's session.
