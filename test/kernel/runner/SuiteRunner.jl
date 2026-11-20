# ============================================================================
# The runner of a suite.
#
# A suite is a value: the name of its testset and a table of its parts. The
# runner calls each part through the table, at run time. So Julia compiles a
# part only when the part runs, and the memory of that compile is free again
# for the next part. A function that names each of its parts in its body makes
# Julia compile every part before the first test runs.
# ============================================================================

"""
    TestPart(run; name = String(nameof(run)))

One part of a [`TestSuite`](@ref): `run`, a function with no argument that runs
tests, and the name of the part. A plain function in the table of a suite becomes
a part with the name of the function. A test that takes an argument becomes a
part through a function with no argument and a name:

```julia
TestPart(() -> test_part_click(text_example); name = "test_part_click(text_example)")
```
"""
struct TestPart
    name::String
    run::Any
end

TestPart(run; name::AbstractString = String(nameof(run))) = TestPart(String(name), run)

"""
    TestSuite(name, entries)

A suite of tests as a value: `name`, the name of its testset, and `entries`, its
parts and the suites inside it, in the order they run. A plain function in
`entries` becomes a [`TestPart`](@ref) with the name of the function. A suite in
`entries` runs as a testset inside the testset of this suite.

Call the suite to run it:

```julia
const test_json = TestSuite("ProjecturedJSON", [test_json_layering, test_json_document])
test_json()
```

Each part runs in a testset of its own, with the name of the part. So a part
that throws records an error, and the parts after it still run.
"""
struct TestSuite
    name::String
    entries::Vector{Union{TestPart, TestSuite}}
end

TestSuite(name::AbstractString, entries::AbstractVector) =
    TestSuite(String(name), Union{TestPart, TestSuite}[_suite_entry(entry) for entry in entries])

_suite_entry(entry::Union{TestPart, TestSuite}) = entry
_suite_entry(run) = TestPart(run)

"""
    run_suite(suite::TestSuite) -> Test.AbstractTestSet

Run each entry of `suite` in its order, inside the testset of the suite, and give
that testset. A part runs through [`run_part`](@ref).
"""
function run_suite(suite::TestSuite)
    @testset "$(suite.name)" begin
        for entry in suite.entries
            _run_entry(entry)
        end
    end
end

_run_entry(suite::TestSuite) = run_suite(suite)
_run_entry(part::TestPart) = run_part(part)

"""
    run_part(part::TestPart) -> Test.AbstractTestSet

Run `part` in a testset with its name. The call goes through `invokelatest`, so
the part runs in its newest form and Julia compiles it only now.
"""
function run_part(part::TestPart)
    @testset "$(part.name)" begin
        Base.invokelatest(part.run)
    end
end

(suite::TestSuite)() = run_suite(suite)
