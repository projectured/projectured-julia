# Bounded sync — a shadow that grows only where someone looked

> **Kind:** reference · **Status:** current · **Stands on:** [system-anatomy.md](../../design/system-anatomy.md)

`sync_document!(shadow, source)` walks the whole source. That is right for a
small document and ruinous for a large one. A discrete-event simulation engine
holds per-module hash and count arrays with over a thousand entries each plus a
future-event heap of thousands of closures; syncing all of it every frame to
display four numbers is wasted work, and the usual response is to give up on
shadowing and hand-write a four-field view instead.

Bounded sync removes that trade. The walk stops at a bound and leaves a marker
where it stopped; a consumer that wants more flags the marker, and the next sync
fills that node in one level deeper.

```julia
shadow = copy_document(MutableCell, source, DepthPolicy(depth = 1))
sync_document!(shadow, source, DepthPolicy(depth = 1))   # cheap, every frame

request_sync!(shadow.some_field)                          # a UI expanded a row
sync_document!(shadow, source, DepthPolicy(depth = 1))    # now one level deeper there
```

Three things follow, and they are the reason to prefer this shape over making
the *projection* lazy:

- **Cost is proportional to what is being looked at**, not to the model. Making
  the projection lazy would leave the sync cost untouched — you would still walk
  a thousand elements per frame and then discard them.
- **Expansion state needs no side table.** It *is* the presence or absence of
  markers in the shadow. Since same-type children are synced in place, the node a
  widget holds is still the node it holds after the next sync.
- **It is reusable.** Any consumer shadowing anything large gets it: a debugger
  over a deep AST, a file-tree view, a live object inspector.

## The marker

```julia
@document struct UnsyncedDocument
    kind::Any        # what stands here, for a label
    size::Int        # its child count when cheaply known, -1 otherwise
    requested::Bool  # set by a consumer; the next sync fills this node in
end
```

An ordinary `Document`, so it flows through printers, references and operations
like anything else. `request_sync!(marker)` sets the flag;
`make_unsynced_marker(document)` builds one, which is how you **collapse** — write a
marker over a subtree and the next sync leaves it alone, so the shadow shrinks
again and a long inspection session does not accumulate the whole model.

## The policy

`SyncPolicy` answers two questions, and they are deliberately separate: whether
to descend into a given child, and how many of a collection's elements to
materialise.

```julia
is_descendable_for_sync(policy, depth, shadow_slot) -> Bool
sync_element_limit(policy, source, shadow) -> Int
```

`DepthPolicy(depth = 1, elements = 32)` is the general answer. Its rule is three
cases, and **only the third is the bound**:

| the slot holds | what happens |
|---|---|
| a marker | descend iff `requested` |
| a document already | keep it, whatever its depth |
| nothing yet | grow it only within `depth` |

The middle case is not an optimisation. Without it a node materialised by a
request sits beyond `depth`, so the next sync would collapse it again and
expansion would oscillate instead of converge. With it, `depth` means "where
growth starts" rather than "the deepest anyone may ever see", and collapsing
works symmetrically at any level — including inside the bound.

`elements` matters as much as `depth`: a thousand-entry array is *one level down*,
so a depth-only bound would still walk every entry of it. Past the cap a single
tail marker reports how many are behind it, and requesting it buys one more page
rather than the whole tail.

## Starting bounded

```julia
copy_document(kind, document, policy) -> Document
```

`copy_document(kind, doc, policy)` is sugar for the four-argument kernel form.
Because the shadow is authoritative for everything except empty slots, it has to
be **born** bounded. A shadow made by the ordinary full `copy_document` has
already grown everything, and a bound can only withhold what has not been grown
yet.

## Reflecting a plain object

`sync_document!` needs a `Document` on both sides, and the things one most wants
to inspect, such as a live engine, a model or a driver, are ordinary structs.
`DocumentReflection` closes that gap: it walks any Julia object into a tree of

```julia
@document struct ReflectedNode
    label::Any     # field name, index, or key
    kind::Any      # type name
    value::Any     # a short rendering, for a leaf
    children::Any  # CellVector when expanded, UnsyncedDocument when collapsed, nothing for a leaf
end
```

and syncs that tree in place under the same policy and the same marker. Those
three states of `children` are exactly the three the policy distinguishes, so
collapsing is just writing a marker there.

```julia
shadow = reflect_document(engine, DepthPolicy(depth = 1))
sync_reflection!(shadow, engine, DepthPolicy(depth = 1))
```

Teach it about a type whose useful structure is not its fields by extending
`reflect_child_count` and `reflect_child_pairs`. Note that these are an
**iterator and a count**, never a vector: building a thousand pairs to show the
first eight puts the cost back exactly where the bound was meant to remove it.
Building a thousand pairs to show the first eight can cost as much as 162 KB
per sync; that is the failure mode to watch for in any extension.

## Rendering it

`ReflectionToWidget` (in the reflection package) renders a `ReflectedNode` tree as a
`WidgetTree` whose chevrons drive the sync rather than merely hiding rows. The
projection has no laziness of its own — it prints whatever the shadow holds,
which is small because the sync was bounded.

Expansion state stays in one place: the printer *derives* the tree's `collapsed`
set from the shadow, and the reader translates a chevron click into a request or
a collapse on the shadow and swallows the operation, so the widget never holds a
disagreeing copy. One wrinkle worth knowing — the tree draws a chevron only for a
node that has children, and a collapsed node has none, so a marker node emits a
single placeholder child carrying the marker's summary. It is never rendered; it
exists so there is a chevron to click.

## Where the walk lives

**In the kernel, and there is only one of it.** Bounding is a *parameter* of
`sync_document!` / `copy_document`, not a second traversal beside them:

```julia
sync_document!(shadow, source, policy = nothing, depth = 0)
copy_document(kind, document, policy = nothing, depth = 0)
```

The kernel consults three generics at every child, declared in
`DocumentInterface.jl` with unbounded defaults in `DocumentDefaults.jl`:

| | |
|---|---|
| `is_descendable_for_sync(policy, depth, slot)` | descend, or stop here? |
| `sync_element_limit(policy, source, shadow)` | how many elements to keep |
| `make_unsynced_placeholder(policy, source, current)` | what stands where it stopped |

`policy = nothing` answers "descend" and "keep them all" and so never reaches the
third — an un-policed walk is exactly the walk it always was, and pays nothing
for the option.

Crucially the kernel never names `UnsyncedDocument` or `DepthPolicy`. It knows
only that *something* goes in the stopped slot, and asks the policy for it; the
marker type and the depth rule stay in `source/reflection/`. `HiddenElements` is the one
piece of vocabulary the contract needs — the elements a capped walk is not
keeping, handed over without copying them, since a positional collection document
is not `view`-able.

A document whose children link back to it adds a method of its own, because the
walk of a record would follow a link and come back through the one that answers
it. The `ListNode` of the collection package is the one such document: its
`sync_document!` syncs each node through this walk, without the two links, and
follows the links itself, from the node held outward; see
[collection.md](../collection/collection.md).

A second, bounded walk kept beside the sealed one would mirror
`_sync_fields!` / `_sync_elements!` / `copy_document` line for line: two
traversals differing only by a policy check, kept in step by hand. It would
also have to reach the kinded-copy machinery by importing kernel internals,
which the module boundary forbids. Folding the bound into the sealed walk
avoids both problems.
