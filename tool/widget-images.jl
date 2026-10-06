# ═══════════════════════════════════════════════════════════════════════════
# The instrument the widget-sizing plan is measured with.
#
#     julia --project=environment/all tool/widget-images.jl write  before
#     julia --project=environment/all tool/widget-images.jl write  after
#     julia --project=environment/all tool/widget-images.jl compare before after
#
# It draws every widget example to an image and compares two such directories.
#
# **A changed picture is not a failure and an identical one is not success.**
# Several steps of the plan are meant to change what things look like. What the
# comparison buys is that every change is one somebody looked at and named, so a
# step's commit says, per example, either "unchanged" or what moved and why it is
# right.
# ═══════════════════════════════════════════════════════════════════════════

using ProjecturedExample
# `write_image` is a backend seam; the SDL package is what fills it in.
using ProjecturedSDL
using SHA

# One per widget, plus the two that show a widget tree the conversation builds.
const WIDGET_EXAMPLES = [
    "widget", "widget_label", "widget_text", "widget_checkbox", "widget_button",
    "widget_button_action", "widget_button_image", "widget_tooltip",
    "widget_menu_item", "widget_menu", "widget_toolbar", "widget_toolbar_item", "widget_composite",
    "widget_title_pane", "widget_split_pane", "widget_scroll_bar",
    "widget_scroll_pane", "widget_transform_pane", "widget_shell",
    # The one example that hands its widgets a real offer on both axes.
    "widget_offered",
    "widget_tabbed_pane", "widget_badge", "widget_separator", "widget_card",
    "widget_switch", "widget_progress_bar", "widget_progress_ring", "widget_slider", "widget_radio_group",
    "widget_avatar", "widget_alert", "widget_skeleton", "widget_toggle",
    "widget_toggle_group", "widget_select", "widget_textarea", "widget_accordion",
    "widget_table", "widget_table_offered", "widget_table_frozen",
    "widget_tree", "widget_disabled", "widget_focus",
    "conversation_widget",
]

"""
    write_widget_images(directory) -> Vector{String}

Draw every example of `WIDGET_EXAMPLES` into `directory`. An example that throws
is written as a `.failed` file holding the error, so a step that breaks one is
visible in the comparison rather than absent from it.
"""
function write_widget_images(directory::AbstractString)
    mkpath(directory)
    written = String[]
    for name in WIDGET_EXAMPLES
        path = joinpath(directory, name * ".bmp")
        try
            write_example_image(name, path)
            # A previous run may have left the note of a failure here.
            isfile(path * ".failed") && rm(path * ".failed")
            push!(written, name)
        catch e
            write(path * ".failed", sprint(showerror, e))
            @warn "[widget-images] $name did not draw" exception = e
        end
    end
    @info "[widget-images] wrote $(length(written)) of $(length(WIDGET_EXAMPLES)) into $directory"
    written
end

# A BMP's pixel size, read from its header (bytes 19-26, little endian).
function _bmp_size(bytes::Vector{UInt8})
    length(bytes) < 26 && return (0, 0)
    read32(i) = Int(bytes[i]) | Int(bytes[i+1]) << 8 | Int(bytes[i+2]) << 16 | Int(bytes[i+3]) << 24
    (read32(19), read32(23))
end

_differing_bytes(a::Vector{UInt8}, b::Vector{UInt8}) =
    count(i -> a[i] != b[i], 1:min(length(a), length(b))) +
    abs(length(a) - length(b))

"""
    compare_widget_images(before, after) -> Bool

Compare two directories written by `write_widget_images`, one line per example.
Answers `true` when every example drew in both.
"""
function compare_widget_images(before::AbstractString, after::AbstractString)
    all_drew = true
    for name in WIDGET_EXAMPLES
        a = joinpath(before, name * ".bmp")
        b = joinpath(after,  name * ".bmp")
        if !isfile(a) || !isfile(b)
            println(rpad(name, 24), isfile(a) ? "GONE — it drew before and not after" :
                                    isfile(b) ? "NEW — it drew after and not before" :
                                                "MISSING from both")
            all_drew = false
            continue
        end
        ba, bb = read(a), read(b)
        if ba == bb
            println(rpad(name, 24), "unchanged")
            continue
        end
        wa, ha = _bmp_size(ba)
        wb, hb = _bmp_size(bb)
        size_note = (wa, ha) == (wb, hb) ? "same size $(wa)x$(ha)" :
                    "size $(wa)x$(ha) -> $(wb)x$(hb)"
        differing = _differing_bytes(ba, bb)
        share = round(100 * differing / max(1, length(ba)); digits = 1)
        println(rpad(name, 24), "CHANGED   ", size_note,
                "   ", differing, " bytes differ (", share, "%)")
    end
    all_drew
end

if abspath(PROGRAM_FILE) == @__FILE__
    length(ARGS) >= 1 || error("usage: widget-images.jl write <dir> | compare <before> <after>")
    if ARGS[1] == "write"
        length(ARGS) == 2 || error("usage: widget-images.jl write <dir>")
        write_widget_images(ARGS[2])
    elseif ARGS[1] == "compare"
        length(ARGS) == 3 || error("usage: widget-images.jl compare <before> <after>")
        compare_widget_images(ARGS[2], ARGS[3]) || exit(1)
    else
        error("usage: widget-images.jl write <dir> | compare <before> <after>")
    end
end
