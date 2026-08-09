# Fragment of `DocumentModule` — the value a `selection` cell holds.
#
# A selection used to be a bare reference, so the injected field was
# `Union{Nothing, Reference}` and a node either had a selection or did not. That
# leaves nowhere to say *which* selection is the one the editor acts on. A
# document that keeps the selection it loses — a tab group, so that it still shows
# the tab it showed — needs to keep the path **and** record that it is no longer
# the live one.
#
# So the cell holds a document of its own. `primary` is the reference, `live` says
# whether it is the selection the editor acts on. Everything that asks a node
# "which selection is this" then reads that node alone: no walk from the root, no
# answer threaded down the printer context.
#
# **Why it lives here, next to the macro.** `@document` emits the injected field's
# type as an *expression*, resolved in the caller's module, and 64 modules import
# the reference layer by name (`import ..ReferenceModule: Reference`) rather than
# wholesale. A type declared above this layer would therefore not be in scope where
# the expansion lands. Declared here, in the macro's own module, it is spliced as a
# type **object** and needs no import anywhere.
#
# `primary` is `Any` for the same layering reason in the other direction: this
# layer sits below the reference layer and cannot name `Reference`.

"""
    unwrap_selection(value)

What a `selection` **property** read answers, given what the cell holds.

A [`SelectionDocument`](@ref) answers its `primary` while it is live, and
`nothing` once it is dormant. Every other value — `nothing`, or a bare
`Reference` — answers itself.

Dispatch on the stored value, not on the field name, so a read of any other field
of any other document pays nothing for this.

Answering `nothing` for a dormant selection is deliberate. It makes every reader
that was written against a bare reference correct by default: a printer draws no
caret for a selection that is not the live one, and only a printer that asks for
the document itself — through `getfield` — can draw it pale.

Declared before the struct below, because `@document` splices this function into
the accessors it emits, including the ones it emits for `SelectionDocument`.
"""
unwrap_selection(value) = value

"""
    SelectionDocument(primary; live = true)

The value a document's `selection` cell holds: a reference in `primary`, and
`live` saying whether it is the one selection the editor acts on.

A `false` in `live` makes it **dormant** — still stored, still drawable, but not
acted on. A dormant selection is what a document keeps when the live selection
moves elsewhere, so that it can be made live again when the focus returns.

The field is declared explicitly as `ImmutableCell{Nothing}`, the value-document
pivot: a selection is not itself selectable, and the explicit field also stops the
macro from injecting a field whose type names this very type.
"""
@document struct SelectionDocument
    primary::Any = nothing
    live::Bool = true
    selection::ImmutableCell{Nothing} = nothing
end

unwrap_selection(value::SelectionDocument) = value.live ? value.primary : nothing
