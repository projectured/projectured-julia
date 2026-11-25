# A reader is split by its jobs

> **Status:** approved by the owner, 2026-11-17 ("yes I approve the plan"). In work: the
> design is decided (§4, §5), and the steps of §6 stop at the review stops of §6. Theme T1 of the architecture review
> ([architecture-review/README.md](architecture-review/README.md)). Nothing is built. The
> owner rejected one form of `read_intent` with a mixed payload: "what? no, from one bad
> solution to another? There should be a better way. Perhaps a different function?" The
> owner chose the direction of this file: "Yes, I like the separate functions idea, we
> should consider other names though." The table of the readers of today is
> [a-reader-is-split-by-its-jobs/readers.tsv](a-reader-is-split-by-its-jobs/readers.tsv).

## 1. The jobs of a reader

A reader takes a change on its way back from the screen to the data, and answers it one
stage nearer to the data. Today one function, `read_intent`, does three different jobs
([ProjectionInterface.jl:222](../../source/kernel/projection/ProjectionInterface.jl#L222):
"routing is entirely up to each projection"):

1. **Make an operation from a gesture**, for example a click on the edge of a box.
2. **Map an operation back**: translate an operation of the output into an operation of
   the input, for example a range of the text into a range of a string of the document.
3. **Walk**: give the change to the right child, extend the answer of the child to this
   stage, and keep the route, the label and the description of the change.

The older form `read_intent(projection, iomap, payload)` mixes jobs 1 and 2 in one
argument, "a gesture OR an operation". The newer form gives each reader job 3 as well, so
each reader walks by hand, and some lose the route or the labels.

## 2. The count

Five readers read each `read_intent` method of projectured-julia, omnet-julia and
inet-julia on 2026-11-17 and marked the jobs of its body. Each mark was checked on a sample
against the code.

- **543 methods written by hand:** 453 of the older form and 90 of the newer form.
  projectured-julia has 454 of them: the kernel and the projection algebra 70, the widgets
  and the text 139, the rest of the platform 128, the domains, the adapters and the
  examples 117. omnet-julia has 88 and inet-julia 1.
- **Readers that a macro makes:** `@projection_template` makes one for each of 162 types,
  and `@rst_flat` and `@rst_indented` make one for each of 32 more. All 194 call the one
  reader `read_template_intent` (`ProjectionTemplate.jl:1695`). `@_printer_only` makes a
  reader that declines everything for 7 widgets, and two `@eval` loops make 3.

| What the body does | Methods | What it becomes |
| --- | --- | --- |
| maps an operation, and nothing else | 249 | one method of job 2 |
| makes an operation from a gesture, and nothing else | 56 | one method of job 1 |
| none of the three: a bridge between the two forms (54 have one), a decline, or an identity such as `op isa Operation ? op : nothing` | 110 | goes: the defaults do it |
| makes its own operation and passes a gesture to a child | 55 | one method of job 1, and the walk |
| passes to a child, and nothing else | 28 | goes into the walk |
| two or three of the jobs: G+M 16, M+W 14, G+M+W 15 | 45 | split into the two functions and the walk |

omnet-julia shows the plainest case: 86 of its 89 readers only map an operation back. Of
these, 34 are the identity one-liner, and 6 call the default first and then change its
answer.

## 3. What the walk does by hand today

The kernel already has the walk of a route: `read_routed_child` gives a change to the child
that its route names, over `get_child_iomaps`, and `reroot_operation` extends the answer of
the child (`source/kernel/projection/ProjectionDefaults.jl`). The bridge from the newer form
to the older one calls it, and then drops the route for the older reader. The readers do the
rest by hand:

- **A key goes to the child on the selection path.** For example `YamlToSyntax.jl:235` and
  the focused child of `read_template_intent`.
- **A pointer gesture goes to the child under the pointer**, with its position moved into
  the frame of the child (`shift_event_position` in the widget containers, `ScreenToScreen.jl:297`
  and `:400`).
- **The order of the answers.** Most wrappers ask the child first and answer their own key
  only when the child declines (`UndoBufferToAny`, focus, selection walking, Escape). Some
  widgets answer their own gesture first, for example a button.
- **A list of what a gesture would do** (`CollectIntents`): 8 wrappers repeat the same merge
  of the answer of the child with their own.
- **An override of a stage further out.** A stage nearer the screen already made an
  operation, and a document rule marked `override` replaces it. Only `read_template_intent`
  makes a `ClaimedGesture` (`ProjectionTemplate.jl:1705`). Navigator, Explorer, the find bar,
  the evaluator and Git pass `claimed = change.operation` by hand.
- **Labels lost:** `SyntaxToText.jl:210` and `:1320` and `WindowInputUnwrapping.jl:48` drop
  the description and the domain of the change, and ignore its route.
- **A wrapper that does something with each answer:** the undo buffer records it, the
  gesture log logs it, the fault barrier catches an exception of the inner reader.

## 4. The design

- **Job 1, a function of each stage:** `(projection, iomap, gesture) -> operation or
  nothing`. The default fires the gesture table of the projection, as
  `read_projection_gesture` does today, and then the table of the input document, as
  `read_gesture(document, gesture)` does. Julia chooses the method by the type of the
  gesture, as about 45 older readers do today.
- **Job 2, a function of each stage:** `(projection, iomap, operation) -> operation or
  nothing`. The default maps each reference of the operation with `map_reference_backward`,
  as the default does for a path today, and keeps any other operation as it is, so the
  identity readers go. Julia chooses the method by the type of the operation, as about 130
  older readers do today.
- **Job 3 stays local, and only the passing is written once.** Each container chooses the
  child of a gesture, as the owner decided (PAR-DECIDE-LOCALLY and PAR-NO-GLOBAL-ROUTING in
  [architecture-invariants.md](../../documentation/rule/architecture-invariants.md)): a
  pointer gesture by its position, a key where the container sends it, usually along its
  selection, and a route only for an operation that a verb returns from one place. No walk
  over the tree decides it. What is written once is the passing to the chosen child and back:
  the position into the frame of the child and back, the steps of the child before each path
  of the answer, the change with its route, its description and its domain, the merge of a
  `CollectIntents` list, and the rule of an override. The default reader of a container
  chooses by these rules, and a container writes `read_intent` only to choose otherwise.
- **O1, decided by the owner (2026-11-17, "yes, that's better"): a pointer gesture goes to
  the child that the container's own point mapper names.** A point is a reference step,
  `PointReferenceStep(x, y)`, and each container that draws children maps a point back to the
  child at that point with its own `map_reference_backward`, as 13 files do today (for example
  [WidgetToGraphics.jl:1701](../../source/platform/widget/WidgetToGraphics.jl#L1701)). The
  answer names the steps to the child and the point in the frame of the child, so the passing
  gives the gesture to that child at that point, and the choice stays in the container. The
  generic child entry of the kernel (`get_child_iomaps`, the entries of `ChildrenIoMap`) gets
  no place and no pixel: a domain with no positions never sees a pointer gesture. Rejected: a
  list of drawn children with their rectangles (`DrawnChild.jl`) for each container, because it
  repeats the children and their steps beside the generic list. The 42 hand-written moves of a
  position and the lists of parts of the two charts go. Found: the widget mapper searches for
  the steps of a child at each point (`search_references`, three levels); the printer knew
  them, so the entry carries them.
- **O2, decided by the owner (2026-11-17, "yes"), replaced by O4 at R2.** It said that
  `override` means "this rule wins over the answer nearer the gesture", for a stage and for a
  container alike. At R2 this order gave the outer of two nested XML elements a key that the
  inner one answered (§7). The owner: "this override rule seems to be pretty bad in terms of
  how it can combine". The fact stays: the readers of today use two orders. The child first,
  and the own rule of the container only when the child declines: focus cycling, selection
  walking, Escape, the tooltip decorator, the file, the settings, the appearance, the
  arrangement, the undo buffer ("with a buffer inside a buffer, the inner one must win") and
  the node of a template. The own rule first: the versioning wrapper, the tooltip window
  (Escape closes it), the two clipboard wrappers and the global shortcuts of the window shell.
- **O4, decided by the owner (2026-11-17): a level asks its child first, and then its rules
  read the answer of the child.** The owner: "always go down and ask your child first, then
  apply your rules, override if the condition holds true for what the child returned.
  Unconditional override means you don't even need to go down to the child because the part
  overrides anyway. … an undo buffer can allow not overidding a nested undo buffer by
  realizing that the operation is an undo buffer related one." The rule of one level:

  ```
  answer = the answer of the child
  answer is nothing → the first rule of the level that matches answers
  otherwise         → a rule replaces answer only when its condition holds for answer
  ```

  A plain rule has no condition, so it never replaces an answer; an unconditional `override`
  always replaces it. It is one walk, innermost first, for the stages and for the containers:
  the "child" of a stage is the stage nearer the screen, as the chain reads today. The eight
  cases of §7 come out right with it.
- **O5, decided by the owner (2026-11-17, "yes, absolutely"): a rule can build its operation
  from the answer of the child**, not only test its condition on it. The layer of a dwell joins
  the layer of the child; the rule of a Git line finds its line from the caret that the child
  moved; the explorer adds the opening of the tree to an answer that visits a page.
- **O6, asked by the owner (2026-11-17): "this rule has to be documented in design documents,
  guides and code as well".** Step 3a writes O4 and O5 into the docstrings, the architecture
  rules, the design documents and the guides.
- **O3, decided by the owner (2026-11-17, "yes"): the six wrappers that act on the passing keep a `read_intent` of their own, and pass the change only through the one helper.** Six higher-order stages with one
  child do something to the passing itself, not to one answer:
  - they change the gesture for the inner stage: `WindowInputUnwrapping` gives it the event
    of a `WindowInput`, and `DragTracking` and `GestureTracking` keep state over time and make
    gestures of their own from raw events and timers (a drag, a click count, a dwell);
  - they record the gesture with the answer: `GestureLogRecording` and the undo buffer, which
    need the gesture as well as the operation, so `map_operation_backward` can not do it;
  - they guard the call: `FaultCatching` catches an exception of the inner reader and records
    a fault.

  `WindowInputUnwrapping` and `FaultCatching` drop the description and the domain of the
  change. The rule: these six keep a `read_intent` of their own, as stages of the walk, because
  each does what no part can do alone. Each passes the change to its child with the one helper
  of the passing, so the route, the description and the domain stay.

## 5. The names

The naming rules name two kinds of protocol functions
([naming-rules.md](../../documentation/rule/naming-rules.md), "Protocol functions come in
two kinds"): a function that moves a unit up the ladder, `read_gesture` (gesture in,
operation out), and a function that moves a unit across one projection and keeps its
kind, `map_reference_backward` (reference in, reference out). The subject comes from
dispatch, not from the name.

| Job | Name | For it | Against it |
| --- | --- | --- | --- |
| 1 | `read_gesture(projection, iomap, gesture)` | the rule names it for this job; the document form exists, and the subject comes from dispatch | one name for two forms: of a document and of a stage |
| 1 | `read_projection_gesture` (exists) | no new name | the rules reject a subject in the name |
| 2 | `map_operation_backward(projection, iomap, operation)` | the family of `map_reference_backward`: one kind in, the same kind out | a long name |
| 2 | `read_operation(projection, iomap, operation)` | mirrors `print_document` | "read" is the verb of a change of kind, and an operation stays an operation |
| 3 | `read_intent` | the walk keeps its name; only the kernel writes it | the name stays, with a new meaning |
| 3 | `run_reader` | says that it runs the stages | a new name for the walk of the editor |

**Decided by the owner (2026-11-17, "looks good to me"):** `read_gesture(projection, iomap,
gesture)` for job 1, `map_operation_backward(projection, iomap, operation)` for job 2, and
`read_intent` for the walk, which only the kernel writes. Each follows the kind that the
rules give it.

## 6. Steps

Each step keeps main working: the old forms stay reachable through the bridge until step 6.
Each step runs its suites against a baseline of main, in a worktree with a private depot.

- [x] **1. The baseline.** Done 2026-11-17 (§7). On main: `test_kernel()`, `test_platform()` and the 23 domain
  suites (`test_book()` … `test_yaml()`), each in a process of its own, in a worktree detached
  at the base with a depot of its own. The counts and the failing lines go in §7. The baseline
  of omnet-julia (`test_legacy()`, `test_ide_file_navigator()`, the presentation suites) is
  taken at step 7, because main holds steps 2 to 5 then.
- [x] **2. The seams and the passing, in the kernel.** Landed 2026-11-17 with steps 3 and 3a,
  after R1 and R2 (§7). `read_gesture(projection, iomap,
  gesture)` with its default (the table of the projection, then the table of the input
  document), `map_operation_backward(projection, iomap, operation)` with its default (each
  reference mapped back, any other operation kept), and the one helper that passes a change to
  a chosen child and back (P1). The default `read_intent` of a stage calls the two seams, and of
  a container chooses the child by the rules of §4 and the order of O2. Test: `test_kernel()`
  with new testsets for each default, the passing and the override order.
- [x] **3. The template reader.** Landed 2026-11-17 with steps 2 and 3a. `read_template_intent` uses the seams and the helper, so the
  194 readers of `@projection_template`, `@rst_flat` and `@rst_indented` follow in one place,
  and `ClaimedGesture` becomes the override of O2. Test: `test_syntax()`, the JSON, XML, YAML,
  SQL, Julia, Markdown and RST suites, `test_position_navigations()`. Built 2026-11-17; R2 found
  the fault of §7, which step 3a corrects.
- [x] **3a. The rule of a level (O4, O5, O6), in the kernel and the template.** Landed
  2026-11-17 with steps 2 and 3, in projectured-julia and omnet-julia, after R2. A rule gets its
  condition and the answer of the child (P4, P5, P6); the passing helper and the template walk
  read the rules of a level with the answer of the child (P7, P8); the XML rules and the links
  of Markdown and RST get their conditions (P9); the 82 calls of `GestureBinding` in
  projectured-julia and the 2 files of omnet-julia take the answer. The process
  is documented as one process: a level asks its child, lifts the answer of the child into its
  own input, and then its rules read that answer and replace it when their condition holds, so
  the answer goes up level by level, innermost first. The owner (2026-11-17): "I meant by
  documentation earlier that this process of overriding and recursing and lifting needs to be
  well documented not the individual rules of the domain documents. That's also good but on a
  different level". The process goes into: the rule PAR-DELEGATE-AND-LIFT of
  [architecture-invariants.md](../../documentation/rule/architecture-invariants.md); the design
  section "Reader (reverse projection)" of
  [system-anatomy.md](../../documentation/design/system-anatomy.md); the kernel guide
  [projection-system.md](../../documentation/package/kernel/projection-system.md), section
  "Recursive gesture reading", with the eight cases of §7 as its examples; and the docstrings of
  `read_child_intent`, `read_intent`, `read_gesture`, `fire_gesture_bindings`, `GestureBinding`,
  `@gestures` and the reader of `ChainingProjection`. On the level below, the pages that name an
  `override` rule say its condition: the rules of a table in
  [devices-and-backends.md](../../documentation/package/kernel/devices-and-backends.md),
  [domain-anatomy.md](../../documentation/design/domain-anatomy.md),
  [xml.md](../../documentation/package/domain/xml/xml.md) and
  [markdown.md](../../documentation/package/domain/markdown/markdown.md).
  Test: `test_kernel()` with a testset for each of the eight cases of §7, the nested XML case of §7 in `test_xml()`, and the suites of step 3.
- [x] **4. The stages.** Landed 2026-11-18 after R3 (§7), rebased with no conflict over main
  a2faf9fa0, whose two commits only call `read_intent` through the bridge. The 249 readers that only map become methods of
  `map_operation_backward`, the 56 that only read a gesture become methods of `read_gesture`,
  and the 110 bridges, declines and identities go, slice by slice in the order of the package
  graph. Test: the suite of each slice.
- [x] **5. The containers and the wrappers.** Landed 2026-11-19 after R4 and R5 (§7), rebased with
  no conflict over main 3d8a0402a. The 128 readers that walk keep only their own
  rules: a pointer gesture goes through the point mapper of the container (O1), the rules that
  answer first become unconditional `override` rules (O4), and the six wrappers of O3 pass with
  the helper. The six readers that read a claim by hand (navigator, explorer, evaluator, find
  bar, formula, Git line) keep only their rules, and their guides
  ([navigator.md](../../documentation/package/platform/navigator/navigator.md),
  [explorer.md](../../documentation/package/platform/explorer/explorer.md),
  [conversation.md](../../documentation/package/platform/conversation/conversation.md)) say O4.
  The 42 hand-written moves of a position and the lists of parts of the two charts go. Test:
  `test_platform()`, the chart and graph suites, `test_dataframes()`.
- [x] **6. One form.** Landed 2026-11-25 with step 7 after R6 (§7), rebased with no conflict
  over main b4c60496a; main cfc64f945. The 3-argument form of `read_intent`, the bridge and the 3-to-4
  wrappers go; the docstrings of `ProjectionInterface.jl`, the guide of the projection system
  and the naming rules say the new form. Test: `test_kernel()`, `test_platform()`, the guards.
- [x] **7. omnet-julia and inet-julia follow:** Landed 2026-11-25 with step 6: omnet-julia
  main d419fe0ad, rebased with no conflict over main 873125d89; inet-julia main 861de37 by a
  fast-forward. 86 of the 89 readers only map, so they become
  methods of `map_operation_backward`. Test: the suites of step 1, `Pkg.precompile()` with no
  warning.
- [x] **8. The compile-ahead lists** (recorded 2026-11-25, §7; projectured-julia 937909bbc and f2a6f957e,
  omnet-julia 5d6ccad0f, inet-julia 30053d6) of the three repositories record again, as in
  [a-file-format-is-declared-once.md](../done/a-file-format-is-declared-once.md). Test: a
  precompile with no warning of a stale list.

**Review stops (owner, 2026-11-17: "As we go through the changes I would like to stop at
places to review what has been changed and how. This is to avoid going in the wrong direction
and stop early if something is wrong.").** At each stop the assistant shows what changed, file
by file, one example before and after, and the counts against the baseline, and waits for the
owner. A step lands only after its stop.

- **R1** after step 2: the two seams, their defaults, the passing helper and the default
  walk, with their tests, before any reader moves.
- **R2** after step 3a: the template reader on the new seams, and the rule of a level (O4) with
  the eight cases of §7.
- **R3** in step 4, after the first slice: the pattern of a converted slice, before the other
  slices.
- **R4** in step 5, after the first container and the first wrapper: the pattern, before the
  other ones.
- **R5** after step 5, before step 6 removes the old form.
- **R6** before steps 6 and 7 land.

**Proposed decisions (approved with the plan):**
- **P1. The helper of the passing is `read_child_intent(recursion, change, child)`**, beside
  `print_child(recursion, input, context)` of the printer: it gives `change` to the chosen
  child, moves a point into the frame of the child, puts the steps of the child before each
  path of the answer, keeps the route, the description and the domain, and merges a
  `CollectIntents` list.
- **P2. The steps of a child are in its entry.** A container writes the steps from its input
  to the child when it prints the child, and the point mapper reads them; no mapper searches
  for them (O1).
- **P3. Steps 2, 3 and 3a land together, steps 4 and 5 land one at a time, and steps 6 and 7
  land together.** The bridge keeps each old reader working until step 6, so a step lands when
  its suites equal the baseline. Step 3 alone has the fault of §7, so it lands only with step
  3a. Step 3a lands in omnet-julia too, because its rules take the answer (P5); inet-julia has
  no rule. Step 6 removes the old form, which the readers of omnet-julia and inet-julia still use,
  so step 7 lands with it.

**Decisions of step 3a, approved by the owner (2026-11-17, "Yes, I agree"):**
- **P4. A table writes the condition beside the pattern.** `override(PATTERN)` is the
  unconditional rule, as today; `override(PATTERN, CONDITION)` is the conditional rule, and
  CONDITION is an expression of `answer`, as the operation of a rule is an expression of `doc`
  and `sel`: `override(KeyPress('<'), is_text_edit(answer)) => "Insert an element" =>
  _xml_insert_element(doc)`. The field `override` of `GestureBinding` holds a function of the
  answer: `answer -> false` for a plain rule, `answer -> true` for an unconditional one.
- **P5. The operation of a rule takes `(document, gesture, answer)`**, one form for each rule,
  and `answer` is `nothing` when the child answered nothing. In a table, the operation names
  `answer` as it names `doc`.
- **P6. The keyword `claimed` becomes `answer`** in `fire_gesture_bindings`,
  `read_bound_gesture`, `read_gesture` of a document and of a projection, and
  `read_projection_gesture`: it is the answer of the child, of a part or of a stage nearer the
  screen.
- **P7. A level always asks its child first**, also when it has an unconditional rule. A reader
  changes nothing, so the result is the same, and a rule that builds from the answer (O5) needs
  it. Not to ask is only a saving, which the owner allows ("you don't even need to go down") and
  which no reader needs now. The gesture help always asks the child, for its rows.
- **P8. An answer that collects lets each rule of the level answer, and the two answers join**,
  as `is_collecting_operation` does today for the layers of a dwell. No rule writes this
  condition.
- **P9. The conditions of the 28 `override` rules of today.** The XML keys `<`, `"`, space and
  `=`: "the answer edits a text", so of two nested elements the inner one keeps the key. The
  links of Markdown and RST: "the answer moves the caret". The Git line: "the answer moves the
  caret", and its operation finds the line from the answer (O5). The navigator (5), the
  explorer (2), the pane (2), the find bar (2), the evaluator (1) and the formula (2):
  unconditional, as today. The undo buffer stays a plain rule, as today; the condition that the
  owner named ("the operation is an undo buffer related one") is there if it must replace the
  answer of its content.

## 7. Found during the work

**2026-11-17, before step 2: the design changes an architecture rule.**
[architecture-invariants.md](../../documentation/rule/architecture-invariants.md),
PAR-FOUR-FUNCTIONS: "The four functions are the entire projection interface. Every projection
implements exactly `print_document`, `read_intent`, `map_reference_forward`, and
`map_reference_backward` … Do not add a fifth generic function that projections are expected
to implement." `read_gesture(projection, iomap, gesture)` and `map_operation_backward` are two
such functions. The reason of the rule is PAR-RECURSION-CONTRACT: all descent into a child goes
through the same function of the child, so a pipeline that mixes a projection with a fifth
descending function and one without it breaks. The two new functions descend into no child:
only `read_intent` passes a change to a child, through the stored child IO maps, as today, and
each projection has the two through their defaults. So the design keeps the reason and changes
the letter. The docstring of `ClaimedGesture` gives the same rule as the reason for a payload in
place of a function. **Answer of the owner:** "But read_gesture and map_operation_backward are not recursive in the
sense that they do not call themselves directly. They still go back to the child's four
functions, so they are ok, right? So in this sense, they are helper functions." So the two are
helpers of one stage, as `print_child` is of the printer; they call no child, and only
`read_intent` passes a change to the `read_intent` of a child. Step 6 adds one sentence to
PAR-FOUR-FUNCTIONS that says so.

**2026-11-17, step 2: the seams and the passing.**

- **The transition goes through the older form.** Each entry point still calls
  `read_intent`: the walk calls the 3-argument form, as before. Its default is now a bridge:
  an operation goes to `map_operation_backward`, a gesture, a key or a `CollectIntents` payload
  to `read_gesture`, and any other payload answers `nothing`, as the old default did through
  `operation_reference` and `is_self_contained_operation`. So a projection with a 3-argument
  reader of its own answers first, and a projection that moved to the two functions answers
  through the bridge. A member of a compound, the operation of a wrapper and each operation of
  a collection go back through the 3-argument `read_intent` too, so an old reader for a member
  still answers. Until step 6 no code calls the two functions directly; step 6 removes the
  bridge, and then the walk and the default of a compound call them.
- **`read_gesture(projection, iomap, gesture; claimed)`** is a method of the function of
  `GestureBindingModule`, so a stage and a document share one name, and the subject comes from
  dispatch. Its default is the rule that `_read_own_override_click` of the template already
  has: the table of the projection, then the table of the input document. No projection of
  today gets a table fired twice: each projection that declares a table has a reader of its own
  that fires it, so the default is not reached for it. `read_projection_gesture` takes
  `claimed` too.
- **The default of `map_operation_backward`** is the operation half of the old default, branch
  for branch.
- **`read_child_intent(projection, recursion, change, iomap, child, steps = ())`** (P1). It needs
  the projection and the IoMap of the container as well, because the rules of the container
  answer by the order of O2. The child reads with `read_intent`, or with `read_routed_intent`
  when the change has a route. The documents on the steps read outward as in `read_routed_child`
  (`_read_outward`), now with the override of O2: a rule of a level answers when nothing
  answered, an `override` rule wins over a plain answer, and an answer that collects is joined.
  The container level reads `read_gesture(projection, iomap, gesture)`. A child whose input is
  the input of the container shares its table, so the container level then reads only the table
  of its projection, as the wrappers do today.
- **The default walk of a container is not changed in step 2.** A container with no reader of
  its own still reads a change through the bridge, as today; a generic choice of the child would
  change what such a container does. Step 5 moves each container to `read_child_intent`.
- **Found, for R1: the point mapper does not give the point in the frame of the child.** O1 says
  that the answer of the point mapper names the steps to the child and the point in its frame.
  The mapper of a widget container (`_map_point_to_child`, `WidgetToGraphics.jl:1701`) finds the
  child and the point in its frame, but then gives that point to the mapper of the child and
  answers the whole path down to the innermost part: the point of the child does not come back.
  So the passing of a pointer gesture needs the one level that the mapper finds before it
  delegates.
- **The runs of step 2.** `test_reader_jobs()` (new, 23 assertions) passes. `test_kernel()`:
  5215 passed, 2 broken, none failed, which is the 5192 of the kernel before and the 23 new
  ones; the compare with the baseline follows when the baseline runs.

**2026-11-17, step 3: the template reader.**

- **`ClaimedGesture` goes.** `read_template_intent` calls the override walk itself
  (`_read_template_override`), so no payload carries a claim. Each level of the walk reads
  `read_gesture(projection, iomap, gesture; claimed)`, which is the code of
  `_read_own_override_click`, so that function goes too. A key now reads the table of the
  projection of each level as well as the table of its document, as a click did. The type was
  exported from `IntentModule`, so the next release takes a minor version step. Its test in
  `IntentTest.jl` and the three lines of the layer tables of `architecture.md` and
  `system-anatomy.md` go with it.
- **A key goes to the focused child through `read_child_intent`** (`_read_template_key`). It
  does three things that the old key walk did not: an `override` rule of the node wins over the
  answer of the child (O2); the node reads the table of its projection before the table of its
  document; and the collection on the steps to the child reads its table. No list and no
  generic document declares a table, so the third adds nothing today. The second adds nothing
  today either: the one template projection with a table of its own, the rendered reference of
  RST (`RstReferenceToSyntaxNode`), holds click rules only.
- **The maps of an operation stay** in the 3-argument methods on `TemplateIoMap` until step 4.
- **The compare with the baseline of main (`e9af3a5a7`), steps 2 and 3 together.** `test_kernel()`:
  main 5192 passed and 2 broken, the branch 5212 and 2, the 23 new assertions less the 3 removed
  ones. `test_platform()`: main and the branch 236357 passed, 15 failed, 1 error, 21 broken, with
  the same lines. The 23 domain suites: the same counts and the same lines of failure on main and
  on the branch. Main fails in formula (1), graph (6 and 2 errors), julia (1), math (1) and pivot
  (2 and 1 error). One run of `test_languageserver()` on the branch failed in
  `SemanticTokensTest.jl:111-113`, where clangd was not seen as ended 10 s after a kill while
  other jobs ran; a second run alone passed 114 of 114, as main does.
- **Found at R2: of two `override` rules on the way of a key, the one further out wins.** An
  `XmlElement` has the rule `override(KeyPress('<'))`, "Insert an element". In `<a><b>x</b></a>`
  with the whole of `b` selected, `<` on main gives `b` a new element: the child answers first,
  and `a` answers only when it declines. On the branch, `b` answers, and then the `override`
  rule of `a` wins over that answer (`_read_level`), so `a` gets the new element. The probe
  shows it with the syntax stage only and with the full chain. No suite covers the case: the
  one test with a selected child is an `XmlInsertion`, where `_xml_insert_element` declines by
  hand. The claimed walk of the same branch (`_read_override_gesture`) reads the innermost
  part first and stops at the first answer, so the same key and the same rules give a
  different element when a stage nearer the output claimed the key. Two ranks of rules, read in
  two passes, were proposed and not taken; the owner decided O4 (§4).
- **The eight cases that the rule of a level must give (R2, 2026-11-17).** "Nearer" is the part
  nearer the gesture, or the stage nearer the screen; "further" is the part outside it. Step 3a
  tests each case.

  | # | Nearer answer | Further rule | Result | Example |
  | --- | --- | --- | --- | --- |
  | 1 | plain | plain | nearer | An undo buffer in an undo buffer, Ctrl+Z: the inner one undoes. |
  | 2 | none | plain | further | JSON, `,` on a delimiter: the text can not take it, so a sibling goes in. |
  | 3 | plain | `override` | further | XML, `<` in a tag name: a child element. A click on a link: the link opens. Evaluator, Enter: the input runs. |
  | 4 | `override` | plain | nearer | No case today. |
  | 5 | `override` | `override` | nearer | `<a><b>x</b></a>`, `b` selected, `<`: `b` gets the element. |
  | 6 | any | answers before its content | further | The window, Ctrl+S; the clipboard, Ctrl+C; an open tooltip, Escape. |
  | 7 | list | list | both | The gesture help lists the keys of `b` and of `a`. |
  | 8 | layer | layer | both, joined | A dwell on `b`: the layer of `b` and the layer of `a`. |

  With O4: case 1, the inner undo stays (the outer rule is plain, or its condition rejects an
  undo); case 2, the child answers nothing, so the plain rule answers; case 3, the condition of
  the further rule holds ("the answer edits a text", "the answer moves the caret") or the rule
  is unconditional; case 4, a plain rule never replaces an answer; case 5, the answer of `b` is
  an XML insert and not a text edit, so `a` keeps it; case 6, the rule is unconditional; case 7,
  each level asks its child and adds its rows; case 8, the answer collects, so the layers join.
  In case 3 the further rule must know where the gesture is: today a link learns it from the
  caret move that the text stage made of the click, which O5 keeps.
- **The runs.** `test_kernel()`: 5212 passed, 2 broken, none failed: step 2 and the 3 assertions
  of the removed test less.
  The domain suites on the branch: `test_json()` 405, `test_xml()` 86, `test_yaml()` 64 and 2
  broken, `test_sql()` 671, `test_markdown()` 346 and `test_rst()` 140 pass with no failure;
  `test_julia()` has 794 passed and 1 failure, `TooltipWindowTest.jl:179`, the padding `(9, 9)`
  where the test expects `(13, 13)`, which fails on main since `2d8d7e117`. The compare with
  the baseline follows when it runs.

**2026-11-17, step 3a: the rule of a level.**

- **The two conditions.** `is_selection_change(operation)` is in the kernel, beside
  `ReplaceSelectionOperation` (`Operations.jl`): a selection move, wrapped or in a compound,
  as a text answers a click. `is_text_edit(operation)` is in the primitive slice of the
  platform, beside `ReplaceRangeOperation` (`PrimitiveDocument.jl`): a range edit of
  characters, wrapped or in a compound, as a text answers a typed key. The kernel docstrings
  name only the kernel one.
- **`GestureBinding`.** The field `override` is a function of the answer, `Returns(false)` by
  default; the operation is `operation(document, gesture, answer)`; `fire_gesture_bindings`
  fires a binding with an answer only when `binding.override(answer)` holds. `@gestures` writes
  `override(PATTERN)` as `Base.Returns(true)` and `override(PATTERN, CONDITION)` as
  `answer -> CONDITION`, and the `rhs` of every rule names `answer`. A Sonnet agent changed the
  operations of the hand-written bindings: about 80 sites in `source/` and 30 in `test/`, and
  the direct calls of a binding operation; a parse of every `GestureBinding(` call finds no
  operation with two arguments.
- **The answer goes up one step at a time.** `read_child_intent` lifts the answer of the child
  by one step of `steps` at a time, so each document on the steps reads it in its own frame, as
  a rule that builds from the answer needs (O5).
- **The outward reading of a route reads by the rule of a level too** (`_read_outward`, under
  `read_routed_child` and `read_gesture_outward`). There the answer is in the frame of the input
  of the container, so a condition can read its kind and not its paths. Step 5 moves the pointer
  containers to the point mapper and the helper, which gives each level its own frame.
- **The claim walks of the template follow the rule of a level.** Each part reads the answer
  that came up so far: the answer of the stage nearer the output, or the operation of a part
  inside that replaced it, and the walk no longer stops at the first answer. The answer of the
  stage is in the vocabulary of that stage, not mapped into the input of the part; a condition
  reads its kind. Step 4 moves the operation maps to `map_operation_backward`, which can give
  the mapped answer.
- **Other repositories.** omnet-julia has two bindings with a two-argument operation
  (`SimulationToWidget.jl`, `LegacyIniFileEntryToWidget.jl`), changed in the worktree
  `/home/projectured/workspace/omnet-julia-reader-split` on the branch `reader-split`.
  inet-julia has no binding and no claim, so step 3a does not change it.
- **The compile-ahead lists** of `package/*/precompile/workload.txt` hold signatures with the
  keyword `claimed`; step 8 records them again. The precompile of the branch warns once: "511
  of the 2968 recorded calls of ProjecturedJulia no longer resolve"; main warns not at all.
- **The runs of step 3a**, against the baseline of main (`e9af3a5a7`). `test_kernel()`: 5226
  passed and 2 broken, none failed: step 3 and 14 new assertions of the rule (`ReaderJobsTest.jl`
  and `GestureBindingTest.jl`). `test_platform()`: 236362 passed, 15 failed, 21 broken, with the
  15 lines of main; main has one more error, `TaskWorkItemTest.jl:171`, a test of a running loop,
  which did not occur here, so its testset ran 4 more assertions; it occurred on main and on the
  run of steps 2 and 3. The 23 domain suites: the counts and the lines of failure of main;
  `test_xml()` has 90 for the 86 of main, the 4 assertions of the two nested cases of §7, which
  pass.
- **omnet-julia and the guards.** `Pkg.precompile()` of omnet-julia in an environment that
  names the two worktrees (`/var/tmp/projectured-julia-reader-split-depot/env-omnet`): 101
  packages, no error and no warning. No suite of omnet-julia presses the two links. The guards
  `test_naming()`, `test_arguments()`, `test_exports()`, `test_documentation()` and
  `test_package_graph()` give the lines of failure of main on the branch: `test_arguments()`
  6, `test_exports()` 37 and `test_documentation()` 11, the same on main; `test_package_graph()`
  562 passed. The probe of the nested XML case gives the answer of main again: `b` gets the
  new element, with the syntax stage alone and with the full chain.
- **Found: the list of ProjecturedJulia goes stale.** On the branch, a load of ProjecturedJulia
  warns "The precompilation of ProjecturedJulia failed, so it compiles more while it runs. 511
  of the 2968 recorded calls of ProjecturedJulia no longer resolve"; main does not warn. The
  calls name the keyword `claimed` and the operations of two arguments. Proposed for R2: record
  that list again before steps 2, 3 and 3a land, so main does not warn until step 8.
- **The documentation of the process:** PAR-DELEGATE-AND-LIFT; the section "Reader (reverse
  projection)" of `system-anatomy.md` and the section "Edit" of `concepts.md`; the section
  "Recursive gesture reading: ask the child, lift its answer, apply the rules" of
  `projection-system.md`, with the eight cases, and the paragraph of `operation.md` that links
  it; the docstrings of `read_intent`, `read_child_intent`, `read_routed_child`,
  `read_gesture_outward`, `read_gesture`, `read_projection_gesture`, `fire_gesture_bindings`,
  `read_bound_gesture`, `GestureBinding`, `@gestures` and the reader of `ChainingProjection`.
  The level below: the rules of a table in `devices-and-backends.md`, `domain-anatomy.md`,
  `xml.md`, `markdown.md`, and the wording of a claimed key in `navigator.md`, `explorer.md` and
  `conversation.md`.

**2026-11-17, R2: the owner approves the landing.** "yes" to: "do you approve the landing of
steps 2, 3 and 3a on main of projectured-julia and omnet-julia, after I record the list of
ProjecturedJulia again?" The list of ProjecturedJulia records again (2331 lines, no call with
`claimed`), and a precompile of the branch then gives no warning. The other lists that name
`claimed` (ProjecturedExample 216, ProjecturedPlatform 93, and 14 more with 4 to 28) stay
under the share of 10% that fails a precompilation, so they compile what still resolves,
with no warning; step 8 records them. Steps 2, 3 and 3a land by a fast-forward of main of
projectured-julia and of omnet-julia; nothing is pushed.

**2026-11-17, step 4: the 3-to-4 wrappers wait for step 6.** Step 4 says that "the 110
bridges, declines and identities go", and step 6 that "the 3-to-4 wrappers go". The 54
bridges of §2 are those wrappers (`read_intent(p::X, iomap, payload) = read_intent(p,
nothing, Intent(payload), iomap).operation`). While the walk calls the older form, a
3-argument call of a projection that has a reader of the newer form reaches that reader only
through its wrapper: without it, the call goes to the default of the older form, which hands
the payload to `read_gesture` or `map_operation_backward` and skips the reader. So the
wrappers go in step 6, with the older form, and step 4 removes the declines and the
identities, and converts the readers that only map or only read a gesture. The slices of
step 4 are the four groups of §2, in the order of the package graph: the kernel and the
projection algebra, the widgets and the text, the rest of the platform, and the domains, the
adapters and the examples.

**2026-11-17, step 4, the first slice: the kernel and the projection algebra.** Of its 38
readers, 6 change in step 4; the walks wait for step 5 and the wrappers for step 6.

- **A reader that is the default goes.** The path map of the template
  (`ProjectionTemplate.jl`, `read_intent(p, iomap::TemplateIoMap, op::ReplacePathOperation)`)
  is the path branch of the default `map_operation_backward`, so it goes, and with it the
  method of `RecursiveProjection` that broke its ambiguity (`ReaderDefaults.jl`). The reader of
  `IdentityProjection` goes: the default `read_gesture` asks the table of the input, and the
  default map passes an operation through the identity map unchanged. The one difference: a
  gesture other than a key, a click or a help list, such as a dwell, now reads the table of the
  input too.
- **A reader that only maps becomes `map_operation_backward`.** The retype of a text edit of
  the template (`ReaderDefaults.jl`) is `map_operation_backward(p, iomap::TemplateIoMap,
  op::ReplaceStringRangeOperation)`; its inner call of an element stays the older form until
  step 6. Its ambiguity breaker for `RecursiveProjection` goes; the breaker of a key stays,
  because the key reader of the template is a walk of step 5.
- **A reader that declines everything is not the default.** The default `read_gesture` asks
  the table of the input, and the default map keeps an operation that names no reference. So
  `ConstantProjection`, whose output does not come from its input, answers nothing in two
  methods, typed on its `SimpleIoMap` so that they are not ambiguous with the method of the
  template.
- **`FocusingProjection` gets the defaults, with two changes of behavior.** Its two readers go.
  The default `read_gesture` fires its table first, as before, and then the table of the input,
  which the old reader did not ask. The default map puts the focused part before the paths of
  every operation; the old reader mapped a path and declined every other operation, so an edit
  through a focus mapped to nothing.
- **For the next slices: a hand-written `read_gesture` of a container reads `answer`.** A stage
  of a chain reads a gesture only when no later stage answered, so its `answer` is `nothing`.
  But `read_child_intent` calls the `read_gesture` of a container with the answer of the child,
  so a method of a container that does not read `answer` acts as an unconditional `override`.
- **The runs of the first slice**, against a new baseline of main `24536d808` (main holds steps
  2 to 3a and the plan of the type `View` of another session, which adds tests to the
  platform suite), in the base worktree moved to that commit. `test_kernel()`: 5226 passed on
  both; one run of the branch failed the time guard `FeedsTest.jl:260` (0.064 s for a limit
  of 0.045 s) while the two chains ran, and a run alone passed 5226. `test_platform()`: 236368
  passed, 15 failed, 1 error, 21 broken on both, with the same lines. The JSON, XML, YAML, SQL,
  Julia, Markdown and RST suites: the same counts and lines on both. The precompile of the
  branch gives no warning.

**2026-11-17, R3: the owner approves the pattern.** "Yes" to: "do you approve these four
rules and the behavior changes of `FocusingProjection` for the other three slices of step 4?"
The four rules: a reader that only does what the default does goes; a reader that only maps an
operation becomes `map_operation_backward`; a reader that declines everything becomes two
methods that answer nothing; the 54 wrappers wait for step 6. A change of behavior is taken
where the default is the correct model, and each one is named in this section.

**2026-11-17, step 4, the second slice: the widgets and the text.** Two Sonnet agents
converted the rows of `source/platform/widget/` (37 of 70) and of `source/platform/text/`
(60 of 69) by the four rules, and the walks and the wrappers stay.

- **Found: the bridge gave no raw input event to `read_gesture`.** `MouseDown`, `MouseUp`,
  `MouseMove` and `MouseScroll` are subtypes of `Event`, not of `Gesture`, so the bridge of
  step 2 answered nothing for them, and a reader of a press or a move that became a method of
  `read_gesture` was never reached: the first run of this slice failed 36 assertions and gave
  9 more errors, in the carets of labels, the drags of scroll bars, sliders and headers, the
  drag tracking, and the Alt+double click of `TextToGraphics`. The bridge now gives every
  `Event`, every `Gesture` and a `CollectIntents` payload to `read_gesture`. No gesture table
  has a pattern of a raw press, release, move or scroll, so the default answers nothing for
  one, as the bridge did.
- **The widgets.** 16 widgets whose reader declined everything on the `WidgetBoxIoMap` get the
  two methods that answer nothing; the macro `@_printer_only` (7 widgets that only show a value)
  writes them too. 17 readers of a gesture become methods of `read_gesture`, and
  `ObjectFieldToValue` maps an operation with `map_operation_backward`. Change of behavior: the
  readers of a gesture of the label, the badge, the avatar, the alert and seven more widgets
  took any payload and declined an operation; an operation now goes to the default map, which
  maps it with the reference map of the widget. `ObjectFieldToValue` gave a gesture back as its
  answer; a gesture now goes to the default `read_gesture`.
- **The text.** The maps of `PrimitiveToText`, `MarkedTextToText`, `TextLineNumbering`,
  `TextFirstLine`, `SelectionInverting`, `TextFolding`, `HighlightedTextToText`,
  `FilteredTextToText` and `WordWrapping` become methods of `map_operation_backward`, the
  readers of a key, a click, a press, a move and a drag of `TextToGraphics` and `TextView` become
  methods of `read_gesture`, and the five projections of `TextToString` answer nothing. Three
  maps of `PrimitiveToText` called the default of the older form with `invoke`; that call now
  reaches the same method again through the bridge, so they call the default of
  `map_operation_backward` instead. Where an old reader declined a payload for which the default
  would answer, a method that answers nothing keeps the old answer: `TextToGraphics` (any other
  gesture, any operation but a path), `TextLineNumbering` and `TextFolding` (a gesture).
  `TextBlockToScrollLayout.jl:318` stays: the walk of its untyped reader at :323 catches the call
  first, so step 5 converts both.
- **The runs of the second slice**, against main `24536d808`, after the change of the bridge.
  `test_kernel()` 5226 passed on both. `test_platform()`: the 15 lines of failure of the base,
  and 236373 passed for its 236368; the base gave the error of the running loop
  (`TaskWorkItemTest.jl:171`), which did not occur here, so its testset ran 4 more assertions.
  The 23 domain suites: the counts and the lines of the base, with two exceptions that depend on
  the load. `test_formula()` passed its time guard `FormulaFrameGuardTest.jl:67` (312 for 311
  and 1 failure). `test_process()` passed 316, as on `e9af3a5a7`; on the base it hung in
  `ProcessDebugTest.jl:185`, where `wait(run.task)` waits while the task of the process waits on
  its channel, and the run was stopped after 45 minutes.

**2026-11-18, step 4, the third slice: the rest of the platform.** Two Sonnet agents
converted the rows of 20 folders of `source/platform/` (86 rows that are no walk and no
wrapper) by the four rules.

- **Converted:** the maps and the key readers of the syntax stages (`SyntaxToText`,
  `PrimitiveToSyntax`, `InsertionToSyntax`, `CollectionToSyntax`), of the file system, the
  panes, the reflection, the roster, the links, the terminal, the settings, the address of the
  navigator, the assistant, the statistics, the conversation editor and the graphics; the
  safe mode of a fault answers nothing in the two methods. Eight more calls of
  `invoke(read_intent, Tuple{Projection, Any, Any}, ...)` in converted maps call the default of
  `map_operation_backward` now (`PrimitiveToSyntax`, `RosterToGraphics` twice, the settings,
  the assistant twice, the statistics, the conversation editor).
- **The old answer is kept where the default answers more:** `InsertionToSyntax`,
  `GraphicsCaching` and `GraphicsToGraphics` answer nothing for an operation, or for a gesture,
  that their untyped reader declined; the split pane of the assistant answers nothing for a
  gesture.
- **Changes of behavior:** the untyped identities of `ReflectionToWidget` and
  `RosterToGraphics`, like that of `ObjectFieldToValue` in the second slice, gave a gesture back
  as their answer; a gesture now goes to the default `read_gesture`.
- **Left for step 5:** the 3-argument readers that the `@eval` loops of `ConversationToWidget`
  write for three conversation projections, because their 4-argument reader calls them by the
  older form; and the readers of the navigator, the explorer and the evaluator that read the
  answer of a later stage. `SyntaxToText` still gives a key that it declines back as its
  answer, as before; step 6 removes such answers with the older form.
- **The runs of the third slice**, against main `24536d808`: `test_kernel()` 5226 passed;
  `test_platform()` the 15 lines of failure of the base, with 236373 passed, as in the second
  slice; the 23 domain suites the counts and the lines of the base, and `test_process()` 316 as on
  `e9af3a5a7`. The precompile gives no warning.

**2026-11-18, step 4, the fourth slice: the domains, the adapters and the examples.** Two
Sonnet agents converted the rows of `source/domain/`, `source/adapter/` and `example/` (108
rows that are no walk and no wrapper) by the four rules.

- **Converted:** the maps of SQL, the database catalog, Markdown, RST, the book, YAML, the
  math, Git, the workflow, the research, the pivot table and the data frames; the readers of a
  key of the data frames and the pivot table; the catalog to SQL and SQL to a cell table answer
  nothing in the two methods. Many maps of a path were the default and go (the database
  catalog, the book, Markdown, RST, the math, YAML, the Julia insertion, the select statement of
  SQL). Four more calls of the default of the older form with `invoke` call the default of
  `map_operation_backward` (the research and the workflow, two each).
- **The old answer is kept where the default answers more.** 19 nodes of SQL declined every
  operation but a path, and every gesture: each keeps its path map, which is the default, and
  answers nothing in the two methods for the rest. `MathProjection` answers nothing for an
  operation, as its untyped reader did.
- **Found for step 5:** the new `read_gesture` of `MathProjection` passes the gesture to its
  children by the older form, so it is a walk inside a method of job 1; step 5 moves that walk
  out. The data frame view reads a drag and converts the writes that it makes in one method of
  `read_gesture`; the conversion reads no answer of a child.
- **Found: a module that no longer extends `read_intent` must not import it.** The layering guard
  "every file imports what it extends" failed in nine domain suites: their modules (the book,
  the database catalog, Julia, Markdown, the math, the research, RST, SQL, the workflow) imported
  `read_intent` from `ProjectionModule` and no longer define a method of it. The name leaves
  their import lists; `using ..KernelModule` still gives it to their calls. The guard of the
  platform gives the message of the base.
- **The runs of the fourth slice**, against main `24536d808`: the 23 domain suites give the counts
  and the lines of the base, after the change of the imports; `test_math()` fails
  `MathToGraphicsTest.jl:346` (the depth limit of the walk of the printer) on both. One run of
  `test_process()` hung in the race of `ProcessDebugTest.jl:185`, as the base did, and a second
  run passed 316. The precompile gives no warning.
- **Step 4 before its landing.** The five guards give the failures of the base `24536d808`, the
  line numbers aside (the modules have new import lines). `Pkg.precompile()` of omnet-julia, its
  main checkout `f58aa51b4` with the branch of projectured-julia in the environment
  `/var/tmp/projectured-julia-reader-split-depot/env-omnet`: 89 packages, no error and no warning.
- **Step 4 rebased over main `31c803857`.** Main got the plan "a view type is declared, and a list
  has a view" of another session (13 commits, no reader of any form). The rebase had one
  conflict, in the imports of `TextModule.jl`: main dropped the import of `make_content_view`,
  and step 4 adds `map_operation_backward` and `read_gesture`; the merge keeps both changes.
  Against a new baseline of `31c803857`: `test_kernel()` 5226 passed on both; `test_platform()`
  236418 passed, 15 failed, 21 broken on both, with the same lines; the 23 domain suites the
  counts and the lines of the base, but for the time guard of `test_formula()`, which passed on
  the branch.

**2026-11-18, step 4 lands.** The owner: "Land first, check only if needed." Main had moved to
`a2faf9fa0` (the table rule of another session: helpers in the roster, the data frame view and
the widget table, and calls of `read_intent` through the bridge, no new reader). The rebase had
no conflict, and no reader of the two commits clashes with step 4, so no new test round ran.
Step 4 is on main `6de377ef2`; nothing is pushed.

**2026-11-18, step 5, the first container and the first wrapper (for R4).**

- **The kernel has no pixel, so the helper takes the read of the child.** The functions that
  move a position (`shift_event_position`, `shift_operation_position`) are in the graphics
  slice, and O1 keeps the kernel free of places and pixels. So `read_child_intent` gets the
  keyword `read_child`, the function with which the child reads the change, by default
  `read_routed_intent`. A container that draws its children in frames of their own gives a
  `read_child` that moves the point in and the positions of the answer out. With
  `child === nothing`, no child reads, and only the rules of the container answer: the
  container is the part.
- **The passing of a placed child is written once, in the layout slice:**
  `read_entry_child(projection, recursion, change, iomap, entry, steps)`, beside
  `read_child_event`. It takes the frame of the child from the `(x, y, child_iomap)` entry,
  gives the moved gesture to the child by the rules of `read_child_event` (the Alt+click, the
  Alt+double click, the focus of a press, a dwell and a right click inside the child), moves
  the positions of the answer back, and the kernel lifts the answer by `steps` with the rule of
  a level. `read_child_event` gets a form that takes the change, so the route, the description
  and the domain reach the child.
- **The first container, `WidgetCompositeToGraphicsCanvas`, keeps only its own rules:** a key,
  a gesture with no point and an operation go to the child that its selection names; a
  pointer gesture goes to the topmost child that drew at its point; a pointer off the
  composite answers nothing; a move goes to the child that the pointer leaves as well; a press
  over no child goes to the first child that takes it (the divider of a split pane in the gap);
  Tab is a plain rule of its level (`read_gesture` on a key), which moves the selection to the
  next focusable child when the selected child declines Tab. A route goes to the child that it
  names, as by default. `_route_composite_press` and `_forward_composite_event_slot` go, and
  `_composite_tab` keeps only the move of the selection. The 3-to-4 wrapper of the composite
  stays until step 6.
- **The first wrapper, `WindowInputUnwrappingProjection`,** passes the event of a window input
  to its inner stage with `read_child_intent`, so the route, the description and the domain of
  the change and of the answer stay; before, it dropped all three.
- **The O1 finding, as built:** the composite chooses the child with the hit test of its point
  mapper (`_find_widget_child_point`, the first level of `_map_point_to_child`), not with the
  whole mapper, which answers the path down to the innermost part. The steps of a child of the
  composite are `elements[i]`, which the composite knows by the slot, so no search finds them
  (P2); the other containers carry the steps in their entries when they move.
- **Changes of behavior:** a pointer gesture reaches only the topmost child at its point (O1);
  before, a child under it got a gesture that the topmost one declined. Every gesture, not only
  a dwell and a right click, now reads the documents on the steps and the tables of the
  composite and of its input; no widget document and no widget projection has a table, so no
  answer changes today. A press over no child gives the positions of its answer back in the
  frame of the composite.
- **Not moved yet:** the move of the pointer asks two children, the one under the pointer and
  the one that the pointer leaves, and joins the two answers, so it is no single passing; it
  stays the own code of the composite (`_read_composite_move`).
- **The narrow runs:** the window input, the point of a widget, the mouse target of a move, a
  routed gesture, the selection walk, the selection of a widget, the button, the popup example,
  the window wrappers, the drag tracking, the context menu and the size of a composite: 626
  passed, none failed. `test_reader_jobs()` has a testset for the two new parts of the helper.
- **The runs against the baseline**, the branch at 7a50bfbf7 and main at 6de377ef2, each with
  its own precompile: the kernel 5228 passed and 2 broken (main 5226 and 2; the 2 more are the
  new testset); the platform 236428 passed, 15 failed, 1 error and 21 broken, as on main; the
  chart 645, the data frames 622, as on main; the graph 630 passed, 6 failed and 2 errors, as on
  main. The failed tests are the same tests at the same lines, and the text of the layering
  failures is the same.

**2026-11-18, R4: the owner approves the pattern.** "Yes, I approve the pattern": the
`read_child` keyword and the child of `nothing` of the kernel helper, `read_entry_child` in the
layout slice, Tab as a rule of the level of the composite, and the topmost child only, for the
other containers and wrappers.

**2026-11-18, step 5 after R4: the decisions as built (for R5).**

- **An operation in the place of the gesture.** The 3-to-4 wrappers give an operation as
  `Intent(payload)`, so the operation stands where the gesture stands. `read_child_intent` passes
  such a change as that operation, so no container repeats the check. It goes with the older form
  in step 6.
- **A stage reads the answer of the stage nearer the screen by the rule of a level (O4 for the
  stages).** The default 4-argument reader maps a carried answer back, and then the rules of the
  stage read the mapped answer: `read_gesture(p, iomap, gesture; answer)` through the rule of a
  level. Before, a stage with no reader of its own only mapped the answer, and only the template
  and six readers by hand read it with their rules. So a stage that builds on the answer of a
  later stage writes a method of `read_gesture` or of `map_operation_backward` and needs no reader:
  the help group (a double press opens the page of the node), the frame statistics (the drag of
  the thumb), and the pages of the background work, the record table and the open files (the
  held arrangement, the open of a held row), which are maps.
- **A wrapper that shares the input of its child writes its rules as a method of
  `read_projection_gesture`.** The passing reads only `read_projection_gesture` for a level whose
  input is the input of its child, because the child reads the table of that input. So focus
  cycling, the selection walk and the quit on Escape have one `read_child_intent` call and a
  method of `read_projection_gesture`; a container and a wrapper whose child stands at steps write
  a method of `read_gesture`.
- **The layouts.** The eight layouts with children (`children[i]`) read with one reader of the
  layout slice, `_read_layout_children`; a stack, a constraint layout and an anchored layout take
  the topmost child that holds the point in its box. The scroll layout, the constraint of one
  child, the list layout and the grid list read with the same parts. Tab is a rule of the level of
  a layout, as of the composite. An answer comes back with the types that its path needs, as
  before (`_annotate_operation`).
- **The steps of a child of a widget container come from the container (P2), not from a search.**
  The tooltip and the title pane (`content`), the menu and the toolbar (the widget element at the
  slot, `elements[i]`), the dialog (`buttons[i]`, `content`), the menu item (`action.label`), the
  context menu (`child`) and the shell (the field of the band) give the steps of the child at a
  slot. The move of the pointer still finds the steps by identity (`_read_children_move`), as R4
  says.
- **The controls that read only their own drawn text** (the button, the link, the item of a
  toolbar, the toggle group) read no child, so they are methods of `read_gesture`, and a method of
  `map_operation_backward` answers nothing, as their old reader did for an operation.
- **A child that maps its answer by the backward map of the container, not by steps.** The text
  field, the text area and the two pages of the appearance give `read_child_intent` a `read_child`
  that moves the point and translates the answer (`_read_text_content_change`, `_read_tab_child`),
  with no steps: a plain value has a text view of its own, and a tab maps its commands, writes,
  edits and folds.
- **The gesture help and the command palette keep a reader of their own,** because they read their
  content a second time, for its rows; they pass the change with the helper.
- **Changes of behavior so far:**
  - a stack, a constraint layout and an anchored layout give a press, a release and a dwell to the
    child at the point too, as the other layouts do; before, only a click, a turn of the wheel and a
    move;
  - the answer of a child of a tooltip, a menu, a title pane, a toolbar, a dialog and a menu item to
    a click or a turn of the wheel comes back rooted at the steps of the child; before, it came back
    as the child answered it;
  - the answer of a band of a shell comes back rooted at the field of the band (`menu_bar`,
    `toolbar`, `status_bar`, `overlay`); before, at `content`, but for the Alt+double click;
  - the overlay of a shell takes a pointer gesture before the content under it, as the topmost child;
  - a press and a release reach the child of a context menu in the frame of the child; before, at
    the point of the menu;
  - a click on a button of a dialog that the button declines does not go on to the content;
  - every level reads the tables of its documents for every gesture; no widget and no layout has a
    table, so no answer changes today.
- **A plain rule of code answers only with no answer.** The walk of a stage gives the answer
  of a later stage to `read_gesture` of each earlier stage, and a container gives the answer of
  its child to its own `read_gesture`; the methods of `read_gesture` that step 4 made never
  got an answer, and did not read it, so each acted as an unconditional `override`. 54 of them
  now begin with `answer === nothing || return nothing` (O4: a plain rule never replaces an
  answer); a method that builds on the answer reads it.
- **A carried `CollectIntents` list only maps back.** The chain collects the rows of each
  stage itself (`_collect_intents`), so the walk of a stage reads no rules for it.
- **The six readers of a claim by hand.** The explorer, the evaluator, the navigator and the
  find bar drop their hand reading of the table with the answer of the later stage, because the
  walk of a stage does it; the navigator and the find bar keep the join of the rows of the
  gesture help. The rule of the Git line reads the mapped answer and maps its path forward
  again, to find the caret in the output. The formula keeps its reader: its rule reads the table
  of the formula in edit mode, a document inside the input of the stage, which the walk of a
  stage does not read. The guides of the navigator, the explorer and the conversation say O4.
- **An operation goes to a child without the gesture.** A container passes a carried
  operation down to its selected child to map it back. With the gesture, the default reader of
  a leaf read its rules on it as on the answer of a later stage, so a carried dwell got the
  tooltip layer of the selected widget again. `read_child_intent` gives the child the operation
  alone, as the older form did; the shell does the same in its loop over the bands.
- **The tabbed pane roots the answer of a page by fixed steps,**
  `selector_element_pairs[i].element` for a `WidgetTabPage` (`_get_tab_page_steps`), the path
  that its own comment named correct. The decoder of the pane, `PaneToWidget`, reads a path with
  and without the step (`_after_element_step`), so it needs no change. The move uses the same
  steps, and `_prefix_tab_operation` and `_descends_into_page` go. The strip of the tabs, the
  name of a tab and the close buttons are rules of the pane.
- **The two charts give a pointer gesture on a part to the part by the one passing**
  (`read_child_in_frame`); their hit test, their move and the point map of a part keep the
  list of parts of the graphics slice, and `read_drawn_child_event` goes. Their other rules
  are methods of `read_gesture`.
- **The math projection** gives a key to the child that holds the selection with a 4-argument
  reader for a key; its rules on the answer stay in `read_gesture`. **The readers that the
  `@eval` loops of `ConversationToWidget` write** are methods of `map_operation_backward` and
  `read_gesture`. **The text block, the text gutter, the image, the URL view, the object field,
  the YAML sequence, the accordion, the fact group, the card, the table and the table parts**
  pass with the helper.
- **The moves of a position:** 44 calls of `shift_event_position` on main, 15 now; 45 calls of
  `read_container_gesture`, 11 now.
- **Kept for now, with a reason each (for R5):** the stages whose rules read the raw gesture
  with the answer before the map, or keep state (the syntax stages, the choice list, the pane
  tree, the conversation, the roster rows, the pivot table, the terminal, the task pages, the
  file system trees, the formula); the screen and the window manager, which have the
  4-argument form and pass with their own code; the graph, which gives a key to each vertex and
  label in turn and roots each answer with its own helpers; the copying projection, whose route
  of an operation reads the child by the path of the operation.
- **Fixed after the runs of snapshot 3:** a container passes a carried operation to its child
  with its gesture again, because the undo buffer joins a typing run by the gesture and the
  override walk of a template needs it; instead the walk of a stage reads no rules for an answer
  that collects, so a leaf adds no layer of a dwell, and the navigator keeps its hand join of
  such an answer. A container of widgets lists no row of its own for the gesture help, as the
  old level reader (`read_container_gesture`) read the tables only for a dwell and a right
  click. A right click on the header of an accordion is the item's, not the toggle. A key whose
  selection is in the name of a tab reaches the rules of the tabbed pane. The Git line keeps its
  projection table, which a cut had taken away.
- **The runs of snapshot 4** (e7cd5c3c6, the tree before the fix of the tab name), in the base
  worktree with its own precompile, against main `6de377ef2` for the kernel and the platform
  and the step-4 runs for the domain suites: the kernel 5232 passed and 2 broken (4 new tests);
  the platform 236429 passed, 19 failed and 21 broken: the 15 failures of main, with the same
  text of the layering failures, and 4 of the rename of a tab (`PaneConstructTest.jl`), which
  the fix of the tab name answers; the 23 domain suites give the counts and the failures of the
  base, but the time guard of the formula (`FormulaFrameGuardTest.jl:67`), which fails on main
  as well (two runs alone on main `ef8023369`: 3.86 and 3.06 for a limit of 3.0; on the branch:
  3.38 and 3.28), and one more passing test of the pivot table, which main added after the base.
- **After the fix of the tab name** (commit `ecaa17619`): the pane, tab, window wrapper,
  navigator and explorer suites, run alone, pass 1985, and fail only the 4 assertions of
  `NavigatorChoicesTest.jl` that fail on main.

**2026-11-18, R5: the owner approves step 5 as built.** "yes" to: "Do you approve step 5 as
built, with the walk of a stage and the plain rule in the kernel? If yes, I convert the
remaining readers in the same way, rebase onto main, run the suites again, and land step 5."

**2026-11-18, step 5 after R5: the remaining readers.**

- **The stages that read the answer of a later stage with their own rules lose their reader.**
  Each rule on the answer becomes a method of `read_gesture`, and each map of the answer a
  method of `map_operation_backward`, as R5 approved for the stages before:
  - the terminal: a plain click whose answer is a caret outside the input line puts the caret
    in the input line; the rule reads the mapped answer, a path of the terminal;
  - the lines of a stream of a task: the turn of the wheel scrolls whatever a part answers, and
    a write of the value of the scroll bar maps to the line at that value;
  - the group of tasks: the held arrangement, the open of a held row and the open of a task are
    maps; the selection of a row and the write of the head of a list of a group are a rule on
    the answer (`_convert_table_answer`);
  - the tree of the explorer, the chooser of files and the tree of documents: the write of the
    open nodes is a map (`_map_open_folder_answer`, `_read_open_node_write`), and the
    3-to-4 wrapper of the tree of documents goes with its reader;
  - the rows of a roster and the view of a data frame: the double click that opens the item or
    the row, and the press that keeps the drag of the thumb, are rules on the answer; each
    keeps a reader only for an operation that a route brings to its place, which no child
    takes;
  - the pivot table: the press, the drag and the drop of a badge are rules, and so are the
    start of the drag past the threshold, with the answer of the table, and the right click
    and the dwell on an item. The write of the version of the source for an edit of the data
    stays in a reader, because it is for the answer as a whole: the default map gives each
    member of a compound and the write inside a write of view state to the map of the stage
    alone, so a map method wrote a version for the drag state of a chart in a cell, and the
    pivot printed the chart again (`PivotChartViewTest.jl:102`, `:105`);
  - the transcript of a conversation: the Alt+arrow walk, the Alt+double click and the plain
    click are rules on the answer. It now follows a route into its children as every container
    does; before, its reader read a change with a route as a change with none.
- **A stage whose map drops the answer reads the raw gesture again.** The chain does it
  (`_read_chain_from`), so the rules of a level that answered with no answer before (the turn
  of the wheel of the stream, the start of a drag of the pivot) still answer: the walk of a
  stage needs no change for it.
- **Kept, with a reason each:**
  - the syntax compound reads the path of a click in the frame of its output, before the map,
    to find a fold marker or a character place (`_resolve_click`, `_read_character_place`), and
    the leaf cuts the answer to a move in the same way as the compound;
  - the choice list drops the answer of the field of its typed text for a key that it does not
    take, and a rule of a level can only replace an answer;
  - the pane tree joins the layers of a dwell of the pane documents to an answer that collects,
    which the walk of a stage only maps, and a press on a tab reads the operation before the map;
  - the screen and its window give the content the event inside a `WindowInput` that names its
    window, and a move reads the window that the pointer leaves too;
  - the window manager closes windows while it reads (`_apply_close!`,
    `_close_popup_windows!`), and a modal window takes all input, so it does not ask its child
    first;
  - the formula reads the table of the formula in edit mode, a document inside its input;
  - the workspace reads a change with a route as a change in the tree of its view;
  - drag tracking, gesture tracking, the tooltip window and the context menu window make new
    gestures and read the child more than once; each passes the content with the helper;
  - the graph and the copying projection pass a change to a child with the 3-argument form
    (`read_intent(child.projection, child, payload)`), so they change in step 6, which removes
    that form.

**2026-11-19, step 5: the runs before the landing.** The branch, rebased over main 3d8a0402a,
against main 3d8a0402a, each of the 25 suites in a process of its own:

- 24 suites give the same counts and the same failing lines as main, among them
  `test_platform()` (236492 pass, 15 fail, 1 error, 21 broken), the chart (656), the graph
  (630 pass, 6 fail, 2 error) and the data frames (622). The pivot fails only at the lines that
  fail on main (`PivotModuleTest.jl:21`, `:23`, `PivotZoneEditTest.jl:84`), so the fix of the
  chart in a cell holds: `PivotChartViewTest.jl:102` and `:105` pass.
- The kernel has the 6 new tests of `ReaderJobsTest.jl`, which pass, and one failure,
  `FeedsTest.jl:260`: the reader, print or paint time of a frame over a new backend type
  must stay below 45 ms. The first such frame compiles code. A probe in a fresh process
  measured the same time on both sides: reader 26.5 ms and print 21.5 ms on the branch, 27.0 ms
  and 22.2 ms on main. Under load the time goes above the limit, so the failure is not a change
  of the branch. It failed once before on the branch at step 4 and passed in the runs after.

**2026-11-19, steps 6 and 7 as built (for R6).** A parser of the files found each use of
`read_intent` and counted its arguments, so a nested call or a call over two lines is not
missed. A tool on the same parser made the mechanical changes at the lines that it found.

- **The 3-argument form goes.** The bridge, 76 wrappers of the form
  `read_intent(p::X, iomap, payload) = read_intent(p, nothing, Intent(payload), iomap).operation`,
  the key wrapper of the template, the resolver of a clash between that wrapper and the
  recursive projection, and the 3-argument forward of the reference dispatch. No
  3-argument definition, call or `invoke` is left in the source, the tests, the packages and
  the examples of the three repositories.
- **The default reader** gives the operation of a change to `map_operation_backward` and
  otherwise the gesture to `read_gesture`, as the bridge did. **The default map** gives each
  member of a compound, the inner operation of a wrapper and each operation of a collection to
  `map_operation_backward` of the projection, and `read_move_answer` does the same.
- **The 56 calls of the source.** 16 map an operation of the stage itself and call
  `map_operation_backward`. 11 read the operation of the change, or its gesture when it has
  none, and call the function of that kind. 29 pass a change to a child and take the
  4-argument form `read_intent(child.projection, nothing, Intent(x), child).operation`, which
  is what each wrapper did.
- **Three readers of the older form change shape.** The graph canvas gives its payload to a
  private helper of its 4-argument reader (`_read_graph_payload`), so its choice of the vertex
  and the drag of a vertex stay. The copying projection reads with a 4-argument reader that
  routes as before and hands the answer of a stage nearer the screen to the default, so the
  rules of its level read it as before. The two text edits of the syntax compound are methods
  of `map_operation_backward`.
- **The tests.** 976 calls take the 4-argument form. Of the 9 test definitions of the older
  form, two probes of a click become `read_gesture` methods with a decline of each operation,
  two become `map_operation_backward` methods, the timer probe becomes a 4-argument reader
  (a `WindowInput` is not an `Event`, so the default gives it to no job function), a forward
  goes, and the test of the bridge in `ReaderJobsTest.jl` tests the default map instead.
- **Found: an operation travels in the gesture field.** `Intent(x)` puts `x` in the gesture
  field, also an operation, and the default reader maps an operation from that field. The
  wrappers did the same, so the 4-argument calls keep `Intent(x)`. A later change can put an
  operation in the operation field (`Intent(nothing, op)`). The first run of the suites
  (s6a) showed that this is not enough: a reader that reads its own payload took the gesture
  field for a gesture, so an operation that a caller handed there went to `read_gesture` and
  answered nothing. A typed character through a view did not edit (json, xml, markdown,
  julia). The fix (commit e51b45e9a): the template reader, the workspace directory, the pane
  tree, the screen at two places, and the leaf and the compound of the syntax give an
  operation in the gesture field to `map_operation_backward`, as the bridge did and as
  `read_child_intent` and the text block do.
- **Found: a 3-argument call skipped a reader.** 17 types and the template types have a
  4-argument reader and had no wrapper, so a 3-argument call of them went to the bridge and
  not to their reader. Examples are the navigator, the explorer, the pivot, the screen and the
  pane tree. Now a test that reads one of them reaches its reader, as the editor does.
- **The text.** The docstrings of `ProjectionInterface.jl`, `ProjectionDefaults.jl` and
  `ProjectionTemplate.jl`, the guide of the projection system, the naming rules, the rule
  "write a method of a job only when re-targeting a reference is not enough", the guides of
  the navigator, the explorer, the video recorder, the mouse target and the tests say the two
  jobs. PAR-FOUR-FUNCTIONS has the sentence of the owner: `read_gesture` and
  `map_operation_backward` are the two jobs of `read_intent` for one stage, as `print_child`
  is a helper of the printer; they call no child, and only `read_intent` passes a change to
  the `read_intent` of a child.
- **omnet-julia (step 7)**, worktree `omnet-julia-reader-split`, branch `reader-split`: 88
  definitions are methods of `map_operation_backward` now; the identity one-liners keep any
  operation as it is (`op isa Operation ? op : nothing` reads as `op` for an operation). The
  double click of the result frame and the click of the module canvas are rules of
  `read_gesture` that answer only with no answer; the module canvas declines any other gesture
  and any operation, as its reader did. Each file imports the function that it extends.
  **inet-julia**, worktree `inet-julia-reader-split`: one test call takes the 4-argument form.
- **2026-11-19, step 6: the runs.** The suites of step 1 over the branch (run s6b, after the
  fix of the gesture field and of a duplicate probe in `ReaderJobsTest.jl`) against the runs
  of step 5 (s5full): 21 suites are the same. The kernel passes now; step 5 had the flaky time
  test `FeedsTest.jl:260`. Graph and math have the same failures one line up, because a call
  of two lines became one. The platform has one more failure, `TaskVerbsTest.jl:101` (the
  process and the time in the facts of a failed task). That run was at 13.5G of its 14G cap,
  with a frame of 33 s; alone, `test_task_group_verbs()` passes 87/87 three times on main and
  on the branch, so the failure comes from the load and not from the change.
- **2026-11-19/20, step 7: the runs.** Each job ran in a process of its own with no network
  (bwrap), so no test reached a model server. Main: projectured 0ae98a75b with omnet
  21d013f2f (the branch `no-ollama-in-suites`, landed on omnet main 2026-11-19, takes the
  model tests out of the suites). Branch: projectured reader-split with omnet d44b8279f and
  inet bec5a98.
  - The precompile of omnet-julia gives no warning on either side, but the one that says the
    registry cannot be downloaded.
  - `test_legacy()`: the same on both sides, 3512 pass, 23 fail, 68 error, 1 broken.
  - `test_legacy_result()`: the same, 307 of 307.
  - `test_presentation()`: the same failure lines, but `CheckpointViewTest.jl:188`, which
    failed on main only. That test reads the state of the session before the archive ends,
    so it fails at random under load. The suite does not end in 4 h on either side: it stays
    in the navigation walk over `omnet/omnet_workbench`, after the notebook tests. The 12 tests
    after the walk use no assistant.
  - `test_ide()`: the branch gives 2745 pass, 23 fail, 12 error, 3 broken. The run of main
    stopped at its memory cap of 12 G in the build of the image, near the end; up to that
    point the failure lines are the same. The branch has one more failure,
    `IdeWorkloadTest.jl:160`: the build of the image warns that 554 of the 3186 recorded calls
    of ProjecturedJulia no longer resolve. On main the same list has 527 such calls, so the
    test most probably fails on main too; step 8 records the list again.
  - inet-julia `test_queuing()`: the same on both sides, 422 pass, 21 fail, 16 error, at the
    same lines. The packages of inet-julia compile with no warning; the one warning on both
    sides is the stale list of ProjecturedJulia (527 calls on main, 554 on the branch).
- **2026-11-20, the rebase over main 8e792dc15.** Other sessions landed 66 commits on main
  after 0ae98a75b. One conflict: main adds `keep_held_arrangement(operation, ::Nothing, ...)`
  next to the wrapper of `ArrangingProjection` that step 6 removes; the rebase keeps the new
  line and removes the wrapper. The parser of the files then finds no 3-argument definition
  and eight 3-argument calls, all in tests of the new main: three in `ChartProjectionTest.jl`,
  one each in `JsonFileViewContentTest.jl`, `JsonUndoBufferViewTest.jl`,
  `JsonViewNaturalRowTest.jl`, `PaneReaderTest.jl` and `WidgetPointTest.jl`. They take the
  4-argument form (commit bf0b2926b). Five readers have lines of the new main: the anchored
  layout, the viewing projection, the undo buffer, the rows of a list and the table. On main
  each of the first three had a 3-argument wrapper that put the payload in the gesture
  field, so a call with an operation takes the same path on the branch. The table declines
  an operation, as before, and the list gives its gesture to the default reader.
- **2026-11-25, the rebase over main 28dfc9f93 (projectured), fa9b3b2b6 (omnet) and 86910a9
  (inet).** Main moved by 203, 41 and 1 commits; step 5 and the omnet change with no model
  are on origin. The check of the rebase over 8e792dc15 stopped before its end, at the
  request of the owner, so its results do not count.
  - projectured: three files conflict, each where main changed a line with a 3-argument
    call. The table cell and the table route keep the `_find_control_answer` of main around
    the 4-argument call; the name of a tab keeps the `part` of main. `ClipboardTest.jl` keeps
    the three `@test_broken` of main for the cut of a range, with the 4-argument call.
  - The parser then finds fifteen 3-argument calls, all in tests of the new main: the
    research and the workflow page (two each), `PaneConstructTest.jl` (one),
    `PaneGestureTest.jl` (two), `WidgetMenuKeysTest.jl` (three), `WidgetPointTest.jl` (one)
    and `WidgetTabStripTest.jl` (four). They take the 4-argument form (commit a18148823). A
    scan of the whole worktree then finds no call and no definition with other than four
    arguments.
  - Two readers are new on main: the commit range of git calls the default reader with
    `invoke` and changes only the answer to a double click; the command card of the assistant
    adds a method of `map_operation_backward`. Both meet step 6.
  - omnet: one test file conflicts, `LegacySimulationRunnerTest.jl`, where main put three
    tests in a `try` with a `@test_broken` for a print that throws. The rebase keeps the side
    of main and gives its calls the 4-argument form.
  - The scan of step 7 covered only `source` and `test` of omnet-julia and inet-julia. A scan
    of the whole worktrees finds two more 3-argument identity readers, which step 6 makes
    dead: the configuration form of the watch demo (omnet `demo/watch/config_form.jl`) and the
    diagram of a state machine in the catalog example (inet `example/catalog/Machines.jl`,
    imported in `InetExample.jl`). Each becomes a method of `map_operation_backward`, as the
    identity readers of step 7 did (omnet 5d6885c2a, inet 861de37).
  - The test rule of the repositories changed on 2026-11-21: main is green, so an unmarked
    `Fail` or `Error` on the branch is a fault of the branch, and no run of main goes beside
    it. The check is the land run of `CLAUDE.md` in each worktree, with no network, through
    `julia-worktree run`.
  - The land run of projectured (1 h 14 min, the record of 3766c0a3a) ends each of its
    768 parts: 3520443 pass, 7 fail, 0 error, 3601 broken. The 7 failures are in 4 parts, and
    each is a failure of main that has no mark:
    - `test_exports`, 2: `GestureModule.jl:37` exports its names in an order that
      `MouseGesture.jl` does not define them, since main c5a6627f2 of 2026-11-23.
    - `test_documentation`, 3: `dragtracking.md:94` and `pane.md:291` link to the plan of the
      tab that moves along its strip in `plan/pending`, which main moved to `plan/done` in
      d85427334 of 2026-11-23.
    - `test_scroll_work`, 1 (`ScrollWorkTest.jl:195`, the count of the work of the Files
      pane), and `test_application`, 1 (`ApplicationTest.jl:2006`, an Alt+double click on a
      row of the Files pane selects no file). The plan of the JSON file through its views
      found both on main at 567b5665b, with no mark.

    The branch changes none of these test files, none of the files that the two guards name,
    and nothing in `source/kernel/gesture/`. The record of another branch over main
    3dcb5f516 has the same two guard failures.
  - inet, at the neutral paths of `julia-worktree` in `bwrap` with no network, against the
    omnet and the projectured branches (the tool mounts no inet-julia, so the command is
    written out):
    - `test_queuing`: 402 pass, 21 fail, 16 error, 1 broken. The fail and the error counts
      are those of step 7; the pass count was 422. Each failure is in `tutorial.jl`, where a
      page gives each embed inside a `File`, and the test asks for the embed. The one line of
      the branch in that file, the 4-argument call at line 253, passes.
    - `test_inet`: 390 pass, 46 fail, 34 error, from one cause: `open_page!` is ambiguous in
      `InetTest`, because `ProjecturedAll` exports the one of the navigator (since
      2026-10-15) and `OmnetPresentation` its own (since 2026-08-31). The branch changes
      neither.
    - The guards: `style.jl` passes, `packagegraph.jl` has 39 of 39, and `tree.jl` finds the
      two `precompile` folders of `InetExample` and `InetRunner`, which inet main tracks since
      2026-10-29.
  - omnet, the two land commands of its `CLAUDE.md` with `--with` the projectured branch:
    - All the parts (1 h 09 min, the record of 5d6885c2a): 268 parts done, 880645 pass,
      0 fail, 0 error, 334 broken.
    - The three suites of `test/runtests.jl`: 125 pass, 0 fail, 0 error, 88 broken.
    - The last full record of main, at cfdb5c3a6, has 265 parts and 267 broken. Of the 67
      more, 64 and 4 are in two parts that main added after it, `test_presentation_atoms` and
      `test_ide_gestures_compile_little`. `test_task_group_pane` has one pass and one broken
      fewer: its loop counts one of each for each look at the group while it runs.
  - Three facts of the runs, none of the branch:
    - The omnet worktree had no `Manifest.toml` in `environment/all` and `environment/build`,
      so the runner found no `ProjecturedKernelTest`. The copies of main fixed it, as
      `julia-worktree new` does.
    - A depot made by hand from `compiled` alone has no `tmp`, and `TMPDIR` of the run names
      it, so each `mktemp` fails. The first omnet run stopped after 31 parts for this.
    - With a depot that must compile `OmnetPresentationExample`, its precompilation was
      killed at the cap of 8 GB, and at 9 GB. The job of 14 GB compiled it.

**2026-11-25, R6: the owner approves the land of steps 6 and 7.** "yes, land it". Main of
projectured-julia had moved by two commits that change only plan files, and main of omnet-julia
by two commits that change no file of the branch and name no removed name. Both branches rebased
with no conflict, and main of the three repositories moved by a fast-forward: projectured-julia
cfc64f945, omnet-julia d419fe0ad, inet-julia 861de37. Nothing is pushed.

**2026-11-25, step 8: the lists record again.** Four jobs, one after the other, each with no
network:

- **projectured, the source lists** (45 min, peak 9.7 GB): the 21 source packages with a
  workload, each after the packages that it depends on, and then
  `record_application_calls!("ProjecturedBuild", "projectured")`. `record_repository_calls!`
  is not used, because each test package has a workload now (compile-ahead.md, Decision 11),
  so it would record all 60 lists and run each whole suite. The driver keeps the packages that
  do not end in `Test`.
- **projectured, the test lists** (21 min, peak 6.3 GB): `tool/record-test-calls.jl --changed
  b4c60496a`, the 14 test packages whose files the land changed. One commit, 937909bbc, holds
  the 51 lists of both jobs. No list names the 3-argument `read_intent`, `ClaimedGesture`,
  `read_drawn_child_event` or the keyword `claimed`.
- **omnet** (46 min, peak 9.1 GB): the 18 packages with a workload and then the application
  `omnet_ide`, against projectured with its new lists; 22 lists, 5d6ccad0f. The trace gives
  OmnetBuilder no call of `omnet_ide`, so its file of 2 calls of `Artifacts` (2026-11-02)
  goes.
- **inet** (12 min, peak 7.7 GB): `InetRunner` and `InetExample`; only the list of
  `InetExample` changes, 30053d6.
- **Faults of main that the logs show, none of the branch:**
  - The workload of `ProjecturedExample` fails for 13 of 142 examples. `filesystem` and
    `files` have the field errors of the record of 2026-11-16. The 7 chart and the 4 sequence
    chart examples stop at "under-typed @reference" in `ChartToChartPlot.jl:106` and
    `SequenceChartToSequenceChartPlot.jl:110`, the lines of 3951f31b3 (2026-11-18), which
    main had before steps 6 and 7. The list keeps the calls of each example before its failure.
  - The workload of the application warns 16 times "The agent did not stop", with
    `MethodError: no method matching stop_agent_connection!(::Nothing)`.
  - In the recording of `ProjecturedKernelTest`, the time check `KernelFrameGuardTest.jl:147`
    fails (a ratio of 35.6 against a bound of 3), while the trace compiles each call and a
    second recording runs beside it. The land run passed it. The suite runs to its end, so
    the list holds all its calls.
- **Main moved during step 8.** Another session landed 13 commits on main (595d81e4b): the
  time axis of a chart, a dependency of `ProjecturedChart` on `Dates`, and new parts of
  `ProjecturedKernelTest` and `ProjecturedChartTest`. Then it landed the lists of
  `ProjecturedBuilderTest` and `ProjecturedPivotTest` (306018039), and pushed main with the
  approval of the owner, so steps 6 and 7 of projectured-julia are on origin. The branch
  rebased twice with no conflict. The lists of `ProjecturedChart`, `ProjecturedKernelTest` and
  `ProjecturedChartTest` recorded again over 595d81e4b (17 min, peak 7.3 GB, no workload
  failed), f2a6f957e. The worktrees of omnet-julia and inet-julia took the manifests that the
  other session resolved in the main checkouts.
- **The test of step 8.** `Pkg.precompile()` of `environment/all` in each repository, with no
  network, after the last recording: projectured (18 min, peak 9.0 GB), omnet (20 min, peak
  13.5 GB) and inet (10 min, peak 12.3 GB). None warns that a recorded call no longer
  resolves.
- **The land of step 8, 2026-11-26.** "Yes land it", to the land of step 8 and the push of the
  three main branches. Main had moved again: projectured-julia by 42 commits of other plans,
  pushed (0b3175fe3), and omnet-julia by 2, pushed with d419fe0ad (11b9281ac). The one file
  that both sides changed is the list of `ProjecturedKernelTest`, which main recorded in
  34dbdf4fe on newer code that holds steps 6 and 7. The rebase keeps the list of main, so the
  branch changes 50 lists of projectured-julia and not 51. omnet-julia rebased with no conflict
  (5d6ccad0f), and inet-julia moved by a fast-forward (30053d6).
