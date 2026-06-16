"""
    EvaluatorModule

The evaluator document domain — a code form paired with the result of
evaluating it. Modeled on the Common Lisp ProjecturEd `evaluator.lisp`:

- `EvaluatorForm`     — one `form` (the code, e.g. a `JuliaDocument`) and its
                        `result` (a result document; `TextText` of the output
                        for now — richer result documents are future work).
- `EvaluatorToplevel` — a sequence of `EvaluatorForm`s (a notebook / REPL
                        toplevel).

`is_error` and `tool_use_id` are protocol metadata for the Anthropic tool
round-trip (an assistant `tool_use` paired with a `tool_result`); the
conceptual core is the two fields `form` + `result`.
"""
module EvaluatorModule

import ..ReactiveModule: Cell, setfn!, setval!
import ..DocumentModule: Document, @document
import ..CollectionModule: CellVector
import ..ReferenceModule: Reference
import ..TextModule: TextText, TextString

export EvaluatorDocument, EvaluatorForm, EvaluatorToplevel,
       IEvaluatorForm, IEvaluatorToplevel

# ── Abstract base ────────────────────────────────────────────────────────────

abstract type EvaluatorDocument <: Document end

# ── EvaluatorForm ────────────────────────────────────────────────────────────

"""
    EvaluatorForm(form; result, is_error, tool_use_id)

A code form paired with its evaluation result. `form` is the code document
(a `JuliaDocument`); `result` is the result document (`TextText` for now).
"""
@document struct EvaluatorForm <: EvaluatorDocument
    form::Document
    result::Document
    is_error::Bool
    tool_use_id::String
    selection::Reference
end

EvaluatorForm(form::Document;
              result::Document = TextText(),
              is_error::Bool = false,
              tool_use_id::AbstractString = "") =
    EvaluatorForm(Cell(form), Cell(result), Cell(is_error),
                  Cell(String(tool_use_id)), Cell(nothing))

# Convenience: build a result document from a plain output string.
result_text(s::AbstractString) = TextText(TextString(String(s)))

# ── EvaluatorToplevel ────────────────────────────────────────────────────────

"""
    EvaluatorToplevel(elements = [])

An ordered sequence of `EvaluatorForm`s.
"""
@document struct EvaluatorToplevel <: EvaluatorDocument
    elements::CellVector
    selection::Reference
end

EvaluatorToplevel() = EvaluatorToplevel(CellVector(), Cell(nothing))
EvaluatorToplevel(elements::Vector) =
    EvaluatorToplevel(CellVector(Cell[Cell(e) for e in elements]), Cell(nothing))

# ── Element access on the toplevel ───────────────────────────────────────────

Base.length(t::EvaluatorToplevel)  = length(t.elements)
Base.isempty(t::EvaluatorToplevel) = isempty(t.elements)
Base.getindex(t::EvaluatorToplevel, i::Integer) = t.elements[i]
Base.firstindex(::EvaluatorToplevel) = 1
Base.lastindex(t::EvaluatorToplevel) = length(t)
Base.iterate(t::EvaluatorToplevel, s...) = iterate(t.elements, s...)
Base.eachindex(t::EvaluatorToplevel) = eachindex(t.elements)

Base.push!(t::EvaluatorToplevel, fs::EvaluatorForm...) =
    (for f in fs; push!(t.elements, Cell(f)); end; t)

setfn!(t::EvaluatorToplevel, f::Function) =
    (setfn!(getfield(t.elements, :elements), () -> Cell[Cell(x) for x in f()]); t)

# ── Display ──────────────────────────────────────────────────────────────────

Base.show(io::IO, f::EvaluatorForm) =
    print(io, "EvaluatorForm(", f.form, ", is_error=", f.is_error, ")")

Base.show(io::IO, t::EvaluatorToplevel) =
    print(io, "EvaluatorToplevel(forms=", length(t), ")")

end # module
