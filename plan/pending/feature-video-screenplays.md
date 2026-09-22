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

Three faults of the editor came out of the work on S3 on 2026-09-22. The owner said not to fix a fault that the video work finds, so each one is written here and left alone. Each was found with a headless replay of the gestures through `read_intent` and `evaluate_operation`, over a real `Editor` with a `ConsoleBackend`.

**F1. A file tab of the application takes no character.** Open `person.json` in `bin/projectured`, with content or empty. The pane focus is on the tab, the JSON draws, and no key reaches the document: `x`, `,` and `{` each answer no operation. `Alt+Down`, `Tab` and `Alt+click` answer a `ReplaceSelectionOperation`, so the selection moves, but a key after them still answers nothing. A plain click on the text answers nothing at all. The evaluator tab is the control: in the same window `Ctrl+T`, `Insert`, `repl`, Enter and then `1+2` Enter draw `= 3`. So the window, the reader and the loop work, and what fails is the seat of the selection inside a file tab.

What F1 blocks: every screenplay whose keys go into a file tab, which is S3 in the window, and S5 to S8. It does not block S1, S2 and S4, which type into a tool tab: the evaluator and the assistant.

**F2. After a string value, `Right` then `,` inserts nothing.** This is the rule the `json_build` live example is built on. A replay of its timeline today: 192 of its 210 keys answer no operation, and the document stops at `{"name": "Alice"}`. `Alt+Up` in place of the `Right` works, and the same build then runs with no dead key.

**F3. A nested container is never left.** Inside `"address": { … }`, an `Alt+Up` once, twice or three times does not bring the caret back to the root object. The next entry lands inside the nested object again. The live example uses `Alt+Up` four times for exactly this, so F3 is the other half of what broke it.

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
| Q2 | **Deferred by the owner on 2026-09-22: decide it when the takes exist and their length is known.** Where do the videos live? | The short ones go in `projectured.github.io/assets/video/`, and the web site and the README link them. A long main video goes to YouTube, because a forum shows a YouTube link as a player and a file of that length is too large to upload. |
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
| 2 | `clock = get_wall_clock()` | A `=` row shows the clock. | |
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

#### S2. The assistant arranges the window

- **Feature:** the assistant changes the user interface itself: it opens tabs and builds a card with a table, with `open_pane!` and the widget and layout modules.
- **Claim:** the assistant works on the same window as you, and `Ctrl+Z` takes its change back.
- **Setup:** `bin/projectured people.json`, 1280×720, with the assistant pane on the right. `people.json` holds five people with a name, an age and a city.
- **Beats:**

| # | Action | On the screen | Caption |
| --- | --- | --- | --- |
| 1 | Hold 2 s. | The file in a tab, the assistant on the right. | The assistant: qwen3.8:27b through Ollama, on the CPU of this machine. |
| 2 | Type the prompt "Open a second tab with people.json sorted by name, beside the first one." Enter. | The tool calls stream into the conversation, at the speed of the real turn. A new tab opens beside the first. | It searches the API, writes Julia and runs it. |
| 3 | Type the prompt "Under the two tabs, add a card with a table of the names and the ages." Enter. | The same, for the card with the table. | |
| 4 | Press Ctrl+Z. | The card goes away. | A change of the assistant is taken back like one of yours. |

- **Acceptance:** both prompts succeed in the kept take. Beat 4 needs the window history to hold a change that the assistant makes to the panes. Step 6 checks that first. If the history does not hold it, beat 4 changes to an edit of the data, and this plan records why.

#### S3. JSON from nothing

- **Feature:** a structural editor. A key makes a typed element, not a character: `{`, `[`, `"`, `,` and Tab.
- **Claim:** edits are typed operations on the data, and F1 and the command palette list what works where you are.
- **Setup:** the single-document recorder (`record_live_example`), 900×720. The application window is not possible while F1 stands, so this video has no menu bar, no toolbar and no tabs.
- **The take of 2026-09-22.** Recorded: 900×720, 767 frames, 25.6 s, 92 KB, with the human rhythm of D13. The build is `{"name": "Alice", "age": 30, "city": "Wonderland", "address": {"street": "12 Rabbit Lane", "zip": "12345"}}`, and every one of its 84 keys answers an operation, which the script checks headless before it records.

  **What the build must obey, while F2 and F3 stand:** a value is left with `Alt+Up` and never with `Right`; a nested object comes last, because the build can not come out of it again. A number value works when the entry before it was left that way.

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
- **Setup:** `bin/projectured` with no file, 1280×720. The evaluator is on the left. Beat 4 opens the tool in a tab on the right.
- **Beats:** each form is typed and runs on Enter.

