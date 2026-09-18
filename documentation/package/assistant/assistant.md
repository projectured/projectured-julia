# The assistant

> **Kind:** reference · **Status:** current · **Stands on:** [concepts.md](../../design/concepts.md)

The assistant slice: the conversation as a document, the turn that talks to a model, and the view that a window puts beside its panes. It is the code behind [assistant-guide.md](../../guide/assistant-guide.md), which says how to run it.

## What is in the slice

| File | What it holds |
| --- | --- |
| `source/assistant/AssistantDocument.jl` | the `Assistant` document, its fields and its default system prompt |
| `source/assistant/AssistantTurn.jl` | one turn: the request, the tool calls, the reply, and the status while it runs |
| `source/assistant/AssistantToWidget.jl` | the view: the transcript, the input field and the state of a running turn |
| `source/assistant/AssistantModule.jl` | the module, and what it exports |

The model itself is not here. `ProjecturedOllama` and `ProjecturedAnthropic` each give an `Llm`, and the assistant holds one. [llm.md](../llm/llm.md) says what each backend needs to run.

## The document

```julia
@document struct Assistant <: Document
    conversation::ConversationConversation
    input::PrimitiveString
    draft::ConversationDraft
    backend::Symbol
    model::String
    system::String
    api_key::String
    context::Int
    status::Symbol
    collapse_thinking::Bool
    llm::Union{Nothing,Llm}
end
```

The conversation is a document of the conversation domain, so the transcript is data: it is selected, copied, saved and projected like any other document. `input` is what a person types, and `draft` is the part the composer is editing.

`backend` is `:ollama`, `:anthropic` or `:none`, and `model` is empty for the default model of that backend. `status` says what a turn is doing, which is what the view shows while a reply is on its way.

## A turn

A turn takes what the person typed, the transcript so far, and the tool set of the editor, and it asks the model. When the model calls a tool, the turn runs it and asks again, until the model answers with text or the round limit is reached. Each round appends to the conversation, so the transcript is the record of the turn and not a copy of it.

The tools come from the kernel: `register_default_tools!` puts them in the `ToolSet` of the editor, and the same set answers an external client over MCP. [mcp.md](../mcp/mcp.md) says how that client reaches it.

## The view

`AssistantToWidget` makes the pane: the transcript above, the input field below, and a line that says what a running turn is doing. The pane is a widget tree like any other, so it goes in a tab, in a split pane, or in a window of its own.

An application puts one beside its panes:

```julia
assistant = Assistant(; backend = :ollama)
```

`example/projectured/Application.jl` shows the whole arrangement: the navigator, the files and the assistant in one pane tree.

## What to check when a turn fails

- **No model.** With `backend = :none` the pane opens and answers nothing. That is what a test uses.
- **No server, or no model on the server.** The turn writes what is missing into the transcript, including the address it asked.
- **A tool raised.** The tool result carries the error text, and the model gets it, so a miss is visible in the transcript.

`test/workbench/editor/AssistantMvpTest.jl` drives a whole turn with a scripted model, and `assistant_example` runs from a canned transcript, so a test needs no model.
