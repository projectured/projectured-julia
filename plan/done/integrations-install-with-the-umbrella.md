# The integrations install with the umbrella

> **Superseded on 2026-10-02.** The owner rejected this design (B), because
> `add ProjecturedODBC` must bring ODBC. The design that replaced it is
> [auto-integrations.md](auto-integrations.md). The code of this plan stayed on
> the branch `integration-shells`, which is removed.

## 1. Goal

The owner, 2026-10-02: a new user types

```
pkg> add Projectured DataFrames SimpleDirectMediaLayer
julia> using SimpleDirectMediaLayer, DataFrames, Projectured
julia> display_in_editor(df)
```

and the table opens. `add Projectured` installs no third-party package of an
integration: SDL2 comes only with SimpleDirectMediaLayer, which the user adds.
Without the umbrella, `using DataFrames, ProjecturedDataFrames` still works.
The owner chose design B ("do B then").

## 2. Facts (2026-10-02, `julia-112` at `6c47fb276`)

- The umbrella's six extensions (`ProjecturedSimpleDirectMediaLayerExt`, …) only
  call `load_installed_package!("ProjecturedSDL")`. The integration is a
  `[weakdeps]` entry of the umbrella, and Pkg never installs a weak dependency,
  so for a new user there is nothing to load. A test in an empty depot showed
  it: "No loaded package shows a value of type DataFrame". On the owner's
  machine it worked, because `@v1.13` held the integrations and
  `identify_package` searches the whole load path.
- The six integrations:

  | Package | Third-party | Other ProjecturEd deps | Code |
  | --- | --- | --- | --- |
  | `ProjecturedSDL` | SimpleDirectMediaLayer, SDL2_jll, Xorg_libX11_jll | kernel, platform | 4544 lines, 2 files |
  | `ProjecturedVideo` | FFMPEG | kernel, platform, SDL | 819 lines, 3 files |
  | `ProjecturedDataFrames` | DataFrames | kernel, platform | 1753 lines, 11 files |
  | `ProjecturedODBC` | ODBC, DBInterface, Tables | kernel, platform, SQL, Database, DBCatalog | 589 lines, 5 files |
  | `ProjecturedTulip` | Tulip, MathOptInterface | platform | 266 lines, 2 files |
  | `ProjecturedMCP` | ModelContextProtocol | kernel | 262 lines, 2 files |

- Julia gives the names of an extension to no `using`: code reaches them by
  `Base.get_extension(Package, :ExtensionName)`.
- `SdlBackend` is used in 18 files here and 40 downstream, always as a call
  `SdlBackend(…)`; the only type uses are generated precompile statements
  downstream, which a precompile run writes again.
- `default_backend()` finds a backend by the name of its type among the loaded
  modules, and an extension is a loaded module.
- `ProjecturedVideo` uses `SdlBackend(…)` and `write_image`, a function of the
  kernel, and no other name of SDL.

## 3. The design

- **An integration package keeps its name and installs with the umbrella.** Its
  third-party packages become `[weakdeps]`, and its code moves into one
  extension, `<Package><Dependency>Ext` (the naming rule), which Julia loads
  when the third-party package is loaded too.
- **Its main module holds only what needs no third-party package**: the names
  that a user calls. `ProjecturedSDL.SdlBackend` is a function that builds the
  `SdlBackend` of the extension, and says to load SimpleDirectMediaLayer when it
  is not loaded. A user's code does not change.
- **Its main module loads nothing heavy.** The ProjecturEd packages that only
  its extension needs (the three domains of ODBC) stay in its `[deps]`, so they
  install, and only the extension loads them.
- **`Projectured` depends on the six packages** and imports them, so they load
  with it, and their extensions switch on with their third-party packages. The
  umbrella's own six extensions go; `load_installed_package!` stays for the
  domains, the console, PDF and the model adapters.
- **Tests and examples** reach an extension's names with `Base.get_extension`.

## 4. Steps

