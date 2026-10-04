# Fragment of `GraphicsModule` — the baseline of the first line of text that an
# output draws, which a row reads to align its children on their baselines.

"""
    find_first_baseline(iomap) -> Int or nothing

The baseline of the first line of text that the output of `iomap` draws, in
pixels from the top of that output, or `nothing` when it draws no text. A row
that aligns its children on their baselines (`vertical_align = :baseline`) reads
it from each child, as it reads the extent of each child.

A projection whose output draws text answers it. A wrapper answers what it
wraps: a chain the IoMap of its last stage, a barrier its content, a wrapper that
shows its content as its own output that content, and a container of placed
children its first child that has one, offset by the place of that child. Every
other IoMap answers `nothing`.
"""
function find_first_baseline(iomap)
    content = get_content_iomap(iomap)
    content === iomap ? nothing : find_first_baseline(content)
end

function find_first_baseline(iomap::ChainingIoMap)
    steps = iomap.step_iomaps
    isempty(steps) ? nothing : find_first_baseline(unwrap_cell(last(steps)))
end

function find_first_baseline(iomap::ContentIoMap)
    inner = iomap.inner_iomap
    inner === nothing && return nothing
    inner.output === iomap.output ? find_first_baseline(inner) : nothing
end

# A container keeps each child as `(x, y, iomap)`, its place and its IoMap.
function find_first_baseline(iomap::ChildrenIoMap)
    for entry in unwrap_cell(iomap.child_iomaps)
        (entry isa Tuple && length(entry) == 3) || continue
        baseline = find_first_baseline(entry[3])
        baseline === nothing || return Int(unwrap_cell(entry[2])) + baseline
    end
    nothing
end

# A projection with a plain IoMap answers by a method for itself; one that draws
# no text has none.
find_first_baseline(iomap::SimpleIoMap) = find_first_baseline(iomap.projection, iomap)
find_first_baseline(projection, iomap::SimpleIoMap) = nothing
