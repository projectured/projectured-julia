/*
 * adaptagrams_shim.h — a flat `extern "C"` ABI over Adaptagrams (libcola +
 * libavoid) for ccall from Julia.
 *
 * Adaptagrams' public API is C++ (templates, std::vector, namespaces) and is not
 * directly ccall-able. This shim exposes a tiny stable C ABI: one entry point
 * runs constraint-based placement (libcola) and obstacle-avoiding connector
 * routing (libavoid), returning an opaque handle the caller queries for
 * per-node positions and variable-length per-edge routes, then frees.
 *
 * The two-phase opaque-handle shape avoids two awkward things across the FFI
 * boundary: callbacks into Julia, and pre-guessing buffer sizes for routes
 * whose point counts are only known after routing.
 */
#ifndef ADAPTAGRAMS_SHIM_H
#define ADAPTAGRAMS_SHIM_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Opaque layout result. */
typedef struct AdaptagramsLayout AdaptagramsLayout;

/* ABI version of this shim. Bump on any signature change so the Julia side can
 * sanity-check what it loaded. */
int adaptagrams_shim_version(void);

/*
 * Run placement + routing.
 *
 *   n            number of nodes
 *   in_w, in_h   per-node desired width/height (each length n)
 *   ne           number of edges
 *   edge_src     per-edge source node index, 0-based (length ne)
 *   edge_dst     per-edge target node index, 0-based (length ne)
 *   ideal_length ideal edge length fed to libcola's force model
 *   avoid_overlaps  nonzero → libcola prevents node-box overlaps (via
 *                   makeFeasible, a hard guarantee, not just the soft force)
 *   orthogonal      nonzero → libavoid orthogonal routing, else poly-line
 *   node_margin     gap added to each side of every box during overlap removal,
 *                   so the (padded) boxes drawn downstream also clear each other;
 *                   also the inset of the top-left box from the origin
 *   edge_lengths    optional per-edge multiplier of ideal_length (length ne), so
 *                   the effective ideal length of edge i is
 *                   ideal_length * edge_lengths[i]. Pass NULL for a uniform
 *                   ideal_length on every edge. Lets the caller make edge lengths
 *                   scale with the endpoint node sizes — a fixed ideal_length
 *                   packs large boxes nearly on top of each other.
 *
 * Node indices in edge_src/edge_dst must be in [0, n). Edges referencing an
 * out-of-range node are skipped.
 *
 * Returns a handle on success, or NULL on failure (e.g. n <= 0). Free it with
 * adaptagrams_free.
 */
AdaptagramsLayout *adaptagrams_layout(int n,
                                      const double *in_w, const double *in_h,
                                      int ne,
                                      const int *edge_src, const int *edge_dst,
                                      double ideal_length,
                                      int avoid_overlaps,
                                      int orthogonal,
                                      double node_margin,
                                      const double *edge_lengths);

/* Number of nodes / edges the handle holds (echo of the inputs). */
int adaptagrams_node_count(const AdaptagramsLayout *h);
int adaptagrams_edge_count(const AdaptagramsLayout *h);

/*
 * Placed top-left position and size of node i (0-based). Any of the out
 * pointers may be NULL. No-op if i is out of range.
 */
void adaptagrams_node_box(const AdaptagramsLayout *h, int i,
                          double *x, double *y, double *w, double *hgt);

/* Number of waypoints in the route for edge e (0-based); 0 if e out of range
 * or the edge was skipped. */
int adaptagrams_route_size(const AdaptagramsLayout *h, int e);

/* Waypoint k (0-based) of edge e. No-op (leaves *x,*y untouched) if out of
 * range. */
void adaptagrams_route_point(const AdaptagramsLayout *h, int e, int k,
                             double *x, double *y);

/* Release the handle. NULL is tolerated. */
void adaptagrams_free(AdaptagramsLayout *h);

#ifdef __cplusplus
} /* extern "C" */
#endif

#endif /* ADAPTAGRAMS_SHIM_H */
