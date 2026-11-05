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

**Decided by the owner (2026-11-04): one make function for all verbs.** The
assistant calls `make_change(verb, arguments...)` with a verb and the arguments of
that verb, and each verb that changes a document adds one method of
`make_change`. With the combine and the apply, the assistant gets three names, and
the methods of `make_change` show which verbs can make a change. The question
showed them as `make_change`, `combine_changes` and `apply_change!`:

```julia
a = make_change(close_pane!, pane_1)
b = make_change(insert_elements!, items_1, 1, [item_1])
apply_change!(combine_changes(a, b))     # one undo step
```

The other way, one make function for each verb, gives about 48 names, each with
its own docstring and example.

**Decided by the owner (2026-11-04): a change is a small wrapper.**
`make_change` answers a `RootedOperation`: a structural operation, as
`CompoundOperation` is, that holds the operation from the root of the editor's
document, carried there by the readers, and its description. The code tool shows
it as `a change: Close the pane Files`. `combine_changes` and `apply_change!` take
only a `RootedOperation`, so an operation of a kernel maker, which went through no
reader and which no history records, can not be applied by mistake. The assistant
never writes the name of the type. A name with "Change" was not taken, because a
noun-first name with no suffix is the form of an event (`WindowClose`). The other
way, the operation itself, prints as a cut dump of its fields.

**Decided by the owner (2026-11-04): the scope of step 3.**

1. The verbs that apply one change today, about 36, each get a method of
   `make_change`, and the verb becomes make plus apply with no change in what it
   does.
2. The seven makers with no verb (`move_series`, `remove_series`, `jump_to_row`,
   `insert_events`, `delete_events`, `move_axis`, `delete_axis`) become verbs, and
   each gets a method of `make_change`.
3. The verbs that apply several steps, where a later step reads the result of an
   earlier one, about 19, do not change and get no method. A make function can
   read only the document before the group, and the second step of such a verb
   does not exist before the first one applies. §5.3 lists them by name. Open
   item 1 holds the other way for them.

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

**Decided by the owner (2026-11-05): the setting has one field for each part.**
A settings group of its own, "Assistant index", which the window reads when it
starts, holds the preset (automatic, full or compact) and one field for each
part. Each part field has the value "as the preset" first, so a person changes
one part and keeps the preset of the others, for example the compact index with
the type names. Automatic gives the compact index to a local model and the full
index to every other backend. The other ways were one preset field and no part
fields, or a fourth preset "custom" that alone makes the part fields count.

Measured on the surface after step 3 (2026-11-05), with a draft of the
generator: the editor has 56 modules, 251 functions and 469 types, and its full
index is about 5,100 tokens and its compact one about 1,500. The IDE has 92
modules, 335 functions and 406 types: about 7,100 and 2,200 tokens. The
generator is `describe_api`, which makes the answer of a search with no hit
today; it gets one keyword for each part and a preset.

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

- The text answers work with string functions (open item 3). **Decided by the
  owner (2026-11-04):** each verb answers a plain `String`, and
  `_describe_value_for_model` shows a `String` that has a line break as its plain
  lines, without quotes; a one-line string keeps its quotes, as in the REPL.
  `describe_value_for_person` does not change. *Done (2026-11-04).* The
  verbs of 15 files in both repositories answer a `String` (an agent (Sonnet)
  made the change, and I read the diff), and their docstrings say `-> String`.
  The pane verbs answer the `String` of `show_layout`. Tests that read
  `show_layout(…).content`, or `isa Text`, read the string. The guides of the
  pane, the system process and the agent say `String`. Tests: the code tool
  (85/85), the platform suite in its own environment, the application and
  assistant tests, and the IDE tests, each with only the failures known before.
- The scratch module's `show`, `display` and `@show` pass on keywords. *Done in
  step 2 (`dcda01712`):* `show` passes its keywords on, and a test of the declared
  API checks it; `display` and `@show` of Base take no keyword.
