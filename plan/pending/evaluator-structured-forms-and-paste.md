# The evaluator takes structured forms, pasted objects and pasted references

**Status (2026-09-23): IN PROGRESS.** Worktree
`../projectured-julia-evaluator-structured-forms`, branch
`evaluator-structured-forms`, from `main` at `f6b60214`. The owner agreed to the
recommended answer of every question in section 4, to the switch of section 2D,
and to the five mechanisms of section 3, on 2026-09-23.

**Goal:** a person copies or notes an object in the editor, such as a widget, and
pastes it into a form of an Evaluator tab, to call a function on it. A person
also copies the *reference* of a selected object and pastes it into a form. To
hold an object, a form must be a structured Julia document and not a string, so
a new field of `EvaluatorToplevel` lets a person type structured forms.

## 1. What exists

- **Copy and note.** The clipboard holds a `ClipboardSlice` in front of the
  window (`source/clipboard/ClipboardWrapper.jl:14,37`). `Ctrl+C` stores an
  independent copy made by `ClipboardCopyPolicy`, and `Ctrl+N` stores the live
  object itself (`source/clipboard/Clipboard.jl:161-190`). `Ctrl+V` pastes,
  and `Ctrl+Shift+V` pastes a fresh copy each time
  (`source/clipboard/ClipboardSliceToAny.jl:397-420`). So to call a function
  on the widget that the window shows, a person notes it; a copy is a
  different object.
- **A paste has two kinds of target** (`source/clipboard/Clipboard.jl:192-220`,
  `268-313`). At a caret or a range in a string field it pastes *text*, the
  same edit that typing makes, and reads the text of the operating system's
  clipboard first. At a *whole-element selection* it writes the pasted document
  into the slot, when every document on the way accepts a paste. It converts
  nothing: the slot receives the document as it is. `EvaluatorToplevel` and
  `EvaluatorForm` accept a paste; the conversation and the assistant refuse.
- **Alt+click selects an object whole**, and Alt with the arrows walks the tree
  (`plan/pending/select-a-widget-and-paste-it-into-a-tab.md`, steps 0-12 on
  `main`).
- **The Julia domain types structure through holes.** `JuliaInsertion`
  (`source/julia/JuliaDocument.jl:13`) is a text buffer. Enter or Tab commits
  it: a keyword such as `function` becomes a scaffold of new holes, and other
  text is parsed into a Julia document in place of the hole
  (`source/julia/JuliaInsertionToSyntax.jl:87,168,185`). The composer uses the
  same insertion for a Julia part (`documentation/package/conversation/
  conversation.md`, "The composer").
- **A Julia node holds any document.** `JuliaCall.callee::Document` and
  `arguments::CellVector` take a document of any domain
  (`source/julia/JuliaDocument.jl:106`). No node holds an object that is not
  code, and the Julia notation has no rule to draw one.
- **Every evaluation runs text.** `execute_julia_code(set, target, code)` takes a
  `String`, runs `Meta.parseall`, and binds `editor` in the scratch module
  (`source/kernel/tool/CodeExecution.jl:157-182`). No function turns a Julia
  document into an `Expr`; `JuliaParser.jl` goes only from text to a document.
- **No command copies a reference.** A reference prints as a dotted path with
  type checkpoints (`source/kernel/reference/ReferencePath.jl:114-127`), and
  `@reference(path)` builds one from the same shape at macro expansion
  (`source/kernel/reference/ReferenceBuilder.jl:204-218`).
- **Typing into a parsed Julia tree is still weak.** A caret inside an
  identifier or a symbol is not reached: 28 positions of `julia_example` fail
  (`plan/pending/julia-syntax-navigation.md`).

## 2. The design

### A. A structured form

`EvaluatorToplevel` gains a field, proposed name `type_structured_forms::Bool`.
When it is on, a fresh form holds a `JuliaInsertion` instead of a
`PrimitiveString`, as the Julia part of the composer does. A person types code
into the hole; the Julia domain commits holes; Enter evaluates (Q2). A form
without an object evaluates as today: its print is the code.

### B. An object in a form

A person selects a hole of the form whole, or a node of the parsed tree, and
presses `Ctrl+V`. The paste writes the copied or noted object into that slot,
as it already does for any slot. Three things are new:

1. **The Julia notation draws a node that is not Julia as a one-line label**
   (Q4), because a line of syntax can hold only text.
2. **A Julia document becomes an `Expr`**, with a node that is not Julia becoming
   the object itself.
