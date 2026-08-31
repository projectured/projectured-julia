# ═══════════════════════════════════════════════════════════════════════════
# test/editor/ReplTest.jl
#
# Full REPL-loop test.  For each event in _ALL_READER_EVENTS the complete
# editor cycle is exercised:
#   1. read_intent       — translate event to operation
#   2. evaluate_operation    — apply operation to document
#   3. print_document      — re-project the updated document
#   4. _walk! on the iomap   — force every Cell in the new output
# The iomap fed to the next read_intent is always the one produced by
# the most recent print_document, mirroring the real editor loop.
# ═══════════════════════════════════════════════════════════════════════════

# A minimal stand-in for the mutable `Editor`: operations such as
# `ReplaceDocumentOperation` may rebind `.document` (a whole-document swap) and
# null `.iomap`, exactly as the real editor loop allows. The harness re-reads
# `.document` after each operation so a root swap is picked up by the next print.
mutable struct _ReplEditor
    document::Any
    iomap::Any
end

# If `onevent` is supplied it is called once per event with
# `(event, ok::Bool, message::String)` summarising that event's full
# read → evaluate → reprint → walk cycle, letting a caller emit one assertion
# per event.
function walk_repl_loop(document, projection; onevent=nothing)
    errors = String[]
    clear_selection!(document)
    iomap = try
        print_document(projection, document)
    catch e
        msg = "initial print_document threw: $e"
        push!(errors, msg)
        onevent === nothing || onevent(nothing, false, msg)
        return errors
    end
    for event in _ALL_READER_EVENTS
        op = try
            read_intent(projection, iomap, event)
        catch e
            msg = "read_intent threw for $event: $e"
            push!(errors, msg)
            onevent === nothing || onevent(event, false, msg)
            continue
        end
        if op === nothing
            onevent === nothing || onevent(event, true, "")
            continue
        end
        try
            ed = _ReplEditor(document, iomap)
            evaluate_operation(ed, op)
            document = ed.document   # pick up a whole-document swap
        catch e
            msg = "evaluate_operation threw for $event: $e"
            push!(errors, msg)
            onevent === nothing || onevent(event, false, msg)
            continue
        end
        new_iomap = try
            print_document(projection, document)
        catch e
            msg = "print_document threw after $event: $e"
            push!(errors, msg)
            onevent === nothing || onevent(event, false, msg)
            break
        end
        iomap = new_iomap
        before = length(errors)
        _walk!(iomap, Set{UInt64}(), errors)
        if length(errors) > before
            onevent === nothing || onevent(event, false, errors[before + 1])
        else
            onevent === nothing || onevent(event, true, "")
        end
    end
    errors
end

# One @test per event's full read-eval-print cycle. `broken` is an optional
# `(event, message) -> Bool` predicate; a failing event whose error signature it
# recognises is recorded `@test_broken` instead of `@test`, so a *different*
# failure on the same example still surfaces as an unmarked `Fail` (a regression).
# The umbrella supplies the per-example registry (`repl_broken`).
function test_repl(label, document, projection; broken=nothing)
    @testset "$label" begin
        walk_repl_loop(document, projection;
            onevent = (ev, ok, msg) -> begin
                if !ok && broken !== nothing && broken(ev, msg)
                    @test_broken ok
                else
                    ok || @warn "[$label] $msg"
                    @test ok
                end
            end)
    end
end


# The `Example`-typed overload; the all-examples sweep stays in the umbrella.
function test_repl(example::Example)
    test_repl(example.name, example.document, example.projection)
end
