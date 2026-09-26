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

- [ ] **Step 1: the loop.** The warm session, the rehearsal, the checks, the
      early stop, the seeds. Check it with a baseline of seeds 1 to 5.
- [ ] **Step 2: the experiments.** Change one thing at a time, run the same
      seeds, and record the result here: what the model searches, finds and
      misses; the guide, the docstrings, the system text, the search.
- [ ] **Step 3: keep what works**, in its own commits, and record the numbers.

## 4. Results

(Filled as the steps run.)
