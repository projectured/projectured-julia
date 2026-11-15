# Fragment of `TooltipModule` — what the tooltip window holds.

"""
    TooltipContent(; layers, shown)

The content of a tooltip window: `layers` are the `(title, content)` pairs of an
[`OpenTooltipOperation`](@ref), the nearest part first, and `shown` is how many of
them the window shows. The natural projection draws it: the content of each shown
layer; when more than one shows, each starts with a separator and its title,
which names the part it comes from.
"""
@document struct TooltipContent
    layers::Any = Tuple{String,Document}[]
    shown::Int = 1
end

"""
    describe_layer_keys(shown, count) -> String | Nothing

The line under a tooltip that shows `shown` of its `count` layers: the key of
one more while the parts around have more to say, the key of one fewer while
more than one shows, or both; `nothing` when one layer is all there is. The keys
are the ones that the window binds, [`WINDOW_LAYER_MORE_KEY`](@ref) and
[`WINDOW_LAYER_FEWER_KEY`](@ref), so the line names the key that works.
"""
function describe_layer_keys(shown::Int, count::Int)
    more = shown < count ? string(describe_gesture_pattern(WINDOW_LAYER_MORE_KEY), " shows ",
                                  count - shown, " more") : nothing
    fewer = shown > 1 ? string(describe_gesture_pattern(WINDOW_LAYER_FEWER_KEY), " shows one fewer") : nothing
    more === nothing ? fewer : fewer === nothing ? more : string(more, ", ", fewer)
end
