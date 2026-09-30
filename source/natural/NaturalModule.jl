"""
    NaturalModule

What a document's **natural notation** is, and how two notations combine.

A notation is a rung on one ladder:

    domain ──▶ syntax ──▶ text ──▶ graphics
                              └──▶ string

A domain declares the one rung it can reach on its own, and everything above it
is composition. The composition is a `ChainingProjection`, which is what every
caller that wants a document as text would otherwise build by hand.

# The three starting rungs

- `:syntax` — the domain has a `*ToSyntax`, and reaches text and graphics through
  the shared tail. Most domains.
- `:graphics` — the domain draws itself, because a page of blocks or a diagram is
  not a syntax tree.
- `:text` — the domain is prose. It reaches graphics through the text renderer
  and **needs no syntax package at all**.

A domain may declare more than one rung; a caller asking for graphics takes the
highest one the document offers.

# Which rungs live where

This module owns `text → graphics` and `text → string`, because this package
already names the text package. It must not name `ProjecturedSyntax` — that
package names this one, and the arrow cannot turn — so `syntax → text` is
registered from outside, by whoever can supply it. A session that never loads a
syntax package has no `syntax → text` rung, and a document that only speaks
syntax then has no text and no graphics form. That is the rule this repository
works by: what is not loaded is not supported.

# What a domain writes

    register_natural_domain!(JsonDocument;
                             rung      = :syntax,
                             make      = () -> JsonToSyntax(),
                             format    = :json,
                             extension = ".json",
                             parse     = parse_json)

The four separate registrations below are what that calls, and a domain uses them
directly for the cases the one call cannot cover: a second rung, a parser owned
by a package that does not own the printer, or a rung that belongs to no domain.
"""
module NaturalModule

using ..CollectionModule
using ..DocumentModule
using ..DomainModule
using ..GraphicsModule
using ..IoMapModule
using ..LayoutModule
using ..ProjectionAlgebraModule
using ..ProjectionModule
using ..StyleModule
using ..TextModule
using ..WidgetModule
using ..ReferenceModule

# Imported to extend: this module adds a method to each of these.
import ..ProjectionModule: print_document
import ..EditorModule: make_document_projection

export register_natural_domain!, register_natural_notation!, register_natural_format!,
       register_natural_parser!, register_natural_expression!, register_natural_rung!,
       make_natural_projection, get_natural_extension, get_natural_format,
       get_natural_entries, parse_natural_text, has_natural_parser, find_natural_parser,
       make_natural_expression, has_natural_expression,
       print_natural_text
export register_natural_syntax!, register_natural_graphics!, register_natural_fallback!,
       get_natural_syntax_entries, get_natural_graphics_entries, get_natural_fallback_entries
export NaturalToGraphics,
       register_natural_syntax!, register_natural_graphics!, register_natural_fallback!


include("NaturalNotation.jl")
include("NaturalRegistry.jl")
include("NaturalProjection.jl")

end # module
