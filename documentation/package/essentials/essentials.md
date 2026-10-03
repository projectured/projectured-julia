# ProjecturedEssentials

> **Kind:** design · **Status:** current · **Stands on:** [package-rules.md](../../rule/package-rules.md), [autointegrations.md](../autointegrations/autointegrations.md)

`ProjecturedEssentials` holds the few names of the kernel and the platform that most users call. It has no code of its own. The umbrella, each integration and each backend re-export its names, so the package that a user names gives them.

## Why it is so

The kernel exports about 580 names, and the platform about 3000. Most users call a handful of them: they show a value in a window, or open an editor on a document. A user who names `ProjecturedSDL` and `ProjecturedDataFrames` must be able to call `display_in_editor`, and must not get thousands of names in `Main` for it. So one small package holds the names that most users call, and the packages that a user names re-export it.

## The names

| Names | Slice | What they do |
| --- | --- | --- |
| `display_in_editor`, `close_display_editor!`, `refresh_display_editor!`, `EditorDisplay` | platform, display | show a value in a window beside the REPL |
| `run_editor!`, `build_editor`, `Editor` | kernel, editor | open an editor on a document |
| `parse_natural_text`, `NaturalToGraphics`, `FontFileMeasure` | platform, natural and style | make a document from text, and draw it |
| `print_document`, `write_image` | kernel, projection and backend | make a view with no window, and write it as an image |

A program that needs another name loads `ProjecturedPlatform`, which binds every slice: `ProjecturedPlatform.EditorModule` works.

## How it fits

The source is `source/essentials/ProjecturedEssentials.jl`: one `using` line for each group of names and one `export`. It depends on `ProjecturedKernel` and `ProjecturedPlatform`.

These packages depend on it and re-export its names:

- `Projectured`, which re-exports no other name of the kernel or the platform;
- the integrations `ProjecturedSDL`, `ProjecturedDataFrames`, `ProjecturedVideo`, `ProjecturedODBC`, `ProjecturedTulip` and `ProjecturedMCP`;
- the backends `ProjecturedConsole`, `ProjecturedPDF` and `ProjecturedWeb`;
- `ProjecturedIntegrations`, through `Projectured`.

Each one re-exports with one line that reads `names(ProjecturedEssentials)`, so the list has one place. Two packages that re-export the same binding do not conflict in `Main`. A domain does not re-export the names: a user names a backend to see a view, and the names come with it.

`ProjecturedMCP` depended on the kernel alone. Through this package it loads the platform too. An MCP server drives an editor, which needs the platform in each real use.

## Tests

`test_essential_names()` of `ProjecturedTest` checks that each package of the list above depends on `ProjecturedEssentials`, and that it exports the 12 names with the same bindings. The manual case of `test_umbrella_loads_integrations()` checks that `using DataFrames, ProjecturedSDL, ProjecturedDataFrames` makes `display_in_editor` visible.
