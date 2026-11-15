# Architecture review: extension points, registries, factory seams, and the shape of the public API

Commit 3a9b4fae4. Reviewer area key: extension-seams-api.

## Scope

Paths: all of `source/`, by search for `register_`, module-level `const` of a `Dict`, `IdDict`, `Vector`, `Ref` or `Set`, `__init__`, the factory seams (`make_llm`, `make_agent_server`, `make_agent_connection`, `make_database_adapter`, `wrap_editor!`), dispatch on `Val{...}`, `hasmethod`, `applicable` and `methods(`. The export lists of `source/kernel`, `source/platform`, `source/platform/essentials` and `source/all`. The scripts `tool/survey-interface.jl` and `tool/survey-arguments.jl`.

Read in full (about 3 300 lines):

- Documents: `documentation/design/concepts.md`, `documentation/design/architecture-decisions.md`, `documentation/rule/package-rules.md`, `documentation/package/platform/essentials/essentials.md`, `documentation/design/domain-anatomy.md`, and `documentation/package/platform/natural/natural.md` from its tables on.
- Natural slice: `NaturalNotation.jl`, `NaturalRegistry.jl`, `NaturalModule.jl`, `NaturalProjection.jl`.
- Kernel: `editor/EditorBuild.jl`, `editor/BackendChoice.jl`, `tool/ToolSet.jl`, `tool/ToolModule.jl`, `llm/LlmDefaults.jl`, `agent/AgentDefaults.jl`, `agent/AgentConnectionDefaults.jl`, `KernelModule.jl`.
- Platform: `assistant/AssistantApi.jl`, `application/DefaultBackend.jl`, `application/StartSettings.jl`, `screen/DocumentShow.jl`, `essentials/EssentialsModule.jl`; `source/all/ProjecturedAll.jl`; `source/domain/json/JsonFile.jl`.
- The two survey scripts.

Sampled (about 4 500 lines, by range): the 41 `__init__` functions (each body), `serialization/FileProject.jl`, `fileformat/DocumentFile.jl`, `fileformat/NaturalFormat.jl`, `roster/RosterSource.jl`, `roster/RosterProgram.jl`, `kernel/editor/DocumentEdits.jl`, `kernel/editor/Editor.jl`, `kernel/tool/AssistantMark.jl`, `kernel/tool/Documentation.jl`, `application/Application.jl`, `application/ApplicationExplorer.jl`, `shell/WindowChrome.jl`, `syntax/SyntaxNatural.jl`, `pane/PaneProgram.jl`, `pane/PaneTabsWrapper.jl`, `assistant/AssistantDocument.jl`, `assistant/AssistantTurn.jl`, `widget/DocumentComposition.jl`, `widget/WidgetToGraphics.jl` (the table constructor), `display/DisplayWorkload.jl`, `domain/Domain.jl`, `style/Palette.jl`, `style/Theme.jl`, `graph/GraphLayoutChoice.jl`, and the system anatomy and the invariants PAR-BACKEND-SEAM, PAR-OPT-IN-DEPENDENCY, PAR-PER-EDITOR-STATE, PAR-FRAMEWORKS-SINK, PAR-LOWEST-PACKAGE.

Plans read at the head: `packages-compose-by-seams.md` (to step 15), `assistant-api-consolidation.md`, `a-print-writes-and-a-make-answers.md`, `unify-projection-api-parameter-names.md`, `naming-rule-renames.md`, `narrow-the-composition-point.md`, `sdl-per-editor-state.md`, `views-compose-as-content-composes.md`, and the done plan `the-assistant-finds-its-names-by-reflection.md` for two decisions.

Counts come from `grep` and from two small Python scripts that read the source text. No Julia ran. The count of exported names is a count of `export` statements, so it misses the names that a macro exports.

## State

The newest extension points are sound. A package adds a method of a generic function for its own type or for its own `Val{key}`, and the code that needs the list reads the method table. The wrappers of an editor, the backends, the model adapters, the gesture tables, the themes and the settings groups all work this way, and the owner decided on 2026-09-30 that this is the one rule (decision C1 of `plan/pending/packages-compose-by-seams.md`: "Seams only. No registry table, no `__init__` registration").

The main weakness is that the older mechanism is still the larger one. 41 modules have an `__init__`, and almost all of them only fill tables at module level: 8 tables of the natural slice, the table of the file types, the table of the roster stores, two tables for the assistant, and more. Three of these registries came after the decision: the sentences for the assistant, the palettes and the stores of a roster. So one concept, "a package says something about its type", has two mechanisms, and the row of a type in the renderer can be declared in five forms.

The second weakness is that a file format is two contracts. A domain declares its extension and its parser once for the natural slice and once for the serialization slice, and two functions answer "which extension has this document" from two tables.

The third weakness is repetition around the good mechanism. Ten functions read a method table as a list, each written by hand. Fourteen functions get the session document of an editor, each written by hand. Each verb for the assistant is a group of up to six methods.

The process-global state is small and mostly inside the rule. Most module-level values are constant tables, caches of facts that are the same for each editor, or scoped values of one evaluation. The registries are the exception.

The public API has three sizes with nothing between: 12 names (`EssentialsModule`), about 4 000 exported names, and the 414 names that carry the mark `For the assistant.`. The marked names are the only curated middle size.

## Inventory

### A. The extension points

"Scope" says where the declaration lives: P = the process, by a method table; G = the process, by a mutable table at module level; E = one editor. "Listed" says whether the help or the assistant can list what is declared.

