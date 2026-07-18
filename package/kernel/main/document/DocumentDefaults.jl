# Fragment of `DocumentModule` — the default answers for the two traits that
# steer `walk_document` (`is_element_collection` / `is_walk_opaque`, declared in
# `DocumentInterface.jl`). The defaults keep the walk from ever naming a concrete
# collection type: a document opts into a shape by overriding one, and the walk
# reads the shape off the trait, so it sits below every collection it descends.

is_element_collection(value) = false
is_walk_opaque(value) = false
