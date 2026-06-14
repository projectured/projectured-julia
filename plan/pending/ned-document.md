# NED Document Domain — `Ned.jl`

Add an OMNeT++ NED2 document domain to ProjecturEd, modelled after `Xml.jl`
and `Json.jl`. The NED2 grammar is defined in
[`ned2.dtd`](https://github.com/omnetpp/omnetpp/blob/master/doc/etc/ned2.dtd).

## Source material

The DTD declares ~27 element types. Many are thin wrappers (e.g. `extends`,
`interface-name`, `loop`, `condition`) that carry a single `name` or
`condition` attribute. The core modelling types are modules, channels,
parameters, gates, connections, and submodules.

## Design decisions

### Flatten vs. mirror the DTD

The DTD has several wrapper elements (`parameters`, `gates`, `types`,
`submodules`, `connections`) whose only purpose is to group child lists under
an XML parent. In the ProjecturEd document model every `CellVector` already
serves that role, so these wrapper elements can be **flattened into the parent
type as a `CellVector` field** (same as `XmlElement.cell` and
`JsonObject.entries`). The wrapper's own attributes (e.g.
`parameters.is-implicit`, `connections.allow-unconnected`) become boolean
fields on the parent.

### Comment handling

`comment` elements appear almost everywhere in the DTD. Following the XML
domain precedent (where comments are not modelled as separate types), comments
should be stored as optional `String` fields or a leading `CellVector` where
the DTD explicitly allows `comment*` sequences. For a first cut, **defer
comment nodes** and add them later as `NedComment` leaf documents if needed.

### Boolean DTD attributes

The DTD encodes booleans as `(true|false)` with a default of `"false"`. Map
these to `Bool` Cell fields with a `false` default.

### `CDATA` expression attributes

Attributes like `value`, `vector-size`, `like-expr`, `from-value`, `to-value`,
`condition` hold NED expression strings. Store as `String` (or `Nothing` when
`#IMPLIED`). Expression parsing is a separate concern — if a future
NedToSyntax projection is added, it will parse these into syntax trees.

## Type hierarchy

```
Document
 └── NedDocument (abstract)
      ├── NedFile              # top-level container
      ├── NedPackage           # package declaration
      ├── NedImport            # import statement
      │
      ├── NedSimpleModule      # simple module definition
      ├── NedCompoundModule    # compound module definition
      ├── NedModuleInterface   # module interface definition
      ├── NedChannel           # channel definition
      ├── NedChannelInterface  # channel interface definition
      │
      ├── NedParam             # parameter declaration/assignment
      ├── NedProperty          # @property annotation
      ├── NedPropertyDecl      # property declaration
      ├── NedPropertyKey       # key inside a property
      ├── NedLiteral           # typed literal value
      │
      ├── NedGate              # gate declaration
      │
      ├── NedSubmodule         # submodule instance
      ├── NedConnection        # connection arrow
      ├── NedConnectionGroup   # grouped connections with for/if
      ├── NedLoop              # for-loop header
      ├── NedCondition         # if-condition
      │
      ├── NedExtends           # "extends Base" clause
      ├── NedInterfaceName     # "like IFoo" clause
      │
      └── NedInsertion         # insertion cursor (editor)
```

## Field mapping (DTD → Julia)

### `NedFile`
| DTD attribute | Field | Type |
|---|---|---|
| `filename` | `filename` | `String` |
| `version` | `version` | `String` |
| children | `children` | `CellVector` — holds `NedPackage`, `NedImport`, `NedPropertyDecl`, `NedProperty`, `NedSimpleModule`, `NedCompoundModule`, `NedModuleInterface`, `NedChannel`, `NedChannelInterface` |

### `NedPackage`
| Field | Type |
|---|---|
| `name` | `String` |

### `NedImport`
| Field | Type |
|---|---|
| `import_spec` | `String` |

### `NedExtends`
| Field | Type |
|---|---|
| `name` | `String` |

### `NedInterfaceName`
| Field | Type |
|---|---|
| `name` | `String` |

### `NedSimpleModule`
| Field | Type | Notes |
|---|---|---|
| `name` | `String` | |
| `extends` | `Any` | `Nothing` or `NedExtends` |
| `interface_names` | `CellVector` | of `NedInterfaceName` |
| `params` | `CellVector` | of `NedParam` / `NedProperty` |
| `params_implicit` | `Bool` | from `parameters.is-implicit` |
| `gates` | `CellVector` | of `NedGate` |

