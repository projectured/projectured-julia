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