| # | Action | On the screen | Caption |
| --- | --- | --- | --- |
| 1 | Type `repl` into the empty tab, Enter. | The evaluator. | |
| 2 | `presses = Cell(0)` | A `=` row shows the cell. | |
| 3 | `button = WidgetButton(Point2D(0, 0), Point2D(160, 36), "Press me"; action = () -> presses[] += 1)` | The button draws in the result row. | A widget is a document. It draws as itself. |
| 4 | `tool = WidgetComposite(Point2D(0, 0), [button])`, then `open_pane!(editor, tool; title = "My tool")` | A tab "My tool" opens on the right, with the button in it. | |
| 5 | `push!(tool.elements, WidgetLabel(Point2D(0, 0), () -> "Pressed $(presses[]) times"))` | "Pressed 0 times" appears under the button. | A `push!` adds a widget to the running tool. |
| 6 | The pointer clicks the button three times. | The label counts to 3. | A click writes the cell. The label reads it. |
| 7 | `slider = WidgetSlider(Point2D(0, 0), 0.3)`, a `push!` of it, and a `push!` of `WidgetProgress(Point2D(0, 0), () -> slider.value)` | A slider and a progress bar at 30 %. | |
| 8 | The pointer drags the slider. | The progress bar follows the slider. | No callback. The bar reads the slider. |
| 9 | `name = WidgetText(Point2D(0, 0), "Ada")`, a `push!` of it, and a `push!` of `WidgetLabel(Point2D(0, 0), () -> "Hello, $(name.content)")` | A text field with "Ada", and "Hello, Ada" under it. | |
| 10 | Click into the text field, and type a new name. | The greeting changes with each character. | |
| 11 | Hold 3 s on the finished tool. | | A tool window, built while it runs. |

- **Acceptance:**
  - The step writes the real forms into this table. The field names `slider.value` and `name.content`, the layout of `WidgetComposite` as a column, and the placement of the new tab on the right are guesses from `source/widget/WidgetDocument.jl`. The step checks each one.
  - A click on the button, a drag of the slider and the type-in of the text field work in the recording, with the pointer of G3.
  - If a widget in a result row of the evaluator does not draw as itself, beat 3 shows the button first in the tab of beat 4.
  - The video lasts at most 3 min (D5).

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

#### S7. A window on a running object

- **Feature:** a view on demand. The program shows any value, one level at a time, with no view written for it.
- **Setup:** the application with a JSON file open, and the evaluator in a second tab.
- **Beats:** in the evaluator, open a reflection view of `editor` in a new tab. Open it level by level: the panes, the tab with the JSON file, its document, its entries. Change a value in the JSON tab, and bring the view up to date.
- **Acceptance:** Step 8 finds the call that opens the reflection view in a tab (`reflect_document`, `sync_reflection!`, `open_pane!`) and records it here.

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

### Considered, and not chosen now

| Feature | Why not now |
| --- | --- |
| A fault stays where it happened | It works (`example/fault/FaultExamples.jl`), but a red frame in place of a view is weak in a video. It fits a later video for developers. |
| An external client over MCP, the same window in a browser and a terminal | The owner removed tier 3 on 2026-09-22. These videos show more than one program, so they also need a capture of the screen, which `record_video` can not do. |
| Charts with a selected data point, a graph with automatic layout | They work, but a still picture shows them as well as a video. The web page and the README have the pictures. |
| A state machine that makes Julia, a process flowchart with breakpoints | A breakpoint has no click yet (`documentation/package/process/process.md`), so the video would be code. |
| A table with formulas | A formula in a table cell does not take an edit yet (`plan/pending/excel-julia-formulas.md`). |

## 6. Constraints