- A verb keeps the place of what it reads, and a verb that needs a place refuses a
  plain document with a clear error (decided 2026-11-03, §5.2). The work, in this
  order, each part with its own commit:
  - [x] **The walk holds its rules.** `DocumentWalk(; is_opaque, enter_field,
    descend, order, policy)`; `walk_document` takes the walk and the limits, with
    the new `maxvisits`; `search_documents(x, query; walk, places)` and
    `search_references(x, query; walk)`, each node once by default; the keywords
    `descend`, `enter_field` and `include_selection` of the callers move into a walk.
    *Done (2026-11-03).* Facts:
    - `search_documents` moved from the document layer to the reference layer
      (`ReferenceSearch.jl`), beside `search_references`, because `places` answers a
      `ReferencedDocument`; `DocumentSearch.jl` is gone. The walk names a match by a
      chain of steps (`walk_document(…; paths = true)`), and the reference layer turns
      it into a reference. Three omnet imports name `ReferenceModule` now.
    - The default field rule is a named, exported function, `is_field_entered(node,
      name)`: `is_field_walked`, and never `:mouse_target` or `:selection`. A walk
      that changes one rule composes with it. No caller passed `include_selection`.
    - `maxvisits` defaults to 100,000, and to `nothing` with `limit = nothing`,
      because a caller that asks for every match (a save, a load) asks for the whole
      walk. `WalkLimits` gains `maxvisits`, `is_visit_limit_reached` and
      `unreadable_count`.
    - Each node once also changes which callers see a shared node twice: the pane,
      explorer and window searches looped over every path; they see one now.
      `_find_referenced_value`, which asks whether a value stands at one place, uses
      `DocumentWalk(; policy = :once_per_path)`. Three tests that counted every place
      of a shared node now check both walks.
    - An agent (Sonnet) moved 23 call sites in projectured and 10 in omnet; four omnet
      modules and the IDE test module import `DocumentWalk`.
    - Tests: kernel suite, walk, document contract, referenced document, reference
      evaluation, MCP search, declared API, workflow (314/314), the platform suite in
      its own environment (174,827 pass; 1 fail, the known layering guard), the
      application (386 pass; :677 and :789 fail on main too), and the IDE tests
      (known :227 and :325). The step-2 tests that this run caught are fixed: the
      workflow names (five more since step 2), the refusal probe (`read_intent` is
      named by the docstring of `ProjectionModule`, which the subtype rule offers
      through `ProjectionReferenceStep`) and the study window test, which read the
      registry as pairs.
  - [x] **The undo slice skips its two lists** with `is_field_walked`. *Done
    (2026-11-03).* A load clears the mouse targets with a walk of its own that
    enters every field but the mouse target and the selection, so the steps of an
    undo buffer that a file holds lose theirs too. A test checks that a search of a
    buffer does not find a value that only a step holds, and that a search of the
    list of steps does. The platform suite (in its own environment), the
    application suites and the IDE tests give only the failures known on main.
  - [x] **The verbs keep the place:** `get_referenced_value` and the other verbs
    that read a part of the window, in both repositories. *Done (2026-11-03).*
    - `get_referenced_value` answers a part, and `find_pane` answers it as it is.
      `add_study_section!`, `add_study_prose!` and `embed_in_study!` answer their
      blocks as parts when they get the study as a part, found in the report by
      identity.
    - Left as they are, each for a reason: `add_study_formula!` (its answer is
      called like a function, `S_pure(0.5)`, and a part is not callable);
      `open_runner!`, `find_simulation_projects` and `open_simulation_project!` (an
      operation or a registry puts the value in a tab, so only a search would find
      the place, and the IDE verbs accept a plain runner or project);
      `collect_workflow_entries` (records of a journal, read and not acted on);
      `find_task_group`, `find_open_file_document` and the session lists (they read
      registries of the session, not the window); `evaluate_reference` and
      `try_evaluate_reference` (primitives that read any root);
      `get_wrapped_document` (an unwrap by definition).
    - **A part inside a list (owner 2026-11-03, agreed):** code that builds a
      document from parts, `PaneGroup([a, b])` or `group.tabs = [a, b]`, stored
      the parts, because the constructor that `@document` generates and the write
      of a field called `get_document` on the list, which answers the list
      unchanged. The new public `get_stored_value(value)` answers `get_document`,
      and for a plain `Vector` that holds a part a new vector of the
      `get_document` of each element. The generated constructor, the field write,
      `insert_elements!`, `replace_referenced_value!` and `CellVector(items)` store
      it. The last is where a plain vector becomes a document list, for the
      constructor that `@document` generates for a list field (`PaneGroup([a, b])`)
      and for a hand-written one (`PaneSplit`), so the pane
      programs of the IDE tests, which build panes from the answers of
      `get_referenced_value`, pass unchanged.
    - Tests that check a type with `isa` or `===` unwrap the answer with
      `get_document`. The research list gained the names that step 2 marked (eight)
      and the two subtypes that the root offers (`ResearchItem`,
      `ResearchDecisionDraft`). `BuildEditorTest.jl:257` counts one stop step more
      when `ProjecturedResearchTest` is loaded in the same process; the kernel suite
      passes in its own environment (5033/5033).
  - [x] **The error for a plain document:** the hint on Julia's `MethodError` and
    the fallback of `get_reference`. *Done (2026-11-03).*
    - `get_reference(x)` of any value that is not a part throws an `ArgumentError`:
      "A JsonObject has no place, because it is not a part. Pass a part, a document
      with its place: a read of a part gives one, and so does
      `search_documents(editor.document, query; places = true)`."
    - The `__init__` of `ReferenceModule` registers a hint on `MethodError`. When an
      argument is a `Document` where a method of the function takes a
      `ReferencedDocument` (the type of the parameter meets it, and is not `Any`),
      the error ends with "The argument 1 is a plain document, a JsonObject, and
      `select_part!` takes a part there." and the same advice. A keyword call
      reaches the hint as `Core.kwcall` with the keywords and the function first,
      and the hint reads past them.
    - The texts are general: they name no verb and no tab. The owner confirmed
      them (2026-11-03).
    - Tests: `test_referenced_document` (73/73), the kernel suite in its own
      environment (5039/5039), the naming guard.
  - [x] **The texts:** the docstrings of the two searches, and the system text that
    teaches `search_references(editor.document, query)`. *Done (2026-11-03).* The
    docstrings changed with the walk. The system text in `AssistantDocument.jl` and
    the orientation guide teach `search_documents(editor.document, query; places =
    true)` first, say that each node is found once, and name the two bounds and the
    keywords that lift them. The docstring of `ReferenceModule` places both
    searches in the reference layer, and the reference document says how a plain
    document is refused.
    - `test_assistant_documentation` and `test_assistant_verbs` found two gaps of
      this step, which the earlier runs did not cover: the "See also" line of
      `is_field_entered` named `is_field_walked`, which the assistant cannot write
      (the prose names it now, the line does not), and `test_assistant_verbs` looked
      for the old clock example, `2pi * get_reactive_clock_time`. The three
      `evaluate_operation` examples fail as recorded in §5.2.

## 5. Steps

Each step is done in a worktree, runs the narrowest tests that cover it, and
ends with a commit in each repository that it changes.

