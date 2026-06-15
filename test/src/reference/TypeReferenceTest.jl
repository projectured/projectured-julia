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

prefix = valid_reference_prefix(changed, annotated)
@test prefix != annotated
@test evaluate_reference(changed, prefix) === changed[1]
@test strip_reference_types(prefix) == plain

# ── structural (non-type) truncation ─────────────────────────────────────

# An out-of-range index is unfollowable: the whole path is dropped.
oob = ConcreteReferencePath(ElementReference(5), EmptyReferencePath())
@test valid_reference_prefix(arr, oob) == EmptyReferencePath()

# ── the one-arg structural check is unchanged ─────────────────────────────

@test is_valid_reference(TypeReference(JsonString))
@test is_valid_reference(annotated)

end
end