### `NedCompoundModule`
| Field | Type | Notes |
|---|---|---|
| `name` | `String` | |
| `extends` | `Any` | `Nothing` or `NedExtends` |
| `interface_names` | `CellVector` | of `NedInterfaceName` |
| `params` | `CellVector` | of `NedParam` / `NedProperty` |
| `params_implicit` | `Bool` | |
| `gates` | `CellVector` | of `NedGate` |
| `types` | `CellVector` | inner type definitions |
| `submodules` | `CellVector` | of `NedSubmodule` |
| `connections` | `CellVector` | of `NedConnection` / `NedConnectionGroup` |
| `connections_allow_unconnected` | `Bool` | |
| `collapsed` | `Bool` | UI fold state |

### `NedModuleInterface`
| Field | Type |
|---|---|
| `name` | `String` |
| `extends_list` | `CellVector` — of `NedExtends` (multiple allowed) |
| `params` | `CellVector` |
| `params_implicit` | `Bool` |
| `gates` | `CellVector` |

### `NedChannel`
| Field | Type |
|---|---|
| `name` | `String` |
| `extends` | `Any` |
| `interface_names` | `CellVector` |
| `params` | `CellVector` |
| `params_implicit` | `Bool` |

### `NedChannelInterface`
| Field | Type |
|---|---|
| `name` | `String` |
| `extends_list` | `CellVector` |
| `params` | `CellVector` |
| `params_implicit` | `Bool` |

### `NedParam`
| Field | Type | Notes |
|---|---|---|
| `name` | `String` | |
| `type` | `Any` | `Nothing` or `Symbol` — `:double`, `:int`, `:string`, `:bool`, `:object`, `:xml` |
| `value` | `Any` | `Nothing` or expression `String` |
| `is_volatile` | `Bool` | |
| `is_pattern` | `Bool` | |
| `is_default` | `Bool` | |
| `properties` | `CellVector` | of `NedProperty` |

### `NedProperty`
| Field | Type |
|---|---|
| `name` | `String` |
| `index` | `Any` — `Nothing` or `String` |
| `is_implicit` | `Bool` |
| `keys` | `CellVector` — of `NedPropertyKey` |

### `NedPropertyDecl`
| Field | Type |
|---|---|
| `name` | `String` |
| `is_array` | `Bool` |
| `keys` | `CellVector` |
| `properties` | `CellVector` |

### `NedPropertyKey`
| Field | Type |
|---|---|
| `name` | `Any` — `Nothing` or `String` |
| `literals` | `CellVector` — of `NedLiteral` |

### `NedLiteral`
| Field | Type | Notes |
|---|---|---|
| `type` | `Symbol` | `:double`, `:quantity`, `:int`, `:bool`, `:string`, `:spec` |
| `text` | `Any` | `Nothing` or `String` |
| `value` | `Any` | `Nothing` or `String` |

### `NedGate`
| Field | Type |
|---|---|
| `name` | `String` |
| `type` | `Any` — `Nothing` or `Symbol` `:input`, `:output`, `:inout` |
| `is_vector` | `Bool` |
| `vector_size` | `Any` — `Nothing` or expression `String` |
| `properties` | `CellVector` |

### `NedSubmodule`
| Field | Type |
|---|---|
| `name` | `String` |
| `type` | `Any` — `Nothing` or `String` |
| `like_type` | `Any` |
| `like_expr` | `Any` |
| `is_default` | `Bool` |
| `vector_size` | `Any` |
| `condition` | `Any` — `Nothing` or `NedCondition` |
| `params` | `CellVector` |
| `params_implicit` | `Bool` |
| `gates` | `CellVector` |

### `NedConnection`
| Field | Type |
|---|---|
| `src_module` | `Any` |
| `src_module_index` | `Any` |
| `src_gate` | `String` |
| `src_gate_plusplus` | `Bool` |
| `src_gate_index` | `Any` |
| `src_gate_subg` | `Any` — `Nothing` or `Symbol` `:i`, `:o` |
| `dest_module` | `Any` |
| `dest_module_index` | `Any` |
| `dest_gate` | `String` |
| `dest_gate_plusplus` | `Bool` |
| `dest_gate_index` | `Any` |
| `dest_gate_subg` | `Any` |
| `name` | `Any` — channel name |
| `type` | `Any` — channel type |
| `like_type` | `Any` |
| `like_expr` | `Any` |
| `is_default` | `Bool` |
| `is_bidirectional` | `Bool` |
| `is_forward_arrow` | `Bool` |
| `params` | `CellVector` |
| `loops` | `CellVector` — of `NedLoop` |
| `conditions` | `CellVector` — of `NedCondition` |

