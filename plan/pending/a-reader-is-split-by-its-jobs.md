# A reader is split by its jobs

> **Status:** plan proposed, 2026-11-17: the design is decided (§4, §5), and the steps of §6
> wait for the approval of the owner. Theme T1 of the architecture review
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
- **O2, decided by the owner (2026-11-17, "yes"): `override` means "this rule wins over the answer nearer the gesture", for a stage and for a container alike.** The readers of today use two
  orders. The child first, and the own rule of the container only when the child declines:
  focus cycling, selection walking, Escape, the tooltip decorator, the file, the settings, the
  appearance, the arrangement, the undo buffer ("with a buffer inside a buffer, the inner one
  must win") and the node of a template. The own rule first: the versioning wrapper, the
  tooltip window (Escape closes it), the two clipboard wrappers and the global shortcuts of the
  window shell. The rule: one rule for the stages and for the containers. The part nearer the
  gesture answers first, and a rule further out answers when it declines. A rule marked
  `override` wins over the answer nearer the gesture. Today `override` means this for a stage:
  a document rule replaces an operation that a stage nearer the screen made
  (`GestureBinding.jl:119`); with the proposal it means the same for a container and its
  child. The rules that answer first today become `override` rules of the table of the
  container, and no container writes the order by hand. The text below is the proposal that
  the owner accepted.
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

- [ ] **1. The baseline.** On main: `test_kernel()`, `test_platform()`, the eighteen domain
  suites, and the omnet-julia suites that open a file or press a key (`test_legacy()`,
  `test_ide_file_navigator()`, the presentation suites). The counts and the failing lines go
  in §7.
- [ ] **2. The seams and the passing, in the kernel.** `read_gesture(projection, iomap,
  gesture)` with its default (the table of the projection, then the table of the input
  document), `map_operation_backward(projection, iomap, operation)` with its default (each
  reference mapped back, any other operation kept), and the one helper that passes a change to
  a chosen child and back (P1). The default `read_intent` of a stage calls the two seams, and of
  a container chooses the child by the rules of §4 and the order of O2. Test: `test_kernel()`
  with new testsets for each default, the passing and the override order.
- [ ] **3. The template reader.** `read_template_intent` uses the seams and the helper, so the
  194 readers of `@projection_template`, `@rst_flat` and `@rst_indented` follow in one place,
  and `ClaimedGesture` becomes the override of O2. Test: `test_syntax()`, the JSON, XML, YAML,
  SQL, Julia, Markdown and RST suites, `test_position_navigations()`.
- [ ] **4. The stages.** The 249 readers that only map become methods of
  `map_operation_backward`, the 56 that only read a gesture become methods of `read_gesture`,
  and the 110 bridges, declines and identities go, slice by slice in the order of the package
  graph. Test: the suite of each slice.
- [ ] **5. The containers and the wrappers.** The 128 readers that walk keep only their own
  rules: a pointer gesture goes through the point mapper of the container (O1), the rules that
  answer first become `override` rules (O2), and the six wrappers of O3 pass with the helper.
  The 42 hand-written moves of a position and the lists of parts of the two charts go. Test:
  `test_platform()`, the chart and graph suites, `test_dataframes()`.
- [ ] **6. One form.** The 3-argument form of `read_intent`, the bridge and the 3-to-4
  wrappers go; the docstrings of `ProjectionInterface.jl`, the guide of the projection system
  and the naming rules say the new form. Test: `test_kernel()`, `test_platform()`, the guards.
- [ ] **7. omnet-julia and inet-julia follow:** 86 of the 89 readers only map, so they become
  methods of `map_operation_backward`. Test: the suites of step 1, `Pkg.precompile()` with no
  warning.
- [ ] **8. The compile-ahead lists** of the three repositories record again, as in
  [a-file-format-is-declared-once.md](../done/a-file-format-is-declared-once.md). Test: a
  precompile with no warning of a stale list.

**Proposed decisions (approved with the plan):**
- **P1. The helper of the passing is `read_child_intent(recursion, change, child)`**, beside
  `print_child(recursion, input, context)` of the printer: it gives `change` to the chosen
  child, moves a point into the frame of the child, puts the steps of the child before each
  path of the answer, keeps the route, the description and the domain, and merges a
  `CollectIntents` list.
- **P2. The steps of a child are in its entry.** A container writes the steps from its input
  to the child when it prints the child, and the point mapper reads them; no mapper searches
  for them (O1).
- **P3. Steps 2 to 5 land one at a time, and steps 6 and 7 land together.** The bridge keeps
  each old reader working until step 6, so each of steps 2 to 5 lands when its suites equal the
  baseline. Step 6 removes the old form, which the readers of omnet-julia and inet-julia still
  use, so step 7 lands with it.

## 7. Found during the work

(empty)
