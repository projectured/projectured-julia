# A verb gets the editor of the evaluation

> **Kind:** plan · **Status:** pending, 2026-10-06. The owner decided the
> mechanism, the form of a verb and the names (§2). The place of the rule, D3
> and D4 are open (§9). Step 2 waits for the place of the rule, and step 3
> waits for D4. ·
> **Stands on:** [PAR-PER-EDITOR-STATE](../../documentation/rule/architecture-invariants.md#par-per-editor-state),
> [code-quality-rules.md §4](../../documentation/rule/code-quality-rules.md),
> [agent.md](../../documentation/package/kernel/agent.md),
> [assistant-editor-reference.md](../done/assistant-editor-reference.md)

## 1. The goal

A person in the evaluator and a model through `execute_julia_code` write
`focus_pane!(tab)`, not `focus_pane!(editor, tab)`. The verb acts on the editor
that runs the code.

Three things do not change:

- One process runs many editors (PAR-PER-EDITOR-STATE).
- Code that has an editor passes it, and the verb acts on that editor.
- An edit is an operation that the editor evaluates, so undo, the logs and the
  mouse target stay correct.

## 2. The owner's decisions (2026-10-06)

- **The editor of an evaluation is a `ScopedValue`, bound for the time of one
  evaluation.** The verbs read it when the caller gives no editor. The owner
  said: "yes, I accept the scoped value, write the plan".
- **D1: the editor is a keyword of the verb**, form A of §9:
  `focus_pane!(reference; editor = get_evaluation_editor())`. The owner said:
  "I agree, it's option A". The reason is the rule of §3: "Anything that a
  caller may leave out is a keyword."
- **D2, the names:** `get_evaluation_editor()` and
  `MissingEvaluationEditorException`. The owner said: "I accept the names".

## 3. What exists

- **The binding is a global variable now.** `_run_expression` writes
  `editor = target` into the scratch module before each call
  ([CodeExecution.jl:318](../../source/kernel/tool/CodeExecution.jl#L318)). The
  evaluator sets it to `nothing` after each evaluation
  ([Evaluator.jl:427](../../source/platform/conversation/Evaluator.jl#L427)).
  The code that the person or the model types can see this global. The verbs
  that the code calls can not see it, so each verb takes `editor` as an
  argument.
- **One function is the entry for every caller.** `_run_expression` runs the
  code for `execute_julia_code!` and `execute_julia_expression!`. Each caller
  gives the editor as `target`:
  - the MCP tool and the tool call of the assistant, through the handler in
    [DefaultTools.jl:150](../../source/kernel/tool/DefaultTools.jl#L150);
  - the code of the assistant,
    [AssistantTurn.jl:214](../../source/platform/assistant/AssistantTurn.jl#L214);
  - the composer,
    [ConversationEditor.jl:381](../../source/platform/conversation/ConversationEditor.jl#L381);
  - the evaluator, two calls,
    [Evaluator.jl:420-422](../../source/platform/conversation/Evaluator.jl#L420-L422).
- **The MCP call runs on the task of the editor.** The server calls
  `run_on_editor_task!(editor)` and then `tool.handler(editor, args)`
  ([McpServer.jl:165-179](../../source/adapter/mcp/McpServer.jl#L165-L179)).
- **A precedent exists.** `_PAINTING_EDITOR` is a `ScopedValue` that holds the
  editor for one paint
  ([FaultBarriers.jl:49](../../source/kernel/editor/FaultBarriers.jl#L49)), and
  `ReadEvaluatePrint.jl:202` binds it.
- **The rule permits it.** PAR-PER-EDITOR-STATE: "State that belongs to a
  single *evaluation* rather than to an editor is instead task-local (its
  natural scope)."
- **Julia gives the scope to a task that starts in it.** Measured on Julia
  1.13.1: inside `with(S => :a)`, `@async S[]` and `Threads.@spawn S[]` both
  answer `:a`. After the `with`, `S[]` answers `nothing`. A task does not get
  `task_local_storage` from its parent: `@async` answers `nothing` for a key
  that the parent set.
- **The argument rule.** [code-quality-rules.md §4](../../documentation/rule/code-quality-rules.md):
  "Anything that a caller may leave out is a keyword", and "The subject comes
  first — the document, the store, the editor". The guard
  `test/suite/arguments.jl` parses each definition and loads nothing.
- **The functions that take `editor` first.** `source/` has 204 such methods.
  Only 41 methods of 31 verbs are in the scope of this plan; §4 lists them all.
- **None of the files to change is sealed.** `tool/` (layer 18) and
  `editor/ReadEvaluatePrint.jl` are `⬜` in [SEALING.md](../../SEALING.md).
  Check each file again before its edit, because the marks change.

## 4. The verbs

A survey of 2026-10-06 parsed every definition whose first positional argument
is `editor`. A count of calls is the count of `name(` outside the file of the
definition, as source / test / documentation. A count can include a method of
the same name that takes no editor.

### 4.1 projectured-julia

`source/` has 204 such methods:

| group | methods | the editor |
| --- | ---: | --- |
| private, `_` first | 46 | stays explicit |
| `evaluate_operation` | 87 | stays explicit |
| the editor loop | 20 | stays explicit |
| other functions whose subject is the editor | 10 | stays explicit |
| verbs | 41 methods, 31 names | this plan |

The other functions whose subject is the editor are `start_settings!`,
`read_settings_from_editor!`, `apply_settings_to_editor!`,
`is_settings_group_used`, `apply_settings!(editor::Editor, ::FaultSettings)`,
`McpServer`, `render_mcp_tools`, `play_live!` and `post_pane_operation!` (two
methods).

**The 13 declared verbs.** `make_pane_api()`
([PaneProgram.jl:90](../../source/platform/pane/PaneProgram.jl#L90)) and
`make_application_api()`
([Application.jl:316](../../source/platform/application/Application.jl#L316))
declare them, so a model sees them.

| verb | the editor | calls |
| --- | --- | --- |
| `open_pane!` | makes an operation and evaluates it | 43 / 30 / 33 |
| `find_pane` | reads the tree of the document | 13 / 34 / 8 |
| `focus_pane!` | makes an operation and evaluates it | 3 / 14 / 19 |
| `find_pane_reference` | reads the tree of the document | 0 / 19 / 12 |
| `insert_elements!` | makes an operation and evaluates it | 4 / 4 / 14 |
| `replace_referenced_value!` | makes an operation and evaluates it | 3 / 2 / 15 |
| `get_referenced_value` | reads the tree of the document | 0 / 9 / 9 |
| `find_pane_tree_reference` | reads the selection | 3 / 5 / 9 |
| `close_pane!` | makes an operation and evaluates it | 0 / 8 / 7 |
| `delete_elements!` | makes an operation and evaluates it | 2 / 2 / 8 |
| `move_pane!` | makes an operation and evaluates it | 0 / 4 / 4 |
| `show_layout` | reads the tree of the document | 0 / 1 / 7 |
| `duplicate_pane!` | makes an operation and evaluates it | 0 / 2 / 5 |
| **sum** | | **71 / 134 / 150** |

**The 18 verbs that are exported but not declared.** A person in the evaluator
can call them, because the evaluator has the whole surface.

- `get_window_tree`. Not declared on purpose
  ([PaneProgram.jl:88](../../source/platform/pane/PaneProgram.jl#L88)). It has a
  method for a tree already: `get_window_tree(tree::PaneTree) = tree`.
- The five `make_*_pane_operation` functions, `get_pane_file_group`,
  `show_document!` (three methods), `open_file_dialog!`, `save_file_dialog!`,
  `save_user_interface`, `find_editor_appearance` and `find_editor_settings`.
- `find_rooted_operation`, `read_rooted_operation`, `sync_draft_selection!`,
  `copy_system_colors!` and `copy_zoom_to_display!`. The code that calls them is
  an operation evaluation or a wrapper that has the editor already. Nine of the
  eleven calls of `sync_draft_selection!` are in its own file.

**No new method clashes with a method that exists.**
The guards `close_pane!(_, ::Nothing)` and `focus_pane!(_, ::Nothing)` change
together with their verbs.

**Three verbs have an optional positional argument:**
`delete_elements!(editor::Editor, collection, index::Integer, count::Integer = 1)`,
`open_file_dialog!(editor, directory::AbstractString = pwd())` and
`save_file_dialog!(editor, file, directory::AbstractString = pwd())`.

**How a verb reaches the task of the editor.** A pane verb evaluates its
operation at once, through `_evaluate_pane_operation!`. A call from a task on
another thread is not safe, now or after this plan.

### 4.2 omnet-julia

The repository, outside `test/`, has 66 such methods: 15 private, 6
`evaluate_operation`, and 45 verbs with one method each.

- **29 verbs are declared:** `CampaignVerbs` (3), `TaskVerbs` (15) in
  `make_campaign_api()`, `ResultVerbsModule` (2) in `make_result_api()`, and
  `StudyVerbsModule` (9) in `make_study_api()`. Their calls are about
  85 / 84 / 99.
- **16 are not declared:** three helpers of `tool/assistant/study_rehearsal.jl`;
  `get_runner_filter` and `wait_for_task_group!`, which are not exported on
  purpose; six functions of the demo `demo/recording/Mm1kDocument.jl`;
  `watch_notebook!` and `install_notebook!`, which set up an editor; and
  `open_task_group_pane`, `run_filter_in_new_pane!` and `show_task_group_pane!`,
  which buttons call.
- **A verb does its work on the task of the editor**, through
  `run_on_editor_task!`. A person at the plain REPL calls the same verbs while
  the window runs on another thread. The docstring of `CampaignVerbs` says:
  "**Every verb takes the editor first**".
- `run_filter_in_new_pane!` and `show_task_group_pane!` have a method that
  takes a `PaneTree` in place of the editor.
- `check_expectations!(editor)`, `save_study!(editor)` and `stop_task!` share
  their names with functions of other arities. No clash.

## 5. The design

### 5.1 The scoped value

The scoped value is in `ToolModule`, beside `_run_expression`, because
`ToolModule` is below `EditorModule` and `_run_expression` binds it.

```julia
# The editor that runs the code of this evaluation, or `nothing` outside one.
const _EVALUATION_EDITOR = ScopedValue{Any}(nothing)

"""
    get_evaluation_editor() -> editor

The editor that runs the code of this evaluation: the code of the evaluator, of
the assistant, or of `execute_julia_code`. Throws `MissingEvaluationEditorException`
outside an evaluation, and its message tells the caller to pass `editor`.
"""
function get_evaluation_editor()
    editor = _EVALUATION_EDITOR[]
    editor === nothing && throw(MissingEvaluationEditorException())
    editor
end
```

`_run_expression` binds it around the statements of one call:

```julia
with(_EVALUATION_EDITOR => target) do
    # the Core.eval of each statement, as now
end
```

- The five callers of §3 need no change, because they all go through
  `_run_expression`.
- Nothing clears it. The scope ends when the call ends.
- A task that the code starts gets the editor. A callback, a cell or a timer
  that runs later from another task does not get it, and the verb throws.
- **Proposed:** the global `editor` in the scratch module stays (D3). Code that
  reads `editor.document` keeps working.

### 5.2 Who reads it

Only a verb reads the scoped value, and only when the caller gives no editor.
The editor is a keyword of the verb (D1):

```julia
focus_pane!(reference::Reference; editor = get_evaluation_editor()) = …
```

- One method for each verb. A call that has an editor passes it:
  `focus_pane!(reference; editor)`.
- A verb that dispatches on the type of the editor moves that dispatch to a
  private helper, which takes the editor first.
- A method that forwards to another method of the verb passes `editor` on.

### 5.3 What keeps the explicit editor

- `evaluate_operation(editor, op)`. The editor gives itself to the operation
  that it evaluates. This is the owner's rule of 2026-10-05: "an act gets the
  editor when it is evaluated".
- The editor loop: `run_frame!`, `drain_operations!` and the others. The editor
  is their subject.
- Projections, printers, readers and cells. PAR-NO-PROJECTION-GLOBALS applies to
  them, and a projection never reads the state of another projection.
- The tool dispatch: `tool.handler(editor, args)`,
  `execute_julia_code!(set, editor, code)`. §6 says why.

### 5.4 The rule and the guard

- **Proposed (D2):** add one paragraph to PAR-PER-EDITOR-STATE, after the
  sentence about state of a single evaluation. It says that the editor of an
  evaluation is a scoped value that `_run_expression` binds, and that only a
  verb reads it, when the caller gives no editor.
- The guard is in `test/suite/arguments.jl`, because that guard parses the
  definitions already. It fails where `get_evaluation_editor` occurs outside its
  own definition and outside the default of an `editor` keyword.

## 6. The earlier decision about task-local storage

[assistant-editor-reference.md](../done/assistant-editor-reference.md)
(2026-06-03) chose an explicit argument for the tool dispatch. It rejected
task-local storage for two reasons: it is ambient, and "a future contributor
refactoring the agent loop to use a thread pool would lose the editor
silently". [assistant.md](../../documentation/package/platform/assistant/assistant.md)
line 94 records this.

This plan keeps that decision:

- The dispatch still passes the editor as an argument. The scope starts from
  that argument, in one place, and only a verb reads it.
- A `ScopedValue` is not `task_local_storage`. A task started with
  `Threads.@spawn` gets the scope (§3, measured), so a thread pool does not lose
  the editor.
- Code outside the scope gets an exception that names the fix. It never gets
  the wrong editor.

The sentence in assistant.md stays true. Step 4 adds one sentence after it
about the verbs.

## 7. The steps

Each step is one commit or more, in a worktree. Mark a step done here when it
lands on the branch.

1. **The scoped value.** Add `_EVALUATION_EDITOR`, `get_evaluation_editor` and
   `MissingEvaluationEditorException` to `ToolModule`, and bind the value in
   `_run_expression`.
   Tests: in `test_code_execution()` (`test/kernel/tool/CodeExecutionTest.jl`),
   code that calls `get_evaluation_editor()` answers the target, and so does
   code that reads it in an `@async` and in a `Threads.@spawn` task. After the
   call, `get_evaluation_editor()` throws. Two `ToolSet`s with two targets each
   answer their own target. In `test_evaluator_toplevel()`, a form answers the
   editor of the evaluator.

   **Done 2026-10-06** (6151ec8ae). What the implementation found:
   - `with(_EVALUATION_EDITOR => target)` wraps only the `redirect_stdio` block
     that evaluates the statements. The parse and the description of the value
     run outside it, because they call no verb.
   - The test is the verb `get_toy_editor(; editor = get_evaluation_editor())` in
     a declared toy module `EditorToy`. It also checks that a task that the code
     starts and that ends after the call still answers the editor of its own
     call, and that code with the target `nothing` answers the exception as its
     message. `test_code_execution()` 66 / 66, `test_evaluator_toplevel()`
     239 / 239.
   - The static guards (naming, arguments, exports, documentation) report the
     same faults as `main` ffb99115a, and none in a changed file.
   - The first precompile of `environment/all` in the worktree went over a cap of
     10 GB with two precompile tasks, and the OOM killer stopped it. A second run
     that only loads needs 2.1 GB.
2. **The rule and the guard** (§5.4). Test: `test_arguments()`, and one case
   that the guard must refuse.
3. **The verbs of projectured-julia**, with the editor as a keyword, and their docstrings,
   their call sites and their tests. First the 13 declared verbs, then the
   verbs that D4 adds. Test: the test function of each slice that holds a verb,
   and `test_referenced_document_editor()`.
4. **The text that the model reads.** The descriptions keep the sentence that
   `editor` is bound (D3), and they show the verbs without `editor`:
   - `_EDITING_VERBS`, `_WHOLE_SURFACE_DESCRIPTION` and the declared description
     in [DefaultTools.jl](../../source/kernel/tool/DefaultTools.jl);
   - [mcp-guide.md:54](../../documentation/guide/mcp-guide.md),
     [assistant-guide.md:62](../../documentation/guide/assistant-guide.md),
     [agent.md](../../documentation/package/kernel/agent.md) lines 108 and 186,
     [assistant.md](../../documentation/package/platform/assistant/assistant.md)
     line 94, and the examples in the docstrings.
   `search_api` scores the signature line of a docstring, so each signature must
   still start with the name of the verb. Tests: `test/projectured/SearchRankingTest.jl`,
   `test/projectured/editor/McpSurfaceTest.jl`, `test/kernel/tool/DeclaredApiTest.jl`,
   `test/projectured/CallSiteTest.jl`.
5. **The verbs of omnet-julia**, in its own worktree and commits: the 29
   declared verbs, and the docstring of `CampaignVerbs` that says "Every verb
   takes the editor first". Run `Pkg.precompile` and a scan of the calls,
   because a change of signature in projectured-julia breaks a call there.
6. **A check with the model.** Run `tool/assistant/rehearsal.jl` on the seeds,
   before and after. The model writes the verbs without `editor`, and the count
   of turns that pass does not go down.

## 8. Out of scope

- **The plain Julia REPL** (`jp`, `jo`, `ji`) has no evaluation scope. There the
  caller passes the editor. A REPL AST transform that wraps each input in `with`
  is possible later.
- **The signature of `evaluate_operation`** does not change.
- **The rule that no document holds the editor** does not change. The scoped
  value is not a field of a document.

## 9. Decisions

**D1. The form of a verb. Decided 2026-10-06: A** (§2). The options and the
facts stay here as the reason.

- **A. A keyword.** `focus_pane!(reference; editor = get_evaluation_editor())`.
  One method for each verb. Every call that passes the editor changes from
  `focus_pane!(editor, reference)` to `focus_pane!(reference; editor)`. A verb
  that dispatches on the type of the editor moves that dispatch to a private
  helper.
- **B. A second method.** `focus_pane!(editor, reference)` stays, and
  `focus_pane!(reference)` is added. No call changes. Each verb shows two
  signatures to `search_api`. No method clashes now (§4.1), but each new verb
  can clash with a method of the same arity.
- **C. The scope only.** The verb takes no editor at all, and a caller that has
  one wraps the call in `with`. The fewest signatures, but every call from the
  code of a package then depends on a value that the reader can not see.

Facts for D1:

- In form A, the three verbs with an optional positional argument (§4.1) break
  the clause "never one beside a keyword argument". `count` and `directory`
  then become keywords too, or take an `# @optional:` marker.
- The cost of form A is the calls: about 71 / 134 / 150 for the 13 declared
  verbs of projectured-julia, and about 85 / 84 / 99 for the 29 of omnet-julia.
  `workspace/bin/julia-rename.jl` renames a name. It does not move an argument,
  so the change needs a tool of its own or edits by hand.
- A person at the plain REPL passes the editor in both forms: in A as
  `editor = e`, in B as the first argument, as now.

The recommendation before the decision was A, for the rule of §3. Form B
keeps the editor as an optional positional argument in two methods, so the
guard does not see it, but the rule says no.

**D2. The names and the place of the rule.**

- **The names. Decided 2026-10-06** (§2): `get_evaluation_editor` and
  `MissingEvaluationEditorException`. The function is `get_`, not `find_`,
  because it never returns `nothing`: it throws outside an evaluation. The
  exception puts its adjective first, as `RecordedFaultException` does.
- **Open: the place of the rule.** Proposed: a paragraph in
  PAR-PER-EDITOR-STATE, because that invariant already says that state of one
  evaluation is task-local, and the guard of §5.4 enforces the rule. The other
  option is a new invariant, with an ID of its own that the seal audit can name.

**D3. Open: the global `editor` in the scratch module.** Proposed: it stays, so
that code that reads `editor.document` keeps working.

**D4. Open: which verbs, and the three optional arguments.** Proposed: the 13
declared verbs, and then the exported verbs of §4.1 except the last group
(`find_rooted_operation`, `read_rooted_operation`, `sync_draft_selection!`,
`copy_system_colors!`, `copy_zoom_to_display!`). The code that calls those five
has the editor already. Proposed: `count` of `delete_elements!` and `directory`
of the two file dialogs become keywords, with no marker.

## 10. Risks

- **A dependency that the reader can not see.** The guard of §5.4 holds it to the
  verbs.
- **Code that runs late.** A callback outside the scope gets
  `MissingEvaluationEditorException`, and its message names the fix.
- **A task on another thread.** A task that the code starts gets the editor and
  can call a verb from another thread. The verbs of omnet-julia run their work
  with `run_on_editor_task!`. The pane verbs of projectured-julia evaluate at
  once (§4.1), so such a call is not safe. It is not safe now either, but the
  scope makes the call easier to write.
- **Two editors.** Code in editor A that makes editor B must pass
  `editor = b`. A verb without it acts on A. Step 1 tests two targets.
- **A stand-in editor in a test.** A test that passes a `NamedTuple` as the
  editor still passes it. The scoped value is `ScopedValue{Any}`.
