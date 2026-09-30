# Fragment of `ProjectionModule` — the kinds of path of an output document: the
# selection and the part under the pointer, each the forward image of the same kind
# of path of the input.

"""
    make_output_path_cells(input, map_forward) -> NamedTuple

The cells of every kind of path of the output document that a printer makes from
`input`, as keyword arguments for the constructor of the output: `selection` and
`mouse_target`. Each cell holds the forward image of the same kind of path of
`input`, through `map_forward(path)`, which answers the path in the output or
`nothing`. The selection carries a dormant selection as one
(`map_selection_forward`); the part under the pointer maps as it is.

Use it wherever a printer wires the selection of its output: the one forward map of
the place then wires every kind of path, and a later kind needs no code there.
`map_forward` must map the path it gets, and not read the selection of `input`.

# Example

    iomap_cell = Cell(nothing)
    paths = make_output_path_cells(leaf, path -> begin
        iomap = iomap_cell[]
        iomap === nothing ? nothing : map_reference_forward(p, iomap, path)
    end)
    output = TextBlock(elements; paths...)
"""
make_output_path_cells(input, map_forward) =
    map(compute -> Cell(@computation(compute())), _get_output_path_computations(input, map_forward))

"""
    set_output_path_computations!(output, input, map_forward) -> output

Set the computation of every path cell of `output`, which a printer built already,
as [`make_output_path_cells`](@ref) makes them: each holds the forward image of the
same kind of path of `input` through `map_forward`. A field that `output` does not
have is left out.
"""
function set_output_path_computations!(output, input, map_forward)
    for (name, compute) in pairs(_get_output_path_computations(input, map_forward))
        hasfield(typeof(output), name) && set_cell_computation!(getfield(output, name), compute)
    end
    output
end

# One computation for each kind of path of an output document, by field name.
_get_output_path_computations(input, map_forward) =
    (selection = () -> map_selection_forward(input, map_forward),
     mouse_target = () -> map_mouse_target_forward(input, map_forward))

"""
    map_mouse_target_forward(input, map_forward) -> Reference or nothing

The forward image of the part under the pointer of `input` through `map_forward`,
or `nothing` when `input` holds none or has no such field. A printer whose
selection cell is its own wires the mouse target with it:

    mouse_target = Cell(@computation(map_mouse_target_forward(input, map_forward)))
"""
function map_mouse_target_forward(input, map_forward)
    hasfield(typeof(input), :mouse_target) || return nothing
    path = getfield(input, :mouse_target)[]
    path === nothing ? nothing : map_forward(path)
end
