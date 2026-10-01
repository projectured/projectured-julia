# Acronyms in capitals in the package names

## 1. Goal

The packages whose name holds an acronym write it in capitals, as the Julia
ecosystem does (`JSON.jl`, `YAML.jl`, `ODBC.jl`): `ProjecturedJson` is
`ProjecturedJSON`. This is R29 of
[release-the-binary-and-the-packages.md](release-the-binary-and-the-packages.md),
which the maintainers of the General registry asked for. The owner deferred it
on 2026-09-30 and asked for it on 2026-10-01: "Let's do the package renames
now". It must come before the first registration anywhere, because a new name
is a new package for each user.

## 2. Facts (2026-10-01, `main` at `d09dc611d`)

- Twelve packages hold an acronym, and eighteen of their test and example
  packages follow them: 30 package folders in all.
- The name appears in 226 files of this repository (1,366 times outside the
  recorded precompile statements), in 46 files of omnet-julia and in 15 of
  inet-julia.
- The branch `appearance` of another session is open; it changes files of
  `ProjecturedSdl`, so it must follow the rename of that folder.

## 3. The names

| Now | New |
| --- | --- |
| `ProjecturedJson` | `ProjecturedJSON` |
| `ProjecturedYaml` | `ProjecturedYAML` |
| `ProjecturedXml` | `ProjecturedXML` |
| `ProjecturedRst` | `ProjecturedRST` |
| `ProjecturedSql` | `ProjecturedSQL` |
| `ProjecturedDbCatalog` | `ProjecturedDBCatalog` |
| `ProjecturedFsm` | `ProjecturedFSM` |
| `ProjecturedSdl` | `ProjecturedSDL` |
| `ProjecturedPdf` | `ProjecturedPDF` |
| `ProjecturedMcp` | `ProjecturedMCP` |
| `ProjecturedOdbc` | `ProjecturedODBC` |
| `ProjecturedRepl` | `ProjecturedREPL` |

Each `…Test` and `…Example` package follows its package. The uuids stay.

**Only the names of the packages change** (my reading of "package renames";
the owner can widen it). The modules, the types, the functions, the files and
the folders of `source/` keep their names: `ProjecturedJSON` holds `JsonModule`
in `source/domain/json/`, with `JsonDocument` and `test_json()`. The naming
rules derive those from the lower-case slice, which does not change.
`DbCatalog` → `DBCatalog` follows `DBInterface.jl`; `ProjecturedREPL` is not
registered but keeps the rule for all. `ProjecturedJulia` stays: the rule
against "Julia" in a name is a separate question.

## 4. Steps

- [x] **Step 1, the rename.** A script moves the 30 package folders and their
      entry files, and replaces each old name by the new one in every file
      outside `plan/`: the `Project.toml` files, the code, the scripts, CI, the
      documents and the recorded precompile statements. The tracked manifest
      of `environment/all` follows, and `Pkg.resolve` checks it.
      Done: 30 folders moved, 226 files changed; no sealed file names a
      package of the list, so none changed. `Pkg.resolve` accepts the manifest
      as the text substitution left it. One rule of the naming guard derived
      the name of a suite file from the name of the test package
      (`ProjecturedJSONTest` asked for `JSONSuite.jl`); it now compares with
      the slice regardless of case, because the case of a slice is the case of
      its module (`JsonSuite.jl` beside `JsonModule`). The example of an
      extension in `naming-rules.md` is `ProjecturedSQLSQLiteExt`. No code
      builds a package name from a slice name.
- [ ] **Step 2, the check.** The guards, a precompile of `environment/all`, and
      the CI-like run of the 28 jobs, against the CI-like run of `main`.
- [x] **Step 3, downstream.** The same script in omnet-julia and inet-julia, on
      branches of their own; both precompile against this branch.
      Done: the branch `acronym-package-names` of omnet-julia (`74c88707`, 46
      files) and of inet-julia (`0c109c7`, 15 files); no sealed file changed.
      Both precompile against a clone of this branch, every package (100 and
      12), with no package from a main checkout.
- [x] **Step 4, the release plan.** R29 is done.
      Done: the release plan records R28 and R29 as done, so Steps B5 and B6
      wait for R27 alone.

A folder whose name changes only in case (`ProjecturedSdl` → `ProjecturedSDL`)
is a rename that a case-insensitive file system can not do in place; git on
Linux does it, and a fresh clone anywhere has the new names.

## 5. Decisions made during the work

(filled in as the work goes)
