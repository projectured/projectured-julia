# ═══════════════════════════════════════════════════════════════════════════
# test/editor/NavigationPresets.jl
#
# The visual-tier instantiations of the generic navigation driver
# (`ProjecturedKernelTest.explore_selections` / `test_navigation`). Both gesture
# vocabularies preset here are handled by visual-tier readers — the text domain
# resolves the character / word / line position moves, the syntax domain the
# Alt+arrow structural moves — so this is their lowest home. A later domain
# (e.g. vector collections) adds its own preset in its own tier the same way,
# pairing a gesture set with a ground-truth enumerator.
#
# * position navigation — positions between elements (PositionReferenceStep; in the
#   text domain these are the carets): explore_position_selections,
#   test_position_navigation.
# * tree navigation — whole-element (∅) selections on structural nodes:
#   explore_tree_selections, test_tree_navigation.
# ═══════════════════════════════════════════════════════════════════════════

# Position navigation: character / word / line / document moves.
const POSITION_NAV_KEYS = [
    KeyDown(:left,  ModifierKeys()),
    KeyDown(:right, ModifierKeys()),
    KeyDown(:up,    ModifierKeys()),
    KeyDown(:down,  ModifierKeys()),
    KeyDown(:home,  ModifierKeys()),
    KeyDown(:end,   ModifierKeys()),
    KeyDown(:home,  ModifierKeys(ctrl=true)),
    KeyDown(:end,   ModifierKeys(ctrl=true)),
    KeyDown(:left,  ModifierKeys(ctrl=true)),
    KeyDown(:right, ModifierKeys(ctrl=true)),
]
const POSITION_SEED_GESTURE = KeyDown(:home, ModifierKeys(ctrl=true))

# Tree navigation: Alt+arrow structural moves. The seed Ctrl+Alt+Home is
# recognised and resolved at the syntax layer, selecting the root ∅.
const TREE_NAV_KEYS = [
    KeyDown(:up,    ModifierKeys(alt=true)),
    KeyDown(:down,  ModifierKeys(alt=true)),
    KeyDown(:left,  ModifierKeys(alt=true)),
    KeyDown(:right, ModifierKeys(alt=true)),
]
const TREE_SEED_GESTURE = KeyDown(:home, ModifierKeys(ctrl=true, alt=true))

explore_position_selections(document, projection, initial_selection=nothing; onstate=nothing) =
    explore_selections(document, projection;
                       nav_keys=POSITION_NAV_KEYS, seed_gesture=POSITION_SEED_GESTURE,
                       initial_selection=initial_selection, onstate=onstate)

explore_tree_selections(document, projection; onstate=nothing) =
    explore_selections(document, projection;
                       nav_keys=TREE_NAV_KEYS, seed_gesture=TREE_SEED_GESTURE,
                       onstate=onstate)

# One @test per reachable position state. When `check_reaches_all=true`,
# additionally assert navigation reaches every position enumerated directly from
# the document (subset: enumerated ⊆ reachable); the default ground truth is the
# generic document walk `collect_position_selections`.
function test_position_navigation(label, document, projection, initial_selection=nothing;
                                  check_reaches_all=false, collect=collect_position_selections,
                                  seed_broken=nothing, broken=nothing, unreached_broken=nothing,
                                  throws_broken=nothing)
    test_navigation(label, document, projection;
                    nav_keys=POSITION_NAV_KEYS, seed_gesture=POSITION_SEED_GESTURE,
                    initial_selection=initial_selection,
                    check_reaches_all=check_reaches_all, collect=collect,
                    seed_broken=seed_broken, broken=broken, unreached_broken=unreached_broken,
                    throws_broken=throws_broken)
end

# The `Example`-typed overload; the all-examples sweeps stay in the umbrella,
# which owns the example registry.
test_position_navigation(example::Example; check_reaches_all=false) =
    test_position_navigation(example.name, example.document, example.projection;
                             check_reaches_all=check_reaches_all)

# One @test per reachable whole-element state. `is_node` selects which nodes the
# default ground-truth enumerator counts as structurally selectable; `collect`
# overrides the enumerator entirely (domains whose document is not a native
# syntax tree pass a projection-aware one, e.g. JSON passes
# `collect_json_tree_selections`, which mirrors JsonToSyntax's decomposition).
function test_tree_navigation(label, document, projection;
                              check_reaches_all=false, is_node=nothing, collect=nothing,
                              seed_broken=nothing, broken=nothing, unreached_broken=nothing,
                              throws_broken=nothing)
    if collect === nothing
        collect = is_node === nothing ? collect_tree_selections :
                  d -> collect_tree_selections(d; is_node=is_node)
    end
    test_navigation(label, document, projection;
                    nav_keys=TREE_NAV_KEYS, seed_gesture=TREE_SEED_GESTURE,
                    check_reaches_all=check_reaches_all, collect=collect,
                    seed_broken=seed_broken, broken=broken, unreached_broken=unreached_broken,
                    throws_broken=throws_broken)
end

# The `Example`-typed overload of `test_tree_navigation` (with its
# projection-aware default enumerator and the syntax-domain `_is_syntax_node`
# predicate) lives in `ProjecturedDomainTest`, which owns the domain documents
# it dispatches on.
