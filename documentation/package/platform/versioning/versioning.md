# Versioning

> **Kind:** design · **Status:** current · **Stands on:** [projection-system.md](../kernel/projection-system.md), [clipboard.md](../clipboard/clipboard.md), [undo.md](../undo/undo.md)

`ProjecturedVersioning` lets any subtree of a document hold several versions of itself. A `VersionedObject` holds the versions, and `VersioningToAnyProjection` shows one of them in place of the wrapper, so every projection after it sees an ordinary document. This document says how the active version is chosen, how edits reach it, and why versions are documents and not a log of operations.

## How it works

The package has two levels of documents:

| Document | Fields |
| --- | --- |
| `VersionedObject` | `versions`, a `CellVector` of `ObjectVersion`, newest first; `criterion`, which selects the active one |
| `ObjectVersion` | `value`, the document of this version; `properties` |
| `VersionProperties` | `timestamp`, `author`, `origin`, `label`, each optional |

Versioning is **optional**: only a subtree inside a `VersionedObject` has versions, and nothing else changes. It is **recursive**: the value of a version can hold more `VersionedObject`s, and each one selects its own version.

### The criterion

**The criterion is a field of the document, not of the projection.** So two versioned nodes in one tree can use two criteria at the same time. The choice is saved with the document, and one projection instance serves every versioned node.

| Criterion | Selects |
| --- | --- |
| `VersionCriterionLatest()` | the newest version, index 1; the default |
| `VersionCriterionIndex(i)` | the version at index `i`, from 1 |
| `VersionCriterionByAuthor(a)` | the newest version with `properties.author == a` |
| `VersionCriterionAsOf(t)` | the newest version with `properties.timestamp <= t` |
| `VersionCriterionPredicate(f)` | the newest version for which `f(properties)` is `true` |

`select_version(object)` dispatches on the criterion and returns `(index, version)`, or `nothing` when no version matches. The versions are newest first, so the newest match is the lowest index. A new way to select is a new subtype of `VersionCriterion` and a method of `_select_version`; the projection does not change.

`SetVersionCriterionOperation(object, criterion)` writes the `criterion` cell. The projection computes the selected version in a cell that reads the criterion. So the view prints the new version, and the editor keeps its IO map. The clipboard uses the same pattern for its toggle; see [clipboard.md](../clipboard/clipboard.md).

### The projection

`VersioningToAnyProjection` prints the `value` of the selected version through `print_child`, and that output is its own output. The wrapper draws nothing. When no version matches, the output is `DocumentNothing()`, as for an empty clipboard slice. A nested `VersionedObject` needs no special code: `print_child` dispatches again at each node, so each level is resolved by its own criterion.

The IO map holds `selection_cell`, a computed cell of `(index, value_iomap)`, and three computed fields that read it: `output`, `index` and `value_iomap`. The reference maps and the reader therefore always use the version that is selected now.

The reference maps are asymmetric, because the wrapper is not in the output. The forward map requires the three steps `versions[index].value` with the selected index, removes them, and gives the rest to the map of the value. The backward map calls the map of the value and puts the three steps in front.

### The reader

**The reader reads its own keys first and the value second.** Two keys belong to the projection, in a `get_projection_gesture_bindings` table:

| Key | What it does |
| --- | --- |
| Ctrl+Shift+S | copies the active value with `copy_document`, clears its selection, and puts it in a new `ObjectVersion` at the front of `versions`, with an author and a time |
| Ctrl+Delete | deletes the active version |

A version that Ctrl+Shift+S makes has the properties that `VersionCriterionByAuthor` and `VersionCriterionAsOf` read. Its `timestamp` is `time()`, the seconds since 1970, and its `author` is the `author` of the projection, `VersioningToAnyProjection(author = "alice")`. With no author named, it is the user of the system, `Sys.username()`, when the version is made.

A key that the table does not take goes to the reader of the selected value. `_prefix_op` puts the three steps `versions[index].value` in front of the operation that comes back. It has a case for each operation shape that holds a reference, from a selection and a range edit to a compound and a collection of intents.