3. **The evaluator runs that `Expr`** in the same scratch module, with the same
   `editor` binding and the same capture of output, when the form holds an
   object. A form without one still runs its text.

### C. Copy a reference

A new key of the clipboard, proposed `Ctrl+Shift+C`, copies the reference of the
complete selection, read from the root document of the editor when the key is
pressed. It writes code that evaluates to the selected object:

    evaluate_reference(editor.document, @reference(<the path>))

It goes to the operating system's clipboard, and to the slice as text. A paste
at a caret pastes text, so the reference goes into a string form and into a
structured form alike, and also into another program.

### D. How a person switches

The two fields are the state of the tab, so the printer of `EvaluatorToplevel`
shows them as widgets: one row above the scroll pane, which stays in place when
the forms scroll.

    ☐ Parse evaluated forms    ☐ Structured forms

Each check box is an existing projection: `ObjectField(object, "field")`
projected by `ObjectFieldToWidget`, which shows a `Bool` field as a
`WidgetCheckbox` that edits it (`source/widget/ObjectFieldToWidget.jl:103`).
The row is two labels and `ObjectField(t, "parse_evaluated_forms")` and
`ObjectField(t, "type_structured_forms")`. How the check box writes its value
back is not read yet; step 2 reads it first, and if the edit does not reach the
field through the reference maps that exist, the step stops and asks.

The gesture table of the toplevel also gains two rules with no key, "Parse
evaluated forms" and "Type structured forms", so a keyboard user switches through
the command palette, and the gesture help lists them. A rule with no key already
reaches a person by name in the JSON domain.

What a switch does:

- **Structured forms changes the bottom form at once, and keeps its text.** A
  `PrimitiveString` becomes a `JuliaInsertion` with the same text, and a
  `JuliaInsertion` becomes a `PrimitiveString`; a form that is already a parsed
  tree becomes the string of its print. The evaluated forms keep their shape.
- **Parse evaluated forms changes only the evaluations that come after it.**

## 3. New mechanisms

The owner said yes to all five on 2026-09-23. None is a `SyntheticEvent`, and
none adds a `read_intent` method for a new payload type.

- **M1. A rule of the Julia notation for a node that is not Julia**: it prints
  as a `SyntaxLeaf` that shows the label of Q4 and takes no typing. It lives in
  the Julia domain's projection, where a projection may cross domains.
- **M2. `make_julia_expression(document) -> Expr`** in the Julia domain: the
  inverse of `convert_expr`, with a node that is not Julia becoming the object.
  Proposed implementation: print a shadow of the form in which each object is a
  unique placeholder name, parse it with `Meta.parseall`, and put each object
  where its name stands. The objects are never copied, so a noted object keeps
  its identity.
- **M3. `execute_julia_expression(set, target, expression)`** in the kernel's
  tool code, beside `execute_julia_code`, which shares everything with it
  except the parse.
- **M4. `CopyReferenceOperation`**, which holds no path and travels up the
  chain unchanged (`operation_travels_unchanged`), like
  `EvaluateSelectedFormOperation`. `evaluate_operation` reads the complete
  selection from `editor.document` and writes the text. It is registered as an
  operation (`PAR-REGISTER-NEW-OPERATION`).
- **M5. A printer of a reference as `@reference` code**, without type
  checkpoints, if the present `show` of a stripped reference does not parse
  back already. Step 6 checks it first.

## 4. Questions for the owner

**Decided on 2026-09-23:** the owner agreed to the recommendation of each.

- **Q1. The default of the new field.** My recommendation: off. A caret inside
  a parsed identifier is not reached yet, so a person who types a plain
  expression is better served by a string form until that is fixed.
- **Q2. Enter in a structured form.** My recommendation: Enter evaluates the
  whole form, and commits an open hole as part of it, as in a string form. Tab
  commits a hole and goes to the next one, as the Julia domain does now, and
  Shift+Enter puts a line break in a hole. The other choice is the composer's:
  Enter commits, Alt+Enter evaluates. Step 1 checks that the evaluator can
  claim Enter before the hole does.
- **Q3. Where an object sits.** My recommendation: the pasted document itself is
  the child of the Julia node, because a paste already writes any document
  into a Julia slot. The other choice is a wrapper node `JuliaValue(object)`
  that the Julia domain owns; the paste would then need a new hook to wrap
  what it pastes.
- **Q4. How an object draws in a form.** My recommendation: its title from
  `get_document_title` in angle marks, such as `⟨Table⟩`, or its type name
  when it has no title. Drawing the object itself inside a line of code is not
  possible, because the chain from syntax to text holds only text.