### `NedConnectionGroup`
| Field | Type |
|---|---|
| `loops` | `CellVector` — of `NedLoop` |
| `conditions` | `CellVector` — of `NedCondition` |
| `connections` | `CellVector` — of `NedConnection` |

### `NedLoop`
| Field | Type |
|---|---|
| `param_name` | `String` |
| `from_value` | `Any` |
| `to_value` | `Any` |

### `NedCondition`
| Field | Type |
|---|---|
| `condition` | `Any` — expression `String` |

### `NedInsertion`
| Field | Type |
|---|---|
| `value` | `Any` |

Every type above also gets the mandatory `selection::Reference` field.

## Implementation steps

### Step 1 — Scaffold `Ned.jl` (document types only) ✅

Done. Created [`program/src/document/Ned.jl`](../../program/src/document/Ned.jl)
containing `module NedModule` with:

- `abstract type NedDocument <: Document end`
- 22 concrete `@document struct` types (leaf → mid-level → compound → top-level)
- Keyword-argument convenience constructors for every type
- `Base.show` methods for REPL display
- Export list (concrete types + I-struct counterparts)

### Step 2 — Register in `Projectured.jl` ⏳

Add `include("document/Ned.jl")` and `using .NedModule` to the main module,
insert the appropriate exports.

### Step 3 — Parser: `nedparse` ✅

Done. Created [`program/src/parser/NedParser.jl`](../../program/src/parser/NedParser.jl)
containing `module NedParserModule` with `nedparse(text)` and `nedparse_file(path)`.

Parses `.ned` source text directly into the document model. This is more useful
than an XML-based converter because `.ned` files are the primary authoring format.

#### NED syntax overview (from samples)

The NED language is brace-delimited, C-style commented (`//`), with these
top-level constructs:

```
package <dotted-name>;
import <dotted-name-with-wildcards>;
@<property-name>(<keys>);
simple <Name> [extends <Base>] [like <IFace>, ...] { ... }
module <Name> [extends <Base>] [like <IFace>, ...] { ... }   // "network" = module
moduleinterface <Name> [extends <Base>, ...] { ... }
channel <Name> [extends <Base>] [like <IFace>, ...] { ... }
channelinterface <Name> [extends <Base>, ...] { ... }
```

`network` is syntactic sugar for a compound module (uses `NedCompoundModule`).

Inside braces, section keywords introduce child lists:

```
parameters:      // param decls, @property annotations
gates:           // gate decls
types:           // inner channel/module definitions
submodules:      // submodule instances
connections:     // connection arrows
connections allowunconnected:
```

#### Lexer tokens

The parser needs to recognise:

- **Keywords**: `package`, `import`, `simple`, `module`, `network`,
  `moduleinterface`, `channelinterface`, `channel`, `extends`, `like`,
  `parameters`, `gates`, `types`, `submodules`, `connections`,
  `allowunconnected`, `input`, `output`, `inout`, `volatile`, `default`,
  `if`, `for`, `int`, `double`, `string`, `bool`, `object`, `xml`, `true`,
  `false`
- **Identifiers**: `[A-Za-z_][A-Za-z0-9_]*`
- **Qualified names**: `id(.id)*`
- **Punctuation**: `{`, `}`, `(`, `)`, `[`, `]`, `;`, `,`, `=`, `@`, `.`,
  `..`, `:`, `++`
- **Arrows**: `-->`, `<--`, `<-->`
- **Comments**: `//` to end-of-line (discard for now)
- **String literals**: `"..."`
- **Numeric literals**: integers, floats, with optional unit suffix
- **Expressions**: everything between `=` and `;` or between `(` `)` in
  property values — captured as opaque strings (no expression AST)

#### Parser strategy

A hand-written recursive-descent parser, operating on the token stream.
Expressions are **not** parsed into an AST — the parser collects tokens
between delimiters and joins them back into a string. This matches the
"opaque strings" decision.

Pseudo-structure:

