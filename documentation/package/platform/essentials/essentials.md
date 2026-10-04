# Essentials

> **Kind:** design · **Status:** current · **Stands on:** [display.md](../display/display.md), [natural.md](../natural/natural.md), [autointegration.md](../../autointegration/autointegration.md)

`EssentialsModule` is the slice of the platform that holds the few names of the kernel and the platform that most users call. It has no code of its own. The umbrella, each integration and each backend re-export its names, so the package that a user names gives them.

## Why it is so

The kernel exports about 580 names, and the platform about 3000. Most users call a handful of them: they show a value in a window, or open an editor on a document. A user who names `ProjecturedSDL` and `ProjecturedDataFrames` must be able to call `display_in_editor`, and must not get thousands of names in `Main` for it. So one short list holds the names that most users call, and the packages that a user names re-export it.

The list is a module of the platform and not a package of its own. Each package that re-exports it depends on the platform, and no user installs the list or names it in a `using` line. A package of its own would cost a registry entry, a README, a version and a test job, and give the user nothing.

## The names

| Names | Slice | What they do |
| --- | --- | --- |
| `display_in_editor`, `close_display_editor!`, `refresh_display_editor!`, `EditorDisplay` | platform, display | show a value in a window beside the REPL |
| `run_editor!`, `build_editor`, `Editor` | kernel, editor | open an editor on a document |
| `parse_natural_text`, `NaturalToGraphics`, `FontFileMeasure` | platform, natural and style | make a document from text, and draw it |
| `print_document`, `write_image` | kernel, projection and backend | make a view with no window, and write it as an image |

A program that needs another name loads `ProjecturedPlatform`, which binds every slice and exports every name of the platform: `ProjecturedPlatform.EditorModule` works.

## How it fits

The source is `source/platform/essentials/EssentialsModule.jl`: one `using` line for each slice that owns a name, and one `export`. The slice uses the display, natural and style slices of the platform, and the kernel (`PLATFORM_SLICE_EDGES`).

These packages re-export its names:

- `Projectured`, which re-exports no other name of the kernel or the platform;
- the integrations `ProjecturedSDL`, `ProjecturedDataFrames`, `ProjecturedVideo`, `ProjecturedODBC`, `ProjecturedTulip` and `ProjecturedMCP`;
- the backends `ProjecturedConsole`, `ProjecturedPDF` and `ProjecturedWeb`;
- `ProjecturedIntegrations`, through `Projectured`.

Each one writes `using ProjecturedPlatform.EssentialsModule` and one `export` that reads `names(EssentialsModule)`, so the list has one place. Two packages that re-export the same binding do not conflict in `Main`. A domain does not re-export the names: a user names a backend to see a view, and the names come with it.

`ProjecturedMCP` depends on the platform for this list. An MCP server drives an editor, which needs the platform in each real use.

## Tests

`test_essential_names()` of `ProjecturedTest` checks that each package of the list above depends on `ProjecturedPlatform`, and that it exports the 12 names with the same bindings as `EssentialsModule`. The manual case of `test_umbrella_loads_integrations()` checks that `using DataFrames, ProjecturedSDL, ProjecturedDataFrames` makes `display_in_editor` visible.