- **Q5. How a reference is pasted.** My recommendation: as the code text of
  section 2C, which needs no new node and works in every kind of form. The
  other choice is a node `JuliaReference(reference)` that draws as a label and
  evaluates to the object; it reads better but needs its own rule of M1 and M2.
- **Q6. The key of Copy reference.** `Ctrl+Shift+C` is not bound. Step 6 checks
  that the pattern of `Ctrl+C` does not also match it.
- **Q7. Up on a form that holds an object.** The history reads a form as text,
  and the text of an object is only its label, which does not evaluate. My
  recommendation: the history skips such a form in the first version.

## 5. Steps

After the answers, in a worktree, one commit for each step. Every step tests
what renders, through the window with a real `Editor`, as
`test_application()` does.

- [x] **Step 1. The field and a structured form.** *Done.* As built:
  - The field is `type_structured_forms`, off by default. A fresh form holds the
    insertion that `resolve_insertion(Document, "julia")` names, so the
    conversation package still does not depend on the Julia domain;
    `_is_julia_hole` knows the hole by its insertion root and its format `:jl`.
  - A hole and a string form are both *text forms*: they keep their text in
    `value`, so the caret references, Shift+Enter and the history treat them
    alike. The history reads a hole's `value`, because its print adds the pale
    completion hint.
  - Enter commits the hole by the same token rule as a string form, even with
    `parse_evaluated_forms` off, so a hole with a comment stays a hole with its
    text.
  - **The Enter rule is `override`, and the evaluator's projection reads a
    claimed key.** Measured: with the rule alone, the hole's own Enter won in
    the window (a document replace, and no evaluation). An `override` rule
    fires only where a reader offers the claimed key to the document's table,
    which the reader of `@projection_template` does and the generic bridge does
    not. So `EvaluatorToplevelToWidgetComposite` gained that reader, a
    `read_intent` for an `Intent`: a key already answered goes to
    `read_gesture(toplevel, key; claimed)`, and anything else to the generic
    bridge. It is the existing `claimed` path, not a new payload type.
  - **Behaviour change:** Enter evaluates only from the code of a form
    (`_make_evaluate_operation`). Before, Enter with the selection in a result
    evaluated that result's form. Now it answers nothing there, so a result that
    reads Enter keeps it.
  - Tests: `test_evaluator_toplevel()` 164 of 164, `test_application()` 171 of
    171 with a window test of typing, Enter and the one caret in the fresh
    hole; `test_conversation()` keeps its one known failure.
  Originally: **The field and a structured form.** A fresh form is a
  `JuliaInsertion` when the field is on. The keys of Q2. Evaluation of a form
  without an object through its print. Tests: typing, committing, evaluating,
  the history, the field off.
- [x] **Step 2. The switch (section 2D).** *Done.* As built, with three changes
  from section 2D:
  - **No `ObjectField`.** It has no row in the natural projection, and a plain
    write of the field could not convert the bottom form. The evaluator builds
    its own two `WidgetCheckbox`es instead, bound to the fields by a cell
    function, each with per-instance bindings (a plain left press, Space, Enter)
    that answer `ToggleEvaluatorOptionOperation(toplevel, option)`. The check
    box reader reads per-instance bindings before its own toggle
    (`source/widget/WidgetToGraphics.jl`, "per-instance gestures win"), so this
    is an existing mechanism. The operation holds the toplevel and travels up
    unchanged; it carries no path, so the path enumerations need no entry.
  - **A grid of one column, not a `LayoutConstraint`.** The first build put the
    pane in `LayoutConstraint(pane; height = Fill)` under a `VerticalLayout`;
    typing then stopped reaching the form, because
    `LayoutConstraintToGraphicsCanvas` forwards a key to its child with the
    three-argument reader and does not add its `child` step to the answer. A
    `GridLayout` of one column gives each row a policy (`Content`, `Fill`) with
    no wrapper, and routes keys with the same routine as a vertical layout.
    The natural row of the toplevel ends in `GridLayoutToGraphicsCanvas`.
  - **The pane stays transparent through its style.** Drawn through the widget
    row, the pane painted the theme background under the forms (measured: a
    600 × 372 rectangle). `WidgetStyle(content_color = color_transparent)` on
    the pane document overrides it, as `_get_part_color` reads the widget's
    style.
  - The names of the rules are "Parse evaluated forms" and "Type structured
    forms"; the labels of the boxes are "Parse evaluated forms" and "Structured
    forms".
  - **Found on the way, not from this branch:** a `PrimitiveString` now draws as
    a quoted literal, so an empty form draws `""` after its prompt, and a lone
    `PrimitiveString` does too. The evaluator probe of 2026-09-23 before the
    survey-faults work landed drew the same form without quotes. Reported to
    the owner, not changed here.
  - Tests: `test_evaluator_toplevel()` 193 of 193, with the drawn words of the
    toplevel, the options in place while the forms scroll, a press on each box,
    the conversion of the bottom form with its text and caret, and the palette;
    `test_application()` 173 of 173, whose structured-form test now presses the
    box in the window; `test_shell()` passes; `test_conversation()` keeps its
    known failure.
  Originally: Read first how `ObjectFieldToWidget`
  writes a value back. Then the row of two check boxes above the scroll pane,
  the two rules with no key, and the change of the bottom form. Tests, through
  the window: a press on each check box flips its field and draws the new state;
  the bottom form changes kind and keeps its text; the row stays in place when
  the forms scroll; the command palette lists the two rules.
