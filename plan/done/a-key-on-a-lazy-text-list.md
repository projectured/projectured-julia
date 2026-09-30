# A key on a lazy text list reads no link

## Problem

`test_reader(lazy_example)`, and so `test_example` and every sweep over the
examples, never ended: the process grew until the memory cap killed it
(measured on `main` at 4d9f08e3, 2026-09-27). The lazy example is an endless
list of primes, and `SyntaxListToText` makes a `TextBlock` whose `elements` are
a `ListNode`. `TextToGraphics` draws such a block paragraph by paragraph and
keeps no line geometry (its `char_to_coord` is empty).

Three places walked the list:

1. The key reader of `TextToGraphics` calls `_has_caret_span`, which runs `any`
   over `styled.elements`. Iterating a `ListNode` yields its links, not their
   values, so no link is a span, and `any` walks the whole list from its left
   end. On an endless list it never ends.
2. `_read_lowered_gesture`, the text domain's key reader that every text
   projection uses, computes flat offsets over `block.elements`. Ctrl+End threw
   `MethodError(get_flat_length, (ListNode, …))`.
3. The type-in harness `_walk_strings!` reads every field of every node, so it
   computed each `next` link of the list, without end.

## Design

- A block whose elements are a list has no flat caret stream and no line
  geometry. `_read_lowered_gesture` and the geometry arms of the
  `TextToGraphics` key reader decline for it, before they walk anything. The
  condition is the one the printer uses to choose its lazy path.
- The type-in walk visits the links of a list that exist and computes none, as
  `count_computed_nodes` counts them.

A caret and editing inside a lazy text list are a feature that this does not
add: Ctrl+Home still answers `nothing` there, so the navigation sweep of the
lazy example has no start.

## Steps

- [x] 1. The two readers decline for a list block.
- [x] 2. The type-in walk reads no link that is not computed.
- [x] 3. A test: a key on a list of ten thousand lazy paragraphs computes no link.
- [x] 4. Run the text tests, `test_substrate()`, and `test_example` on the lazy
      examples, against `main`.

## Results (2026-09-27)

- The new test computes 1 link with the fix and 9999 with the code of `main`.
- `test_text_to_graphics()` passes. `test_substrate()` has only the
  `AnchorPointTest` and `SplitPaneDragTest` failures that `main` has, and 7
  more passes.
- `lazy_example` and `lazy_bidirectional_example`: the printer, the reader, the
  REPL loop and the type-in sweep pass, with a peak of 1235 MB; before, the
  reader grew past the cap. `test_position_navigation` fails on both, with no
  start state, because Ctrl+Home answers `nothing` in a list block (see
  Design). `collection_example` has the counts of `main`.
