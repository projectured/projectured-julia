# ═══════════════════════════════════════════════════════════════════════════
# test/src/editor/ReplTest.jl
#
# Full REPL-loop test.  For each event in _ALL_READER_EVENTS the complete
# editor cycle is exercised:
#   1. projection_read       — translate event to operation
#   2. evaluate_operation    — apply operation to document
#   3. projection_print      — re-project the updated document
#   4. _walk! on the iomap   — force every Cell in the new output
# The iomap fed to the next projection_read is always the one produced by
# the most recent projection_print, mirroring the real editor loop.
# ═══════════════════════════════════════════════════════════════════════════

# If `onevent` is supplied it is called once per event with
# `(event, ok::Bool, message::String)` summarising that event's full
# read → evaluate → reprint → walk cycle, letting a caller emit one assertion
# per event.
function walk_repl_loop(document, projection; onevent=nothing)
    errors = String[]
    clear_selection!(document)
    iomap = try
        projection_print(projection, document)
    catch e
        msg = "initial projection_print threw: $e"
        push!(errors, msg)
        onevent === nothing || onevent(nothing, false, msg)
        return errors
    end
    for event in _ALL_READER_EVENTS
        op = try
            projection_read(projection, iomap, event)
        catch e
            msg = "projection_read threw for $event: $e"
            push!(errors, msg)
            onevent === nothing || onevent(event, false, msg)
            continue
        end
        if op === nothing
            onevent === nothing || onevent(event, true, "")
            continue
        end
        try
            evaluate_operation((document=document,), op)
        catch e
            msg = "evaluate_operation threw for $event: $e"
            push!(errors, msg)
            onevent === nothing || onevent(event, false, msg)
            continue
        end
        new_iomap = try
            projection_print(projection, document)
        catch e
            msg = "projection_print threw after $event: $e"
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

# One @test per event's full read-eval-print cycle.
function test_repl(label, document, projection)
    @testset "$label" begin
        walk_repl_loop(document, projection;
            onevent = (ev, ok, msg) -> begin
                ok || @warn "[$label] $msg"
                @test ok
            end)
    end
end

function test_repl(example::Example)
    test_repl(example.name, example.document, example.projection)
end

function test_repls()
    @testset "Repls" begin
        for example in examples
            @testset "$(example.name)" begin
                test_repl(example)
            end
        end
    end
end
