# Rename AutoIntegrations to AutoIntegration

The owner, 2026-10-03: rename the package AutoIntegrations to AutoIntegration,
and its folder beside this checkout too. Nothing is announced yet, so the
registry and the release take the new name with a fresh overwrite.

## What stays

- The uuid `40fd747d-4b08-4b8c-98c4-74a2b6295b1b` and `set_auto_integration!`.
- The table `[auto-integration]` in the `Project.toml` of an integration; it is
  singular already.
- The plans: they are history.

## What changes

| place | what |
| --- | --- |
| the package repository | the name, the module, `src/AutoIntegration.jl`, the README, the test, the licence line, and the table of `LocalPreferences.toml` that it reads, `[AutoIntegration]` |
| the folder beside this checkout | `auto-integrations` becomes `auto-integration` |
| this repository | the `import` of the umbrella, its `[deps]` and `[sources]`, the two environments, the builder (`AUTOINTEGRATION_URL`, the front page, the README of a package, the release workflow), the CI step that places the package, a comment in 30 `Project.toml` files, two tests, about 20 guides, and the guide folder `documentation/package/autointegration/` |
| the statement files | 4 lines of the recording "readme-data-frame" name the module; record it again |
| GitHub | the repository becomes `projectured/AutoIntegration.jl`; GitHub sends the old address to the new one |
| the registry and the release | a fresh overwrite with the new name |
| the site | 2 lines |

## Steps

1. The package repository, on a branch, in a worktree at the new folder name.
   Its test passes.
2. This repository, on a branch, in a sibling worktree. The recording
   "readme-data-frame" again. The tests: the package test of AutoIntegration,
   the integration loading test, `test_package_release()`,
   `test_package_graph()`, `test_naming()` and the documentation test.
3. Land both, and move the folder.
4. Publish, with the owner's word for each push: the GitHub rename, both
   repositories, the site, and the fresh release and registry.
5. A memory note for old branches: they rebase onto the rename.