- Run every Julia process of a recording with a memory cap: `systemd-run --user --scope -p MemoryMax=20G`. Give every long run a timeout, and write its output to a file.
- The model needs 17 GB and runs in the Ollama server. Run one Julia process at a time during a take. Check the free memory before a take. Do not unload a model that another session uses.
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
| `read_from_devices` | answers the next timeline entry whose fire time passed, as a `WindowInput`, and moves the pointer for a mouse event |
| `write_to_devices` | renders the canvas of the screen, writes the PNG of the frame, and first repeats the last frame for each frame slot that passed with no repaint (G2) |
| `wait_for_input` | sleeps at most `1/fps`, so the loop keeps a frame rate |
| `get_pointer_position` | the pointer of the timeline (G3) |
| `get_display_size`, `open_native_windows!`, `configure_devices!` | the video size, and no native window |
| `measure_text`, `render_canvas`, `decode_image`, `quit_backend!`, `wake_backend!` | as `ProjecturedSdl` does |

The number of the frames follows the wall clock, so one second of the session is one second of the video (D12), and the clock of the editor stays the wall clock, so an animation runs at its real speed. The overlay of G3 (the pointer, the name of the last key, the caption bar) is drawn over the canvas of the screen in `write_to_devices`, so nothing of it enters the document of the application.

`record_application_video(paths, timeline, filename; …)` builds the document and the projection with `make_application_window`, runs `run_with_window_tools` and `run_editor!` with a `VideoBackend`, stops the loop after the last entry and the final hold, and encodes the frames with the `ffmpeg` call of `record_video`.

- [x] G1: `VideoBackend` and `record_application_video` (commit 5b2b0cc6). The clip of 5 s shows the menu bar, the toolbar, the two tabs and the evaluator with its prompt. `test_video()` passes 15/15, `test_video_layering()` 7/7.

      Two faults of the first cut, both found and fixed in that commit: an entry that fires before the first print is dropped, because `read!` has no IO map yet, so the clock of the timeline starts when the first frame is on disk; and `run_frame!` batches up to 32 operations into one repaint, so the backend holds the next entry until the frame of the one before it is rendered. `ProjecturedVideo` now also depends on `ProjecturedScreen`, and the table of `package-rules.md` says so.
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
- [ ] When F1 is fixed, move the video into the application window and add the beats of F1, the command palette and Ctrl+Z.

### Step 4: S4, a tool window from widgets

- [ ] Write the real forms of the beats, test each one in the evaluator of the application, and record them in §5.
- [ ] Check the click, the drag and the type-in of beats 6, 8 and 10 in a recording.
- [ ] Write the timeline, record, and give the video to the owner.

### Step 5: the real model in a take

- [ ] Start the assistant of a take as `OllamaLlm` with a `seed` and a `temperature` of the screenplay.
- [ ] Save the turn log of a take beside the video: the model, the seed, the rounds, the tool calls, the tokens and the seconds of each turn.
- [ ] A rehearsal runs the screenplay without a video, turn by turn, until each turn succeeds. Record the seed of the rehearsal that works.

### Step 6: S2, the assistant arranges the window

- [ ] Check that `Ctrl+Z` takes back a change of the panes that the assistant made. Record the result in §5.
- [ ] Rehearse (Step 5), record, and give the video to the owner.

### Step 7: S0, the M/M/1/K study with the real model (in omnet-julia)

- [x] Q1 is answered: yes (D11).
- [ ] Replace the `ScriptedLlm` of `mm1k_demo_live` with the `OllamaLlm` of Step 5. Keep the typed prompts.
- [ ] Remove the silent `using Main.OmnetLegacyExample` of `_warm_up_mm1k_demo`. The model finds the study functions itself (D8): each one has a docstring, and a guide says how a study is written. The warm-up keeps only the compilation.
- [ ] Rehearse turn by turn. Where the model fails, improve the docstrings, the guide or the prompt of the user. Do not give the model a reply. Record each change and its reason here.
- [ ] Record the take and give the video to the owner.

### Step 8: tier 2

- [ ] S5, S6, S7, S8, each with the checks of its acceptance.
- [ ] S9, the editor from a plain Julia REPL. It needs G6 first: choose the tool that captures the screen of the desktop session, and check that the terminal and the window are both legible at 1920×1080.

### Step 9: publish and close

- [ ] Give the owner the length and the size of each take, and ask Q2 then. Put the videos where the answer says.
- [ ] Put the videos in place of the placeholder of the post, and link them from the README and the web site.
- [ ] Mark the video item of Step 9 of `documentation-rewrite.md` as moved to this plan.
- [ ] Move this plan to `plan/done/`.
