# ═══════════════════════════════════════════════════════════════════════════
# test/editor/JsonContentClicksTest.jl
#
# JSON content click → clean path. Uses the TextToGraphics traversal helpers
# from ProjecturedVisualTest and JSON domain vocabulary; migrates to
# ProjecturedDomainTest in phase 3 of plan/pending/test-package-split.md.
# ═══════════════════════════════════════════════════════════════════════════

# ── JSON content click → clean path ────────────────────────────────────────

# A click on a character that comes from a JSON document's content (a
# JsonString/JsonNumber/JsonBool value, or a JsonObjectEntry key) must
# produce a path made entirely of FieldReferenceStep / RangeReferenceStep steps —
# no ProjectionReferenceStep, since the click did not land on a
# projection-introduced character (delimiter, separator, whitespace).
#
# Clicks on JsonNull / JsonInsertion are deliberately *not* asserted because
# their rendered text ("null", placeholder) is projection-introduced.

"""
    test_json_content_clicks_clean(label, document, projection)

For each rendered segment whose content matches a known JSON content
string (a JsonString/JsonNumber/JsonBool value or an object key), fire a
click and assert the resulting path contains no `ProjectionReferenceStep`.
"""
function test_json_content_clicks_clean(label, document, projection)
    @testset "$label" begin
        clear_selection!(document)
        iomap = print_document(projection, document)
        t2g = _find_text_iomap(iomap)
        if t2g === nothing
            @test true
            return
        end
        coords = t2g.char_to_coord[]
        measure = _pipeline_measure(projection)
        content_strings = _collect_json_content_strings(document)
        errors = String[]
        for sc in coords
            sc.text in content_strings || continue
            line_h = sc.font.size
            # Click in the middle of the segment, well inside content.
            cx = sc.x + max(1, (_seg_x_at(sc, sc.char_end, measure) - sc.x) ÷ 2)
            cy = sc.y + max(1, line_h ÷ 2)
            op = read_intent(projection, iomap, MousePress(:left, cx, cy, ModifierKeys()))
            op isa ReplaceSelectionOperation || continue
            if _path_contains_projection_ref(op.path)
                push!(errors, "click on content $(repr(sc.text)) at ($cx,$cy) produced path with ProjectionReferenceStep: $(op.path)")
            end
        end
        for e in errors
            @warn "[$label] $e"
        end
        @test isempty(errors)
    end
end

# Recursively collect every string that came from the JSON document
# content (not from projection-introduced delimiters or literals).
_collect_json_content_strings(_) = String[]

function _collect_json_content_strings(j::JsonModule.JsonString)
    [String(j.value)]
end

function _collect_json_content_strings(j::JsonModule.JsonNumber)
    [string(j.value)]
end

function _collect_json_content_strings(j::JsonModule.JsonBool)
    [j.value ? "true" : "false"]
end

function _collect_json_content_strings(j::JsonModule.JsonArray)
    out = String[]
    for e in j.elements
        append!(out, _collect_json_content_strings(e))
    end
    out
end

function _collect_json_content_strings(j::JsonModule.JsonObject)
    out = String[]
    for e in j.entries
        push!(out, String(e.key))
        append!(out, _collect_json_content_strings(e.value))
    end
    out
end

# The all-examples sweep (`test_json_content_clicks_clean_all`) lives in the
# `ProjecturedTest` umbrella, which owns the example registry.
