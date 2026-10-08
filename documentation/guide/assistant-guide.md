# The assistant

> **Kind:** procedure · **Status:** current · **Stands on:** [concepts.md](../design/concepts.md)

How to run the AI assistant inside ProjecturEd: a local model through Ollama, or Claude through the Anthropic API. It says what the assistant can do, what it costs to set up, and where it stops.

## Open the assistant

The application opens it beside your files:

```sh
bin/projectured notes.md            # the assistant is the right pane
bin/projectured --assistant=none    # without it
```

Type in the field at the bottom of the pane and press Enter. The conversation above it is a document like any other: you can select a part of it, copy it, and save it.

## A local model through Ollama

Ollama is the default. ProjecturEd sends the turn to `http://localhost:11434`, so the Ollama server must run on your machine, and the model must be on the server.

1. Install Ollama from [ollama.com](https://ollama.com) and start it.
2. Pull the default model of ProjecturEd:

   ```sh
   ollama pull qwen3.8:27b
   ```

3. Pull the model of the search by description, which is a second, small model:

   ```sh
   ollama pull nomic-embed-text
   ```

4. Start the application. `--model=NAME` selects another model:

   ```sh
   bin/projectured --model=llama3.1:70b notes.md
   ```

A model of this size needs several gigabytes of memory. If the server does not answer, or the model is not on it, the assistant says so in the conversation and names what is missing.

## Claude through the Anthropic API

Set the key in your environment, and name the backend:

```sh
export ANTHROPIC_API_KEY=sk-ant-…
bin/projectured --assistant=anthropic notes.md
```

`--model=NAME` names a model; without it the backend uses its default. A turn goes to the Anthropic API and is paid for by your key.

## An agent that runs its own loop (ACP)

An agent of the Agent Client Protocol runs its own loop, its own model and its own tools, in a process of its own. The assistant sends it what you write and draws what it reports: its text, a summary of its reasoning, each tool call, and its plan. The agent reaches the open documents through the tools of this editor, so its edits are operations of the editor.

The built-in agent is Claude Code. It runs in the process of the editor and starts the `claude` program that you installed, so it needs no Node.js and no other program. Install Claude Code and sign in once, and then start:

```sh
claude auth login
bin/projectured --assistant=acp notes.md
```

When Claude Code is not signed in, the conversation says how to sign in. The built-in agent is the package [ClaudeCodeACP.jl](https://github.com/projectured/ClaudeCodeACP.jl), which another editor can start as the program `claude-code-acp`.

`--agent-command=COMMAND` names another agent of the Agent Client Protocol, as one argument, which then runs in a process of its own and signs in with its own sign-in. For example, the adapter `claude-agent-acp`, which needs Node.js 22 or newer:

```sh
npm install -g @agentclientprotocol/claude-agent-acp
bin/projectured --assistant=acp --agent-command=claude-agent-acp
```

The settings tab keeps the command for the next start. A session in Julia loads the client by name: `using ProjecturedACP`.

When the agent asks to run a tool, the conversation shows a card with its answers, and the agent waits for your click. Escape stops the turn of the agent. ProjecturEd reads no key and no token of the agent: the agent signs in with its own sign-in, and its use counts as its provider decides.

## What the assistant can do

The assistant has a set of tools, and the same set is what an external client gets through MCP ([mcp-guide.md](mcp-guide.md)).

| Tool | What it does |
| --- | --- |
| `search_api` | finds a module, a type or a function of the loaded packages, by name, by pattern or by description |
| `search_guides`, `read_resource` | reads the guides of this repository |
| `execute_julia_code` | runs Julia in the running program, with `editor` bound to the editor; a verb acts on that editor, so the code does not pass it |
| the operations | changes the data with the same edits as your key presses |

So a question can be about the data in front of you, about the API, or about a change to make. Examples:

- "What is in the second entry of this object?"
- "Sort the entries by key and show the result in a new tab."
- "Which function opens a window on a value?"
- "Add a state called `waiting` to this state machine, with a transition from `idle`."

The assistant answers with text, and it changes the data with an operation. A change by the assistant and a change by your keys are the same kind of thing, so the same tests cover both.

## The search by description

`search_api` ranks by name and by the words of a docstring. It can also rank by meaning: the description you give is turned into a vector, and so is every candidate. That needs the meaning model on the Ollama server (`nomic-embed-text` by default). The vectors are computed once and kept in a file, under `~/.cache/projectured/meaning` for a built binary and under `build/meaning/` in a checkout.

## The limits

- The assistant needs a running Ollama server with a pulled model, or an Anthropic API key. There is no model inside ProjecturEd.
- A local model of a few billion parameters makes more mistakes than Claude. Ask it for one change at a time.
- The assistant changes the data of the editor it runs in. It does not change files on disk, except through a save that you ask for.
- A change by the assistant goes into the history like a change of yours, so `Ctrl+Z` takes it back, and the assistant can take its own change back too. That holds in the application, which keeps a history; a window of your own keeps none until you put one there.
