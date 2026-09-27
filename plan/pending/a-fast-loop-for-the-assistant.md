# A fast loop for the assistant

> **Status:** pending. Written 2026-09-27.

## 1. The request

Takes 7 and 8 of S2 (`plan/pending/feature-video-screenplays.md`) each cost
about 14 minutes and showed one path of the model. The owner (2026-09-26): "we
first need to figure out a faster loop to test this", then chose loop A: the
model is real, the person's side is done by operations, no video. Then:
"iterate documentation, simplify or extend, generalize or specialise, add
examples or remove them. Try to figure out what documentation and where would
help the module find the tools and combine them. Do we need to regenerate the
API documentation embedding? Perhaps a better search would help? Perhaps the
matches are not right and it's not about the documentation. [...] Experiment and
figure out in the fast loop in a warm Julia."

## 2. The loop

- **One warm Julia process** that runs command files dropped into a directory
  (`tool/assistant/warm_session.jl`), with Revise, so a change of the source, a
  docstring or a guide is in the next run without a new load.
- **The rehearsal** (`tool/assistant/rehearsal.jl`) builds the window of the
  application headless, with no loop and no frames, as
  `tool/video/rehearse_assistant.jl` did, and starts it as the application does
  (`start_application!`). The person's side of S2 is done by operations: the
  first prompt is submitted, the file's own history takes one undo, the second
  prompt is submitted.
- **Checks after each step:** after turn 1 the file prints as JSON with the five
  people and Frank, 30, from Paris at the end; after the undo it prints the five
  people; after turn 2 a new tab holds a table with the five names sorted and
  without Frank.
- **Early stop:** the model is wrapped, and before each round the wrapper checks
  that the file still prints, that the rounds of the turn are under a limit, and
  that the run is under its time limit. A check that fails ends the run with its
  reason.
- **Seeds:** a run takes a list of seeds and prints one line for each, with the
  steps that passed, the rounds and the seconds, and writes the whole
  conversation of each seed to a file.

## 3. Steps

- [x] **Step 1: the loop.** Done (2026-09-27, 4f9f1f29): `tool/assistant/warm_session.jl`
      runs as the user service `s2-assistant-loop` (8 GB cap, cores 24-27, 8 h
      bound) over `/var/tmp/s2/loop`; `tool/assistant/rehearsal.jl` has the
      rehearsal of S2, four tasks of one prompt (change a value, remove a record,
      show a computed value in a new tab, close a pane), the watched model, the
      memory check before each seed (the cap and 10 GB, and the model when it is
      not loaded yet), the reset of the documentation indexes before each batch
      (they are built once in a process), and a `system` hook that gives a run any
      system text. A run of S2 takes 52 to 151 s; a take took 4 to 14 minutes.
- [ ] **Step 2: the experiments.** Change one thing at a time, run the same
      seeds, and record the result here: what the model searches, finds and
      misses; the guide, the docstrings, the system text, the search.
- [ ] **Step 3: keep what works**, in its own commits, and record the numbers.

## 4. Results

### The baseline (2026-09-27, the system text of s2-video at 1a3b1955)

- **S2: 9 of 10 seeds pass.** Turn 1 takes 3 to 8 rounds, turn 2 takes 2 to 4. Every
  seed that read the orientation guide first passed and copied its example
  almost word for word; seed 1 did not read it and failed.
- **The tasks: 2 of 5 runs pass** (the other 7 were not run: another session's
  processes brought the available memory under the need of a run).

### What the runs and a probe of the search showed

1. **Skipping the guide is the failure.** The model that does not read the guide
   does not know how to make a JSON value, and copies the printed form of one.
2. **The printed form of a document misleads.** A tool answer shows
   `JsonObject(CellVector(Cell[Cell(value, JsonObjectEntry(…))…]), false)`, and a
   model writes `JsonObject(CellVector([...]))` or reads `.value` of an object.
3. **The default system text sends the model the other way.** Its paragraph "TO
   INSPECT OR CHANGE THE DOCUMENT" says to search `editor.document`, evaluate
   references and build an `Operation`, "the one way to change the document",
   while the application says to use `find_pane`, `get_edited_document` and the
   verbs. A model that skips the guide follows the first, and guesses names
   (`parent_of`, `.fields`).
