# Fragment of `ProjectionModule` — the kinds of path of an output document: the
# selection and the part under the pointer, each the forward image of the same kind
# of path of the input.

"""
    make_output_path_cells(input, map_forward; dormant = true) -> NamedTuple

The cells of every kind of path of the output document that a printer makes from
`input`, as keyword arguments for the constructor of the output: `selection` and
`mouse_target`. Each cell holds the forward image of the same kind of path of
`input`, through `map_forward(path)`, which answers the path in the output or
`nothing`. The selection carries a dormant selection as one
(`map_selection_forward`); with `dormant = false` it maps only a live one, for an
output that routes keys by its selection. The part under the pointer maps as it is.

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
make_output_path_cells(input, map_forward; dormant::Bool = true) =
    map(compute -> Cell(@computation(compute())),
        _get_output_path_computations(input, map_forward, dormant))

"""
    set_output_path_computations!(output, input, map_forward; dormant = true) -> output

Set the computation of every path cell of `output`, which a printer built already,
as [`make_output_path_cells`](@ref) makes them: each holds the forward image of the
same kind of path of `input` through `map_forward`. A field that `output` does not
have is left out.
"""
function set_output_path_computations!(output, input, map_forward; dormant::Bool = true)
    for (name, compute) in pairs(_get_output_path_computations(input, map_forward, dormant))
        hasfield(typeof(output), name) && set_cell_computation!(getfield(output, name), compute)
    end
    output
end

# One computation for each kind of path of an output document, by field name.
_get_output_path_computations(input, map_forward, dormant::Bool) =
    (selection = dormant ? () -> map_selection_forward(input, map_forward) :
                           () -> (is_live_selection(input) ? map_selection_forward(input, map_forward) : nothing),
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

"""
    set_output_tree_path_computations!(root) -> root

Set the path cells of each document below `root`, an output that a printer built:
each child holds the part of each kind of path of its parent below the step that
reaches it, as [`set_output_path_computations!`](@ref) makes them. A key is routed
by the selection, and every container between the root of the output and the part
that holds the caret must carry the path, or the key stops at the first that does
not. Wire the paths of `root` itself first, with `set_output_path_computations!`.
"""
function set_output_tree_path_computations!(root)
    _set_child_path_computations!(root, Base.IdSet{Any}())
    root
end

function _set_child_path_computations!(node, seen::Base.IdSet{Any})
    node in seen && return nothing
    push!(seen, node)
    for (step, child) in child_reference_steps(node)
        child = unwrap_cell(child)
        (child isa Document && hasfield(typeof(child), :selection) &&
         getfield(child, :selection) isa Cell) || continue
        set_output_path_computations!(child, node, path -> _get_path_below(path, step))
        _set_child_path_computations!(child, seen)
    end
    nothing
end

# The part of `path` below its first step when that step is `step`, or `nothing`.
_get_path_below(path, step) =
    (path isa ConcreteReference && path.head == step) ? path.tail : nothing
