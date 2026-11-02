# The assistant finds its names by reflection

Status: a plan. Written 2026-11-02 from the answers of the owner on that day.
Step 1 is done on the branch `reflection-api` of both repositories (2026-11-02).

Spans two repositories. projectured-julia holds the rule, the index, the
tools, the guides and the verbs of the editor. omnet-julia holds the verbs of
the IDE, its texts and its guides.

## 1. Goal

The owner, 2026-11-02:

- "I want both projectured and the omnet IDE assistant to be a generally useful
  tool for the user which can do all sorts of things in the editor itself. It
  should work with both ACP, and with the internal agent loop."
- "I prefer not having manually maintained documents for things that can be
  collected by reflection, e.g. function names, available type names."
- "we need to fix the verbs available for the assistant. E.g. search_references
  should be available"
- The documentation is "overly focused on the example videos we have created to
  tune the agents for that. We should aim for a generally useable assistant."

## 2. Facts (2026-11-02)

Measured in a live process of each window, and in 29 recorded sessions of an
ACP agent inside a window (648 tool calls).

- **Both paths share one tool set.** The built-in loop and an ACP agent call the
  same nine tools and can write the same declared names. Only the text that
  introduces the tools differs.
- **The texts differ much.** The built-in loop of the IDE gets about 5,800
  words, and 15 sections of them are the study of the video. An ACP agent gets
  about 680 words of general text (`DEFAULT_AGENT_INSTRUCTIONS`), with no word
  about OMNeT++. An outside MCP client of the editor gets one sentence.
- **The surface is a hand list.** The editor offers 225 of the 4,475 names that
  its packages export. The IDE offers 354 of 5,247.
- **The texts name what the windows do not offer.** The orientation guide,
  which every agent reads first, names 61 names that are not offered. Agents
  called `search_references` 6 times, `parse_math` 7 times and
  `get_window_tree` once, and each call failed. All three exist in the code.
- **Discovery is expensive.** Each Aloha session spent its first six calls on
  learning what exists. An agent asked for `make_study!` under four different
  module names.
- **Defects of the surface:** a verb answers `Base.Text`, so `split` and
  `lastindex` on the answer fail (7 times). The scratch module's own `show`
  takes no keyword, so `show(frame; allrows = true)` fails (7 times). Some
  verbs take only a plain document, and others take only a referenced one
  (4 times).
- **The proposed surface** has 1,081 of the 5,428 exported names: 407
  functions and 674 types. The study of each name is in the session scratchpad
  (`breakdown-what-the-assistant-will-have.md`); its tables are summarized in
  §4.2.
- **"Use it to" is not a sign.** 135 functions that the windows do not offer
  have a "Use it to" paragraph, among them `set_selection!` and
  `set_cell_value!`. 627 docstrings have an "Example" section, the cell
  internals among them.
- **Guides.** `search_guides` searches 171 documents: 119 package documents,
  29 guides, 20 design, rule and requirement documents, and 3 others. 170 have
  a header line with the kind, the status and what they stand on. None says
  who it is for. The guide folder holds about 15 guides for a user and 14 for
  a developer.

## 3. Decisions

Each decision is the owner's answer of 2026-11-02.

- **D1. A rule read by reflection chooses the surface** (option C). No central
  hand list.
- **D2. The sign is a fixed line in the docstring of the generic function**
  (option A). No macro, and no list that a macro fills.
- **D3. Operation types stay hidden.** The assistant gets make functions that
  answer a change as a value, a function that combines changes, and a function
  that applies a change with its routing as one undo step. The owner answered
  "continue" to the two conditions of §4.3.
- **D4. The index has two sizes from one generator** (option B), "and there
  should be parameters to control the size".
- **D5. `search_guides` searches the documents for users by default** (option
  C). A parameter `audience` reaches the rest. Each hit shows its kind as a
  label. A new header field says who a document is for.
- **D6. Both paths get the same text** (option B): hand-written rules, one
  general worked example for each window, and the generated index. The study
  sections leave the IDE text and stay in its guide.

## 4. Design

### 4.1 The mark

The mark is a paragraph of its own at the end of a docstring:

    For the assistant.

- **A function** is offered when the docstring of its generic function has the
  mark. The docstring has the form that `test_assistant_documentation` checks
  now: the signature, what it answers, a "Use it to" paragraph, an example.
- **A type** is offered when the type or one of its supertypes has the mark.
  One mark on the root type of a domain, such as `JsonDocument` or
  `NedDocument`, offers the whole family. The types that `@domain` generates
  for an insertion and for an empty placeholder stay out: reflection finds
  them through the domain. A domain with no root type marks each type.
- **The person's own names never get the mark:** `set_selection!`,
  `replace_selection!`, `clear_selection!`, `clear_undo_history!`, the file
  dialogs, the answers to a request of an agent. A test holds this short list
  and fails when one of them gets the mark.

The mark on a supertype refines what the study said ("types need no sign").
Without it, 111 document types that are views of the window, placeholders or
insertions would enter the surface, and only a hand list could keep them out.
This is open item 2.

### 4.2 The surface

