# Duplicate the explorer and the evaluator

## 1. The goal

The tab of the file explorer (`Workspace`) and the tab of the evaluator
(`EvaluatorToplevel`) show no `+` above their `x`, because their kinds declare no
duplicate. A person must be able to duplicate both, with the `+` and with
`Ctrl+Shift+D`, as the assistant and the widget tabs do.

The mechanism exists: `plan/done/duplicate-a-pane.md` made it. This plan only
declares the duplicate of three kinds and adds one copy method.

## 2. What is known, 2026-09-25

A probe script declared the duplicates at run time, with no source change, and
made duplicates of a real explorer and of an evaluator after four evaluations.

### 2a. The explorer

- `Workspace` holds `folders::CellVector` of `WorkspaceFolder`, and a folder
  holds two strings, `name` and `pathname`. Nothing holds a function, a `Ref`, a
  task or a cell that computes.
- A declaration on `Workspace` alone gives a duplicate that shares the
  `WorkspaceFolder` node with the original. A declaration on the abstract
  `WorkspaceDocument` copies the folders, and a change of `pathname` in the
  duplicate does not change the original.
- The row selection and the closed folders are not in `Workspace`. The reader of
  `WorkspaceToFileSystemDirectory` writes a row selection on the computed
  `FileSystemDirectory`, and the `collapsed` set is a cell of the `WidgetTree`
  that `FileSystemToWidgetTree` makes. So the duplicate opens with no row
  selected and with every folder open.

### 2b. The evaluator

- `EvaluatorToplevel` holds `elements` (a `CellVector` of `EvaluatorForm`), view
  state (`follow_end`, the three `history_` fields) and two options. An
  `EvaluatorForm` holds the code in `form`, the value in `result`, the fold
  flags, and plain values (`source`, `tool_name`, `input`).
- A declaration on `EvaluatorDocument` alone copies the forms, the fold flags,
  the history state and the caret. But the walk shares every Julia document,
  because the Julia domain declares no duplicate:
  - the code of each form that the evaluation parsed (`JuliaAssignment`,
    `JuliaCall`);
  - the bottom form when "Type structured forms" is on, a `JuliaInsertion`. Text
    typed into the bottom form of one pane goes into both.
- A declaration on `JuliaDocument` copies them. The copy prints the same text.
- A result can be a live document. `CellVector(@computation Any[1, 2])` as a
  result makes the whole duplicate refuse: "it computes its value, and a copy
  would not follow what it reads". A widget with a validator refuses too. A `+`
  that refuses only logs a warning.
- A method `copy_document(::DuplicatePolicy, ::EvaluatorForm)` that gives the
  result as a replacement makes the duplicate share the result. An evaluation
  in the duplicate then writes a new result cell of the duplicate, and the
  original does not change.
- All evaluators of one window evaluate in one namespace, keyed by the
  `ToolSet` of the editor. The duplicate reads a name that the original bound:
  `x = 1 + 1` in the original, then `x + 10` in the duplicate gives `12`.
- The transcript of an assistant holds each tool call as an `EvaluatorForm`
  part. The fork of an assistant shares these parts now, so a fold in the fork
  folds the original. With this plan, the fork gets forms of its own and shares
  only their results.
- The clipboard uses a duplicate only for a kind that refuses a paste
  (`accepts_pasted_document`). `Workspace`, the evaluator and the Julia domain
  accept a paste, so a copy gesture does not change.

### 2c. The files

- None of the files that this plan changes is sealed: `Workspace.jl`,
  `FileSystemModule.jl`, `Evaluator.jl`, `JuliaDocument.jl`, `JuliaModule.jl`.
- `ConversationModule` already imports `copy_document` and
  `has_document_duplicate`. `FileSystemModule` and `JuliaModule` import neither.

## 3. The decisions

The report of 2026-09-25 gave three recommendations, and the user answered
"yes" to it.

- **D1. The duplicate of the explorer opens fresh.** Same folders, no row
  selected, every folder open. A plan of its own can move the row selection and
  the closed folders into `Workspace`, so that the duplicate takes them.
- **D2. The evaluators of a window stay one session.** The duplicate evaluates
  in the namespace of the window.
- **D3. A form shares its result.** A result is history, and it can be live.

## 4. The design

```julia
# Workspace.jl
has_document_duplicate(::WorkspaceDocument) = true

# JuliaDocument.jl
has_document_duplicate(::JuliaDocument) = true

# Evaluator.jl
has_document_duplicate(::EvaluatorDocument) = true
copy_document(policy::DuplicatePolicy, form::EvaluatorForm) =
    copy_document_fields(policy, form; result = form.result)
```

## 5. The steps

Work in the worktree `../projectured-julia-duplicate-tools`, on the branch
`duplicate-tools`. Commit each step.

- [x] **Step 1. The Julia domain declares a duplicate.** `JuliaDocument.jl` and
  the import in `JuliaModule.jl`. A test in `test/julia/document/`: a parsed
  document and an insertion have a duplicate that prints the same text and
  shares no node.
  - Done. `test_julia_duplicate()` sweeps every `make_julia_*_document_example`.
    It compares `print_natural_text`, not the `Expr`: a fragment example such as
    ` where {T}` becomes an `Expr` that holds a `ParseError`, and two
    `ParseError` values are never `==`. `test_julia_layering()`,
    `test_julia_duplicate()` and `test_julia_expression()` pass, 306 tests.
- [x] **Step 2. The explorer declares a duplicate.** `Workspace.jl` and the
  import in `FileSystemModule.jl`. A test in `test/filesystem/document/`: the
  folders are copied, and a change in the duplicate leaves the original.
  - Done. `test_workspace_duplicate()` also duplicates an explorer tab through
    `make_pane_duplicate_tab_operation`: the duplicate is the next tab,
    "Explorer (2)", with the focus. `test_filesystem_layering()` and
    `test_workspace_duplicate()` pass, 25 tests.
- [ ] **Step 3. The evaluator declares a duplicate, and a form shares its
  result.** `Evaluator.jl`. A test in `test/projectured/editor/`: after real
  evaluations the duplicate owns its forms, its code and its folds; it shares a
  live result; its bottom hole is its own; it evaluates alone in the shared
  namespace. Run `test_assistant_duplicate()` and `test_evaluator_toplevel()`.
- [ ] **Step 4. The guides.** `filesystem.md`, `conversation.md` and `julia.md`
  say that the kind has a duplicate and what it shares.
- [ ] **Step 5. The narrow tests and the layering guards,** then move this plan
  to `plan/done/`.
