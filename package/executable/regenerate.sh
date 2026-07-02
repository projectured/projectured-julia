#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Regenerate the Projectured native executable with the CURRENT editor spec:
# a workbench, multi-domain (json / xml / sql / julia) file editor — json the
# default/scratch domain — with the SDL backend baked in.
#
# This is a full PackageCompiler `create_app` build: it compiles the whole native
# stack and takes several minutes. All Julia output is written to build.log; only
# the start/end markers print to the terminal.
#
# To rebuild the plain JSON-only v1 default instead, run `julia Build.jl`.
#
# Usage:  ./regenerate.sh
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

cd "$(dirname "$0")"

echo "Regenerating projectured executable (workbench; json/xml/sql/julia; SDL) — logging to build.log ..."

julia --project=. -e '
    include("Builder.jl")
    using .ProjecturedBuilder
    build_executable(; domain=:json,
                       domains=[:json, :xml, :sql, :julia],
                       workbench=true,
                       file_backed=true,
                       backends=[:sdl])
' > build.log 2>&1

echo "Done. Binary: build/bin/projectured"
