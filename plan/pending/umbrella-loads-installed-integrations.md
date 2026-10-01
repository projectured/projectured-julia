# The umbrella loads the installed integrations

## 1. Goal

The owner, 2026-10-01:

> I want this:
> `using SimpleMediaLayer, DataFrames, Projectured`
> would load ProjecturedSdl ProjecturedDataFrames
>
> `using SimpleMediaLayer, DataFrames, ProjecturedDataFrames, ProjecturedWeb`
> would load only what is listed

and: "cover all integrations". `add Projectured` must not install an
integration: "why would using Projectured mean that it installs SDL2?"

So there are two ways to use ProjecturEd, and the user picks one:

- **With the umbrella.** `using Projectured` loads the integrations that the
  user installed, each when its trigger is loaded too.
- **Without the umbrella.** `using ProjecturedDataFrames, ProjecturedWeb` loads
  what is listed and nothing else.

The owner lifted the rule against package extensions for this use, because the
user can opt out (2026-10-01): "the way I presented the user can absolutely do
that and choose what's best for her".

## 2. Facts (2026-10-01, `main` at `e8be64774`)

- **An extension can not load what is not installed, and Pkg installs only
  `[deps]`.** An extension whose integration package is in `[deps]` makes
  `add Projectured` install it, SDL2 and DataFrames included.
- **An extension can load an installed package that is not its trigger, by the
  environment of the session.** Tested on Julia 1.13 and 1.11, in both orders of
  `using`, with stand-in packages (`/var/tmp/r30/ext/`): inside the extension,
  `Base.identify_package(@__MODULE__, "Loaded")` answers `nothing` for a weak
  dependency that is not a trigger, but `Base.identify_package("Loaded")` finds
  it when the environment of the session has it, and `Base.require(id)` loads
  it. When the package is not installed, the extension does nothing and no
  error shows.
- **Loading is enough to make an integration active.** The platform finds a
  backend with `compute_loaded_subtypes(Backend)` (`default_backend` prefers
  SDL, then Web, then the console), a model adapter by the method
  `make_llm(::Val{:ollama})`, and the MCP server by the methods that
  `McpModule` adds to the agent server. No name has to reach the session of
  the user. To write `SdlBackend()` by hand, the user still needs
  `using ProjecturedSDL`.
- **The integrations and their own dependencies:**

  | Package | Dependencies outside ProjecturEd | Trigger |
  | --- | --- | --- |
  | `ProjecturedSDL` | `SimpleDirectMediaLayer`, `SDL2_jll`, `Xorg_libX11_jll` | `SimpleDirectMediaLayer` |
  | `ProjecturedVideo` | `FFMPEG` (and `ProjecturedSDL`) | `FFMPEG` |
  | `ProjecturedDataFrames` | `DataFrames` | `DataFrames` |
  | `ProjecturedODBC` | `ODBC`, `DBInterface`, `Tables` | `ODBC` |
  | `ProjecturedTulip` | `Tulip`, `MathOptInterface` | `Tulip` |
  | `ProjecturedMCP` | `ModelContextProtocol` | `ModelContextProtocol` |
  | `ProjecturedWeb` | `HTTP`, `JSON3`, `Base64` | open (O1) |
  | `ProjecturedOllama` | `HTTP`, `JSON3` | open (O1) |
  | `ProjecturedAnthropic` | `HTTP`, `JSON3` | open (O1) |
  | `ProjecturedOpenRouter` | `HTTP`, `JSON3` | open (O1) |

  `ProjecturedConsole` and `ProjecturedPDF` have no dependency outside
  ProjecturEd and are `[deps]` of the umbrella already. `ProjecturedAdaptagrams`
  is not released.
- **The rules allow it.** The naming rule names an extension
  `<Package><Dependency>Ext`, and the tree guard allows `ext/` in a package
  folder. No package has one yet. The `Project.toml` of the kernel says that it
  has no extensions; that stays true.
- **The umbrella re-exports a flat namespace** of its own `[deps]`. An
  integration that the extension loads does not join it.

## 3. The design

- **One extension of `Projectured` for each trigger**, named by the rule:
  `ProjecturedSimpleDirectMediaLayerExt`, `ProjecturedFFMPEGExt`,
  `ProjecturedDataFramesExt`, `ProjecturedODBCExt`, `ProjecturedTulipExt`,
  `ProjecturedModelContextProtocolExt`. Its `__init__` loads the integration
  package when the environment of the session has it, and does nothing
  otherwise.
- **The triggers and the integration packages are `[weakdeps]`** of the
  umbrella. A trigger must be one; an integration package is one only for its
  `[compat]` bound, so a user can not mix an umbrella with an integration of
  another release.
- **No load during precompilation.** When the extension runs in a process that
  writes a cache file, it loads nothing, so the cache file of another package
  never depends on what one user installed. Step 3 tests this.
- **One function does the load**, `load_installed_package!(name)` in the
  platform, beside `compute_loaded_subtypes`: it loads the package called
  `name` when the environment of the session has it, and answers the module or
  `nothing`. Each extension calls it once.
- **The release copy** writes `ext/` and the `[weakdeps]`, `[extensions]` and
  `[compat]` of the umbrella; a weak dependency needs a `[compat]` bound in
  General too.
- **The binary** does not change: it lists its packages, and an extension that
  runs in it finds no environment and loads nothing.

## 4. Decisions

The owner accepted both recommendations on 2026-10-01 ("O2: no message", "O1: yes").

| # | Question | Decision |
| --- | --- | --- |
| O1 | Web and the three model adapters have no trigger of their own: all four use `HTTP` and `JSON3`, and the adapters load `HTTP` themselves. | The model adapters: the umbrella loads each one that is installed, with no trigger, in its own `__init__`. Loading one changes nothing until the user asks for it by name (`assistant = :ollama`). Web: no auto-load, because a loaded web backend becomes the default backend when SDL is absent. |
| O2 | Does the umbrella tell the user what it loaded? | No message. |

## 5. Steps

- [ ] **Step 1, the load.** `load_installed_package!` in the platform, with
      its test: an installed package is loaded, a package that is not
      installed gives `nothing`, and a process that writes a cache file loads
      nothing.
- [ ] **Step 2, the extensions.** `ext/` of the umbrella, `[weakdeps]` and
      `[extensions]` in its `Project.toml`, and `environment/all` resolved.
- [ ] **Step 3, the test of the two ways.** A test that starts a new Julia
      process in a scratch environment, for each way and each order of `using`:
      with the umbrella, an installed integration is loaded and one that is not
      installed is not; without it, only what is listed is loaded.
- [ ] **Step 4, the release copy.** The generator copies `ext/` and writes the
      `[compat]` of the weak dependencies; `test_package_release()` covers it.
- [ ] **Step 5, the binary.** Build it, and run the check of the copied
      binary.
- [ ] **Step 6, the guides.** The setup guide and the own-project guide show
      the two ways; `documentation/package/` names the extensions; the naming
      rule loses "No package here has one yet".

## 6. Decisions made during the work

(filled in as the work goes)