- [x] **Step 1, DataFrames, and the tools.** Shell and extension
      `ProjecturedDataFramesDataFramesExt`; its tests reach the names with
      `Base.get_extension`, and its layering guard walks from the extension
      file. The tools that read the `include` of an entry file also read
      `ext/`: the release copy, `get_package_source_root`, the package graph,
      the naming guard and the tree guard. `environment/all` resolved again,
      because Julia reads the extensions of a developed package from its
      manifest. `test_dataframes()` 272 of 272; `test_package_release()` 61
      and 119; the release copy holds the slice and includes
      `../source/adapter/dataframes/…` from `ext/`.
- [x] **Step 2, SDL and Video.** Shells and extensions, `SdlBackend` as a
      function; the builder's table of backends; their tests. Done: the SDL
      suite gives only the 7 failures of `main` (`PointerShapeTest`), Video 74
      of 74, `test_builder()` 425 of 425, `test_repository()` 370 of 370,
      `environment/all` precompiles.
- [x] **Step 3, ODBC, Tulip, MCP.** The same. Done: ODBC 41 of 41, Tulip 14
      of 14, MCP 440 of 440, the builder 425 (the binary also imports
      ModelContextProtocol), `test_repository()` 370. ODBC keeps SQL, Database
      and DBCatalog in its `[deps]`: they install with it and only its
      extension loads them. Its extension switches on with ODBC, DBInterface
      and Tables, and Tulip's with Tulip and MathOptInterface; ODBC.jl and
      Tulip.jl load the others.
- [x] **Step 4, the umbrella.** `[deps]` on the six, its six extensions go, the
      integration test of the two ways; the guides. Done: the umbrella imports
      the six, one per line (the package graph reads the first name of an
      `import`); the loading test reports the extensions that switch on, and its
      case of a user's environment (the umbrella and SimpleDirectMediaLayer)
      now switches SDL on. `test_repository()` 370, `test_builder()` 431, the
      guards give only the findings of `main`. The own-project guide, the
      package and naming rules, the system anatomy, and the documents of the
      domain slice, SDL, Video, ODBC, Tulip, MCP and the builder follow.
- [ ] **Step 5, the check.** The suites of the six and the umbrella,
      omnet-julia and inet-julia precompile, and the new user's lines in an
      empty depot for SDL with DataFrames.

## 5. Decisions made during the work

### 5.1 The names of a shell call the extension

`ProjecturedSDL` keeps its ten exported names. `write_image` is the function of
the kernel; each other name is a function of the shell that calls the same name
in the module of the extension, found with `Base.get_extension` and called with
`invokelatest`, because the extension loads after the shell. Without
SimpleDirectMediaLayer a call says to load it. `ProjecturedVideo` does the same
for `encode_frames_to_video!` and `VideoBackend`, and passes on `record_video`
of the kernel. `default_backend()` still finds the type `SdlBackend` of the
extension by its name. A test that uses a type in a signature names the type of
the extension (`SdlModule.GraphicsCanvasToImageFile`).

### 5.2 One trigger for each extension

The SDL extension switches on with SimpleDirectMediaLayer alone. `SDL2_jll` stays
a weak dependency for its bound. `Xorg_libX11_jll` is no dependency: the backend
finds it among the loaded packages to set `XLOCALEDIR`, because `SDL2_jll` loads
it on Linux and on no other system, where a trigger of it would keep the
extension off.

### 5.3 The binary imports the triggers

`write_app_package` and `build_executable` take `triggers`: packages of a
registry that the binary imports so that the extensions of its packages switch
on, with the uuid from their `[weakdeps]`. `PROJECTURED_EXTENSION_TRIGGERS`
names one for each shell that the binary holds.

### 5.4 The loading test sees the scratch environment alone

`test_umbrella_loads_integrations` ran its processes with the default load
path, so a package of the shared environment of the machine (`@v1.13`) stood
in for one that the scratch environment lacks. The processes now run with
`JULIA_LOAD_PATH=@:@stdlib`.