The surface of a window is every marked name of every module that the window
loads. It replaces `make_editor_api`, `make_campaign_api`, `make_result_api`,
`make_study_api` and the names of `register_assistant_api!`. The sentence that
a domain gives with `register_assistant_api!` moves into the docstring of its
module, so the index carries it. `declare_api!` stays: the window declares the
list that reflection computes. `search_api` searches the same list.

Expected size, from the study, by area:

| Area | Offered now | Added |
|---|---|---|
| Find and read documents | 18 | 80 |
| Change documents | 7 | 3 |
| Window, panes, explorer, settings | 30 | 14 |
| Show: widgets, drawings, charts, tables | 92 | 96 |
| Files, clipboard, links | 13 | 20 |
| Tasks and processes | 13 | 26 |
| Session logs and assistants | 4 | 28 |
| Document domains | 48 | 343 |
| OMNeT++ | 78 | 158 |
| Machinery of the editor | 4 | 6 |

The added functions are the study's list. Each slice checks its own names when
it marks them.

### 4.3 Changes as values

The operation types stay hidden. The assistant gets:

- **make functions**, one for each verb that changes a document. A make
  function takes what its verb takes, such as a part of a tab, and it routes
  and checks as the verb does. It answers the change and does not apply it.
  The kernel's `make_*_operation` functions take a path from the root and do
  not route, so they stay hidden.
- **a function that combines** several changes into one.
- **a function that applies** a change: it evaluates it on the editor's task,
  restores the shown tab and the focus as the verbs do, and the history
  records it as one step.

Each verb is its make function plus the apply function, so there is one code
path for each change. The names follow `naming-rules.md` and are chosen in
step 3.

The docstring of the combine function states the order rule: the changes of a
group are made before any of them applies, so a path by position names the
document as it was before the group.

`run_command!` stays the way to any command of the person. Step 3 checks the 73
operations for edits, files and tabs. A change that no verb and no command
reaches gets a verb.

### 4.4 The index

One generator makes the index from the surface. Its parts are switches:

| Part | Full | Compact |
|---|---|---|
| One sentence for each module, from its docstring | on | off |
| The function names, grouped by module | on | on |
| One sentence for each function | off | off |
| The types | names | a count for each module |

Measured on the proposed surface: the full index is about 8,000 tokens, and
the compact one about 3,750. The backend chooses the default preset: a local
model gets "compact", and any other backend gets "full". A setting chooses the
other preset, or sets each part.

The weak first sentences of the module docstrings must improve, because the
index shows them. An example is `JsonModule`: "The JSON slice."

### 4.5 The guides

- Every document gets the field `**For:** user`, `**For:** developer` or both
  in its header line. The package, design, rule and requirement documents get
  `developer`. The 29 guides get the value that the study listed. The section
  of `documentation/README.md` that defines the header line gets the field.
- `search_guides` gets the parameter `audience`: `"user"` (the default),
  `"developer"` or `"all"`.
- The first line of a result names what matched outside the search, for
  example: `Searched the documents for users. 3 documents for developers also
  match: audience = "developer".`
- Each hit shows its kind, such as `procedure` or `reference`, as a label.
- `read_resource` reads any document by its URI, whatever its audience.

### 4.6 The texts

- **One hand-written part for each window:** what the window is, the tools, the
  rules of behaviour, and one general worked example. In the editor the example
  is find → read → change → show. In the IDE it is project → Runner → runs →
  results → table or plot → tab. It is about 600 to 900 words.
- **The same text on all paths.** The built-in loop gets it as its system text.
  An ACP session gets it in place of `DEFAULT_AGENT_INSTRUCTIONS`, through the
  field that `any-acp-agent-gets-the-instructions-and-a-sign-in.md` added. An
  outside MCP client gets it as the instructions of the server, in both
  windows.
- **Removed from the texts:** the 15 study sections of the IDE text, the
  separate tool guide `EDITOR_TOOL_GUIDE`, and the concept table of the
  orientation guide, which the index replaces.
- **Rewritten as general guides:** the orientation guide shows each capability
  in code: find, read, change, show, control, files, tasks. The IDE's assistant
  guide shows each kind of work: run, test, results, study. Neither is tuned
  to a video.
- **A test** fails when a text or a guide for users names a function that the
  window does not offer. It extends the test that the prompt names only what
  exists.

### 4.7 The defects of §2

- The text answers work with string functions (open item 3).
- The scratch module's `show`, `display` and `@show` pass on keywords.
- A marked function that takes a document takes both a plain and a referenced
  document. A test checks each marked function by reflection.

## 5. Steps

Each step is done in a worktree, runs the narrowest tests that cover it, and
ends with a commit in each repository that it changes.

1. **The mark and the surface by reflection, with no change of the surface.**
   *Done (2026-11-02); the facts are in §5.1.*
   Read the mark, compute the surface, declare it. Mark the 307 names that are
   offered now. Check that the computed surface is exactly today's declared list
   in both windows. Tests: `test_assistant_documentation`,
   `test_ide_documentation`, `test_assistant_verbs`.