```
nedparse(text)
  → tokenize(text) → Vector{Token}
  → parse_file(tokens) → NedFile
      ├── parse_package()       → NedPackage
      ├── parse_import()        → NedImport
      ├── parse_property()      → NedProperty   (file-level @prop)
      ├── parse_simple_module() → NedSimpleModule
      ├── parse_compound_module() → NedCompoundModule  (also handles `network`)
      ├── parse_module_interface() → NedModuleInterface
      ├── parse_channel()       → NedChannel
      └── parse_channel_interface() → NedChannelInterface

Inside module/channel bodies:
      ├── parse_parameters_block() → populate params CellVector
      │     ├── parse_param()      → NedParam
      │     └── parse_property()   → NedProperty
      ├── parse_gates_block()      → populate gates CellVector
      │     └── parse_gate()       → NedGate
      ├── parse_types_block()      → populate types CellVector
      ├── parse_submodules_block() → populate submodules CellVector
      │     └── parse_submodule()  → NedSubmodule
      └── parse_connections_block() → populate connections CellVector
            ├── parse_connection()       → NedConnection
            └── parse_connection_group() → NedConnectionGroup
                  ├── parse_loop()       → NedLoop
                  └── parse_condition()  → NedCondition
```

#### File location

Created as `program/src/parser/NedParser.jl` — a standalone `NedParserModule`
alongside `IniParser.jl`, importing `NedModule` types.

#### Test data

Parse files from `omnetpp/samples/` — good coverage set:

- `aloha/Aloha.ned` — compound module (`network`) with params, submodules
- `aloha/Host.ned` — simple module with `@signal`, `@statistic`, `volatile`,
  `default()`, `@display`
- `aloha/package.ned` — file-level `@namespace`, `@license` (no module body)
- `routing/networks/Net5.ned` — `package`, `import`, inner `types:` channel,
  `<-->` connections with channel type
- `cqn/ClosedQueueingNetA.ned` — `for` loops in connections, submodule vector
  sizes with expressions, gate vector sizes with expressions
- `neddemo/RandomGraph.ned` — `extends`, `inout g[]`, `<-->` with `if`
- `petrinets/Arc.ned` — `channel extends ned.IdealChannel`

### Step 4 — `_apply_string_replace!` methods ⏳

Implement string-replace operations for the editable string fields: module
names, parameter names/values, gate names, import specs, package names, etc.
Follow `Xml.jl`'s pattern of one method per concrete type dispatching on
`field_name`.

### Step 5 — Tests ⏳

- Unit tests: construct each type, verify field access, push/delete children.
- Parser tests: parse each file from the test data set, verify structure.
- Round-trip: build a NedFile, snapshot via the I-struct, hydrate back,
  and compare.

### Step 6 (future) — `NedToSyntax` projection

A printer/reader pair that renders NED documents as syntax-highlighted text.
This is a separate plan; the document types must exist first.

### Step 7 — NED document example ⏳

Create `example/src/document/Ned.jl` with a `make_ned_document_example()`
function that builds a representative `NedFile` by hand (or via `nedparse`).
Follow the `Xml.jl` example pattern — the document should showcase the main
NED features: a compound module with parameters, gates, submodules, and
connections.

A good candidate is a simplified version of the Aloha network:

```julia
function make_ned_document_example()
    nedparse("""
        package aloha;

        simple Host {
            parameters:
                double txRate @unit(bps);
                volatile double iaTime @unit(s);
                @display("i=device/pc_s");
            gates:
                input in;
                output out;
        }

        simple Server {
            parameters:
                @display("i=device/antennatower");
            gates:
                input in;
        }

        network Aloha {
            parameters:
                int numHosts;
            submodules:
                server: Server;
                host[numHosts]: Host;
            connections:
                for i=0..numHosts-1 {
                    host[i].out --> server.in;
                }
        }
    """; filename="aloha.ned")
end
```

### Step 8 — NED projection example ⏳

Create `example/src/projection/Ned.jl` with a
`make_ned_projection_example(; measure=sdl_measure_text)` function that wires
the standard projection pipeline. Once `NedToSyntax` exists this will be:

```julia
function make_ned_projection_example(; measure=sdl_measure_text)
    SequentialProjection(
        RecursiveProjection(NedToSyntax()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end
```

Until then, a placeholder that projects through `XmlToSyntax` or a simple
`show`-based text projection can be used.

Register the example in `example/src/Examples.jl`:

```julia
const ned_example = Example("ned", make_ned_document_example, make_ned_projection_example)
```

And add it to the `examples` vector.

## Resolved questions

1. **Expression parsing**: NED expressions in `value`, `vector-size`,
   `condition` etc. are opaque strings. This is fine for now.
2. **Comment nodes**: deferred — add `NedComment` if/when syntax-level fidelity
   is required.
3. **The `unknown` element**: deferred — add `NedUnknown` only if needed for
   real-world `.ned` files.
