# Help

> **Kind:** design · **Status:** current · **Stands on:** [domain.md](../domain/domain.md), [syntax.md](../syntax/syntax.md)

The help slice of `ProjecturedPlatform` holds what the Help menu of a window opens: the list of every document type, the list of every projection, and the page that says what the program is. This document says why the two lists hold no field, where the description of a type comes from, and what the page about the program shows.

## How it works

Three documents live in the help slice:

- **`DocumentTypeList`** holds no field. It stands for every document type that an empty tab can make.
- **`ProjectionList`** holds no field. It stands for every concrete projection: the views a window draws a document with, and the projections that combine other projections.
- **`AboutPage`** holds `name`, `summary`, `version` and `homepage`. It says what a program is.

**A list holds no field, and the projection computes its lines when it prints.** Three reasons hold together:

1. The list follows the program that is loaded. A type that a session defines after the window opens still shows up the next time the tab prints, because the printer reads the loaded modules again at that moment.
2. A saved window has nothing of the list to save. `pred_arguments` answers an empty argument list for both, so a `.pred` file that holds one of them writes only its type name, and a load makes the same empty document, whose print computes the list again.
3. `insertable(T)` calls `T()` while it walks the candidates that [`get_insertion_candidates`](../domain/domain.md#completion-by-reflection) enumerates. `DocumentTypeList` is itself a document type, so the walk constructs one to test it. A constructor that filled the list at construction time would call the enumeration that already calls it.

`compute_help_entries(list)` computes the entries: `get_insertion_candidates(Document)` for `DocumentTypeList`, and [`compute_concrete_subtypes(Projection)`](../domain/domain.md#completion-by-reflection) for `ProjectionList`. Each entry is `(name, package, typed, summary)`, sorted by name with no regard to case. `name` is the bare name of the type, and `package` the package that defines it. `typed` holds the names a person types into an empty tab to make the type, taken from `get_insertion_names` with the type's own name removed; it is empty for a projection, because a projection is drawn and not typed. `summary` is `compute_docstring_summary(T)`, or `""` when `T` has no docstring.

`compute_docstring_summary(T)`, of the tool layer of the kernel, reads the first paragraph of the docstring of `T`, on one line, or `""` when `T` has none. A fenced or an indented block is code, and a line that starts with `#` is a heading; both are skipped, so the description is prose. The function reads the docstring of the type before the docstrings of its constructors, and answers the first paragraph it finds: a constructor's docstring speaks for a type that has none of its own.

`HelpListToSyntax` prints one heading line that names the count, then two lines for each entry: the name and the package, with the typed names for a document type, then the description, or "no description" in a muted color when there is none. The start of the list of document types:

```
170 document types. Type one of the names in an empty tab to make a document of that type.
...
CellVector   ProjecturedPlatform   type: cell vector
    A sequence of values, each in a cell of its own.
```

`AboutPageToSyntax` prints the name of the page, its summary when it is not empty, a blank line, "Version " and the version when it is not empty, "Julia " and the Julia version that runs, and the home page when it is not empty. The Julia version comes from `VERSION` and not from a field, so it shows even when every field of the page is empty. A field the page leaves empty prints no line, and the blank line prints regardless.

With the packages of the application loaded, the Documents list holds 170 types and the Projections list holds about 445. The first `get_insertion_candidates(Document)` of a session walks every loaded module and takes 3 to 5 seconds; an empty tab pays the same cost once. After that walk, the first list that `compute_help_entries` builds takes about 0.2 seconds, and the next takes about 0.01 seconds.

### The theme

`HelpTheme` holds the text of a heading, a name, a detail, a description and a muted note of the lists of help, and the title of the about page. Each value has the default that the slice draws with no
appearance. `HelpListToSyntax` and `AboutPageToSyntax` hold their styles and no theme. `make_help_list_projection(; theme)`
and `make_about_page_projection(; theme)` fill them with `get_help_style`, from a `HelpTheme` scaled or not, or the
default values for `nothing`. The registration of help gives the scaled theme of the `Appearance`.

## How it fits

The help slice depends on the domain slice for `get_insertion_candidates`, `compute_concrete_subtypes` and `get_insertion_names`; on the syntax and text slices for the `SyntaxNode`, `SyntaxLeaf` and `TextString` that the two printers build; on the style slice for the styles of a list and of the page; on the natural slice for `register_natural_syntax!`; and on the serialization slice for `pred_arguments`, besides the kernel.

Its `__init__` registers the three document types with `register_natural_syntax!(:help, …)`: `HelpListToSyntax` for the two lists, `AboutPageToSyntax` for the page. A `.pred` file builds all three by their names, so a saved window can hold a tab of each.

The shell slice depends on it. `make_window_help_menu` opens each of the three documents through `_reach_tool!`, and its `about` keyword makes the page of the host's own program. [shell.md](../shell/shell.md) describes the menu.

## Design decisions

- **The lists compute their lines when they print, and hold no field.** [How it works](#how-it-works) gives the three reasons: the list follows the loaded program, a saved window has nothing to save, and a constructor that filled the list in would call the enumeration that constructs it.
- **The description is the raw text of the docstring, read through `Base.Docs.meta`.** It keeps the inline Markdown marks as they are written, and needs no dependency on the `Markdown` standard library.
- **`_get_typed_names` takes its type behind `@nospecialize`, so Julia compiles one method for it and not one for each type in the list.** A closure that holds the type compiles once for each of the 170 document types, and that costs about 10 seconds on the first list. With one method, the first list takes about 0.2 seconds, and the next about 0.01 seconds.
- **`AboutPage` is a document of the host program, and `about` is a function of the editor.** The default page names ProjecturEd. A host that runs its own program gives its own name, summary and home page.

## Usage

```julia
make_window_help_menu(; about = editor -> AboutPage(name = "My editor",
                                                     summary = "What it does.",
                                                     homepage = "https://example.org"))
```

- Tests: `test_help()`, in `package/ProjecturedHelpTest`, runs the layering guard, `test_docstring_summary()`, `test_help_list_to_syntax()` and `test_about_page_to_syntax()`.

## Limits

- The two lists show no group, no filter and no search: every type is one entry in one alphabetical list.
- Many projections have no docstring, so many of their entries show "no description".
- `HelpListToSyntax` has no reader. A press on an entry does not open a tab with that type; only the three items of the Help menu open a tab.