2. **The new names.** Mark the added functions and the root types, one area at
   a time. Give each marked function the docstring form. Fix the defects of
   §4.7. Tests: the same, plus the test of the person's own names and the test
   of both document forms.
3. **Changes as values.** The make functions, the combine and the apply. Each
   editing verb becomes make plus apply. Check the 73 operations for edits,
   files and tabs. Tests: `test_assistant_verbs`,
   `test_referenced_document_editor`.
4. **The index.** The generator, its parts, its presets and the setting. Improve
   the first sentence of each module docstring that the index shows.
5. **The guides.** The `For` field in all 171 headers and in the README rule.
   `audience`, the first line of a result, and the kind label in
   `search_guides`.
6. **The texts.** One hand-written part for each window, the same on all three
   paths, with the index. Rewrite the orientation guide and the IDE's assistant
   guide. Remove the study sections from the IDE text. Add the test of the
   names in the texts.
7. **Measure.** Run `tool/assistant/rehearsal.jl` with the local model and the
   compact index. Run ACP sessions on three general tasks: change a value in an
   open file, arrange the panes, and read and plot a result in the IDE. Count
   the calls before the first useful act (6 today) and the failures by cause,
   and compare them with §2. Then move this plan to `plan/done/`.

### 5.1 Facts found in step 1

- `collect_marked_api` in the tool layer (`source/kernel/tool/AssistantMark.jl`)
  reads `Base.Docs.meta` of every documenting module. It takes 1.4 s at its first
  call, most of it compilation, and 0.02 s after that.
- The computed surface equals the old lists in both windows, except for three
  names. `ChartFunctionSeries` is new in the editor, because the IDE offered it and
  its mark is in the chart domain. `get_clock_time` and `get_reactive_clock_time`
  carry the mark in the sealed `kernel/clock/Clock.jl`, by the owner's permission
  for that file (2026-11-02); the code of the file did not change.
- The storage variants that `@document` writes beside a type share its docstring,
  so `ACStyleColor` came in with `StyleColor`. The collection skips a variant, as
  the search index does.
- 300 docstrings got the mark: 222 in projectured-julia and 78 in omnet-julia.
  `add_element!` had its docstring on its one method; it now documents the generic
  function.
- The verbs of `DataFrames` stay a declaration of the DataFrames adapter
  (`register_assistant_api!`), because no mark can reach the docstrings of a
  foreign package. `register_assistant_api!` keeps that job and the sentence of
  each domain.
- Step 1 marks each offered type itself, so the mark on a supertype (open item
  2) is not needed before step 2.
- `register_assistant_api!` stores each entry as an `ApiEntry`, so
  `make_editor_api` answers one shape and a test reads every entry by its module.
- The deleted `make_pane_api` held two reasons that step 2 must keep.
  `get_window_tree` stays unmarked: it answers the tree of the first window only,
  and a model names a part by a complete reference from the root. The IDE guide
  names it in its section on refusals, so the guide changes in step 6.
  `get_document_title` stays unmarked: a caller names a pane with the `title` of
  `open_pane!`.
- On main, `test_interface_api` (2 failures) and `test_assistant_documentation`
  (11 errors, nine names without the full docstring form) fail already. The
  platform layering guard fails on main too, for `filechange/FileChangeModule.jl`
  and `shell/ShellModule.jl`. Step 1 changes none of these files.

## 6. What else changes

- omnet-julia loses its API lists, and its texts change. Its precompile lists
  must be recorded again, because the workload of the IDE builds the system
  text. Before the landing, check that no new platform method overwrites a
  method that omnet-julia defines.
- The rank of `search_api` moves when docstrings change. Run
  `test_referenced_document_editor` after step 2.
- The search corpora of `measure_search_scale!` change with the surface.
- Step 1 removes the exported list functions `make_pane_api`,
  `make_interface_api`, `make_file_api` and `make_task_api` of
  `ProjecturedPlatform`, and the constants `RESEARCH_ASSISTANT_API` and
  `WORKFLOW_ASSISTANT_API`. By decision R36 of the release plan, each package that
  loses an exported name takes a minor version step at its next release.

## 7. Related plans

- `any-acp-agent-gets-the-instructions-and-a-sign-in.md` (pending) delivers the
  instructions to an ACP agent. This plan changes the text that it delivers.
- `an-insert-moves-the-paths-after-it.md` (pending) moves the stored paths after
  an insert. It does not change the order rule of a group of changes.
- `assistant-api-consolidation.md` (pending, 2026-09-13) chose the surface by
  hand lists. This plan replaces how the surface is chosen.
- `plan/done/the-assistant-uses-the-whole-editor.md` keeps its goal. Its hand
  lists go.

## 8. Open items

1. **The order rule of a group.** If step 7 shows that agents often fall into
   it, the other way is a group that applies each verb at once and joins only
   the undo steps. That changes the undo buffer, so it is a new mechanism, and
   the owner decides first.
2. **The mark on a supertype** (§4.1). The owner confirms it before step 2.
3. **The text answers.** My recommendation: a verb answers a `String`, and the
   code tool shows a `String` answer as its plain text. The owner confirms it at
   step 2.
