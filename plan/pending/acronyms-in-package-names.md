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

## 2. Facts (2026-10-01, `main` at `c45e0eaa0`)

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

- [ ] **Step 1, the rename.** A script moves the 30 package folders and their
      entry files, and replaces each old name by the new one in every file
      outside `plan/`: the `Project.toml` files, the code, the scripts, CI, the
      documents and the recorded precompile statements. The tracked manifest
      of `environment/all` follows, and `Pkg.resolve` checks it.
- [ ] **Step 2, the check.** The guards, a precompile of `environment/all`, and
      the CI-like run of the 28 jobs, against the CI-like run of `main`.
- [ ] **Step 3, downstream.** The same script in omnet-julia and inet-julia, on
      branches of their own; both precompile against this branch.
- [ ] **Step 4, the release plan.** R29 is done.

A folder whose name changes only in case (`ProjecturedSdl` → `ProjecturedSDL`)
is a rename that a case-insensitive file system can not do in place; git on
Linux does it, and a fresh clone anywhere has the new names.

## 5. Decisions made during the work

(filled in as the work goes)
