# What each graph layout engine costs, and what it draws, at the three sizes that
# matter: a dozen boxes, a small network, a real one.
#
# The point is not a league table. The engines answer different questions —
# GridEmbedding does not simulate, SpringEmbedderLayout ignores node sizes,
# ForceDirectedLayout carries them and pays for it — and the numbers are what
# decide where the line between them goes. `DeferredLayout` draws that line at
# 20 vertices, which is Qtenv's own threshold; this is how to check it is still
# the right one.

"""
    layout_bench_graph(count) -> (graph, sizes)

A network-shaped graph of `count` vertices: a chain with a longer-range link
every seventh vertex, so it is connected, sparse and not a tree — the shape a
network usually has. Every vertex is 40 by 20.
"""
function layout_bench_graph(count::Integer)
    vertices = [GraphVertex("v$i") for i in 1:count]
    edges = GraphEdge[GraphEdge(vertices[i], vertices[i+1]) for i in 1:count-1]
    for i in 1:count-8
        push!(edges, GraphEdge(vertices[i], vertices[i+7]))
    end
    (GraphGraph(vertices, edges), Dict(objectid(v) => (40, 20) for v in vertices))
end

# How many pairs of placed boxes overlap. Zero is what a reader wants; a large
# number is what "runs off the pane" looks like from the inside.
function layout_overlap_count(positions)
    boxes = collect(values(positions))
    count = 0
    for i in 1:length(boxes), j in (i+1):length(boxes)
        a = boxes[i]; b = boxes[j]
        apart = a[1] + a[3] <= b[1] || b[1] + b[3] <= a[1] ||
                a[2] + a[4] <= b[2] || b[2] + b[4] <= a[2]
        apart || (count += 1)
    end
    count
end

"The mean centre-to-centre length of the edges, and the box the whole drawing fills."
function layout_measures(graph, positions)
    total = 0.0
    counted = 0
    for i in 1:length(graph.edges)
        edge = graph.edges[i]
        source = get(positions, objectid(getfield(edge, :source)[]), nothing)
        target = get(positions, objectid(getfield(edge, :target)[]), nothing)
        (source === nothing || target === nothing) && continue
        total += hypot((source[1] + source[3]/2) - (target[1] + target[3]/2),
                       (source[2] + source[4]/2) - (target[2] + target[4]/2))
        counted += 1
    end
    boxes = collect(values(positions))
    width = maximum(b[1] + b[3] for b in boxes) - minimum(b[1] for b in boxes)
    height = maximum(b[2] + b[4] for b in boxes) - minimum(b[2] for b in boxes)
    (counted == 0 ? 0.0 : total / counted, width, height)
end

"""
    layout_picture(positions; columns = 68, rows = 20) -> String

A picture of a placement, as characters. `*` is one vertex and `#` is more than
one in the same cell, so a drawing that has collapsed reads as a row of hashes.

Characters rather than an image file on purpose: the answer belongs in the same
output as the numbers, and a benchmark that writes six files is a benchmark
nobody looks at.
"""
function layout_picture(positions; columns::Integer = 68, rows::Integer = 20)
    boxes = collect(values(positions))
    xs = [b[1] + b[3]/2 for b in boxes]
    ys = [b[2] + b[4]/2 for b in boxes]
    x1, x2 = extrema(xs); y1, y2 = extrema(ys)
    grid = fill(' ', rows, columns)
    for i in 1:length(boxes)
        column = x2 > x1 ? round(Int, 1 + (xs[i] - x1)/(x2 - x1)*(columns - 1)) : 1
        row = y2 > y1 ? round(Int, 1 + (ys[i] - y1)/(y2 - y1)*(rows - 1)) : 1
        grid[row, column] = grid[row, column] == ' ' ? '*' : '#'
    end
    join((String(grid[r, :]) for r in 1:rows), "\n")
end

"""
    graphlayoutbench(; io = stdout, counts = (10, 60, 300), pictures = true)
        -> Vector{NamedTuple}

Time every layout engine over `counts` vertices and report what each one drew.

Returns one row per engine and size: the engine's name, the vertex count, the
seconds it took, the box it filled, how many boxes overlap and the mean edge
length. Set `pictures = false` for the numbers alone.

`AdaptagramsLayout` is included only when `ProjecturedAdaptagrams` is loaded and
its shim is built.
"""
function graphlayoutbench(; io::IO = stdout, counts = (10, 60, 300),
                          pictures::Bool = true, engines = nothing)
    if engines === nothing
        engines = Any[("GridEmbedding", GridEmbedding()),
                      ("SpringEmbedderLayout", SpringEmbedderLayout()),
                      ("ForceDirectedLayout", ForceDirectedLayout())]
    end

    rows = NamedTuple[]
    println(io, "="^92)
    println(io, "Graph layout: what each engine costs and what it draws")
    println(io, "="^92)
    println(io, rpad("engine", 22), rpad("nodes", 7), rpad("seconds", 11),
                rpad("extent", 15), rpad("overlaps", 10), "mean edge")

    for count in counts
        graph, sizes = layout_bench_graph(count)
        for (name, engine) in engines
            layout_graph(engine, graph, sizes, [])           # warm up the compiler
            seconds = @elapsed positions, _ = layout_graph(engine, graph, sizes, [])
            overlaps = layout_overlap_count(positions)
            edge_length, width, height = layout_measures(graph, positions)
            push!(rows, (engine = name, nodes = count, seconds = seconds,
                         width = width, height = height, overlaps = overlaps,
                         edge_length = edge_length))
            println(io, rpad(name, 22), rpad(count, 7),
                        rpad(round(seconds, digits = 4), 11),
                        rpad("$(round(Int, width))x$(round(Int, height))", 15),
                        rpad(overlaps, 10), round(Int, edge_length))
            if pictures
                println(io, "\n  ", name, ", ", count, " vertices:")
                println(io, layout_picture(positions))
                println(io)
            end
        end
    end
    rows
end
