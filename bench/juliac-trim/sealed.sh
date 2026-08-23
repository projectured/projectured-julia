#!/usr/bin/env bash
# Build the sealed compiler experiment from a clean checkout of Julia 1.13.
#
#   ./sealed.sh setup   -- copy and patch the Compiler package and juliac
#   ./sealed.sh build   -- build the abstract six subtype program with it
#   ./sealed.sh compare -- build the same program with the stock juliac
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SHARE="$(julia +1.13 --startup-file=no -e 'print(joinpath(Sys.BINDIR, "..", "share", "julia"))')"

case "${1:-}" in
setup)
    rm -rf "$HERE/SealedCompiler2" "$HERE/sealed-juliac2" "$HERE/env2"
    cp -r "$SHARE/Compiler" "$HERE/SealedCompiler2"
    cp -r "$SHARE/juliac"   "$HERE/sealed-juliac2"
    python3 "$HERE/sealed_patch.py" "$HERE" "$SHARE"
    mkdir -p "$HERE/env2"
    printf '[deps]\nCompiler = "807dbc54-b67e-4c79-8afb-eafe4df6f2e1"\n\n[sources]\nCompiler = {path = "%s/SealedCompiler2"}\n' "$HERE" > "$HERE/env2/Project.toml"
    julia +1.13 --startup-file=no --project="$HERE/env2" -e 'using Pkg; Pkg.instantiate()'
    ;;
build)
    mkdir -p "$HERE/work2"
    julia +1.13 --startup-file=no "$HERE/probe.jl" source abstract 6 > "$HERE/work2/abstract6.jl"
    julia +1.13 --startup-file=no --project="$HERE/env2" "$HERE/sealed-juliac2/juliac.jl" \
        --output-exe "$HERE/work2/abstract6" --experimental --trim=safe "$HERE/work2/abstract6.jl"
    "$HERE/work2/abstract6"; echo "sealed abstract n=6 exit code: $?  (expected 21)"
    ;;
compare)
    mkdir -p "$HERE/work3"
    julia +1.13 --startup-file=no "$HERE/probe.jl" source abstract 6 > "$HERE/work3/abstract6.jl"
    julia +1.13 --startup-file=no "$SHARE/juliac/juliac.jl" \
        --output-exe "$HERE/work3/abstract6" --experimental --trim=safe "$HERE/work3/abstract6.jl" || true
    ;;
*) echo "usage: $0 [setup | build | compare]"; exit 1;;
esac
