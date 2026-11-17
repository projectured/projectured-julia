# A reader is split by its jobs

> **Status:** design to decide, 2026-11-17. Theme T1 of the architecture review
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
  older readers do today. The undo buffer and the gesture log are methods of job 2: each
  takes the answer of its content and gives it back recorded.
- **Job 3, written once:** the kernel walks the stages and the children, and no stage
  writes it. The change carries its gesture, its operation, its route, its description and
  its domain through the walk, so no stage can lose them.
- **Open point O1, where a gesture goes.** A key follows the selection path, and a pointer
  gesture goes to the innermost part under the pointer, as the owner decided for the mouse
  target. The walk needs, for each container, the child under a position and the frame of
  each child. Find whether the IO map of a container answers both, so that no container
  writes them, or whether a container declares them with a third function.
- **Open point O2, the order.** The innermost stage answers first; a stage further out
  answers when all inner stages decline, or first when its rule is an override. Find the
  readers that answer their own gesture first, such as a button, and whether an override
  rule covers each of them.
- **Open point O3, a wrapper around the walk.** The fault barrier and the unwrapping of a
  window input act on the walk and not on one answer. Find whether they stay stages of the
  walk or become part of it.

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

## 6. After the decisions

A plan of steps follows the names and the open points O1 to O3. omnet-julia and inet-julia
follow it, and the 194 template readers change in one place, `read_template_intent`.
