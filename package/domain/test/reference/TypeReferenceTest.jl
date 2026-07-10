function test_type_reference()
@testset "TypeReference checkpoints" begin

# ── non-navigating evaluation ────────────────────────────────────────────

js  = JsonString("x")
num = JsonNumber(1)

# A bare checkpoint that holds returns the *same* node (no descent).
hold = ConcreteReferencePath(TypeReference(JsonString), EmptyReferencePath())
@test evaluate_reference(js, hold) === js

# A checkpoint that fails throws ReferenceTypeMismatch.
@test_throws ReferenceTypeMismatch evaluate_reference(num, hold)

# A checkpoint mid-path stays on the current node, then navigation continues.
arr = JsonArray([js, num])
mid = ConcreteReferencePath(TypeReference(JsonArray),
          ConcreteReferencePath(ElementReference(1), EmptyReferencePath()))
@test evaluate_reference(arr, mid) === arr[1]

# ── annotate / strip round-trip ──────────────────────────────────────────

plain     = ConcreteReferencePath(ElementReference(1), EmptyReferencePath())
annotated = annotate_reference_types(arr, plain)

# Annotation inserts checkpoints but resolves to the same node …
@test evaluate_reference(arr, annotated) === arr[1]
# … and stripping recovers exactly the original navigation path.
@test strip_reference_types(annotated) == plain
# On an unchanged document every checkpoint holds.
@test is_valid_reference(arr, annotated)

# ── truncation on a structural change ────────────────────────────────────

# Element 1 was a JsonString when annotated; replay against a document whose
# element 1 is now a JsonNumber. The trailing destination checkpoint fails, so
# the path truncates to the longest still-valid prefix.
changed = JsonArray([JsonNumber(9), num])
@test !is_valid_reference(changed, annotated)

prefix = get_valid_reference_prefix(changed, annotated)
@test prefix != annotated
@test evaluate_reference(changed, prefix) === changed[1]
@test strip_reference_types(prefix) == plain

# ── structural (non-type) truncation ─────────────────────────────────────

# An out-of-range index is unfollowable: the whole path is dropped.
oob = ConcreteReferencePath(ElementReference(5), EmptyReferencePath())
@test get_valid_reference_prefix(arr, oob) == EmptyReferencePath()

# ── the one-arg structural check is unchanged ─────────────────────────────

@test is_valid_reference(TypeReference(JsonString))
@test is_valid_reference(annotated)

# ── Folded form: head is always a navigation step (no checkpoints to skip) ─

# A folded path exposes its navigation step directly as `head` — there are no
# interleaved checkpoint steps, so `skip_type_checkpoints` is gone.
@test annotated isa ConcreteReferencePath
@test annotated.head == ElementReference(1)
@test annotated.type === JsonArray            # the type is a node field, not a step

# Stripping the annotated form to its plain skeleton yields the plain form —
# the recorded types are pure metadata over the same navigation. Strict
# equality still keeps annotated ≠ plain.
@test strip_reference_types(annotated) == plain
@test !is_reference_equal(annotated, plain)

# set_selection! / clear_selection! walk an annotated path exactly like the
# stripped form — the checkpoints are skipped during descent.
obj = JsonObject("a" => JsonString("x"), "b" => JsonString("y"))
# Path to the value string of the first entry: .entries[1].value
plain_sel = ConcreteReferencePath(FieldReference("entries"),
                ConcreteReferencePath(ElementReference(1),
                    ConcreteReferencePath(FieldReference("value"),
                        EmptyReferencePath())))
annot_sel = annotate_reference_types(obj, plain_sel)

# Setting via the annotated path stores the (annotated) sub-paths down the tree.
set_selection!(obj, annot_sel)
@test getfield(obj, :selection)[] == annot_sel
entry1 = obj.entries[1]
@test getfield(entry1, :selection)[] !== nothing
# Descent reached the value node (selection propagated past the field step).
@test getfield(entry1.value, :selection)[] !== nothing

# Clearing walks the same annotated path and resets every cell to nothing.
clear_selection!(obj)
@test getfield(obj, :selection)[] === nothing
@test getfield(entry1, :selection)[] === nothing
@test getfield(entry1.value, :selection)[] === nothing

# @reference_case matches a pattern written against the navigation skeleton
# even when the input path is annotated with interleaved checkpoints.
matched = @reference_case annot_sel begin
    entries[i].value => (:hit, i)
end
@test matched == (:hit, 1)

# The same pattern still matches the plain skeleton (backward compatible).
matched_plain = @reference_case plain_sel begin
    entries[i].value => (:hit, i)
end
@test matched_plain == (:hit, 1)

# The whole-element `∅` pattern matches a canonical whole-element selection.
# Folded: a whole-element selection is a terminal `EmptyReferencePath` that
# records the type of the node it lands on (no separate trailing checkpoint).
whole = annotate_reference_types(obj, EmptyReferencePath())
@test whole isa EmptyReferencePath && whole.type === JsonObject
hit_whole = @reference_case whole begin
    ∅ => :whole
    _ => :other
end
@test hit_whole == :whole

# ── a position is a cursor *between* items, not a descent into one ─────────

# `{3}` is a caret between characters: it lands on no child, so the terminal is
# left untyped — it must not claim the cursor points at a `Char`. This node
# records the container type (String) and keeps its position step as `head`.
pos_ann = annotate_reference_types("hello",
              ConcreteReferencePath(PositionReference(3), EmptyReferencePath()))
@test pos_ann.type === String && is_position_reference(pos_ann.head)
@test pos_ann.tail isa EmptyReferencePath && pos_ann.tail.type === nothing
@test strip_reference_types(pos_ann) ==
      ConcreteReferencePath(PositionReference(3), EmptyReferencePath())

# Contrast: an element step (width 1) descends, so the terminal records the
# destination node's type.
elt_ann = annotate_reference_types(arr,
              ConcreteReferencePath(ElementReference(1), EmptyReferencePath()))
@test elt_ann.tail isa EmptyReferencePath && elt_ann.tail.type === JsonString

# ── Phase 2: producers return canonical (self-describing) references ───────

# collect_references annotates each result against the document, so every search
# result is canonical (carries type checkpoints) and strips back to the plain
# navigation path the search built.
hits = collect_references(obj, "x")
@test !isempty(hits)
canonical_hit = first(hits)
# Canonical: carries folded node types (so its skeleton differs under strict
# equality), and is structurally well-formed (single-arg validity).
@test strip_reference_types(canonical_hit) != canonical_hit
@test is_valid_reference(canonical_hit)
# The first node records the document's own type (folded, not a separate step).
@test canonical_hit isa ConcreteReferencePath && canonical_hit.type !== nothing

end
end
