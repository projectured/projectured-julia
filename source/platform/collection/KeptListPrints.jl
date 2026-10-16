# Fragment of `CollectionModule` — the prints that a view of a list keeps by the
# element of the list, so an element that a new head of the list keeps prints
# once.

"""
    KeptListPrint(value, count, linked)

What a view of a list keeps for one element: `value`, the print of the element
that the view makes; `count`, a cell of the count of the element from the head
of the list, which the path of the print reads; and `linked`, the count of the
last link of the element.

Use it with `KeptListPrints`, which keeps one for each element.
"""
struct KeptListPrint
    value::Any
    count::Union{ImmutableCell{Any}, Cell}
    linked::Base.RefValue{Int}
end

"""
    KeptListPrints

The prints that a view of a list keeps by the element of the list, for the
elements linked under the head of the list and under the head before it. A new
head takes the prints that it has, and only a new element prints; a print that
no link of a head takes goes with the head after it.

The count of a kept element is a computation, so the path of its print follows
the element when it moves. One walk for each head counts the elements, and the
count of an element reads it. On each side of the head the walk goes as far as
the elements linked under this head and under the head before it, and it reads
no link past them, so it builds no element of a lazy list that no link built. An
element that is linked past the walk takes the count of its link. An element
that the walk finds at two places, the same object or an equal value that is no
mutable object, is kept at neither, and each of its prints takes the count of its
link.

Use it in a view that prints each element of a `ListNode`, such as the rows of a
grid of a list.

See also `make_kept_list_prints`, `start_kept_list_head!`, `make_kept_list_count`,
`take_kept_list_print!`, `record_kept_list_print!` and `note_kept_list_link!`.
"""
mutable struct KeptListPrints
    head::Any                         # a function of no arguments that reads the head of the list
    current::IdDict{Any,Any}          # element => KeptListPrint, linked under this head
    before::IdDict{Any,Any}           # element => KeptListPrint, linked under the head before it
    counts::Cell                      # element => its count from the head, or _REPEATED_LIST_ELEMENT
    lowest::Int                       # the lowest count linked under this head, or 1 for none
    highest::Int                      # the highest count linked under this head, or 0 for none
    extent::Tuple{Int,Int}            # the lowest and the highest count linked under the head before it
end

"""
    make_kept_list_prints(head) -> KeptListPrints

The kept prints of a view of the list that `head()` reads: a function of no
arguments that gives the head of the list, a `ListNode`, or anything else for a
view that shows no list.

Use it when a view of a list prints, and give it to the computation of the head
of the view.
"""
function make_kept_list_prints(head)
    keep = KeptListPrints(head, IdDict{Any,Any}(), IdDict{Any,Any}(), Cell(nothing), 1, 0, (1, 0))
    set_cell_computation!(keep.counts, () -> _count_kept_list_elements(keep))
    keep
end

"""
    start_kept_list_head!(keep)

Starts a new head of the list: the prints linked under the head before wait for
one head, and the prints that waited go.

Use it where the view reads a new head, before it links an element of it.
"""
function start_kept_list_head!(keep::KeptListPrints)
    keep.extent = (keep.lowest, keep.highest)
    keep.lowest, keep.highest = 1, 0
    keep.before = keep.current
    keep.current = IdDict{Any,Any}()
    nothing
end

"""
    note_kept_list_link!(keep, k)

Notes that the view linked an element at the count `k` under this head, so the
walk of the counts reaches it when it runs again.

Use it where the view links an element, after its print.
"""
function note_kept_list_link!(keep::KeptListPrints, k::Int)
    keep.lowest = min(keep.lowest, k)
    keep.highest = max(keep.highest, k)
    nothing
end

"""
    make_kept_list_count(keep, element, k) -> (count, linked)

The count of `element` for its print at `k`, and the count of its last link,
`k`. The count is a computation of the count of the element from the head when
the view can keep the print, and the cell of `k` when it can not: the counts
find the element at two places, or at another place nearer the head.

Use it before the print of an element, for the path of its print.
"""
function make_kept_list_count(keep::KeptListPrints, element, k::Int)
    linked = Ref(k)
    _is_repeated_list_element(keep, element) && return (ImmutableCell{Any}(k), linked)
    count = Cell(@computation _get_kept_list_count(keep.counts[], element, linked[]))
    (peek(count) == k ? count : ImmutableCell{Any}(k), linked)
end

"""
    take_kept_list_print!(keep, element, k, is_current) -> KeptListPrint or nothing

The kept print of `element` for its link at `k`, or `nothing` when the element
prints again: it has no kept print, its count is not `k`, the counts find it at
two places, or `is_current(print)` answers `false`, as the view answers for a
print whose cells hold other documents now. A print that it takes is kept under
this head, at `k`.

Use it where the view links an element, before it prints one.
"""
function take_kept_list_print!(keep::KeptListPrints, element, k::Int, is_current)
    _is_repeated_list_element(keep, element) && return nothing
    kept = get(keep.current, element, nothing)
    kept === nothing && (kept = get(keep.before, element, nothing))
    kept === nothing && return nothing
    peek(kept.count) == k || return nothing
    is_current(kept) || return nothing
    delete!(keep.before, element)
    keep.current[element] = kept
    kept.linked[] = k
    kept
end

"""
    record_kept_list_print!(keep, element, print) -> KeptListPrint

Keeps `print`, the print of `element` that the view made under this head, when
its count is a computation; a print whose count is fixed is not kept.

Use it after the print of an element.
"""
function record_kept_list_print!(keep::KeptListPrints, element, print::KeptListPrint)
    print.count isa ImmutableCell || (keep.current[element] = print)
    print
end

# The mark in the counts of a head of an element at two places.
const _REPEATED_LIST_ELEMENT = typemin(Int)

# The count of `element` in `counts`, or `linked` for an element that the counts
# do not reach or find at two places.
function _get_kept_list_count(counts, element, linked::Int)
    count = get(counts, element, nothing)
    (count === nothing || count == _REPEATED_LIST_ELEMENT) ? linked : count
end

_is_repeated_list_element(keep::KeptListPrints, element) =
    get(peek(keep.counts), element, nothing) == _REPEATED_LIST_ELEMENT

# The count of each element of the list from the head: 1 at the head, and 0 and
# less before it; an element that the walk meets two times is marked. The walk
# goes from the head both ways in turn, as far as the elements linked under this
# head and under the head before it on each side.
function _count_kept_list_elements(keep::KeptListPrints)
    counts = IdDict{Any,Int}()
    head = keep.head()
    head isa ListNode || return counts
    lowest = min(keep.extent[1], keep.lowest)
    highest = max(keep.extent[2], keep.highest)
    steps_before = max(0, 1 - lowest)
    after = highest >= 1 ? head : nothing
    before = steps_before >= 1 ? head.prev : nothing
    for i in 1:max(highest, steps_before)
        if after !== nothing && i <= highest
            counts[after.value] = haskey(counts, after.value) ? _REPEATED_LIST_ELEMENT : i
            after = i < highest ? after.next : nothing
        end
        if before !== nothing && i <= steps_before
            counts[before.value] = haskey(counts, before.value) ? _REPEATED_LIST_ELEMENT : 1 - i
            before = i < steps_before ? before.prev : nothing
        end
    end
    counts
end