| # | What is extended | Mechanism | Declared at | Scope | Listed |
| --- | --- | --- | --- | --- | --- |
| 1 | an operation | a method of `evaluate_operation` for the type | [OperationInterface.jl:149](../../../source/kernel/operation/OperationInterface.jl#L149) | P | no list |
| 2 | a gesture or a key binding | the macro `@gestures`, which writes a method of `get_document_gesture_bindings_own(::Type{T})` | [GestureBindingInterface.jl:35](../../../source/kernel/binding/GestureBindingInterface.jl#L35) | P | yes: F1 and the command palette read the same table |
| 3 | a step of a reference | methods of `build_reference_step(::Val{name})` and `match_reference_step(::Val{name})` | [ReferenceInterface.jl:123](../../../source/kernel/reference/ReferenceInterface.jl#L123) | P | no list |
| 4 | a wrapper of an editor (tabs, undo, tooltip, ...) | methods of five functions for `Val{keyword}` | [EditorBuild.jl:67](../../../source/kernel/editor/EditorBuild.jl#L67) | P | yes: the error of an unknown keyword lists them ([EditorBuild.jl:230](../../../source/kernel/editor/EditorBuild.jl#L230)) |
| 5 | a backend | methods of `get_backend_name` and `get_backend_output` for the type | [BackendChoice.jl:15](../../../source/kernel/editor/BackendChoice.jl#L15) | P | yes, `collect_backend_types` |
| 6 | a backend, second way | the loaded subtypes of `Backend`, in a fixed order of preference | [DefaultBackend.jl:28](../../../source/platform/application/DefaultBackend.jl#L28) | P | no |
| 7 | a model | a method of `make_llm(::Val{kind})` | [LlmInterface.jl:105](../../../source/kernel/llm/LlmInterface.jl#L105) | P | yes, `get_llm_backend_names` |
| 8 | a model, in the application | the constant `APPLICATION_ASSISTANTS` | [Application.jl:18](../../../source/platform/application/Application.jl#L18) | closed list | - |
| 9 | an agent connection | a method of `make_agent_connection(::Val{kind})` | [AgentConnectionInterface.jl:21](../../../source/kernel/agent/AgentConnectionInterface.jl#L21) | P | yes |
| 10 | an agent server | a method of `make_agent_server(::Val{kind}, editor)` | [AgentInterface.jl:21](../../../source/kernel/agent/AgentInterface.jl#L21) | P | yes |
| 11 | a database adapter | a method of `make_database_adapter(::Val{kind})` | [DatabaseAdapters.jl:16](../../../source/domain/database/DatabaseAdapters.jl#L16) | P | no list |
| 12 | a tool of the assistant | `register_tool!(set, tool)` on the `ToolSet` of an editor | [ToolSet.jl:85](../../../source/kernel/tool/ToolSet.jl#L85) | E | yes, `list_tools` |
| 13 | a name that the assistant may write | the line `For the assistant.` in a docstring, read by `collect_marked_api` | [AssistantMark.jl:48](../../../source/kernel/tool/AssistantMark.jl#L48) | P, by reflection | yes, `search_api` |
| 14 | a sentence about a domain, and the names of a foreign package | `register_assistant_api!` in `__init__` | [AssistantApi.jl:32](../../../source/platform/assistant/AssistantApi.jl#L32) | G | yes, the system text |
| 15 | a root of guides | `register_guide_root!` | [Documentation.jl:32](../../../source/kernel/tool/Documentation.jl#L32) | G | yes |
| 16 | the text form of a domain (rung, format, extension, parser, expression) | `register_natural_domain!` and five more functions, in `__init__` | [NaturalNotation.jl:117](../../../source/platform/natural/NaturalNotation.jl#L117) | G | yes, `describe_natural_formats` |
| 17 | the row of a type in the renderer | `register_natural_graphics!`, `register_natural_syntax!`, `register_natural_fallback!`, in `__init__` | [NaturalRegistry.jl:55](../../../source/platform/natural/NaturalRegistry.jl#L55) | G | no |
| 18 | the row of a type in the renderer, second way | a method of `make_graphics_projection(::Type{T}; measure, appearance)` | [DocumentComposition.jl:27](../../../source/platform/widget/DocumentComposition.jl#L27) | P | no |
| 19 | the printer of a widget or of a layout | a row in the closed table that `WidgetToGraphics(...)` builds | [WidgetToGraphics.jl:15660](../../../source/platform/widget/WidgetToGraphics.jl#L15660) | closed list | no |
| 20 | a file type | `register_file_document_type!(extension, T)` in `__init__`, and five methods for the type | [FileProject.jl:268](../../../source/platform/serialization/FileProject.jl#L268) | G | no |
| 21 | the first document of a new file | a method of `make_document_seed(::Val{extension})` | [DocumentFile.jl:38](../../../source/platform/fileformat/DocumentFile.jl#L38) | P | no |
| 22 | a word of the marker language of a file | `register_marker_function!` in `__init__` | [FileProject.jl:331](../../../source/platform/serialization/FileProject.jl#L331) | G | no |
| 23 | a source of a roster, as a type | a method of `collect_roster_parts(source, link)` | [RosterInterface.jl:22](../../../source/platform/roster/RosterInterface.jl#L22) | P | yes, `describe_roster_sources` |
| 24 | a source of a roster, as a named store | `register_roster_source!` in `__init__` | [RosterSource.jl:167](../../../source/platform/roster/RosterSource.jl#L167) | G | yes, `describe_roster_sources` |
| 25 | a kind of explorer entry | methods of `is_explorer_entry_type` and `is_session_explorer_entry_type` | [TreeInterface.jl:118](../../../source/platform/tree/TreeInterface.jl#L118) | P | yes, the `+` list |
| 26 | the session documents in the first explorer | a list by hand in `make_editor_explorer_content` | [ApplicationExplorer.jl:35](../../../source/platform/application/ApplicationExplorer.jl#L35) | closed list | - |
| 27 | the items of the context menu of a document | a method of `compute_context_menu(document)` | [DocumentCore.jl:168](../../../source/platform/domain/DocumentCore.jl#L168) | P | - |
| 28 | the menus of the window | the keyword `extra` of `make_window_menu_bar` | [WindowChrome.jl:180](../../../source/platform/shell/WindowChrome.jl#L180) | the caller | - |
| 29 | a theme | the macro `@theme`; an `Appearance` makes the theme at the first `get_scaled_theme!` | [Appearance.jl:202](../../../source/platform/style/Appearance.jl#L202) | E | yes, the appearance tab |
| 30 | a page of settings | the macro `@settings`, which writes a method of `get_setting_descriptions` | [SettingsGroup.jl:40](../../../source/platform/settings/SettingsGroup.jl#L40) | P, values in E | yes, the settings tab |
| 31 | a palette, an icon | `register_palette!`, `register_icon!`, called at the top level of a module | [Palette.jl:127](../../../source/platform/style/Palette.jl#L127) | G, data | yes, `get_palette_names` |
| 32 | a layout engine of a graph | `register_layout_engine!`, one `Ref` | [GraphLayoutChoice.jl:28](../../../source/domain/graph/GraphLayoutChoice.jl#L28) | G | no |
| 33 | a scheme of a URL | a method of `find_url_document(::Val{scheme}, url)` | [UrlInterface.jl:234](../../../source/platform/link/UrlInterface.jl#L234) | P | no |
| 34 | a document type that an empty tab can make | reflection over the loaded subtypes of `Document` | [Domain.jl:342](../../../source/platform/domain/Domain.jl#L342) | P, by reflection | yes, Help > Documents |

### B. How many mechanisms

| Mechanism | Rows of table A |
| --- | --- |
| a method for a type, read from the method table | 1, 2, 5, 18, 23, 25, 27, 30 |
| a method for a `Val{key}`, read from the method table | 3, 4, 7, 9, 10, 11, 21, 33 |
| a mutable table at module level, filled in `__init__` or at load | 14, 15, 16, 17, 20, 22, 24, 31, 32 |
| a registry that an editor owns | 12, 29 |
| a mark in a docstring, or reflection over the loaded types | 13, 34, 6 |
| a closed list in the code | 8, 19, 26 |
| a keyword of the caller | 28 (and `extra` of `NaturalToGraphics`) |

Seven mechanisms. The first two are one rule (a method of a seam). Rows 6, 8, 17, 19, 24 and 26 are second ways of rows 5, 7, 18, 18, 23 and 25.

### C. The row of a type in the renderer: five forms

`NaturalToGraphics` is the projection that draws almost any document. It builds one table `type => projection` ([NaturalProjection.jl:165](../../../source/platform/natural/NaturalProjection.jl#L165)).

| Form | Count in `source/` | Key | When it runs | Example |
| --- | --- | --- | --- | --- |
| a method of `make_graphics_projection(::Type{T})` | 33 methods | the type | at each table build | [PivotModule.jl:61](../../../source/domain/pivot/PivotModule.jl#L61) |
| `register_natural_graphics!(key, factory)` | 24 calls | a symbol; the factory answers several rows | in `__init__` | [GraphLayoutToGraphics.jl:1241](../../../source/domain/graph/GraphLayoutToGraphics.jl#L1241) |
| `register_natural_syntax!(key, factory)` | 6 calls | a symbol | in `__init__` | [BookToSyntax.jl:662](../../../source/domain/book/BookToSyntax.jl#L662) |
| `register_natural_domain!` or `register_natural_notation!(T, rung, make)` | 8 + 3 calls, and 1 more in `package/ProjecturedPlatform` | the type and a rung | in `__init__` | [JsonModule.jl:52](../../../source/domain/json/JsonModule.jl#L52) |
| a row in the closed table of the widget slice or the layout slice | 47 widget rows | the type | at each table build | [WidgetToGraphics.jl:15662](../../../source/platform/widget/WidgetToGraphics.jl#L15662) |
| `extra`, rows of the caller | 2 callers | the type | at the call | [Application.jl:364](../../../source/platform/application/Application.jl#L364) |

Three modules use three forms at once: Julia ([JuliaModule.jl:78](../../../source/domain/julia/JuliaModule.jl#L78), [:119](../../../source/domain/julia/JuliaModule.jl#L119), [:132](../../../source/domain/julia/JuliaModule.jl#L132)), Markdown ([MarkdownModule.jl:55](../../../source/domain/markdown/MarkdownModule.jl#L55), [:65](../../../source/domain/markdown/MarkdownModule.jl#L65), [:76](../../../source/domain/markdown/MarkdownModule.jl#L76)) and RST. Math writes the same `MathToSyntax(...)` call twice, once for each table ([MathToSyntax.jl:687](../../../source/domain/math/MathToSyntax.jl#L687), [:693](../../../source/domain/math/MathToSyntax.jl#L693)).

### D. A file format: two contracts

| Capability | Natural format (natural slice) | File type (serialization slice) |
| --- | --- | --- |
| the key | a symbol, `:json`, and a type | an extension string, `".json"`, and a file type |
| the extension of a document | `get_natural_extension` [NaturalNotation.jl:205](../../../source/platform/natural/NaturalNotation.jl#L205) | `find_file_extension` [FileProject.jl:297](../../../source/platform/serialization/FileProject.jl#L297) |
| the parser | `register_natural_parser!(format, parse)` | a method of `parse_file_content(::Type{<:XFile}, text)` |
| the printer | `print_natural_text(document)` | a method of `emit_text(file)`; 8 of its 11 methods call `print_natural_text` |
| a reference to another file | no | yes, `make_reference_leaf`, `find_reference_marker` |
| the first document of a new file | no | `make_document_seed(::Val{extension})`, a third key |
| read by | `import_document`, `parse_natural_text`, the assistant | `load_file`, `open_file!`, the file tabs |
| chosen in `read_document_file` | first, when a parser has the extension [DocumentFile.jl:43](../../../source/platform/fileformat/DocumentFile.jl#L43) | only when no parser has it [DocumentFile.jl:46](../../../source/platform/fileformat/DocumentFile.jl#L46) |
| used by `make_file_tab`, which opens a file in a tab | the content, through `read_document_file` [DocumentFile.jl:171](../../../source/platform/fileformat/DocumentFile.jl#L171) | the type of the file, through `get_file_document_type` [DocumentFile.jl:170](../../../source/platform/fileformat/DocumentFile.jl#L170) |

### E. The tables that a load fills

| Table | Filled by | Calls in `source/` | A second registration under one key |
| --- | --- | --- | --- |
| `_NOTATIONS`, `_FORMATS`, `_PARSERS`, `_EXPRESSIONS` [NaturalNotation.jl:9](../../../source/platform/natural/NaturalNotation.jl#L9) | `register_natural_domain!` and its four parts | 8 + 4 + 1 | the first stays |
| `_LADDER` [NaturalNotation.jl:17](../../../source/platform/natural/NaturalNotation.jl#L17) | `register_natural_rung!` | 3, all from the platform itself | the first stays |
| `_SYNTAX_FACTORIES`, `_GRAPHICS_FACTORIES`, `_FALLBACK_FACTORIES` [NaturalRegistry.jl:38](../../../source/platform/natural/NaturalRegistry.jl#L38) | `register_natural_syntax!`, `..._graphics!`, `..._fallback!` | 6 + 24 + 1 | the first stays |
| `_FILE_DOCUMENT_TYPES` [FileProject.jl:254](../../../source/platform/serialization/FileProject.jl#L254) | `register_file_document_type!` | 15 | the last wins, with no message |
| `_MARKER_FUNCTIONS` [FileProject.jl:320](../../../source/platform/serialization/FileProject.jl#L320) | `register_marker_function!` | 2 | the first stays, with a warning |
| `_ROSTER_SOURCES` [RosterSource.jl:151](../../../source/platform/roster/RosterSource.jl#L151) | `register_roster_source!` | 6 | the last wins |
| `_ASSISTANT_API`, `_ASSISTANT_API_DESCRIPTIONS` [AssistantApi.jl:6](../../../source/platform/assistant/AssistantApi.jl#L6) | `register_assistant_api!` | 9 | not added again |
| `_EXTRA_GUIDE_ROOTS` [Documentation.jl:17](../../../source/kernel/tool/Documentation.jl#L17) | `register_guide_root!` | 0 here | not added again |
| `_PREFERRED_ENGINE` [GraphLayoutChoice.jl:19](../../../source/domain/graph/GraphLayoutChoice.jl#L19) | `register_layout_engine!` | 0 here | the last wins |
| `_PALETTES`, `ICON_REGISTRY` | `register_palette!`, `register_icon!` | 4 + 1 loop | the last wins |

Seventeen tables, seventeen register functions, five different answers to a second registration.

### F. The mutable values at module level

| Class | Values | Within the rule? |
| --- | --- | --- |
| registries | the 17 tables of E | findings XS-1, XS-2, XS-3 |
| caches of facts that are the same for each editor | `_GUIDE_INDEX`, `_API_INDEX`, `_DECLARED_INDEX`, `_MEANING_STORES` (kernel tool); `_CANDIDATE_CACHE`, `_CONCRETE_CACHE` ([Domain.jl:312](../../../source/platform/domain/Domain.jl#L312)); `_PRED_NAMES` ([FileProject.jl:420](../../../source/platform/serialization/FileProject.jl#L420)); `_THEME_DEFAULTS`, `_UNIT_APPEARANCE`, `_FONT_AVAILABLE`, `_TTF_CACHE` (style); `_EXPRESSION_FUNCTIONS` (data frames); `_NEWEST_MODELS` (Anthropic) | yes, the carve-out of PAR-PER-EDITOR-STATE |
| scoped values of one evaluation or one frame | `_EVALUATION_EDITOR`, `_EVALUATION_STARTER`, `_EVALUATION_OUTPUT`, `_CURRENT_CODE_UNIT`, `_CURRENT_STOP_SCOPE`, `_PAINTING_EDITOR`, `_DESCRIBED_ROOT`, `_counters`, `DEFAULT_BACKEND`, `_PROCESS_IMITATION`, `_IS_BACKGROUND_WORK_ALLOWED` | yes |
| one resource of the process | the OS clipboard (`_READER`, `_WRITER`, `_LAST_CLIPBOARD_WRITE`), `_RUNNING_GROUPS` (process groups to end at exit), the SDL probes and caches, `_SESSION` of `display_in_editor` (one display beside one REPL) | yes; SDL is in `sdl-per-editor-state.md` |
| counters of names | `_ASSISTANT_COUNT`, `_TASK_GROUP_COUNT`, `_OUTPUT_FILE_COUNT`, `_checker_counter` | harmless |
| stores of a session at module level | `_SESSION_MESSAGE_LOG_STORE` ([MessageLogStore.jl:119](../../../source/platform/log/MessageLogStore.jl#L119)), `_SESSION_MCP_LOG_STORE` ([McpLogStore.jl:114](../../../source/platform/mcplog/McpLogStore.jl#L114)), `SESSION_TASK_FEED_STORE` ([TaskFeed.jl:47](../../../source/platform/task/TaskFeed.jl#L47)), `_TURN_WORKS` ([AssistantTurn.jl:135](../../../source/platform/assistant/AssistantTurn.jl#L135)), `_EVALUATOR_SESSIONS` ([Evaluator.jl:537](../../../source/platform/conversation/Evaluator.jl#L537)), `_SESSION_OUTPUT_FOLDER` | not examined in depth; they touch the settled decision "no process-global session document". The area of the feeds and of the assistant should judge them. |
| switches of a check | `_DECLARED_TYPE_CHECK_MODE`, `_FOREIGN_WRITES`, `_MEANING_FOLDER`, `_MEANING_WAIT_SECONDS` | kernel audit |

### G. The readers of a method table

| Reader | What it lists | Filter that only this copy has |
| --- | --- | --- |
| `collect_backend_types` [BackendChoice.jl:32](../../../source/kernel/editor/BackendChoice.jl#L32) | types with `get_backend_output` | concrete and `<: Backend` |
| `get_llm_backend_names` [Llm.jl:33](../../../source/kernel/llm/Llm.jl#L33) | `Val` keys of `make_llm` | skips a `UnionAll` signature |
| `_collect_val_kinds` [AgentDefaults.jl:32](../../../source/kernel/agent/AgentDefaults.jl#L32) | `Val` keys of a factory | same as above, a second copy |
| `_collect_wrapper_keywords` [EditorBuild.jl:210](../../../source/kernel/editor/EditorBuild.jl#L210) | `Val` keys of a wrapper seam | unwraps the signature first |
| `collect_graphics_projection_types` [DocumentComposition.jl:37](../../../source/platform/widget/DocumentComposition.jl#L37) | types with `make_graphics_projection` | handles `Type{<:T}`; sorts a subtype first |
| `collect_workload_file_types` [DisplayWorkload.jl:239](../../../source/platform/display/DisplayWorkload.jl#L239) | types with `make_workload_file` | no check of the signature at all |
| `_collect_source_types` [RosterProgram.jl:144](../../../source/platform/roster/RosterProgram.jl#L144) | types with `collect_roster_parts` | skips a private name |
| `_collect_session_explorer_entry_types` [ApplicationExplorer.jl:63](../../../source/platform/application/ApplicationExplorer.jl#L63) | types whose trait answers `true` | calls the trait |
| `compute_loaded_settings_types` [Settings.jl:39](../../../source/platform/settings/Settings.jl#L39) | types with `get_setting_descriptions` | exactly two parameters |
| `collect_pivot_cell_views` [PivotMenu.jl:17](../../../source/domain/pivot/PivotMenu.jl#L17) | types with `describe_pivot_cell_view` | skips a `TypeVar` |

Four walks of all loaded modules exist beside them: `_collect_named_types` ([Domain.jl:76](../../../source/platform/domain/Domain.jl#L76), kept by world age), `_collect_pred_names!` ([FileProject.jl:447](../../../source/platform/serialization/FileProject.jl#L447), read again when a name is missing), `_collect_loaded_modules` ([AssistantMark.jl:89](../../../source/kernel/tool/AssistantMark.jl#L89), at each call), and the API index ([Documentation.jl:1093](../../../source/kernel/tool/Documentation.jl#L1093), built once and never again).

### H. The shape of the public API

| Surface | Size | How it is made |
| --- | --- | --- |
| `EssentialsModule` | 12 names | one list by hand [EssentialsModule.jl:21](../../../source/platform/essentials/EssentialsModule.jl#L21) |
| the kernel | 691 names in `export` statements of 23 modules (the document says about 580) | one `export` per module |
| the platform | at least 2 344 names in `export` statements of 58 files (the document says about 3 000) | one `export` per module |
| the domains | at least 1 041 names in 21 slices | one `export` per module, plus the names that `@document` exports |
| `ProjecturedAll` | every name above, flat | a loop over the modules [ProjecturedAll.jl:18](../../../source/all/ProjecturedAll.jl#L18) |
| the surface of the assistant | 414 marked names in 130 files | the line `For the assistant.` |

Largest export lists: `StyleModule` 256, `WidgetModule` 247, `TaskModule` 183, `JuliaModule` 137, `RstModule` 109.

Verbs of exported functions (4 135 distinct names outside `source/tool`): `get_` 427, `make_` 386, `find_` 147, `is_` 130, `compute_` 84, `read_` 50, `describe_` 38, `collect_` 36, `run_` 35, `register_` 25, `add_` 23, `start_` 19, `open_` 12, `save_` 10, `show_` 9, `load_` 8, `insert_` 7.

Families that do one job with more than one verb:

| Job | Names | Note |
| --- | --- | --- |
| put a document in the window | `show_document!`, `open_pane!`, `open_page!`, `open_explorer_page!`, `display_in_editor`, and `show_roster!`, `show_document_tree!`, `show_system_process_tree!`, `show_assistant_work!` | finding XS-7 |
| write a document to a file | `save_document` (binary), `write_document_file` (by extension), `export_document` (natural text), `save_file!` and `save_file_text!` (a file type), `save_file_to_disk!` (the verb of Ctrl+S), `save_project!` | finding XS-2 covers the two text paths |
| read a document from a file | `load_document`, `read_document_file`, `import_document`, `load_file`, `load_project`, `open_file!`, `open_file_document!` | same |
| the extension of a document | `get_natural_extension`, `find_file_extension` | finding XS-2 |
| choose a backend | `make_default_backend` (kernel), `default_backend` (platform) | covered by a plan |
| add to a collection | `insert_elements!` (generic), `add_element!`, and 20 `add_<kind>!` verbs of the study and the workflow | the `add_<kind>!` verbs carry domain rules; not a finding |

Definitions with many keywords (922 definitions have keywords; 91 have more than five, 39 more than eight): `Assistant` 29 ([AssistantDocument.jl:290](../../../source/platform/assistant/AssistantDocument.jl#L290)), `WidgetTable` 22, `WidgetText` 17, `ObjectToSyntax` 16, `run_application` 15 ([Application.jl:594](../../../source/platform/application/Application.jl#L594)), `WidgetScrollPane` 14, `WidgetButton` 14. The widgets belong to another area. Twelve of the 29 keywords of `Assistant` are `agent_...` fields of the one external agent backend.

### I. What a domain author writes today

Counted on JSON, beyond the document types and the projection itself.

| What | Declarations | Where |
| --- | --- | --- |
| the view and the text form | 1 call of `register_natural_domain!` with 5 keywords | `__init__`, [JsonModule.jl:52](../../../source/domain/json/JsonModule.jl#L52) |
| the file type | 1 call of `register_file_document_type!`, 5 methods (`get_file_domain`, `make_reference_leaf`, `find_reference_marker`, `parse_file_content`, `emit_text`) | `__init__` [JsonModule.jl:61](../../../source/domain/json/JsonModule.jl#L61) and [JsonFile.jl:21](../../../source/domain/json/JsonFile.jl#L21) |
| the first document of a new file | 1 method of `make_document_seed(::Val{:json})` | [JsonToSyntax.jl:193](../../../source/domain/json/JsonToSyntax.jl#L193) |
| the sentence for the assistant | 1 call of `register_assistant_api!` | `__init__` [JsonModule.jl:65](../../../source/domain/json/JsonModule.jl#L65) |
| a verb for the assistant | the mark in the docstring, no registration | the docstring |
| a menu entry | a method of `compute_context_menu` (context menu); a row of `@gestures` (command palette); no way for the menu bar but `extra` of the host | the document file |
| the compile workload | 1 method of `make_workload_file`, 2 calls in `@compile_ahead` | [JsonModule.jl:70](../../../source/domain/json/JsonModule.jl#L70) and the entry file of the package |

Twelve declarations in four files, by four mechanisms. The string `.json` or the symbol `:json` is written four times, and `parse_json` twice.

## Findings

### XS-1 The row of a type in the renderer is declared in five forms

- **Kind:** several-ways · **Value:** high · **Effort:** large · **Confidence:** high
- **Principle:** first principle 7 (one mechanism, a missing case gets its row) and decision C1 of `packages-compose-by-seams.md` ("Seams only. No registry table, no `__init__` registration"); PAR-FRAMEWORKS-SINK ("multiple dispatch is the registration").
- **Today:** `NaturalToGraphics` builds its table from six sources (table C). The seam `make_graphics_projection(::Type{T}; measure, appearance)` has 33 methods. The older form, a factory under a symbol key, has 24 calls of `register_natural_graphics!` and 6 of `register_natural_syntax!`, all in `__init__`. The table of rungs has 12 more rows. The header of [NaturalRegistry.jl:6](../../../source/platform/natural/NaturalRegistry.jl#L6) says that the factory form is "what is left" so that "a domain can move from one to the other on its own". Decision C7 of the plan says that "a later plan moves the other eight natural register functions to seams"; no such plan exists. The table `_LADDER` has three rows, and the platform package itself registers all three in its own `__init__` ([ProjecturedPlatform.jl:97](../../../package/ProjecturedPlatform/src/ProjecturedPlatform.jl#L97), [SyntaxNatural.jl:154](../../../source/platform/syntax/SyntaxNatural.jl#L154)).
- **Example:**
  ```julia
  # today, the math domain (MathToSyntax.jl:686)
  function __init__()
      register_natural_syntax!(:math, (; appearance) -> Pair{Type,Any}[MathDocument => MathToSyntax(; theme = ..., syntax_theme = ...)])
      register_natural_graphics!(:math, (; measure, appearance) -> make_math_to_graphics_dispatch(; measure, theme = ...))
      register_natural_domain!(MathDocument; rung = :syntax,
                               make = (; appearance) -> MathToSyntax(; theme = ..., syntax_theme = ...),
                               format = :math, extension = ".math", parse = parse_math)
  end
  # and in the entry file of the package, because __init__ runs after the workload
  @compile_ahead run_natural_rows_workload(MathModule)

  # after: methods, no __init__, no key, no second copy
  make_syntax_projection(::Type{<:MathDocument}; appearance) = MathToSyntax(; theme = ..., syntax_theme = ...)
  make_graphics_projection(::Type{<:MathFraction}; measure, appearance) = ...   # one method for each type that draws itself
  ```
- **Problem:** A new domain must choose among three forms, and the choice changes what works. A row by the seam comes before a row by a factory ([NaturalProjection.jl:185](../../../source/platform/natural/NaturalProjection.jl#L185)), and a factory row comes before a rung row, so the order of the forms is a hidden rule. A factory is registered in `__init__`, which runs after the compile workload; so the workload of 17 packages calls `run_natural_rows_workload`, which runs every `__init__` of the module by hand first ([DisplayWorkload.jl:179](../../../source/platform/display/DisplayWorkload.jl#L179), [:194](../../../source/platform/display/DisplayWorkload.jl#L194)), and `test_package_graph()` must check that each package does so. The key of a factory is a free symbol with no meaning but "do not add twice". Math, Markdown, RST and Julia state one projection two or three times.
- **Proposal:** One seam for each question, keyed by the type, read from the method table:
  1. the text form of a type (today the rung row): a method that answers the projection of the type to syntax or to text, with the appearance;
  2. the row in the syntax table of the renderer, which defaults to 1 (Markdown and RST give a second method for the rendered style);
  3. the row in the graphics table, which is `make_graphics_projection` as it is.
  The ladder becomes a plain function of the natural and syntax slices, because its three steps are fixed. The fallback of the syntax slice becomes a method of a seam that the natural slice declares. The widget slice and the layout slice declare their rows by the same seam (see XS-8).
- **What goes away:** `register_natural_syntax!`, `register_natural_graphics!`, `register_natural_fallback!`, `register_natural_notation!`, `register_natural_rung!` and their five tables; the three `get_natural_..._entries` functions; the natural calls in 32 `__init__` functions, most of which then have no body; `run_module_initializers!` and the rule of `test_package_graph()` about it (only when XS-2 and XS-3 land too, because the same `__init__` functions register the file types, the stores and the sentences; `run_natural_rows_workload` itself stays, the packages that use only the seam call it too); the symbol keys. About 300 lines, and the `__init__` section of the domain guide.
- **What stays:** Every row that exists. The order "most specific type first" that `collect_graphics_projection_types` already gives. The rendered style of Markdown in a tab and its source style in a file, by two methods. `extra`, for the rows of one caller. A package that is not loaded gives no row, as now.
- **Risk and open questions:** A factory can answer several rows that share one object (the math rows share one configuration; the appearance rows share one scroll pane projection). A method for each type builds each row alone, so shared objects must come from the `Appearance` or from a small build context. A method for `Type{<:T}` must sort before its supertypes; the reader does this today. A method added after the table is built is not seen, as a late `__init__` is not seen today.
- **Related plans:** `plan/pending/packages-compose-by-seams.md` (in progress; C1 and C7 state the direction, step 4 added the seam, no step moves the tables). `plan/done/natural-projection.md` (done, the origin of the tables).
- **Check:** confirmed-with-corrections. I opened `NaturalRegistry.jl`, `NaturalNotation.jl`, `NaturalProjection.jl`, natural.md and the registration blocks of Julia, Markdown, RST and math, and counted again with grep. The counts hold: 33 methods of the seam, 24 + 6 factory calls, 8 calls of `register_natural_domain!`, 47 widget rows, 17 entry files with `run_natural_rows_workload`, 32 of the 40 `__init__` functions of `source/` with a natural call. One count was wrong and is corrected in table C: `register_natural_notation!` has 3 calls in `source/` and 1 in `package/ProjecturedPlatform`. No plan moves the tables. C7 of `packages-compose-by-seams.md` only promises one ("A later plan moves the other eight natural register functions to seams"), so the direction is the owner's already and this finding is that missing plan. Three things the proposal must add:
  1. `run_module_initializers!` goes only together with XS-2 and XS-3 (corrected above).
  2. The stated reason for the factory form is that one registration carries several rows of one build (the header of `NaturalRegistry.jl`). The other stated reason, "a row is a factory when it holds state" (natural.md), holds for the seam too, because the seam also runs at each table build. So the shared build is the one thing to keep: the math factory makes one `MathConfig` for 21 rows ([MathToGraphics.jl:2067](../../../source/domain/math/MathToGraphics.jl#L2067)), and the task factory one set of styles and cells for 7 rows. One method for the root type that answers one dispatch keeps it. "One method for each type that draws itself", as the example says, does not.
  3. One case breaks under a plain move. The task factory builds an inner table from every row of the seam ([TaskGroupToWidget.jl:1621](../../../source/platform/task/TaskGroupToWidget.jl#L1621)). When the task rows are rows of the seam themselves, that build calls itself with no end. The inner table must go back into the renderer that holds it.
  The value stays high: three forms with a hidden order between them, and three domains that state one projection two or three times.

### XS-2 A file format is declared twice, under three keys

- **Kind:** several-ways · **Value:** high · **Effort:** medium · **Confidence:** high
- **Principle:** first principle 2 (a printer and a reader are one pair) and 7 (one mechanism); settled decision "a saved file is the print of the tree".
- **Today:** The natural slice keeps `type => (format, extension)` and `format => parser` ([NaturalNotation.jl:11](../../../source/platform/natural/NaturalNotation.jl#L11), [:13](../../../source/platform/natural/NaturalNotation.jl#L13)). The serialization slice keeps `extension => file type` ([FileProject.jl:254](../../../source/platform/serialization/FileProject.jl#L254)), and each file type has methods of `parse_file_content` and `emit_text`. The file-format slice adds a third key, `make_document_seed(::Val{extension})` ([DocumentFile.jl:38](../../../source/platform/fileformat/DocumentFile.jl#L38)). Eight domains write both: the same parser twice and `emit_text(f::XFile) = print_natural_text(get_file_content(f))` once each (for example [JsonFile.jl:24](../../../source/domain/json/JsonFile.jl#L24), [:27](../../../source/domain/json/JsonFile.jl#L27); [YamlFile.jl:25](../../../source/domain/yaml/YamlFile.jl#L25), [:28](../../../source/domain/yaml/YamlFile.jl#L28)). `read_document_file` chooses between the two contracts by a private rule: the natural parser first, the file type only when no parser has the extension ([DocumentFile.jl:43](../../../source/platform/fileformat/DocumentFile.jl#L43), [:102](../../../source/platform/fileformat/DocumentFile.jl#L102)).
- **Example:**
  ```julia
  # today, YAML (YamlToSyntax.jl:292, YamlFile.jl:22)
  register_natural_domain!(YamlDocument; rung = :syntax, make = ..., format = :yaml, extension = ".yaml", parse = parse_yaml)
  register_natural_parser!(:yml, parse_yaml)
  register_file_document_type!(".yaml", YamlFile)
  register_file_document_type!(".yml",  YamlFile)
  get_file_domain(::Type{<:YamlFile}) = YamlDocument
  parse_file_content(::Type{<:YamlFile}, text::AbstractString) = parse_yaml(text)
  emit_text(f::YamlFile) = print_natural_text(get_file_content(f))

  get_natural_extension(document)   # ".yaml", from the natural table
  find_file_extension(document)     # ".yml", the shortest key of the file type table

  # after: one declaration, on the file type
  get_file_extensions(::Type{YamlFile}) = (".yaml", ".yml")
  get_file_domain(::Type{<:YamlFile}) = YamlDocument
  parse_file_content(::Type{<:YamlFile}, text::AbstractString) = parse_yaml(text)
  # emit_text has one default: the print of the content.
  # parse_natural_text(:yml, text) finds the file type by its extension.
  ```
- **Problem:** The two contracts can disagree, and they do. For YAML, the two functions above give two extensions for one document, and callers use both ([AssistantTurn.jl:208](../../../source/platform/assistant/AssistantTurn.jl#L208) asks the first, [PredFile.jl:89](../../../source/platform/serialization/PredFile.jl#L89) and [ResearchFolder.jl:55](../../../source/domain/research/ResearchFolder.jl#L55) ask the second). For math, the parser of the file type strips the text and its printer adds a line end ([MathFile.jl:23](../../../source/domain/math/MathFile.jl#L23), [:24](../../../source/domain/math/MathFile.jl#L24)), and the natural parser and printer do neither ([MathToSyntax.jl:697](../../../source/domain/math/MathToSyntax.jl#L697)); so `export_document` and `save_file!` write two different files for one document, and the Julia file type differs the same way ([JuliaFile.jl:28](../../../source/domain/julia/JuliaFile.jl#L28)). One open of a tab reads both tables: `make_file_tab` takes the type from the file type table and the content from the natural parser ([DocumentFile.jl:170](../../../source/platform/fileformat/DocumentFile.jl#L170)), so the method of `parse_file_content` of that file type does not run there; `load_file` runs it. A domain that has a parser and no file type, or the reverse as `SourceFile` of the language server, works in half of the callers. Each new format repeats four declarations.
- **Proposal:** A format is declared once. The file type is the natural owner: it already names its domain (`get_file_domain`), its parser and its printer. Add one seam for its extensions, give `emit_text` the one default (the print of the content), and key the seed of a new file by the file type. The natural slice then needs no format table: `parse_natural_text(format, text)`, `get_natural_extension` and `describe_natural_formats` read the file types. `read_document_file` has one path.
- **What goes away:** `_FORMATS`, `_PARSERS`, `register_natural_format!`, `register_natural_parser!`, the `format`, `extension` and `parse` keywords of `register_natural_domain!`; `_FILE_DOCUMENT_TYPES` and `register_file_document_type!` (15 calls); one of `get_natural_extension` and `find_file_extension`; 8 `emit_text` one-liners; the `Val{extension}` key of `make_document_seed`; the two private tests `_is_natural_path` and `_is_registered_file_path`. About 150 lines and one concept.
- **What stays:** `parse_natural_text(:json, text)` and `print_natural_text(document)` for a part of a file. Two extensions for one format. A file type with no domain text (`TextFile`, `PredFile`, `ImageFile`, `SourceFile`). The references between files. The expression of a format (`register_natural_expression!`, one use, Julia) moves with the rest in XS-1.
- **Risk and open questions:** The line end that the Julia and the math file types add must become a part of the one printer of the format. The natural slice does not import the serialization slice today. But the serialization slice is the lowest of the three already: the platform includes it before style, layout, widget and natural ([ProjecturedPlatform.jl:38](../../../package/ProjecturedPlatform/src/ProjecturedPlatform.jl#L38)), and `StyleModule`, `LayoutModule` and `WidgetModule` import it. Step 4a of `packages-compose-by-seams.md` took serialization out from under Primitive, Domain and Screen, but C17 of the same plan put it under Style again (`is_pred_constructible` for `Point2D` and `Inset`, [StyleModule.jl:28](../../../source/platform/style/StyleModule.jl#L28)), and Style also registers the picture file type there. So the natural slice can read the file types with no new direction of dependency. The other home also works: the natural slice keeps the declaration and the file-format slice gives the file type its defaults from it. Either home keeps one declaration; the owner should choose.
- **Related plans:** `plan/pending/a-print-writes-and-a-make-answers.md` (pending; it renames `print_natural_text` and touches the same `emit_text` lines). `plan/pending/packages-compose-by-seams.md` step 4a (done) and step 15 (pending, the saved forms).
- **Check:** confirmed-with-corrections. I opened `NaturalNotation.jl`, `FileProject.jl`, `DocumentFile.jl`, `NaturalFormat.jl`, fileformat.md, serialization.md and the eight `XFile.jl` files. The counts hold: 15 calls of `register_file_document_type!`, 11 methods of `emit_text` of which 8 call `print_natural_text` (2 of the 8 add a line end), and the same parser in both tables for 8 domains. The two extensions of one YAML document follow from the code (`".yaml"` from `_FORMATS`, `".yml"` as the shortest key of the file type table). One file tab uses both contracts: it reads through the natural parser (`read_document_file`) and Ctrl+S writes through `emit_text` (`save_file!`); for `.math` the read does not strip the text and the save adds a line end. No design document gives a reason for two declarations (fileformat.md says only which slice owns what), and no plan covers it. Corrected: three line links, and the risk about the layers, which was larger than the code shows (the serialization slice is below the natural slice already). The proposal loses nothing that I could find: a parser with no printer (`register_natural_parser!(:yml, …)`) stays as a second extension of the file type; `get_natural_format(T)` follows from `get_file_domain`, as `find_file_extension` reads it today; a file type with no domain text keeps its own two methods. The value stays high.

### XS-3 Five more registries are filled at load, and two of them came after the decision for seams

- **Kind:** several-ways · **Value:** medium · **Effort:** medium · **Confidence:** high
- **Principle:** decision C1 of `packages-compose-by-seams.md`; settled decision "no process-global registry"; first principle 10 (the surface of the assistant comes by reflection).
- **Today:** Beside the natural tables (XS-1) and the file types (XS-2), these tables at module level are filled by a call at load (table E):
  - `register_roster_source!(name, make_source; description)`, 6 calls, added 2026-10-14 ([RosterSource.jl:167](../../../source/platform/roster/RosterSource.jl#L167)). A source of a roster already has a seam, a method of `collect_roster_parts` for a source type, and `describe_roster_sources` lists both kinds ([RosterProgram.jl:120](../../../source/platform/roster/RosterProgram.jl#L120)).
  - `register_assistant_api!(declaration; description)`, 9 calls, added 2026-10-01 ([AssistantApi.jl:32](../../../source/platform/assistant/AssistantApi.jl#L32)). Eight of the nine calls pass `Any[]` and only a sentence (for example [JsonModule.jl:65](../../../source/domain/json/JsonModule.jl#L65), [ChartModule.jl:78](../../../source/domain/chart/ChartModule.jl#L78)). The design of `plan/done/the-assistant-finds-its-names-by-reflection.md` (section 4.2) said: "The sentence that a domain gives with `register_assistant_api!` moves into the docstring of its module". The implementation note of the same plan kept the registry.
  - `register_marker_function!(name, f)`, 2 calls ([FileProject.jl:331](../../../source/platform/serialization/FileProject.jl#L331)).
  - `register_layout_engine!(factory)`, one `Ref` for the whole process ([GraphLayoutChoice.jl:19](../../../source/domain/graph/GraphLayoutChoice.jl#L19)).
  - `register_guide_root!`, which the kernel audit covers (L18-13).
  Each table has its own answer to a second registration under one key (table E).
- **Example:**
  ```julia
  # today (MessageLogToSyntax.jl:98)
  function __init__()
      register_roster_source!(:log, link -> CollectionItems(get_session_message_log().entries);
                              description = "the lines of the message log of the session: level, message")
  end
  function __init__()   # JsonModule.jl:65
      register_assistant_api!(Any[]; description = "A JSON value is a document that is written and read as its JSON text.")
  end

  # after
  "The lines of the message log of the session: level, message."
  make_roster_store(::Val{:log}, link) = CollectionItems(get_session_message_log().entries)
  # the sentence about JSON is a marked paragraph of the docstring of JsonModule; no call
  ```
- **Problem:** The next slice with a store, a marker or a sentence must know which of two mechanisms its neighbours used. A registration in `__init__` is not in the compile workload unless the workload runs `__init__` by hand. Two packages that register one key get a silent winner in three of the tables. The sentence of a domain is a second channel beside the mark, against the design of the done plan.
- **Proposal:** Apply C1 to these four. A named store of a roster is a method for `Val{name}`, and its description is the docstring of the method. A marker word is a method for `Val{name}`. The sentence of a domain is the first paragraph of the docstring of its module, or of its root type, under the mark that `collect_marked_api` reads already. `register_assistant_api!` keeps one job: the names of a foreign package (`DataFrames`), which is a declaration of an adapter and could be a method of a seam too. The preferred layout engine becomes a setting of the graph projection or of the editor, not a `Ref` of the process.
- **What goes away:** `_ROSTER_SOURCES`, `_MARKER_FUNCTIONS`, `_ASSISTANT_API_DESCRIPTIONS`, `_PREFERRED_ENGINE`; `register_roster_source!`, `register_marker_function!`, `register_layout_engine!`; `describe_registered_assistant_api`; about 15 `__init__` bodies; five rules for a second registration. About 120 lines.
- **What stays:** `StoreRecords(:log)` in a saved roster file. The list of `describe_roster_sources`. The sentence of each domain in the system text, only while the domain is loaded. The marker words `section` and `definition`. A package that takes over the layout of a graph.
- **Risk and open questions:** A method can not be replaced at precompile time, which is the stated reason for `register_layout_engine!` ([GraphLayoutChoice.jl:15](../../../source/domain/graph/GraphLayoutChoice.jl#L15)); a setting avoids the replacement. The description of a `Val` method needs one way to read a docstring of a method; the roster already reads the docstring of a source type ([RosterProgram.jl:135](../../../source/platform/roster/RosterProgram.jl#L135)).
- **Related plans:** `plan/pending/packages-compose-by-seams.md` (in progress, C1). `plan/done/the-assistant-finds-its-names-by-reflection.md` (done; its design and its outcome differ on the sentence). `plan/pending/kernel-audit/18-tool.md` L18-13 (pending, the guide roots).
- **Check:** weakened. The counts hold (6 stores, 9 calls of `register_assistant_api!` of which 8 pass `Any[]`, 2 marker words), and git gives the dates: the roster store 2026-10-14 and the sentence 2026-10-01, both after C1 of 2026-09-30. But of the five registries, three remain as a finding:
  1. The guide roots are L18-13 of the kernel audit: covered by a plan, as the report says.
  2. `register_layout_engine!` has a stated reason and one real caller. It replaces a default, which a second method can not do without an overwrite ([GraphLayoutChoice.jl:15](../../../source/domain/graph/GraphLayoutChoice.jl#L15)), and omnet-julia calls it in the `__init__` of its `ModuleLayoutModule`. The proposal says "a setting of the graph projection or of the editor", but `layout_graph(::DeferredLayout, …)` gets no editor, so the report does not show how one loaded package would still take over the layout of every graph. Drop this item, or the takeover is lost.
  3. The sentence of a domain. The done plan records that `register_assistant_api!` keeps it, and gives no reason. The two channels do not do the same job today: the registered sentence is in the system text for both presets of the index, and the sentence of a module docstring is in the index only in the full preset, which a local model does not get. A move into the docstring needs a new marked paragraph and a reader of it for 8 sentences. That is a new mechanism for little gain.
  What remains with a clear gain: a named store of a roster and a marker word as a method for `Val{name}` (6 + 2 calls here, at least 4 marker words more in inet-julia). Each is small. The value is low alone; it is worth doing together with XS-1 and XS-2, when the `__init__` functions go.

### XS-4 A model adapter is an open seam in the kernel and a closed list in the application

- **Kind:** partial-feature · **Value:** medium · **Effort:** small · **Confidence:** high
- **Principle:** PAR-OPT-IN-DEPENDENCY ("generic code requests capability by symbol or supertype"); first principle 5 (a general part knows no domain and no adapter).
- **Today:** The kernel lists the models from the method table of `make_llm` ([Llm.jl:33](../../../source/kernel/llm/Llm.jl#L33)), and the assistant slice builds any kind ([AssistantTurn.jl:847](../../../source/platform/assistant/AssistantTurn.jl#L847)). The application slice names the adapters by hand: `APPLICATION_ASSISTANTS = (:ollama, :anthropic, :acp, :none)` ([Application.jl:18](../../../source/platform/application/Application.jl#L18)); a refusal of any other kind ([Application.jl:94](../../../source/platform/application/Application.jl#L94)); the greeting text, with one branch for each adapter ([Application.jl:51](../../../source/platform/application/Application.jl#L51)); the settings group, whose `assistant` field takes only that list ([StartSettings.jl:22](../../../source/platform/application/StartSettings.jl#L22)); and the size of the index, `backend === :ollama ? :compact : :full` ([StartSettings.jl:73](../../../source/platform/application/StartSettings.jl#L73)). The key of every model is read from `ANTHROPIC_API_KEY`, in the application ([Application.jl:101](../../../source/platform/application/Application.jl#L101)) and in the turn of the assistant ([AssistantTurn.jl:889](../../../source/platform/assistant/AssistantTurn.jl#L889)).
- **Example:**
  ```julia
  # today: a new adapter :mistral adds its method ...
  make_llm(::Val{:mistral}; kwargs...) = MistralLlm(; kwargs...)
  # ... and run_application(; assistant = :mistral) fails: "the backend must be one of ollama, anthropic, acp, none".
  # The author must edit Application.jl (the list, the greeting, the key) and StartSettings.jl.

  # after: the adapter says the rest by the same seam, and the platform names no adapter
  make_llm(::Val{:mistral}; kwargs...) = MistralLlm(; kwargs...)
  describe_llm_requirement(::Val{:mistral}) = "I use Mistral. The environment variable `MISTRAL_API_KEY` must hold your key."
  find_llm_api_key(::Val{:mistral}) = get(ENV, "MISTRAL_API_KEY", "")
  ```
- **Problem:** The seam promises that a package adds a model by loading. The application breaks the promise at four places, so a third model adapter needs an edit of the platform.
- **Proposal:** The application accepts every kind of `get_llm_backend_names()`, every kind of `get_agent_connection_names()`, and `:none`. Three small seams in the kernel's `llm` layer, each with a default, carry what the application now writes by hand: the sentence of the requirement, the key from the environment, and the size of the index that suits the model. "Is this backend an external agent" becomes a question to the list of the agent connections, in place of `backend === :acp` (8 places in the assistant slice).
- **What goes away:** `APPLICATION_ASSISTANTS`; the three branches of `get_application_greeting_text`; two reads of `ANTHROPIC_API_KEY` in the platform; the literal `:ollama` in `describe_api_index`.
- **What stays:** The three assistants of today with the same texts, which move into their adapters. `:none`. The default `:ollama`.
- **Risk and open questions:** The settings group checks its field against a fixed set when the group is declared; it must check against the loaded kinds when a value is set. The 12 `agent_...` fields of `Assistant` are a related question for the area of the assistant: they are the settings of one kind of backend, kept flat on every assistant.
- **Related plans:** `plan/pending/any-acp-agent-gets-the-instructions-and-a-sign-in.md` (steps 1 and 2 done; it opens the agent side to agents other than Claude, not the list of the application).
- **Check:** confirmed-with-corrections. Every cited line holds: the list, the refusal at [Application.jl:94](../../../source/platform/application/Application.jl#L94) and a second one for `--assistant` at [:720](../../../source/platform/application/Application.jl#L720), the three branches of the greeting, the field of the Start settings, the literal `:ollama`, and the 8 places with `backend === :acp`. `Assistant(backend = :x)` builds any loaded kind, and `run_application` and the settings refuse it, so the seam works through one of two entries. No plan names `APPLICATION_ASSISTANTS`. One correction to the proposal: the seam for the key is not needed. `AnthropicLlm` reads `ANTHROPIC_API_KEY` itself when it gets no key ([AnthropicLlm.jl:97](../../../source/adapter/anthropic/AnthropicLlm.jl#L97)), and the Ollama adapter ignores the key, so the platform can stop reading the variable and pass a key only when the assistant holds one. Two seams remain: the sentence of the requirement and the preset of the index. One open cost: `@settings` checks `in values` against a fixed tuple, so an open list needs a check when a value is set and a choice list that reads the loaded kinds. Nothing of today is lost. The value stays medium.

### XS-5 Ten functions read a method table as a list, each written by hand

- **Kind:** repeated-by-hand · **Value:** medium · **Effort:** small · **Confidence:** high
- **Principle:** first principle 7 (generic before special); decision C1 makes the method table the registry of the project, so its reader is a core part.
- **Today:** Table G lists ten readers in the kernel (4), the platform (5) and a domain (1). Each walks `methods(f)`, unwraps the signature, takes the second parameter, and filters. The filters differ: one handles `Type{<:T}`, one skips a `TypeVar`, one checks `isconcretetype`, one checks nothing ([DisplayWorkload.jl:240](../../../source/platform/display/DisplayWorkload.jl#L240) indexes `method.sig.parameters[2].parameters[1]` with no test). Two readers of `Val` keys in the kernel are the same loop twice ([Llm.jl:33](../../../source/kernel/llm/Llm.jl#L33), [AgentDefaults.jl:32](../../../source/kernel/agent/AgentDefaults.jl#L32)). The pattern of a factory by symbol, "a `Symbol` entry, a `Val{K}` fallback with an error that lists the kinds, a lister", is written four times (`make_llm`, `make_agent_server`, `make_agent_connection`, `make_database_adapter`), and the fourth has no lister. Four more functions walk all loaded modules, each with its own rule for when to walk again (below table G).
- **Example:**
  ```julia
  # today (Settings.jl:39), one of ten
  function compute_loaded_settings_types()
      types = Type[]
      for method in methods(get_setting_descriptions)
          signature = Base.unwrap_unionall(method.sig)
          length(signature.parameters) == 2 || continue
          argument = signature.parameters[2]
          (argument isa DataType && argument <: Type && length(argument.parameters) == 1) || continue
          T = argument.parameters[1]
          T isa Type && push!(types, T)
      end
      sort!(unique!(types); by = get_settings_name)
  end

  # after
  compute_loaded_settings_types() = sort!(collect_seam_types(get_setting_descriptions); by = get_settings_name)
  get_llm_backend_names()         = collect_seam_keys(make_llm)
  ```
- **Problem:** Each new seam needs a new reader, and each reader is a place where a signature shape is forgotten: a method for `Type{<:T}` is seen by one reader and skipped by four. The readers call internals of Julia (`Base.unwrap_unionall`, `Type.body.name`), so a change of Julia needs ten fixes.
- **Proposal:** Two functions in the kernel, in the lowest layer that the readers share: `collect_seam_types(f)` for a seam keyed by `Type{T}` (with the `Type{<:T}` case and the order "subtype first" as options) and `collect_seam_keys(f)` for a seam keyed by `Val{key}`. A third helper gives the error text of an unknown key with the loaded keys. One index of the loaded types, kept by world age as [Domain.jl:342](../../../source/platform/domain/Domain.jl#L342) does, can serve the four walks of the loaded modules.
- **What goes away:** about 110 lines in ten readers; the missing lister of `make_database_adapter`; three of the four rules for when a walk of the modules is fresh.
- **What stays:** every list, with its own order and its own extra filter as a short line at the call.
- **Risk and open questions:** The kernel files `Llm.jl` and `AgentDefaults.jl` are in the kernel audit, which notes the two listers one by one; this finding is the model-level view across packages. A sealed kernel file needs the owner's permission to change.
- **Related plans:** `plan/pending/packages-compose-by-seams.md` (in progress; it added four of the ten readers). `plan/pending/kernel-audit/19-llm.md` and `20-agent.md` (pending; file-level notes on the two listers).
- **Check:** confirmed-with-corrections. I opened all ten readers. They exist and differ as table G says, `Llm.jl:33` and `AgentDefaults.jl:32` are one loop written twice, and no shared helper exists (grep for `methods(` in `source/`). `make_database_adapter` has no lister. Corrections:
  1. The keys have three shapes, not two: `Type{T}` (six readers), `Val{key}` (three readers), and the type of an instance, `collect_roster_parts(source::T, link)` (the roster reader). The two helpers cover nine; the roster reader needs a third form or stays.
  2. Some of the different filters are wanted, so they must stay as options and are no defect. The pivot reader and the backend reader skip a method for `Type{<:T}` on purpose, because there it is the general fallback ([PivotCellView.jl:55](../../../source/domain/pivot/PivotCellView.jl#L55)), and the graphics reader counts it as a row.
  3. The last sentence of the proposal, one index of the loaded types for the four walks of the loaded modules, is not shown. The four collect different things (types by supertype, names that a file may build, modules, bindings with docstrings), two in the kernel and two in the platform. Leave it out.
  The value is lowered to low: about 110 lines of code that works, and the next seam saves about ten lines. It is the right first step if XS-1, XS-2 or XS-3 go ahead, because each of them adds readers.

### XS-6 A session document of an editor is declared in up to five places

- **Kind:** repeated-by-hand · **Value:** medium · **Effort:** medium · **Confidence:** medium
- **Principle:** first principle 7; settled decision "no session document at process level: they belong to the editor"; PAR-PER-EDITOR-STATE (the paragraph on `get_session_document!`).
- **Today:** The kernel keeps the documents of the session of an editor in one table by type, and `get_session_document!(make, editor, type)` reads it ([Editor.jl:262](../../../source/kernel/editor/Editor.jl#L262)). Above it, 14 functions `get_session_<kind>(; editor = find_evaluation_editor())` repeat one body, for example [FaultDocument.jl:169](../../../source/platform/fault/FaultDocument.jl#L169), [MessageLogDocument.jl:120](../../../source/platform/log/MessageLogDocument.jl#L120), [McpLogDocument.jl:97](../../../source/platform/mcplog/McpLogDocument.jl#L97), [AssistantList.jl:127](../../../source/platform/assistant/AssistantList.jl#L127). Ten kinds add `make_insertion_document(::Type{X}) = get_session_<kind>()`. Six kinds register a roster store that reads the same document (XS-3). The first content of the explorer names ten kinds by hand ([ApplicationExplorer.jl:36](../../../source/platform/application/ApplicationExplorer.jl#L36)), and one kind, `WorkflowList`, comes by the newer trait `is_session_explorer_entry_type` ([WorkflowList.jl:97](../../../source/domain/workflow/WorkflowList.jl#L97)).
- **Example:**
  ```julia
  # today, for each kind
  get_session_fault_log(; editor = find_evaluation_editor()) =
      editor isa Editor ? get_session_document!(FaultLog, editor, FaultLog) : FaultLog()
  make_insertion_document(::Type{FaultLog}) = get_session_fault_log()
  register_roster_source!(:faults, link -> CollectionItems(get_session_fault_log().entries); description = "...")
  # and ApplicationExplorer.jl names get_session_fault_log(; editor) in its list

  # after
  is_session_document_type(::Type{FaultLog}) = true
  # one generic get_session_document(FaultLog; editor); the insertion and the entry of the
  # explorer follow from the trait (not the store of a roster: see the check)
  ```
- **Problem:** A new tool of the editor (a log, a list) repeats four or five lines in four files, and its author must also edit the application to see it in the explorer, unless the author knows the newer trait. The explorer has two ways for one fact.
- **Proposal:** One trait says that a type is a session document, with an optional method that makes the first one. One generic getter replaces the 14. The default insertion of such a type is its session document. The explorer lists its first content from the trait alone, with a method for the section and the order where the hand list gives one today.
- **What goes away:** 13 one-line getters and their exports, 10 insertion methods, the hand list of ten kinds in `make_editor_explorer_content`; about 80 lines.
- **What stays:** one document for each kind and each editor; the sections of the explorer ("Editor", "Help"); the option `mcp_log`; a kind that takes its first document from the window (`_find_window_task_group_list`).
- **Risk and open questions:** The explorer and the roster belong to other review areas; the order and the sections of the first content are a design of the explorer. Five getters have a maker of their own (the explorer content, the task group list, the background work log, the open file list, the workflow list), which the trait must allow.
- **Related plans:** none found. `plan/pending/document-lifecycle` is deferred by the owner (memory note), and touches when a session document is held.
- **Check:** weakened. The counts hold: 14 getters, of which 13 have the one body `editor isa Editor ? get_session_document!(make, editor, T) : make()`; 10 insertion methods; 10 kinds by hand in the explorer and 1 by the trait. A sixth place was not counted: 11 methods `make_pred_document(::Type{<:X}, …) = get_session_<kind>()` for the saved form. Two facts were wrong: five getters have a maker of their own, not three (corrected), and the store of a roster does not follow from a trait, because three stores read `.entries` and three use a source type of their own (`_SessionTasks`, `_SessionFrames`, `_OpenWorkflows`). The proposal would lose two things:
  1. At least seven of the named getters are part of the surface of the assistant: those of the message log, the fault log, the gesture log, the task group list, the assistant list, the open file list and the workflow list. Each has the mark `For the assistant.`, its own docstring and its own example, and the model finds them by their names. One generic getter removes these names, or keeps each as an alias of one line and then saves nothing.
  2. The hand list in `make_editor_explorer_content` is the layout of the explorer of one host: which kind stands in which section, in which order. A method for the section and the order in ten slices spreads that one design over ten files, with numbers that must agree. The trait was added for the one case that the host can not name, a domain (plan/done/the-explorer-shows-the-open-workflows.md), so the two ways have two jobs.
  What remains: one declaration from which the insertion and the saved form of a session document type follow, in place of about 21 methods of one line. If a trait is made for that, it belongs in the platform; the kernel keeps its plain table by type (settled decision). The value is low.

### XS-7 Four verbs repeat "make, place, find again", because the placing verb answers nothing

- **Kind:** complicated-api · **Value:** medium · **Effort:** small · **Confidence:** medium
- **Principle:** first principle 7 ("verbs combine with no special case"); `plan/pending/assistant-api-consolidation.md` section 3: "A verb that places something answers a reference to what it placed" and section 2b, "the surface grows as make times place".
- **Today:** `show_document!(document; title, editor)` places a document in the window and answers `nothing` ([DocumentShow.jl:17](../../../source/platform/screen/DocumentShow.jl#L17)), though its pane method holds the tab that `open_pane!` answered ([PaneTabsWrapper.jl:84](../../../source/platform/pane/PaneTabsWrapper.jl#L84)). So `show_roster!` and `show_document_tree!` build their document, call `show_document!`, and then search the whole window for the node again, with `search_references(editor.document, node -> node === roster; maxdepth = 24)` ([RosterProgram.jl:39](../../../source/platform/roster/RosterProgram.jl#L39), [TreeProgram.jl:29](../../../source/platform/tree/TreeProgram.jl#L29)). `show_system_process_tree!` wraps the second ([SystemProcessProgram.jl:29](../../../source/platform/systemprocess/SystemProcessProgram.jl#L29)), and `show_assistant_work!` writes its own placement with `open_pane!` and a show operation ([AssistantWorkDocument.jl:120](../../../source/platform/assistant/AssistantWorkDocument.jl#L120)).
- **Example:**
  ```julia
  # today: one verb for each kind of document
  roster_1 = show_roster!(TabDocuments(FileDocument); title = "Files", columns = ["name", "folder"])
  tree_1   = show_document_tree!(plan_1; title = "Plan")

  # after: the constructor makes, one verb places and answers the part
  roster_1 = show_document!(Roster(TabDocuments(FileDocument); columns = ["name", "folder"]); title = "Files")
  tree_1   = show_document!(DocumentTree(plan_1); title = "Plan")
  ```
- **Problem:** Each new kind of view asks for a new `show_<kind>!` verb with its own docstring in the surface of the assistant. The search after the show walks the window and can find nothing, which each verb turns into its own error. None of the four has a method of `make_change`, so none can join one undo step with other edits (the done plan lists them as verbs "that stay as they are").
- **Proposal:** `show_document!` answers the `ReferencedDocument` of what it placed, as `open_pane!` does. A kind then needs its constructor only. The arrangement keywords of `show_roster!` (`filter`, `sort`, `group`, `first`) go to the constructor or to the verbs `filter_collection!` and `sort_collection!` that take the answer. A tree of processes joins its feed when the window acquires the document, not in the verb.
- **What goes away:** the two searches after the show; `show_document_tree!` and `show_system_process_tree!` as separate verbs, or their bodies down to one line; the hand placement in `show_assistant_work!`. About 60 lines and up to four names of the surface.
- **What stays:** a roster, a tree and a work page in a tab, by one call; a document that is shown already comes to the front; the answer is a part that the other verbs take.
- **Risk and open questions:** `show_document!` is a seam of the plan `packages-compose-by-seams.md` with the return `nothing` (its window method opens a window, where a reference is a window and not a tab). The owner decided the pane verbs in `plan/done/a-pane-is-placed-shown-and-focused-by-three-verbs.md`; this proposal keeps the three verbs and changes one return value. The area of the panes and of the assistant should confirm.
- **Related plans:** `plan/pending/assistant-api-consolidation.md` (stale: written 2026-09-13, no step checked, but `open_pane!` and `focus_pane!` by reference exist now). `plan/done/the-assistant-finds-its-names-by-reflection.md` (done).
- **Check:** weakened. The core fact holds: `show_document!` answers `nothing` although its pane method holds the tab, and `show_roster!` and `show_document_tree!` then search the whole window for their node (`maxdepth = 24`). But two verbs repeat the search, not four: `show_system_process_tree!` only calls `show_document_tree!`, and `show_assistant_work!` places a `Navigator` with `open_pane!` and states why it makes its own show operation (the verb `show_pane!` would also print the layout). The proposal has two parts:
  1. `show_document!` answers the part that it placed. This holds. The rule is in §3 of `assistant-api-consolidation.md` already, which does not name this verb, and no owner decision is against it. It removes two searches of three lines each.
  2. "A kind then needs its constructor only." This does not hold as written. `show_roster!` also links the roster to the document of the window (`link_roster!`, [RosterProgram.jl:43](../../../source/platform/roster/RosterProgram.jl#L43)); a roster with no link has no rows, and a constructor has no editor. So `show_roster!` stays, with its arrangement keywords, or a roster must link itself when the window acquires it, which the report does not show. The four verbs are also marked names with their own docstrings and examples.
  For the tree of processes the report is right, and the defect is larger than it says: the verb is the only place that puts a tree into the `SystemProcessFeed` ([SystemProcessProgram.jl:33](../../../source/platform/systemprocess/SystemProcessProgram.jl#L33) is the only push in `source/`), so the tree that the explorer makes with its constructor ([ApplicationExplorer.jl:54](../../../source/platform/application/ApplicationExplorer.jl#L54)) is in no feed. The done plan gives the reason why the four verbs have no method of `make_change`: a later step reads the result of an earlier one. The value is low for the return value alone.

### XS-8 The printer of one widget has no factory, so six views search the whole widget table for it

- **Kind:** complicated-api · **Value:** low · **Effort:** small · **Confidence:** high
- **Principle:** first principle 7; settled decision "a projection never reads the state of another projection".
- **Today:** `WidgetToGraphics(; measure, theme, ...)` builds 47 widget projections, the layout rows and a text view chain, and answers one dispatch table ([WidgetToGraphics.jl:15660](../../../source/platform/widget/WidgetToGraphics.jl#L15660)). A view that needs the printer of one widget builds the whole table and searches it: `last(only(p for p in widgets.dispatch if first(p) === WidgetTable))` at [DataFrameViewToWidget.jl:391](../../../source/adapter/dataframes/DataFrameViewToWidget.jl#L391), [PivotPartTableToWidget.jl:52](../../../source/domain/pivot/PivotPartTableToWidget.jl#L52) and [TaskGroupToWidget.jl:1647](../../../source/platform/task/TaskGroupToWidget.jl#L1647), the same for `GridLayout` in the layout table `LayoutToGraphics().dispatch` at [PivotTableToWidget.jl:556](../../../source/domain/pivot/PivotTableToWidget.jl#L556) and [DataFrameViewToWidget.jl:392](../../../source/adapter/dataframes/DataFrameViewToWidget.jl#L392), and for `WidgetScrollPane` at [AppearanceModule.jl:93](../../../source/platform/appearance/AppearanceModule.jl#L93) and [SettingsManagingModule.jl:84](../../../source/platform/settingsmanaging/SettingsManagingModule.jl#L84). The data frame view then reads a style field of the projection it found ([DataFrameViewToWidget.jl:394](../../../source/adapter/dataframes/DataFrameViewToWidget.jl#L394)). A widget added later, `WidgetChoiceList`, is not in the table at all; it declares its printer by the seam `make_graphics_projection` ([WidgetChoiceList.jl:138](../../../source/platform/widget/WidgetChoiceList.jl#L138)), which only `NaturalToGraphics` reads.
- **Example:**
  ```julia
  # today
  widgets = WidgetToGraphics(; measure, theme, graphics_theme = get_scaled_theme!(appearance, GraphicsTheme))
  table = last(only(p for p in widgets.dispatch if first(p) === WidgetTable))

  # after
  table = make_graphics_projection(WidgetTable; measure, appearance)
  ```
- **Problem:** Widgets have two homes for their printer, the closed table and the seam, and a view built on the table alone does not draw a widget of the second home. The search is copied seven times, in six files: five times in the widget table and twice in the layout table.
- **Proposal:** Each widget and each layout declares its printer by the seam that every other document uses, and `WidgetToGraphics` is the rows of that seam for the widget and layout types. One call gives one printer.
- **What goes away:** seven searches; the split between the 47 rows of the table and the rows of the seam.
- **What stays:** `WidgetToGraphics(...).dispatch` for a caller that splices the whole table; the themes of one editor in each row.
- **Risk and open questions:** The table constructor takes `theme`, `graphics_theme` and `text_theme`; the seam takes an `Appearance`. A caller with no appearance (a test) needs the default appearance. This belongs with XS-1 and with the area of the widgets.
- **Related plans:** `plan/pending/packages-compose-by-seams.md` (in progress, the seam).
- **Check:** weakened. The searches exist. The count is corrected: seven searches in six files, because the report missed the one of the task pane, and two of the seven read the layout table, not the widget table. The title does not hold: the printer of a widget has a factory, its constructor, and each row of the table is one such call.
  - `WidgetScrollPaneToGraphicsCanvas(theme; measure)` is exported, and the graph domain calls it directly ([GraphToWidgetScrollPane.jl:102](../../../source/domain/graph/GraphToWidgetScrollPane.jl#L102)).
  - `GridLayoutToGraphicsCanvas()` is called directly in 17 places of `source/`.
  - Only `WidgetTableToGraphicsCanvas(theme; graphics_theme)` is not in the export list of `WidgetModule`, which is why three views search for it.
  So four of the seven searches need only the direct call, and the other three end when the table printer is exported, or gets one small `make_` function. Moving 47 widgets and 9 layouts to the seam is more than the problem asks, and it costs something: every one of them is in the slice that owns the table, so the table is no closed door for another package; the seam takes an `Appearance` where the table takes plain themes, so `WidgetToGraphics(; theme)` for "an interface with no scales" (its docstring) would have to make an appearance from a theme first; and the natural table would get each widget row from two places. Two more facts, both small: two views read `table.cell_padding` of the printer that they found ([DataFrameViewToWidget.jl:394](../../../source/adapter/dataframes/DataFrameViewToWidget.jl#L394), [TaskGroupToWidget.jl:1649](../../../source/platform/task/TaskGroupToWidget.jl#L1649)), where the style of the theme is the right source; and `WidgetChoiceList` outside the table is true and is one missing row. The value stays low, and the fix is about seven lines, not a move of the widget slice.

### XS-9 A verb of the assistant is a group of up to six methods written by hand

- **Kind:** repeated-by-hand · **Value:** low · **Effort:** medium · **Confidence:** medium
- **Principle:** first principle 3 (one way to edit) and 7 (verbs combine with no special case).
- **Today:** The owner decided on 2026-11-04 that a verb is "its make function plus the apply function", with one generic `make_change(verb, arguments...)` ([DocumentEdits.jl:81](../../../source/kernel/editor/DocumentEdits.jl#L81)). The result is written by hand for each verb: the verb, which wraps `run_on_editor_task!` and calls `apply_change!(make_change(verb, ...))`; the method of `make_change`, which repeats the signature and wraps `run_on_editor_task!` again; a forwarding method of each for a `ReferencedDocument`; and often one for `nothing`. See `close_pane!` at [PaneProgram.jl:1177](../../../source/platform/pane/PaneProgram.jl#L1177) to line 1198, and `insert_elements!` at [DocumentEdits.jl:226](../../../source/kernel/editor/DocumentEdits.jl#L226). Counts: 44 verbs have a method of `make_change`; 28 forwarding methods for `ReferencedDocument`; 112 calls of `run_on_editor_task!(editor; description = "<the name of the function>")`. Of the 72 marked verbs that end in `!`, 28 have no method of `make_change`; about 12 of those change a document (`open_file!`, `select_part!`, `change_setting!`, `add_study_formula!`, the four `show_` verbs, `close_task_group!`, `start_workflow!`, `start_study!`, `check_predictions!`), and the done plan names them as an open item.
- **Example:**
  ```julia
  # today (PaneProgram.jl:1177)
  function close_pane!(reference::Reference; editor = get_evaluation_editor())
      run_on_editor_task!(editor; description = "close_pane!") do
          apply_change!(make_change(close_pane!, reference; editor); editor)
          show_layout(; editor)
      end
  end
  close_pane!(pane::ReferencedDocument; keywords...) = close_pane!(get_reference(pane); keywords...)
  function make_change(::typeof(close_pane!), reference::Reference; editor = get_evaluation_editor())
      run_on_editor_task!(editor; description = "make_change") do ... end
  end
  make_change(::typeof(close_pane!), pane::ReferencedDocument; keywords...) =
      make_change(close_pane!, get_reference(pane); keywords...)

  # after: the author writes the change and the answer; one declaration gives the rest
  @verb function close_pane!(editor, reference::Reference)
      change = _make_close_pane_change(editor, reference)
      change, () -> show_layout(; editor)
  end
  ```
- **Problem:** Whether a verb can join one undo step depends on whether its author wrote the second method. The signature and its keywords are written twice and can drift. A part given as a `ReferencedDocument` works only where the forwarding method exists.
- **Proposal:** One declaration form for a verb of one change. It writes the verb, the method of `make_change`, the forwarding for a part, the default `editor`, and the call on the task of the editor. A verb of several steps keeps its hand form until the open item of the plan is decided.
- **What goes away:** about 90 methods of forwarding and wrapping in the kernel, the pane, arrangement, chart, sequence chart, study and workflow slices.
- **What stays:** `make_change`, `combine_changes` and `apply_change!` as the three names of the assistant; each verb with its docstring and its mark on the generic function; the makers that the key bindings use.
- **Risk and open questions:** The design is two weeks old and the owner chose it; this finding is about the cost of writing it, not about its shape. A macro hides the methods from a reader of the file. The area of the assistant should weigh it.
- **Related plans:** `plan/done/the-assistant-finds-its-names-by-reflection.md` (done, step 3 and its open item 1).
- **Check:** weakened. The counts that I counted again hold: 44 verbs have a method of `make_change` (55 methods in all), 112 calls of `run_on_editor_task!(editor; description = …)`, and `close_pane!` is five methods and a declaration ([PaneProgram.jl:1177](../../../source/platform/pane/PaneProgram.jl#L1177)). I did not count the 72 marked verbs again. But the hand form is the owner's decision of 2026-11-04 in the done plan, on each point that the finding calls a problem:
  - "each verb that changes a document adds one method of `make_change`";
  - for a part, "each of these functions gets one method for each position that takes the part and calls the function again with its document" (the other way that the plan weighed, a hint on the `MethodError`, was not taken; a macro was not weighed);
  - `test_assistant_documentation` checks with `hasmethod` that every offered function takes a part at every document position, so "works only where the forwarding method exists" is kept by a test and not left to the author;
  - which verbs have no method of `make_change` is the scope that the owner set (the verbs of several steps; open item 1).
  D2 of the same plan chose "no macro" for the mark. A `@verb` form is a new mechanism. The verbs differ in their answer (the text of the layout, a part, nothing), in their checks (`_refuse_stale`), in their method for `nothing` with its own message, and in their keywords, so one form covers only the simple ones and hides their methods from a reader of the file. The value is low. The design is two weeks old and the owner chose it, so this is a note on its cost and no proposal to restructure.

## Covered by plans

- The two rules for a backend when the caller names none (`make_default_backend`: exactly one candidate; `default_backend`: a fixed order of preference by type name), the table `PROJECTURED_BACKENDS` of the builder, and `get_backend_name`, which no code in `source/` reads: step 10 of `plan/pending/packages-compose-by-seams.md`.
- The 14 keywords of the gallery's `make_example_editor` become wrappers: step 8 of the same plan.
- The other callers of the old run functions, and the two downstream repositories: steps 11 and 12 of the same plan.
- The 14 types that save a reduced form: step 15 of the same plan.
- `print_natural_text` answers a string and prints nothing: `plan/pending/a-print-writes-and-a-make-answers.md`.
- The parameter names of the four projection functions: `plan/pending/unify-projection-api-parameter-names.md` (waits for the template conversion).
- The guide roots are a process-global registry: `plan/pending/kernel-audit/18-tool.md`, L18-13.
- Three process-global values of the SDL backend: `plan/pending/sdl-per-editor-state.md`.
- The verbs of the OMNeT++ IDE that fuse make, view and place: `plan/pending/assistant-api-consolidation.md` (stale, see XS-7).

## Examined and sound

- The wrappers of an editor: five seams for `Val{keyword}` and one reader serve 25 wrappers in 22 folders of `source/`, with layers, an order, exclusions and defaults ([EditorBuild.jl:67](../../../source/kernel/editor/EditorBuild.jl#L67)). This is the model for the other extension points.
- Gesture bindings: `@gestures` writes a method, so the table that fires is the table that F1 and the command palette list ([GestureBindingModule.jl:26](../../../source/kernel/binding/GestureBindingModule.jl#L26)).
- The steps of a reference: methods for `Val{name}`, none in a table.
- The tools of the assistant: the `ToolSet` belongs to an editor, and every function takes the set ([ToolSet.jl:1](../../../source/kernel/tool/ToolSet.jl#L1)). The host adds `undo`, `redo` and `take_picture` by an explicit call, which fits the decision that the core tool runs Julia and the list of tools stays short.
- Themes and settings: `@theme` and `@settings` write methods, the values live on the `Appearance` and the `Settings` of one editor, and the tabs list them from there.
- Palettes and icons: named data, the same for each editor, filled at the top level of the module that owns the data. A table is the right form for data.
- The keywords of `make_llm`: each adapter ignores the keywords of the others. The docstring states the trade ([LlmInterface.jl:85](../../../source/kernel/llm/LlmInterface.jl#L85)), and a caller needs no adapter in mind.
- The scoped values of an evaluation (`_EVALUATION_EDITOR` and the others): state of one evaluation and its tasks, as PAR-PER-EDITOR-STATE asks.
- The OS clipboard functions at module level: the system has one clipboard, and the two `Ref`s are a test seam.
- `EssentialsModule`: one list of 12 names, re-exported by 11 packages, with a test. The gap between 12 names and about 4 000 is real, but the marked names of the assistant are a ready middle list if the owner wants one; this is a choice, not a fault.
- The caches of reflection (`_CANDIDATE_CACHE`, `_PRED_NAMES`, the API index): the same for each editor, inside the carve-out. Only their four separate walks are noted, in XS-5.
- The `add_<kind>!` verbs of the study and the workflow beside the generic `insert_elements!`: each carries a rule of its domain (the place, the fields, the checks), so they are not a second way of one job.
- The two tables of the natural slice as two questions (the text form of a document; the view of any document in a tab): the document states the reason ([natural.md](../../../documentation/package/platform/natural/natural.md), "Two tables serve two questions"). XS-1 keeps both questions and removes the extra forms of the answer.

## Check of the report

A second agent checked each finding against the code at commit 3a9b4fae4: it opened the cited files, counted again with grep, and read the plans and the design documents for a stated reason. No Julia ran.

| Id | Verdict | Value after the check |
| --- | --- | --- |
| XS-1 | confirmed-with-corrections | high |
| XS-2 | confirmed-with-corrections | high |
| XS-3 | weakened | low |
| XS-4 | confirmed-with-corrections | medium |
| XS-5 | confirmed-with-corrections | low |
| XS-6 | weakened | low |
| XS-7 | weakened | low |
| XS-8 | weakened | low |
| XS-9 | weakened | low |

What changed, in short:

- XS-1 and XS-2 hold and stay the two proposals of this area. XS-1 is the plan that C7 of `packages-compose-by-seams.md` promises; it must keep the shared build of a factory and must not let the inner table of the task pane call itself. XS-2 has less risk than written, because the serialization slice is below the natural slice already.
- XS-4 holds; the seam for the key is not needed, because the Anthropic adapter reads its key itself.
- XS-3 is three registries, not five: the guide roots are in the kernel audit, and the layout engine has a stated reason and a caller in omnet-julia.
- XS-5 holds as a small clean-up and is the first step of XS-1 to XS-3, not a proposal of its own.
- XS-6 and XS-9 would remove names or hand-written methods that the owner decided on or that the assistant reads. XS-7 holds for the return value of `show_document!` only. XS-8 needs seven direct calls and one export, not a move of the widgets.

Seen during the check and not in the report:

- Only `show_system_process_tree!` puts a tree of processes into the `SystemProcessFeed` ([SystemProcessProgram.jl:33](../../../source/platform/systemprocess/SystemProcessProgram.jl#L33)). The tree that the explorer makes with its constructor ([ApplicationExplorer.jl:54](../../../source/platform/application/ApplicationExplorer.jl#L54)), and a tree that a `.pred` file builds, are in no feed, so nothing samples them. Read from the code, not run.
- Only four of the eight text formats have a seed for a new file: `make_document_seed` has methods for `.json`, `.xml`, `.jl` and `.sql` ([JsonToSyntax.jl:193](../../../source/domain/json/JsonToSyntax.jl#L193)), so a new `.yaml`, `.md`, `.rst` or `.math` file opens as `DocumentNothing`.
