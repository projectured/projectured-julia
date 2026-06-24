/*
 * adaptagrams_shim.cpp — implementation of the flat C ABI in adaptagrams_shim.h.
 *
 * Placement:  libcola  (cola::ConstrainedFDLayout) — force-directed layout with
 *             optional non-overlap, operating on vpsc::Rectangle boxes.
 * Routing:    libavoid (Avoid::Router) — poly-line or orthogonal connector routes
 *             that avoid the node boxes as obstacles.
 *
 * NOTE ON API DRIFT: Adaptagrams has no stable release cadence and a few of the
 * calls below have shifted spelling across revisions (most notably how libcola
 * is told to avoid overlaps, and the vpsc::Rectangle ctor argument order). The
 * calls flagged "VERIFY" compile-check against the actually-installed headers;
 * if the build errors there, adjust to the local signature — the ABI exposed to
 * Julia does not change. Argument order that matters is documented inline.
 */

#include "adaptagrams_shim.h"

#include <vector>
#include <utility>
#include <cmath>
#include <new>

#include "libvpsc/rectangle.h"
#include "libcola/cola.h"
#include "libavoid/libavoid.h"

struct AdaptagramsLayout {
    int n;
    int ne;
    // Placed boxes, top-left origin: (x, y, w, h) per node.
    std::vector<double> x, y, w, h;
    // Per-edge polyline route as flat (x,y) pairs; routes[e] may be empty.
    std::vector<std::vector<double> > routes;  // each inner: x0,y0,x1,y1,...
};

extern "C" int adaptagrams_shim_version(void) { return 1; }

