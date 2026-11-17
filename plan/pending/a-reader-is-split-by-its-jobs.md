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

- [ ] **1. The baseline.** On main: `test_kernel()`, `test_platform()` and the 23 domain
  suites (`test_book()` … `test_yaml()`), each in a process of its own, in a worktree detached
  at the base with a depot of its own. The counts and the failing lines go in §7. The baseline
  of omnet-julia (`test_legacy()`, `test_ide_file_navigator()`, the presentation suites) is
  taken at step 7, because main holds steps 2 to 5 then.
- [ ] **2. The seams and the passing, in the kernel.** Built 2026-11-17, waits for R1 and for the
  compare of `test_platform()` with the baseline (§7). `read_gesture(projection, iomap,
  gesture)` with its default (the table of the projection, then the table of the input
  document), `map_operation_backward(projection, iomap, operation)` with its default (each
  reference mapped back, any other operation kept), and the one helper that passes a change to
  a chosen child and back (P1). The default `read_intent` of a stage calls the two seams, and of
  a container chooses the child by the rules of §4 and the order of O2. Test: `test_kernel()`
  with new testsets for each default, the passing and the override order.
- [ ] **3. The template reader.** `read_template_intent` uses the seams and the helper, so the
  194 readers of `@projection_template`, `@rst_flat` and `@rst_indented` follow in one place,
  and `ClaimedGesture` becomes the override of O2. Test: `test_syntax()`, the JSON, XML, YAML,
  SQL, Julia, Markdown and RST suites, `test_position_navigations()`. Built 2026-11-17; R2 found
  the fault of §7, which step 3a corrects.
- [ ] **3a. The rule of a level (O4, O5, O6), in the kernel and the template.** A rule gets its
  condition and the answer of the child (P4, P5, P6); the passing helper and the template walk
  read the rules of a level with the answer of the child (P7, P8); the XML rules and the links
  of Markdown and RST get their conditions (P9); the 82 calls of `GestureBinding` in
  projectured-julia and the 2 files in omnet-julia and inet-julia take the answer. The process
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
- [ ] **4. The stages.** The 249 readers that only map become methods of
  `map_operation_backward`, the 56 that only read a gesture become methods of `read_gesture`,
  and the 110 bridges, declines and identities go, slice by slice in the order of the package
  graph. Test: the suite of each slice.
- [ ] **5. The containers and the wrappers.** The 128 readers that walk keep only their own
  rules: a pointer gesture goes through the point mapper of the container (O1), the rules that
  answer first become unconditional `override` rules (O4), and the six wrappers of O3 pass with
  the helper. The six readers that read a claim by hand (navigator, explorer, evaluator, find
  bar, formula, Git line) keep only their rules, and their guides
  ([navigator.md](../../documentation/package/platform/navigator/navigator.md),
  [explorer.md](../../documentation/package/platform/explorer/explorer.md),
  [conversation.md](../../documentation/package/platform/conversation/conversation.md)) say O4.
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
  3a. Step 3a lands in omnet-julia and inet-julia too, because their rules take the answer
  (P5). Step 6 removes the old form, which the readers of omnet-julia and inet-julia still use,
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

