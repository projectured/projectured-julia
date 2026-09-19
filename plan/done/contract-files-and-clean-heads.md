# Contract files and clean heads

> **Kind:** plan · **Status:** pending · **Written:** 2026-09-20
> **Stands on:** [architecture-rules.md](../../documentation/rule/architecture-rules.md),
> [one-module-per-layer.md](../done/one-module-per-layer.md)

Give every layer with open seams its `<Stem>Interface.jl` (and, where a
fallback exists, its `<Stem>Defaults.jl`), and empty every `<Stem>Module.jl`
of code: a module file holds the docstring, the usings, the exports and the
include list, nothing else. The user accepted the audit of 2026-09-20 and
allowed the unsealing it needs.

## 1. Part A — the contract files

| layer | action | sealed |
| --- | --- | --- |
| operation | rename `Interface.jl` → `OperationInterface.jl`; move the nine scattered declarations into it (`Rerooting.jl` 4, `Inversion.jl` 3, `Operations.jl` 2), docstrings with them; the machinery stays where it is | no |
| device | rename `Device.jl` → `DeviceInterface.jl`; the include line in `DeviceModule.jl` follows | **yes** — both files 🔒 |
| llm | extract `LlmInterface.jl`: the abstract type and the seams (`stream_turn`, `render_tool_schema`) out of `Llm.jl` | no |
| agent | extract `AgentInterface.jl` (the three server seams) and `AgentDefaults.jl` (the `Symbol → Val` redispatch and the missing-kind error); `AgentServer.jl` dissolves if nothing remains | no |
| projection | move `make_children_container` and `get_children_container_type` declarations into `ProjectionInterface.jl` | no |
| reference | move the `match_reference_step_value` declaration into `ReferenceInterface.jl`; `_run_reference_rule_answer` is private and stays | **yes** — `ReferenceInterface.jl` 🔒 |
| binding | extract `GestureBindingInterface.jl` with `read_gesture` | no |

The layering guard's `interface_files` map follows every rename and gains the
three new files, so declares-only is enforced on all of them.

## 2. Part B — the clean heads

Five module files hold their layer's implementation; each body moves into a
fragment (or several), and the head keeps the docstring, usings, exports and
includes:

| module file | fragments | sealed |
| --- | --- | --- |
| `clock/ClockModule.jl` (130) | `Clock.jl` | **yes** 🔒 |
| `gesture/GestureRecognizerModule.jl` (258) | `GestureRecognizer.jl` | **yes** 🔒 |
| `intent/IntentModule.jl` (158) | `Intent.jl` | no |
| `playback/PlaybackModule.jl` (148) | `Playback.jl` | no |
| `editor/EditorModule.jl` (860) | one fragment per section banner of the file — the struct, the inbox, the feeds, read-evaluate-print, the fault barriers and repairs, the frame and the loop | no |

A body split moves lines verbatim; the only new text is each fragment's
header comment.

## 3. Verification

The layering guard (23 folders, the updated interface map), the kernel suite
at its 3+3 baseline, the umbrella guards, the world precompile with its
warnings read, and the spot suites of every touched layer: clock, gesture
recognizer, event case, agent seam, feeds, wait, playback-adjacent repl
drivers.

## 4. The sealed footprint

`device/Device.jl` (rename), `device/DeviceModule.jl` (one include line),
`reference/ReferenceInterface.jl` (one declaration moves in),
`clock/ClockModule.jl` and `gesture/GestureRecognizerModule.jl` (body out,
include in). Allowed by the user on 2026-09-20; each gets a dated note in
`SEALING.md` and joins the re-audit backlog.

## 5. The phases

1. ✅ (2026-09-20) Part A, one commit. Two facts the execution added: the
   operation layer also had two no-op `evaluate_operation` fallbacks hiding
   in `Operations.jl` — they became `OperationDefaults.jl`; and the llm
   split left `Llm.jl` holding what the layer itself does (`is_walk_opaque`,
   `bind_meaning_model!`, the registry read off the method table).
2. ✅ (2026-09-20) Part B, one commit. The editor cut on its own section
   banners into seven fragments: `Editor.jl`, `Inbox.jl`, `Feeds.jl`,
   `ReadEvaluatePrint.jl`, `SafeMode.jl`, `FaultBarriers.jl`,
   `EditorLoop.jl`. Both `SEALING.md` halves landed with part A.
3. ✅ (2026-09-20) Verification: the layering guard passes with the three
   new interface files under declares-only; the kernel suite sits at its
   3+3 baseline; export-collision, documentation, event-case,
   gesture-binding, feeds, statistics and agent-seam suites green; the
   world precompiles with only the pre-existing `test_focusing` warning.
   The five stale file references in the guides follow the renames.
