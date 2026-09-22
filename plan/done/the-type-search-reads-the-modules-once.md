# The type search reads the modules once

## Why

The first key in a name buffer (`DocumentInsertion`) waits about 7 seconds in
`bin/projectured`. The compiles are gone since
`plan/done/the-first-key-in-a-name-buffer.md`: the first key compiles 1 method.
The wait is the search for the candidate types.

`get_insertion_candidates(Document)` calls `_collect_concrete!`, which calls
`subtypes(T)` for `Document` and for each abstract type under it: 485 calls.
Each call reads every name of every loaded module: 77087 names in 445 modules.
So the first key reads 37.4 million names, each through two
`Base.invoke_in_world` calls. The result is cached for the world age, so each
new process pays it one time.

Measured on 2026-09-22, with the approval of the user, in the measurement lane
(cores 28, 30, 31) at a load of about 12.5, two runs, headless, in the
environment of `bin/projectured`. The one-pass search was put in place of the
old one at run time:

| key | run 1 | run 2 |
| --- | ---: | ---: |
| old search, first key | 11452 ms | 12409 ms |
| old search, second key (cache hit) | 12 ms | 13 ms |
| one-pass search, a key that searches | 48–53 ms | 53–60 ms |
| a key that does not search | 14 ms | 14 ms |

The one-pass prototype gave the same 137 candidates in the same order.

## Design

- The walk over the modules and the selection of one type's subtypes become
  two functions. `_collect_named_types(world)` reads every loaded module one
  time and files each named type under the name of its direct supertype.
  `_compute_subtypes(named, x)` selects the direct subtypes of `x` from that
  table, with the same checks and the same sort as before.
- `subtypes(x)` is `_compute_subtypes(_collect_named_types(world), x)`, so its
  callers (`default_backend`) see no change.
- `_collect_concrete!` takes the table and walks the tree in the same order as
  before. `get_insertion_candidates` makes the table from the world age that
  keys its cache.
- A test compares the candidates with an oracle that does not share the code:
  every concrete named type under the root, found by a plain walk in the test.
  A second check compares the order with a recursion over `subtypes`.
- The list is recorded again, because the compiled methods of the search change.

## Steps

1. [x] The search reads the modules once, and the test compares it with the
   oracle. `test_document_insertion()`: 118 pass, 1 fail. The new testset passes
   its 3 assertions, and takes 0.4 s when compiled. The failure is in "rendered
   completion feedback" and is older than this change: the assertion
   `string(node.selection) == ".content.value{0}"` is from `24cd7fa0`
   (2026-09-01), and `ff43f219` (2026-09-18) made the node selection a typed
   forward image, which prints as
   `::SyntaxDelimitation.content::SyntaxLeaf.value::TextString{0}::Position`.
   `test_application()`: 76 of 76.
2. [x] Record the list again at `:none`. 11332 statements, against 11314; 11127
   are shared, and all 338 statements of the first key are still in the list.
   The driver drove 105 examples, and none refused. Of the 187 dropped, 78 no
   longer resolve; most are `print_document` closures of `ProjecturedWidget`,
   which the widget commits on main renumbered.
3. [x] Measure the first key in the environment of `bin/projectured`, built from
   the worktree with `build_projectured_executable(; compile = false,
   resolve = true)`. The warm-up ran in the package's `@compile_workload` and
   logged no warning. The first key compiles 1 method, as before.

   Measured with the approval of the user, in the measurement lane at a load of
   about 8.7 to 9.0, two runs, with the search in the image:

   | key | run 1 | run 2 |
   | --- | ---: | ---: |
   | first key | 70 ms (18 compile) | 167 ms (18 compile) |
   | second key (cache hit) | 13 ms | 14 ms |
   | a key that searches again | 45, 45, 46 ms | 47, 47, 44 ms |
   | a key that does not search | 12 ms | 12 ms |

   Before the change the first key took 11452 and 12409 ms. The search now
   costs about 33 ms. The two first keys differ by about 100 ms, and this run
   does not show why; the keys that search again agree within 3 ms.

## Not in this change

- `get_insertion_candidates` runs `insertable(T)` before the cheap
  `_is_layout_variant(T)`. The cheap checks first would halve the probes that a
  new, unrecorded document type compiles.