**Steps 1 to 4 land on main before steps 5 to 7** (the owner, 2026-11-05). Six
new plans of the assistant start from main and use the mark, so the mark must
be on main first. The branch was rebased on main `de6b4e95d` in projectured-julia
and on main `f7b41c034` in omnet-julia, and landed in both, with the tests after
the landing. Steps 5 to 7 continue on the branch from there.

1. **The mark and the surface by reflection, with no change of the surface.**
   *Done (2026-11-02); the facts are in §5.1.*
   Read the mark, compute the surface, declare it. Mark the 307 names that are
   offered now. Check that the computed surface is exactly today's declared list
   in both windows. Tests: `test_assistant_documentation`,
   `test_ide_documentation`, `test_assistant_verbs`.
2. **The new names.** *Done (2026-11-04); the facts are in §5.2.*
   Mark the added functions and the root types, one area at
   a time. Give each marked function the docstring form. Fix the defects of
   §4.7. Tests: the same, plus the test of the person's own names and the test
   of both document forms.
3. **Changes as values.** *Done (2026-11-04); the facts are in §5.3.*
   The make functions, the combine and the apply. Each
   editing verb becomes make plus apply. Check the 73 operations for edits,
   files and tabs. Tests: `test_assistant_verbs`,
   `test_referenced_document_editor`.
4. **The index.** *Done (2026-11-05); the facts are in §5.4.*
   The generator, its parts, its presets and the setting. Improve
   the first sentence of each module docstring that the index shows.
5. **The guides.** *Done (2026-11-05); the facts are in §5.6.*
   The `For` field in all 171 headers and in the README rule.
   `audience`, the first line of a result, and the kind label in
   `search_guides`.
6. **The texts.** *Done (2026-11-05); the facts are in §5.7.*
   One hand-written part for each window, the same on all three
   paths, with the index. Rewrite the orientation guide and the IDE's assistant
   guide. Remove the study sections from the IDE text. Add the test of the
   names in the texts.
   - [x] **6a. One text for each window, on the three paths.** The text of a
     window is its own part (what the window is, its rules, one worked
     example), the rules that every window shares (`EDITOR_SYSTEM`, the tools
     and the rules of behaviour, without the lists of verbs), and the index of
     the names of the window for the backend (`describe_api_index`). The
     built-in loop gets it as the `system` of the assistant. An ACP agent gets
     the framing of an agent (`DEFAULT_AGENT_INSTRUCTIONS`, the two paragraphs
     about the person's editor and the agent's own file tools) and then the
     `system` of its assistant, in the system prompt of its session; the MCP
     server of the agent gets one sentence, so the text is not sent twice. An
     outside MCP client gets the text of the window with the full index.
     `EDITOR_TOOL_GUIDE`, the 15 study sections and the section of the
     orientation guide leave the texts.
   - [x] **6b. The orientation guide** shows each capability in code: find,
     read, change, show, control, files, tasks. The concept table goes.
   - [x] **6c. The IDE's assistant guide** shows each kind of work: run, test,
     results, study. The study sections stay in it.
   - [x] **6d. The names test.** A text of a window, and a guide for users that
     a window names, names only what the window offers.
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

### 5.2 Facts found in step 2

- A review of the 219 functions that the study added checked each body against
  the rules of the assistant. It kept 188: 173 that read and 15 with an outside
  effect that a person asks for, such as a query of a database or a signal to a
  process. It left out:
  - 5 that write a document directly: `insert_row!`, `delete_row!`,
    `insert_column!`, `delete_column!` (`cm.elements = …`) and `stop_work_item!`;
  - 3 that write a database past its document: `insert_into_db!`,
    `update_db!`, `delete_from_db!`;
  - 10 whose argument no offered function answers, such as the trace of a
    process or the cache of a fingerprint store;
  - 7 that answer an operation and apply nothing (`move_series`,
    `remove_series`, `jump_to_row`, `insert_events`, `delete_events`,
    `move_axis`, `delete_axis`): they are make functions for step 3;
  - `get_window_tree`, `get_document_title` (§5.1), `get_selection`
    (`find_selected_part` answers the selected part), `get_cell_at` (it answers
    a live cell), `open_url!` (it takes the backend; the command of a link opens
    a URL) and `get_task_group` (it answers the mutable group of the engine).
