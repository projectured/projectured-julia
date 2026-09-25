# Key chords come from the gesture bindings

**Status: deferred by the owner on 2026-09-25.** This plan documents the design
only. The audit of the gesture layer (`plan/pending/gesture-layer-audit.md`,
item 4) found that nothing in the editor uses chord recognition. The owner chose
to keep it, and decided that the chord table of an editor comes from its
gesture bindings.

## The facts

- `GestureRecognizer(; chords)` takes a chord table: a list of sequences of
  `KeyDown`s. A sequence of the table becomes one `KeyChord`, with the keys of
  the sequence.
- The editor makes `GestureRecognizer()` with no chord table, and `Editor` has
  no keyword for one. So no chord is ever recognized in an editor.
- No reader, pattern or binding matches a `KeyChord`. `@event_case`,
  `@gestures` and `@gesture_set` have no syntax for a chord, and the event layer
  has no `KeyChord` pattern.

## The design

- **One place for a chord.** A chord is written once, in a gesture binding, as
  a pattern. The editor collects the chord table of its recognizer from the
  `KeyChord` patterns of the bindings that its projection holds. A chord that
  no binding names is no chord, so a key that starts no bound chord is never
  kept back.
- **The pattern syntax.** A chord pattern is a sequence of `KeyDown` patterns,
  each with its own modifiers:

  ```julia
  KeyChord(KeyDown(:x; ctrl), KeyDown(:s; ctrl)) => …
  ```

  It matches a `KeyChord` whose keys match the steps, in order.
  `describe_event_pattern` gives "Ctrl+x Ctrl+s".
- **The table follows the projection.** When the projection of the editor
  changes, the table changes with it, so a reader that comes into view brings
  its chords.

## The open questions

- How the editor finds the bindings of its projection: a walk over the readers
  of the projection, or a registry that each `@gestures` table fills. A
  registry must be per editor or read-only (PAR-PER-EDITOR-STATE).
- Whether a chord of one reader must be able to hide a key of another reader:
  with a table for the whole editor, the first key of a chord is kept back for
  every reader, also for a reader that binds that key alone.
- Whether a chord in progress needs a timeout, after which the kept keys go out
  as ordinary keys. Now a kept key waits until the next key.

## Steps

None until the owner takes this plan up again.