The undo buffer reads in the opposite order, content first and its own keys last, so that the innermost buffer takes Ctrl+Z. [undo.md](../undo/undo.md) gives the reason, and `source/undo/UndoBufferToAny.jl` states it at its head. With the versioning order, the outermost `VersionedObject` on the path takes Ctrl+Shift+S, and a value below it never gets these two keys while a version is selected.

**The two keys use the standard sequence edits.** `insert_elements` and `delete_elements` make a `ReplaceReferencedValueOperation` that ends in a `RangeReferenceStep` on `versions`. Every projection above reroots that operation, so the keys work when the `VersionedObject` is deep in a tree. The operation also has an inverse, so an undo buffer above it can take a new version back.

## How it fits

The code is in `source/versioning/`. `ProjecturedVersioning` depends on the kernel, `ProjecturedCollection` for `versions`, `ProjecturedDomain` for `DocumentNothing` and `ProjecturedPrimitive` for the range edits that `_prefix_op` reroots. No other package depends on it. A program puts a `VersionedObject` into its document and a `VersionedObject => VersioningToAnyProjection()` row into its dispatch table.

It registers nothing at load time; the two keys belong to the projection.

## Design decisions

- **Versions are values in the document, not a log of operations.** A version can then be inspected, printed, edited, copied, saved and versioned again with the machinery that exists. A log that replays inverse operations can not express a branch or a version of one subtree. The undo buffer is that other model, and the two exist side by side. See [plan/pending/object-versioning.md](../../../plan/pending/object-versioning.md).
- **Two levels, not two parallel arrays.** A `values` array beside a `metadata` array falls out of step on an insert or a delete. The properties of a version could then not be selected as one document. `ObjectVersion` keeps the value and its properties together.
- **The criterion is a type with subtypes.** A new way to select is a new subtype, with no `if` chain in the projection.
- **Wrapping turns versioning on.** The projection matches only `VersionedObject`, so no global switch exists.
- **The criterion is on the document.** Two nodes can use two criteria, and a change of the criterion is a cell write.
- **No operation type of its own for a version.** A snapshot and a delete are sequence edits, so every ancestor projection reroots them. A `CreateVersionOperation` and a `DeleteVersionOperation` were the rejected alternative; step 3 of the plan records the reason.

## Usage

```julia
object = VersionedObject(parse_json("""{"status": "draft"}"""); author = "alice", timestamp = 1)
object = VersionedObject([ObjectVersion(parse_json("""{"status": "review"}"""); author = "bob", timestamp = 2),
                          ObjectVersion(parse_json("""{"status": "draft"}"""); author = "alice", timestamp = 1)])
select_version(object)                                        # (1, the version of bob)
operation  = SetVersionCriterionOperation(object, VersionCriterionByAuthor("alice"))
projection = TypeDispatchingProjection(VersionedObject => VersioningToAnyProjection(),
                                       JsonObject => JsonObjectToSyntaxNode())
```

- Example: `versioning_example`, a `VersionedObject` over a JSON object with three versions by three authors. The factories are `make_versioning_document_example()` and `make_versioning_projection_example()` in `example/projectured/`. The example is outside the `examples` registry, because the sweeps share one document; run a test on it by name, for example `test_printer(versioning_example)`.
- Test: `test_versioning_to_any()` in `test/substrate/projection/VersioningToAnyTest.jl`. It covers each criterion, the printer, the empty case, both reference maps, the reader, the two keys and a versioned object inside another.

## Limits

- No view shows all versions of an object at once, to browse or compare them. It is step 5 of [plan/pending/object-versioning.md](../../../plan/pending/object-versioning.md) and is open.
- An edit always changes the selected version. To edit another version, you change the criterion first.
- No key changes the criterion. `SetVersionCriterionOperation` comes from code.
- A new version goes to the front, so `VersionCriterionIndex(i)` then selects a different version than before.