- The scratch module's `show` passes its keywords on, so `show(frame; allrows =
  true)` works.
- A verb that fails on a plain document is one of two kinds. `get_reference`,
  `get_parent` and `replace_referenced_value!` need a place in the window, which a
  plain document does not have. `get_formula_value` only needs to unwrap a
  referenced document, and it does. **Decided by the owner (2026-11-03), option A:**
  - a verb that reads a part of the window answers the part, the document with its
    place, as one `ReferencedDocument`, and never the plain document it found:
    `get_referenced_value` answered the plain node of a reference it knew;
  - a verb that needs a place and gets a plain document refuses it with one error
    from one fallback: "This document has no place in the window. Read it from a
    tab, for example with `find_pane`." The error names the cure, so the agent
    corrects its call.
  - Rejected, option B: a verb finds the place of a plain document again by a
    search of the window. It searches the whole window at each call, a document
    can stand at two places, and it searches for a fact that the first verb knew.
  - The error text is general (the owner found the first one too specific): "This
    document has no place in the window. Pass the part that a read of the window
    gives." About 25 verbs take a part by the type of their argument, so Julia
    refuses a plain document before the verb runs; the text goes on Julia's
    `MethodError` as an error hint, and the fallback of `get_reference` says the
    same for a verb that reads the place itself.
- **The two searches (owner 2026-11-03, agreed with the undo change below).**
  Measured on a window with a 300-row JSON file: `search_documents(editor.document,
  …)` 25 ms; `search_references` 2.9 s, and after 20 edits 441 paths for one row
  (3.9 s, 1 GB) and more than 9 GB for a broad predicate, because it walks each path
  and the old versions that undo keeps share their rows. A prototype that walks each
  node once and records the first path: 11 ms, and its part went straight into
  `replace_referenced_value!`.
  - `search_documents(x, query; places = x isa ReferencedDocument, maxvisits = 100_000,
    limit, maxdepth, background)`: `places = true` answers parts, each with its path
    from `x` (after the place of `x` when `x` is a part); each node once, at the first
    path; `maxvisits` bounds the work. The first line of the answer names each limit
    that stopped the search and the keyword that lifts it.
  - `search_references(x, query; every_path = false, …)`: the paths of
    `search_documents(x, query; places = true)`; `every_path = true` keeps the walk of
    each path, for code that must know whether a node stands at two places; the same
    limits.
  - The undo slice skips its two lists with the existing rule:
    `is_field_walked(::UndoBuffer, name) = !(name in (:undo_entries, :redo_entries))`.
    The kernel search has no undo option. A search of the old versions starts at the
    list, `search_documents(buffer.undo_entries, query)`, because the rule applies to
    the fields of the buffer. No line of the answer says that the old versions were
    skipped: the search does not know why a field was skipped, and it is no limit.
  - A match whose path cannot be read back (47 in the style theme, a dictionary with
    types as keys) is left out and counted in the first line.
  - `get_referenced_value` answers a part.
- **The walk holds its rules (owner 2026-11-03):** "a walk should be parameterized
  with the functions which control what is walked and what is not and in what
  order". `DocumentWalk` has five parameters: `is_opaque(node)` (default
  `is_walk_opaque`), `enter_field(node, name)` (default `is_field_walked`, never the
  mouse target or the selection), `descend(parent, child)` (default every child),
  `order(node, steps)` (default positions in order, fields in declared order) and
  `policy` (default each node once). The search keeps the limits (`limit`,
  `maxdepth`, `maxvisits`, `background`), the form of the answer (`places`, `raw`)
  and what happens at a match (`enter_matches`, `on_error`). The naming of a match,
  a node or a path, leaves the walk for the search; `every_path` is not needed, it is
  `DocumentWalk(; policy = :once_per_path)`. A walk that enters the undo lists:
  `DocumentWalk(; enter_field = (node, name) -> node isa UndoBuffer ||
  is_field_walked(node, name))`. Before this, a walk named only the location of a
  match and its cycle rule, and the searches took `descend`, `enter_field` and
  `include_selection` as keywords (about 50 calls in the source).
- The documentation tests of both repositories check two more rules: the "See
  also" paragraph of an offered name names only what the assistant can write,
  and its example calls only what the assistant can write (or `Base`). An agent
  copies an example, so an example that calls a hidden function teaches a call
  that fails. The first run found 159 gaps: 96 name a document type, which the
  decision about types (open item 2) answers, and 63 are text fixes.
- The examples of `OpenFileOperation`, `SaveFileOperation` and
  `ReloadFileOperation` call `evaluate_operation`. These three are operation types
  that the windows offer today; by D3 they give way to verbs in step 3.
- The examples of `get_reactive_clock_time` and `get_clock_time` made a cell with
  `Cell(@computation …)`, which the assistant cannot write. They now read the clock
  in a function, `() -> get_reactive_clock_time(editor.clock)`, the form that the
  system text teaches. The owner gave permission for the sealed
  `kernel/clock/Clock.jl` (2026-11-03); only the two examples changed. The `Clock`
  docstring, which carries no mark, keeps its cell example.
- **Types (owner 2026-11-02, option A):** a mark on a type offers every exported
  subtype. `collect_marked_api(; exclude)` walks the loaded modules (not `Base` or
  `Core`) for the subtypes; the platform passes `is_domain_placeholder`, so the
  `*Nothing` and `*Insertion` placeholders of a domain stay out. The docstring that
  `@domain` writes for the root it generates carries the mark, so each of the 11
  domains with a generated root offers its documents by construction; the other
  roots and the single types carry the mark by hand: 26 roots, such as
  `MarkdownDocument`, `FileDocument` and `SimulationDocument`, and 33 single types,
  such as `TaskGroupDocument` and `LegacySimulationProject`. A test refuses the mark
  on `Document`. The full docstring form is asked only of a name that carries the
  mark itself; a member of a marked family needs none.
- A docstring of an `@document [M, C]` family sits on its layouts, such as
  `ACTaskExecution`; a mark there offers the name of the family, `TaskExecution`.
  The walk for subtypes finds a name by the module that defines it (`which`), so the
  public name of a layout family, a `Union` of its layouts, comes in as well.
- `is_domain_placeholder` also finds an insertion cursor that a slice writes by
  hand, such as `MarkdownInsertion`, by the end of its name, as the completion of
  the domains reads it.
- The surface after the types: the editor 721 names (480 types, 239 functions),
  the IDE 888 (529 types, 357 functions). No type of a foreign package comes in.
- A larger surface moves the search: four measured searches of
  `test_referenced_document_editor` and `test_interface_api` now give a member of
  a family first, such as `JuliaWhere` for "a document and where it is". The
  ranking is a question for the owner (open item 4).
- The families of `WidgetDocument` (styles, inner widgets), `ConversationDocument`,
  `SyntaxDocument`, the settings and the views of the window stay unmarked; the
  widgets that a model builds carry their own marks.
- The table interface takes a referenced document by one unwrapping method for each
  of its functions (`source/platform/collection/TableInterface.jl`). This is the
  kind of general place that the question of the two document forms looks for.
- **The test of the person's own names** is the first test set of
  `test_assistant_documentation`: `set_selection!`, `replace_selection!`,
  `clear_selection!`, `clear_undo_history!`, `make_file_dialog`,
  `open_file_dialog!`, `save_file_dialog!`, `answer_permission_request!` and
  `answer_question_request!` carry no mark and are not offered (27/27). It runs
  first, because the set of the docstring form fails on the three known operation
  examples and a top-level test set that fails ends the function.
- **The two document forms, measured (2026-11-04):** of the 190 parameters of the
  offered functions whose type is a document type, 77 (in about 55 functions) take
  a plain document and no part, such as `stop_task!(::TaskGroupDocument, ::Integer)`,
  `get_fsm_states(::FsmMachine)` and `get_workflow_node_title(::WorkflowStep)`. A
  part that a read of the window gives meets a `MethodError` there. In the IDE,
  24 more parameters of omnet-julia are the same, such as
  `read_results(::LegacyScalarResultSelection, ::AbstractString)`,
  `run_card!(::LegacySimulationCard)` and `get_simulation_configs(::ILegacySimulationProject)`.
- **The two document forms, decided by the owner (2026-11-04):** each of these
  functions gets one method for each position that takes the part and calls the
  function again with its document, in the form of the table interface:
  `stop_task!(group::ReferencedDocument, index::Integer) = stop_task!(get_document(group), index)`.
  A function with several methods at one position gets one method for all of
  them, and a function with documents at several positions gets one method for
  each position, which types the positions before it as plain documents. The
  other way, a second hint on the `MethodError` that says to pass
  `get_document(x)`, was not taken: the call fails once, and the model must
  repair it.
- **The test of both document forms** is the second test set of
  `test_assistant_documentation`, and a test set of `test_ide_documentation` for
  the methods of omnet-julia. For each offered function, each method and each
  parameter whose type is a document type, a call with a part of that type at that
  position must find a method (`hasmethod`). A trailing `Vararg` counts as no
  argument.
- *Done (2026-11-04).* 63 methods for 56 functions in 31 files of projectured-julia
  (7aef43950), and 17 methods for 17 functions in omnet-julia (7db8e494b). An agent
  (Sonnet) wrote the methods from the measured list, and I read the diff. The test
  found one more gap that the measurement skipped, because the measurement left
  out a method with a trailing `Vararg`: `start_process(model::ProcessModel, arguments...)`.
  Where an old method names its parameter with a short form (`a`, `doc`, `e`,
  `env`, `rel`, `p`), the new method uses the full word. No call with a part is
  ambiguous (`which` at each position). Tests: the new set 196/196, and
  `test_assistant_documentation` has only the 3 known errors of the operation
  examples; `test_assistant_verbs` 83/83; `test_research_assistant_api` 76/76; in
  omnet-julia the new set 52/52, `test_ide_documentation` 967/967 and
  `test_prompt_names` 20/20; both naming guards hold. The kernel guide
  (`reference.md`) says that a function that needs no place takes a part too.
- A function that answers a document under the one it takes, such as
  `find_state(machine, name)`, answers a plain document when it gets a part: the
  extra method passes on the document, not the place. A verb that needs a place
  then refuses that answer with the hint of a plain document.

### 5.3 Facts found in step 3

A survey (an agent (Sonnet), read only, 2026-11-04) of both repositories:

- **106 offered verbs change something.** About 45 change a document or the
  layout of the window; these are the verbs of §4.3. The others start or stop a
  task or a process (35), write a file on disk (5), or change the selection, a
  setting, the clipboard, a database connection or a registry.
- **Some verbs already have a twin that makes the change and applies nothing:**
  `make_close_pane_operation`, `make_focus_pane_operation` and the other pane
  verbs, and `make_filter_collection_operation` and the other collection verbs.
  Each answers an operation from the root of the editor's document, carried
  there by the readers. None carries the mark. The kernel's
  `make_insert_elements_operation(path, index, items)` has the same form of name,
  but it takes a path and goes through no reader, so no history records it.
- **A rooted operation already holds its undo records.** `find_rooted_operation`
  and `read_rooted_operation` carry an operation through the readers, and the
  reader of each history on the way wraps it in a `RecordUndoOperation`. So a
  `CompoundOperation` of two rooted operations records two steps, not one.
- **Many verbs apply several steps.** `make_study!` and `open_study!` evaluate 3
  to 5 operations and also write cells and fields directly; `add_study_formula!`
  evaluates 2 to 3; `check_predictions!` makes one step for each hypothesis;
  `close_task_group!` closes each tab with its own step. `replace_referenced_value!`
  restores the focus with a second operation, and restores the shown tab with a
  direct write.
- **No file verb goes through an operation.** `write_document_file`,
  `export_document` and the study files write the disk directly. None of the 20
  operation types of files is made by a verb.
- **The 73 operations of §5 are not found again.** The survey counts 146 operation
  types: 23 edit a document, 20 a file and 12 a tab or a pane. The study that
  counted 73 is not kept.

**How step 3 is built (decisions made in the implementation, 2026-11-04):**

- **The kernel holds the core.** `RootedOperation`, `make_change`,
  `combine_changes` and `apply_change!` are in `EditorModule`
  (`DocumentEdits.jl`), beside `find_rooted_operation`, because
  `insert_elements!` and `delete_elements!` are verbs of the kernel. A slice adds
  the methods of `make_change` for its verbs.
- **One step without a new mechanism.** `combine_changes` joins each run of
  members, one after the other, that sit in the same wrapper: the wrapper holds
  the run once. Two wrappers are the same when the one, rewrapped around what the
  other holds, is the other. It uses only `get_wrapped_operation` and
  `rewrap_operation`. So the record of the window history holds the whole group,
  and the record of each file history holds its own part: one step in each.
- **The repair of a layout write is made with the write.** Before, the verb
  `replace_referenced_value!` repaired the shown tabs by a direct write and the
  focus by a second operation after the write. Now its make function adds the
  operations that keep them: the dormant selection write of each group that would
  show another tab, and the focus operation when the focused tab gets another
  path. They are made from the tree as the write leaves it, with a walk that reads
  the replaced node or list as its new value, as the pane surgery makes the
  selection shifts of an insert. So a layout write in a group keeps the focus as
  the verb does. A focus operation for a tab that keeps its path is not made any
  more.
- **The twins stay.** `make_close_pane_operation` and the other twins serve code
  that posts an operation. A twin and the method of `make_change` share one
  internal maker, which answers a `RootedOperation`.
- **A caller that holds a pane tree and no editor** applies a change to the tree:
  `evaluate_operation(tree::PaneTree, change::RootedOperation)`.
- **The seven makers became seven verbs, and the makers stay.** The key
  bindings answer the operation of a maker, so `move_series`, `remove_series`,
  `jump_to_row`, `insert_events`, `delete_events`, `move_axis` and `delete_axis`
  keep their names and their work. The verbs `move_series!`, `remove_series!`,
  `jump_to_row!`, `insert_events!`, `delete_events!`, `move_axis!` and
  `delete_axis!` take a part, root the operation of the maker, and have a method
  of `make_change`. `move_series!` moves no selection, because the assistant
  never selects; the key moves it, as before. `remove_series!` takes the index
  of the series, where the key removes the selected one.
- **The three file operations became three verbs.** `open_file!(path)` opens a
  file in the tab where the window puts files, with its history, and answers the
  tab; a file that is open keeps its tab. It does not take the focus.
  `save_file_to_disk!` and `reload_file_from_disk!` take the tab of a file, its
  page or the file, and do what Ctrl+S and Ctrl+O do there, so a page checks the
  disk first. Their names are the words of the two keys, because `save_file!` is
  already the save of the serialization slice. `OpenFileOperation`,
  `SaveFileOperation` and `ReloadFileOperation` lose the mark. omnet-julia's
  `OmnetPresentation` exports an `open_file!` of its own, so its test package
  names it, as it names `open_page!`.
- **The verbs that stay as they are** and get no method of `make_change`,
  because a later step reads the result of an earlier one, or a part of the work
  goes through no reader: `close_task_group!`, `start_workflow!`, `start_study!`,
  `check_predictions!`, `add_study_formula!`, `show_assistant_work!`,
  `show_roster!`, `show_document_tree!` and `show_system_process_tree!`; in
  omnet-julia `select_tests!`, `select_simulations!`, `select_comparison_sides!`,
  `open_project_page!`, `open_fingerprint_store!`, `open_runner!`,
  `open_simulation_project!`, `make_study!`, `open_study!`,
  `check_expectations!`, `run_tests!`, and `open_test_runner!` and
  `open_statistical_baseline!`, which open their tab with the focus and whose
  insert of a runner goes through no reader. `select_part!` and
  `change_setting!` change the selection and a setting with an operation that no
  reader carries.
- **The check of the operations found one gap.** The edits of a table of a data
  frame (`InsertDataFrameRowOperation`, `DeleteDataFrameRowOperation`, the three
  of a column, `SetDataFrameValueOperation`) are reached only by the context menu
  of the table, and `run_command!` reads only the key bindings. So the assistant
  can not edit a data frame through a history. The verbs `insert_row!`,
  `delete_row!`, `insert_column!` and `delete_column!` are of a `CellMatrix` and
  a `CellTable`, not of a data frame. Every other edit, file or tab operation that
  a person reaches has a verb or a command.
- **Done.** 36 verbs of one change have a method of `make_change`: the kernel's
  two, the eight of the panes, and 26 of the platform and the domains (by an
  agent (Sonnet), checked here; it put eight methods inside docstrings, which
  were moved out). The seven new verbs and the three file verbs each have a
  test in an application window. Tests: `test_referenced_document_editor`
  134/134, with a group of a pane change and a file edit as one step of the
  window and one of the file; `test_assistant_documentation` 2756/2756, so the
  three errors of the file operations are gone; `test_assistant_verbs` 83/83;
  `test_chart_verbs` 11/11; `test_sequencechart_verbs` 18/18;
  `test_data_frame_verbs` 5/5; the arrangement, workflow, research, roster and
  data frame cell tests pass; both naming guards pass.
  `test_pivot_zone_edits` fails with one error (31 pass): the drag in a tab of an
  application window finds no text "Rows" (`_pz_place`). It fails in the same way
  on 3854cec3e, the commit before step 3. In omnet-julia,
  `test_ide_documentation` passes 967/967 and its part test 52/52,
  `test_prompt_names` 20/20 and `test_workbench_open_file` 9/9.
  `test_pane_program` fails once at line 227, a click into a grid that calls no
  verb, as on main. `test_ide_file_navigator` fails twice: a Julia file and a
  Markdown file that `open_pane!` places draw no text after one frame. The Julia
  file fails on main since 2026-10-08; the Markdown file was not checked on a
  base. `open_pane!` evaluates the same operation as before step 3, and the new
  tab stays behind the tab that its group shows.

### 5.4 Facts found in step 4

- **The generator is `describe_api`.** It takes one keyword for each part
  (`module_sentences`, `function_names`, `function_sentences`, `types`) and a
  `preset`, `:full` or `:compact`, from `API_INDEX_PRESETS`; a part that is
  `nothing` takes the value of the preset. `signatures` writes each function as
  its signature, as the search hits do. Two entries of one module are one group.
  A search with no hit answers the compact index with the type names, where it
  answered all names on one line before.
- **The setting is the group `AssistantIndexSettings`,** "Assistant index" in
  the settings tab, read at the start, in the start settings of the
  application. `describe_api_index(api, backend; settings)` gives the index of a
  window: the automatic preset gives the compact index to `:ollama` and the full
  index to any other backend, and a part that the settings set wins over the
  preset. Step 6 puts it into the texts; step 4 changes no text.
- **The settings tab orders its groups by name,** so "Assistant index" is its
  first group. Two tests of the tab followed: the test of Tab counts the stops of
  the groups before the faults (a control and a Reset for each setting), and the
  test of the scroll turns the wheel over a label of a setting that is in the
  window.
- **78 module sentences are new** (by an agent (Sonnet), each one read here),
  and 15 were kept. The agent did not wrap its new lines, so a script wrapped the
  paragraph of each new sentence, and only that paragraph. The owner gave
  permission for the first sentence of the sealed `ClockModule.jl`: "Clocks for
  animations: each holds a time in seconds, and a computation that reads it
  computes again when the time changes." The next sentence says only that a
  `Clock` holds its time in a reactive cell.
- **The sizes after the new sentences:** the editor's full index is about 4,900
  tokens and its compact one about 1,500; the IDE's about 6,300 and 2,200. In
  omnet-julia, `test_ide_documentation` passes 967/967 and 52/52, and
  `test_prompt_names` 20/20, with the new sentences.
- **Tests:** `test_declared_api` 175/175, `test_search_answer` 85/85,
  `test_settings_tab` 55/55, `test_assistant_documentation` 2756/2756, both
  naming guards. `test_application` has 2 failures (lines 677 and 800): each
  expects that `open_pane!` or Show moves the focus, which the rule of
  2026-10-27 (8a0c14f1e) ended, and no later commit changed the two lines. The
  settings part of `test_application` with the index passes.

### 5.5 Facts found after the landing of steps 1 to 4

- **The rebase on main** had conflicts in 9 places, each kept both sides: the
  exports `avoids_new_panes` and `compute_document_types` of main beside the
  removed lists and `is_domain_placeholder`; the field `maximized` of `PaneTree`
  beside the mark; the count at the start of a word in the search beside the exact
  hit; and the `grows` of a file tab. Main moved the reload of a file from Ctrl+O
  to F5, so `reload_file_from_disk!` and the file slice guide say F5. In
  omnet-julia, main added `open_chart_baseline!` to the hand list of the IDE, so
  it now carries the mark, and `LegacyTestModule` keeps its new first sentence
  and the second sentence of main.
- **The tests after the landing.** Every test that steps 1 to 4 ran passes
  again, with three exceptions. `test_application` fails at `:682`, `:805` and
  `:2131`, and main before the landing fails at the same three places: the two
  of the focus, and the drag of the divider between the groups (`[250, 988] ==
  [375, 988]`). `test_pivot_zone_edits` keeps its one error. In omnet-julia
  `test_ide_documentation` passes 973/973 and 52/52, `test_prompt_names` 20/20,
  the three workbench file tests pass, and `test_pane_program:227` and the two
  files of `test_ide_file_navigator` fail as before.
- **Two faults of the branch reached main.** `test_search_ranking` made an API
  entry without the field of a family member that step 2 added; a commit of the
  test fixes it. `test_interface_api:92` fails: "a row of widgets side by side"
  answers `jump_to_row!`, `get_table_row_count` and `get_pivot_row_count` first,
  because `jump_to_row!` carries the mark since step 3 and a word of a name ranks
  above the words of a docstring; `WidgetSplitPane` is fourth when every package
  is loaded, and second when only the platform is. The owner agreed (2026-11-05)
  that the test accepts the first five, as for the sentence of
  `parse_natural_text`, and that the ranking stays as it is.
- **The recorded precompile calls** resolve less after the landing:
  ProjecturedPlatform 1618 of 11962 no longer resolve (1233 on main before),
  and ProjecturedChart, ProjecturedDataFrames, ProjecturedSDL and the result and
  format packages of omnet-julia warn too. §6 says to record them again.

### 5.6 Facts found in step 5

- **The header.** 170 documents carry `**For:**` after the kind: 161 in
  projectured-julia, and the 9 guides of omnet-julia. The slide deck has no
  header line, and a guide without one is for developers. For users: in
  projectured-julia `assistant-guide`, `context-menu-guide`, `dragging-guide`,
  `examples-tour`, `gestures-guide`, `keyboard-and-mouse-guide`, `mcp-guide`,
  `orientation`, `own-project-guide`, `pointer-guide`, `popup-window-guide`,
  `setup-guide`, `tooltip-guide` and `view-your-data-guide`, and in omnet-julia
  `assistant-guide` and `vs-code-mcp-guide`. For both: `documentation/README.md`.
  Every other document is for developers: the 6 other guides of
  projectured-julia (build, debugging, new domain, release, static compilation,
  testing), the 7 others of omnet-julia, and every package, design, rule,
  requirement and presentation document.
- **The rule.** `documentation/README.md` defines the field, and the header
  check of `test/suite/documentation.jl` refuses a header without a known value.
  The README of omnet-julia defines it for the documents in `guide/`, the only
  ones that a search reads.
- **The search.** A section of a guide carries the kind and the readers of its
  header. `search_guides` ranks every section as before and keeps those of the
  audience, so the meaning vectors of the sections stay as they are. The line of
  the other audience counts the documents of the other audience that the words
  match, and it stands after the note of a meaning model, before the hits. The
  measurement of the search scale searches with `audience = "all"`, so its
  questions keep their corpus. A test whose answer is a document for developers
  asks for that audience.
- **Tests:** `test_search_answer` 102/102, `test_relevance_search` 36/36,
  `test_meaning_search` 70/70, `test_search_query` 61/61, `test_search_ranking`
  27/27, `test_declared_api` 175/175, `test_search_guides` 6/6,
  `test_search_tools_registered` 8/8, the header check of the documentation.

### 5.7 Facts found in step 6

- **The composition.** `make_assistant_system(text, api; backend, settings)` in the
  application slice joins the text of a window, the paragraph of the loaded
  domains and the index of the names of `api` for `backend`, after the line "THE
  NAMES THAT YOU CAN WRITE, by module". `make_application_system(; backend,
  settings)` and `make_ide_system(; backend, settings)` make the text of each
  window with it. `EDITOR_SYSTEM` holds the tools and the rules of every window and
  names only the verbs that its rules need; `APPLICATION_SYSTEM` and
  `CAMPAIGN_SYSTEM` each add what the window is and one worked example, and
  `IDE_SYSTEM` adds a paragraph about the tests and the studies. The type of the
  keyword `settings` is not written in the application slice, because
  `StartSettings.jl`, which defines `AssistantIndexSettings`, needs
  `APPLICATION_ASSISTANTS` of `Application.jl` and is included after it.
- **The paths.** The built-in loop reads the `system` of the assistant, which the
  window makes for its backend. An ACP session gets `DEFAULT_AGENT_INSTRUCTIONS`,
  now only the two paragraphs about the person's editor and the agent's own file
  tools, then the `system` of its assistant; the MCP server of the agent sends one
  sentence, so the text is not sent twice. An outside client of the application
  reads the text with the full index (`backend = :mcp`). The IDE makes one text
  for the backend of its assistant, and its MCP server sends that text, so an
  outside client of an IDE with a local model reads the compact index; it is one
  window and one text. A window binary passes the setting "Assistant index" of
  its start as `index_settings`. `DEFAULT_ASSISTANT_SYSTEM` is a short fallback
  for an assistant whose window gives no text. `EDITOR_TOOL_GUIDE`, the section
  "Reach what a tab holds" in the text of the application and the 15 study
  sections of the IDE text (`STUDY_GUIDE_SECTIONS`) are gone.
- **The sizes** (a token is about four characters):

  | Text | Words | Tokens |
  |---|---|---|
  | `EDITOR_SYSTEM` | 465 | about 680 |
  | `APPLICATION_SYSTEM` | 675 | about 1,030 |
  | the application, full index | 4,147 | about 9,130 |
  | the application, compact index | 1,733 | about 4,300 |
  | `IDE_SYSTEM` | 971 | about 1,530 |
  | the IDE, full index | 4,443 | about 9,630 |
  | the IDE, compact index | 2,029 | about 4,800 |

  The paragraph of the loaded domains is a large part of what is left: it is the
  same in both sizes.
- **The guides.** The orientation guide shows each capability in code, from a
  search of a name to long work, without the table of concepts, and keeps the
  section "Reach what a tab holds", which the docstring of `read_guide_section`
  names. The IDE's assistant guide has its sections by kind of work, its
  introduction names the orientation guide for the verbs of every window, and a
  tab is found with `find_pane(title)` and read with `get_edited_document`. The
  guide named `build_editor`, `ProjecturedPlatform` and `get_window_tree`, which
  the window does not offer; those lines are gone. The questions of the search
  measurement of omnet-julia name the new headings; one of them named a heading
  that did not exist any more ("run it in the page").
- **The names test.** `test_assistant_documentation` reads the text of the
  application and the orientation guide, and `test_prompt_names` the texts of the
  two IDE windows and the IDE's assistant guide: each name in backticks, and each
  function that a code block calls, is a name that the window offers, a tool or
  an argument of a tool, or a name that no offered module defines.
- **Tests:** `test_assistant_documentation` 2810/2810, `test_assistant_verbs`
  83/83, `test_application` with its 3 known failures (`:682`, `:805`, `:2131`),
  `test_external_agent_turn` 308/308 with the platform test package alone (in a
  process that also loads ProjecturedMCP, the turn starts an MCP server for the
  stand-in editor of the test, which has no tools, and many of its tests fail);
  in omnet-julia `test_prompt_names` 3/3, 4/4 and 187/187, `test_ide_documentation`
  973/973 and 52/52, `test_result_verbs` 68/68, `test_ide_assistant_verbs` 10/10.

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
2. ~~**The mark on a supertype** (§4.1).~~ Decided by the owner (2026-11-02): a mark
   on a type also offers its subtypes (option A).
3. ~~**The text answers.**~~ Decided by the owner (2026-11-04): a verb answers a
   `String`, and the code tool shows a `String` with a line break as its plain
   lines (§4.7).
4. ~~**The rank of a family member in the search.**~~ Decided by the owner
   (2026-11-02): a name with its own mark ranks above a name that only its family
   offers. The word ranking ranks in tiers: an exact name first, then the marked
   names, then the members; each tier weighs its words among its own entries. A
   ranking by meaning or by a relevance model keeps its order inside each tier.
   Two more changes, agreed by the owner the same day: a keyword query of two or
   more plain words that are exactly the words of a name is an exact hit of that
   name ("find pane" is `find_pane`); and the two tests of a sentence search, which
   run with no model of meaning, expect the right name among the first three. The
   owner accepted the first five for one sentence (2026-11-03): "make a document of
   a domain from its text" ranks `parse_natural_text` fourth, below `TextDocument`,
   `make_text_block` and `make_table_document`, which are makers that fit as well.
   The same for "a row of widgets side by side" (2026-11-05): `WidgetSplitPane`
   is fourth, below three verbs of the rows of a table, when every package is
   loaded.
