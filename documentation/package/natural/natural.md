# The natural notation

> **Kind:** reference · **Status:** current · **Stands on:** [concepts.md](../../design/concepts.md)

How a domain says what its text looks like, which file extension it owns, and how a document of any domain reaches the screen with no projection written for the caller. This slice is the registry that makes `parse_natural_text`, `print_natural_text` and `NaturalToGraphics` work for every domain at once.

## What a domain registers

A domain registers itself when its package loads. The JSON domain, in `source/json/JsonModule.jl`:

```julia
function __init__()
    register_natural_domain!(JsonDocument;
                             rung      = :syntax,
                             make      = () -> JsonToSyntax(),
                             format    = :json,
                             extension = ".json",
                             parse     = parse_json)

    register_file_document_type!(".json", JsonFile)
end
```

That one call says four things:

- **the rung**: which step of the ladder the domain enters, and the projection that takes it there. `:syntax` means the domain becomes a syntax tree, which the text and graphics steps already know how to draw.
- **the format**: the name of the notation, `:json`.
- **the extension**: the file name that belongs to the format.
- **the parser**: the function that reads a text of the format back into a document.

`register_natural_notation!`, `register_natural_format!` and `register_natural_parser!` are the three parts on their own, for a domain that has only some of them.

## What a caller gets

```julia
document = parse_natural_text(:json, "{\"name\": \"Alice\"}")
text     = print_natural_text(document)
```

`has_natural_parser(:json)` answers whether a format can be read, for a caller where "no parser" is a normal answer rather than a fault.

`get_natural_extension` and `get_natural_format` map between the two, which is how the format of a file follows from its name.

## The ladder, and the general renderer

The rung of a domain places it on a ladder: a domain becomes a syntax tree, a syntax tree becomes text, and text becomes graphics. `NaturalToGraphics` is the projection that walks the whole ladder for any document:

```julia
projection = NaturalToGraphics(measure = measure_truetype_text)
```

It draws a document of any registered domain, and a plain Julia value through reflection, which is what makes a window on any value possible ([reflection.md](../reflection/reflection.md)).

`extra` adds a pair for a type that needs another view in that window, so an application mixes a designed view and the general one in one tree. `example/projectured/Application.jl` does exactly that.

## Adding a rung or another target

`register_natural_syntax!`, `register_natural_graphics!` and `register_natural_fallback!` add a type to the table of one step: the syntax step, the graphics step, or the fallback that draws whatever nothing else claimed. A domain that draws itself, for example a chart, registers a graphics entry and skips the text steps.

`make_natural_projection(document, target)` answers the projection from that document to a target — `:string` is the one a tool uses to get text out of a document.

## Where it is used

- The file reader and writer: the format follows from the extension, and the parser follows from the format ([fileformat](../../guide/build-guide.md) carries the same table into a binary).
- The application: every tab draws through `NaturalToGraphics` unless its content has a view of its own.
- The assistant: `make_natural_projection(document, :string)` is how a tool turns a document into text for the model.