extern "C" AdaptagramsLayout *adaptagrams_layout(int n,
        const double *in_w, const double *in_h,
        int ne,
        const int *edge_src, const int *edge_dst,
        double ideal_length,
        int avoid_overlaps,
        int orthogonal) {
    if (n <= 0) return NULL;
    if (ideal_length <= 0.0) ideal_length = 50.0;

    try {
        AdaptagramsLayout *out = new AdaptagramsLayout();
        out->n = n;
        out->ne = ne;
        out->x.assign(n, 0.0);
        out->y.assign(n, 0.0);
        out->w.assign(n, 0.0);
        out->h.assign(n, 0.0);
        out->routes.assign(ne < 0 ? 0 : ne, std::vector<double>());

        // ── Placement (libcola) ──────────────────────────────────────────────
        // Seed boxes on a coarse grid so the force model does not start fully
        // degenerate (all-at-origin collapses to NaN). vpsc::Rectangle takes
        // (minX, maxX, minY, maxY) — note the x-pair-then-y-pair order. VERIFY.
        const int cols = (int)std::ceil(std::sqrt((double)n));
        std::vector<vpsc::Rectangle *> rs;
        rs.reserve(n);
        for (int i = 0; i < n; ++i) {
            double bw = (in_w && in_w[i] > 0.0) ? in_w[i] : 60.0;
            double bh = (in_h && in_h[i] > 0.0) ? in_h[i] : 30.0;
            int c = i % cols, r = i / cols;
            double cx = c * (ideal_length + bw);
            double cy = r * (ideal_length + bh);
            rs.push_back(new vpsc::Rectangle(cx, cx + bw, cy, cy + bh));
        }

        std::vector<cola::Edge> es;
        es.reserve(ne > 0 ? ne : 0);
        for (int e = 0; e < ne; ++e) {
            int s = edge_src ? edge_src[e] : -1;
            int t = edge_dst ? edge_dst[e] : -1;
            if (s < 0 || s >= n || t < 0 || t >= n || s == t) continue;
            es.push_back(cola::Edge((unsigned)s, (unsigned)t));
        }

        {
            cola::ConstrainedFDLayout alg(rs, es, ideal_length);
            // VERIFY: overlap avoidance spelling. Current libcola exposes
            // setAvoidNodeOverlaps(bool); older trees used a ctor flag.
            if (avoid_overlaps) alg.setAvoidNodeOverlaps(true);
            alg.run();
        }

        for (int i = 0; i < n; ++i) {
            // getMinX/getMinY give the top-left; width()/height() the size.
            out->x[i] = rs[i]->getMinX();
            out->y[i] = rs[i]->getMinY();
            out->w[i] = rs[i]->width();
            out->h[i] = rs[i]->height();
        }

        // ── Routing (libavoid) ───────────────────────────────────────────────
        {
            Avoid::Router router(orthogonal ? Avoid::OrthogonalRouting
                                            : Avoid::PolyLineRouting);
            // Each placed box is an obstacle. ShapeRef ids must be unique and
            // nonzero; use i+1. Avoid::Rectangle(topLeft, bottomRight) where
            // top-left has the smaller y in this coordinate system.
            for (int i = 0; i < n; ++i) {
                Avoid::Point tl(out->x[i], out->y[i]);
                Avoid::Point br(out->x[i] + out->w[i], out->y[i] + out->h[i]);
                Avoid::Rectangle poly(tl, br);
                new Avoid::ShapeRef(&router, poly, (unsigned)(i + 1));
            }

            // One connector per (valid) edge, centre-to-centre. ConnRef ids are
            // a separate id space; use e+1. Keep a parallel index so we can map
            // routes back to the original edge slot.
            std::vector<Avoid::ConnRef *> conns(ne, (Avoid::ConnRef *)0);
            for (int e = 0; e < ne; ++e) {
                int s = edge_src ? edge_src[e] : -1;
                int t = edge_dst ? edge_dst[e] : -1;
                if (s < 0 || s >= n || t < 0 || t >= n || s == t) continue;
                Avoid::Point sp(out->x[s] + out->w[s] / 2.0,
                                out->y[s] + out->h[s] / 2.0);
                Avoid::Point tp(out->x[t] + out->w[t] / 2.0,
                                out->y[t] + out->h[t] / 2.0);
                conns[e] = new Avoid::ConnRef(&router,
                                              Avoid::ConnEnd(sp),
                                              Avoid::ConnEnd(tp),
                                              (unsigned)(e + 1));
            }

            router.processTransaction();

            for (int e = 0; e < ne; ++e) {
                if (!conns[e]) continue;
                const Avoid::PolyLine &route = conns[e]->displayRoute();
                std::vector<double> &dst = out->routes[e];
                dst.reserve(route.size() * 2);
                for (size_t k = 0; k < route.size(); ++k) {
                    dst.push_back(route.ps[k].x);
                    dst.push_back(route.ps[k].y);
                }
            }
            // router goes out of scope; it owns and deletes its Shape/ConnRefs.
        }

        for (int i = 0; i < n; ++i) delete rs[i];
        return out;
    } catch (const std::exception &) {
        return NULL;
    } catch (...) {
        return NULL;
    }
}

extern "C" int adaptagrams_node_count(const AdaptagramsLayout *h) {
    return h ? h->n : 0;
}

extern "C" int adaptagrams_edge_count(const AdaptagramsLayout *h) {
    return h ? h->ne : 0;
}

extern "C" void adaptagrams_node_box(const AdaptagramsLayout *h, int i,
                                     double *x, double *y, double *w, double *hgt) {
    if (!h || i < 0 || i >= h->n) return;
    if (x) *x = h->x[i];
    if (y) *y = h->y[i];
    if (w) *w = h->w[i];
    if (hgt) *hgt = h->h[i];
}

extern "C" int adaptagrams_route_size(const AdaptagramsLayout *h, int e) {
    if (!h || e < 0 || e >= (int)h->routes.size()) return 0;
    return (int)(h->routes[e].size() / 2);
}

extern "C" void adaptagrams_route_point(const AdaptagramsLayout *h, int e, int k,
                                        double *x, double *y) {
    if (!h || e < 0 || e >= (int)h->routes.size()) return;
    const std::vector<double> &r = h->routes[e];
    size_t idx = (size_t)k * 2;
    if (idx + 1 >= r.size()) return;
    if (x) *x = r[idx];
    if (y) *y = r[idx + 1];
}

extern "C" void adaptagrams_free(AdaptagramsLayout *h) {
    delete h;
}