- [x] **Step 3. A Julia document becomes an `Expr` (M2).** *Done.* As built:
  `make_julia_expression` in `source/julia/JuliaExpression.jl` makes the shadow
  with `copy_document` under a copy policy of its own. The policy's stop hooks
  (`is_descendable_for_copy`, `make_copy_placeholder`) stop at a document that is
  neither Julia nor an element collection, keep it in a table, and put a
  placeholder identifier in its place; a `CellVector` of arguments is a document
  too, so the collection test is needed. A method of `copy_document` for the
  policy and `JuliaInsertion` puts the parse of the hole's text in the shadow,
  because the print of a hole adds its completion. The objects go back into the
  parsed `Expr` as `QuoteNode`s. A document that is not Julia at all becomes
  `Expr(:toplevel, QuoteNode(document))`. Tests: `test_julia_expression()`, in
  `test_julia()`, 133 of 133: more than 40 examples become the `Expr` of their
  own text (a fragment such as `where {T}` is skipped, because it is no code by
  itself), ten sources keep their meaning, an object is the same object after an
  evaluation (`===`), and a hole stands for its code or raises an error.
  Originally: Test on the Julia
  examples: for each, the `Expr` of the parsed document equals `Meta.parseall`
  of its text, apart from line numbers.
- [x] **Step 4. The evaluator runs an `Expr` (M3).** *Done.* As built: the body
  of `execute_julia_code` after the parse moved into a private
  `_run_expression(set, target, make_expression)`, which both entry points call;
  `execute_julia_expression(set, target, expression)` passes its `Expr`, and the
  text entry passes `Meta.parseall(code)`. Each logs its own call and result.
  `CodeExecution.jl` and `ToolModule.jl` are marked `⬜` in `SEALING.md`, not
  sealed. Tests: `test_code_execution()` passes with a new case (the same answer
  and the same binding as text, an object in a `QuoteNode` as itself, a failure
  answered); `test_kernel()` keeps its known 3 failures and 3 errors.
  Originally: Test: the output and the
  scratch module state are the same as for the same code as text.
- [ ] **Step 5. An object in a form (M1).** Note a widget in a tab, paste it into
  a hole of `get_document_title(_)`, press Enter, and check the result. Then
  call a function that changes the widget and check that the tab draws the
  change, which proves the form held the live object.
- [ ] **Step 6. Copy reference (M4, M5).** The key, the operation, and the text.
  Test: pasted into a string form and evaluated, the reference gives the
  selected object itself (`===`).
- [ ] **Step 7. The package documents** of the conversation, the clipboard and
  the Julia domain.

The suites: `test_evaluator_toplevel()`, `test_application()`, `test_julia()`,
the clipboard tests, `test_kernel()` for M3, and the argument and naming guards.
Each run is capped at 8 GB with two threads, after a look at the free memory.

## 6. Limits and what is not in this plan

- **A noted object is live only while the session lives.** If the evaluator tab
  is saved, the object is saved by value (`PAR-PERSISTENCE-BY-VALUE`) and comes
  back as a copy. A reference survives as a path, but a path that goes through
  an index goes stale when the tree changes shape, for example when the tabs
  are moved.
- **An object cannot be typed**, only pasted; and it cannot be pasted at a caret
  inside the text of a hole, only into a slot selected whole. A text buffer that
  holds objects between its characters would be a new mechanism of its own.
- **Not in this plan:** the caret inside a parsed Julia identifier, a comment in
  the Julia domain, and a drag of an object into a form.
