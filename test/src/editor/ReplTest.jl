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

function walk_repl_loop(document, projection)
    errors = String[]
    clear_selection!(document)
    iomap = try
        projection_print(projection, document)
    catch e
        push!(errors, "initial projection_print threw: $e")
        return errors
    end
    for event in _ALL_READER_EVENTS
        op = try
            projection_read(projection, iomap, event)
        catch e
            push!(errors, "projection_read threw for $event: $e")
            continue
        end
        op === nothing && continue
        try
            evaluate_operation(op, document)
        catch e
            push!(errors, "evaluate_operation threw for $event: $e")
            continue
        end
        iomap = try
            projection_print(projection, document)
        catch e
            push!(errors, "projection_print threw after $event: $e")
            break
        end
        _walk!(iomap, Set{UInt64}(), errors)
    end
    errors
end

function test_repl(label, document, projection)
    @testset "$label" begin
        errors = walk_repl_loop(document, projection)
        for e in errors
            @warn "[$label] $e"
        end
        @test isempty(errors)
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