4. **A loop at the top level of a call did not assign the global.** The code ran
   with `Core.eval`, so Julia's soft scope made the variable of the loop a new
   local; the model read the unchanged global as data that changed under it
   ("flaky"). Fixed on the branch: each statement gets the mark of
   `REPL.softscope`, as at the prompt.
5. **A plain value breaks the file.** `"Berlin"` in place of `JsonString("Berlin")`
   is accepted, and the file then does not print (fault b, not in scope).
6. **The search misses the verb when the query names the domain.** "add a record
   to a JSON array" answers six JSON types and not `insert_elements!`, because
   "json" matches their names; the docstring of `JsonObject` says how to read one
   and not how to make one. `search_guides` does not find the section of the
   orientation guide that shows the insert. No new embedding is needed: a vector
   is keyed by its text, so a changed docstring gets its vector on the next search.

### The oracle: what the model does with the right documentation from the start

The owner (2026-09-27): "You could try it the agent would get only the relevant
functions documentation from the search or simply from the start would it then be
able to figure it out? E.g. what is the minimum number of turns it can solve it?"
The fewest rounds are 2 for each prompt: one call of code and the answer.

| Condition | S2 | Tasks | Rounds of turn 1 / turn 2 |
|---|---|---|---|
| Baseline, the code before the soft scope fix | 9 of 10 | 2 of 5 (7 not run) | 3–8 / 2–4 |
| Baseline with the soft scope fix | 9 of 10 | 10 of 12 | 4–8 / 3–4 |
| O1: the docstrings of the 17 names that the tasks need, in the system text, "you do not need to search" | 2 of 5 | 7 of 8 | 3–8 / 2–8 |
| O2: O1 and the section "Reach what a tab holds" of the orientation guide | 4 of 5 (one error of the model's stream) | 6 of 8 | 3–4 / 2–3 |
| **O3: only that section of the guide, in the system text** | **10 of 10** | **12 of 12** | **3–5 / 2–3** (one 8) |
| O4: O3, and the paragraphs of the default system text that send the model to search `editor.document` and to build an `Operation` "the one way" replaced by one that says what the application says | 10 of 10 | 12 of 12 | 3–5 / 2–3 |
| O5: docstrings of the JSON types that say how to make one and which verbs change an array, set at run time, with the system text of the baseline | 9 of 10 | 10 of 12 | as the baseline |

- **The docstrings alone are not enough (O1).** They say how to read a JSON value
  and not how to make one, and not how the names combine, so the model looked at
  `fieldnames` and guessed constructors.
- **The section of the guide is what works (O3).** It shows the three idioms in
  code: look at the data, change a part with a verb, make and insert a record,
  open a table beside a tab. With it in the system text, a run of S2 takes 29 to
  50 s (one 146 s), and seed 1, which failed in every other condition, passes in
  3 and 2 rounds. The model no longer needs to find the guide: the knowledge is
  in front of it at the first round.
- Memory: other sessions kept the available memory at 16 to 17 GB, so runs were
  skipped at the 8 GB cap of the session. Its peak is 1.1 GB, so the cap is now
  3 GB, and the check counts 3 GB (the rule is the same: the cap, the model when
  it is not loaded, and 10 GB).

- **The docstrings do not change the result on their own (O5):** the model
  seldom looks a type up, so a better docstring is not read. They matter where a
  model searches, which the probes of the search measure, not the runs.
- **O4 does no harm and removes the conflict**; O3 is already at the ceiling of
  these tasks, so O4 can not show a gain here.
- **The display experiment did not run** (a parse error in its command, before
  it defined anything).
- **The decision (2026-09-27, the owner's "Yes" to recording the take with it):**
  O3 is the system text of the application. `make_application_system()` in
  `example/projectured/Application.jl` answers `APPLICATION_SYSTEM` and the
  section "Reach what a tab holds" of the orientation guide, read with the new
  public `read_guide_section` of the kernel, so the guide stays the one place of
  the section. The rehearsal now runs with it by default.
