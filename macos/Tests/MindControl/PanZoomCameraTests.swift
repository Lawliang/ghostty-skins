#if os(macOS)
import CoreGraphics
import Testing
@testable import Ghostty

private typealias Camera = MindControl.PanZoomCamera

struct PanZoomCameraTests {
    private let view = CGSize(width: 800, height: 600)

    @Test func screenWorldRoundTrip() {
        let camera = Camera(center: CGPoint(x: 120, y: -40), zoom: 1.7)
        let world = CGPoint(x: 333, y: 21)
        let back = camera.toWorld(camera.toScreen(world, viewSize: view), viewSize: view)
        #expect(abs(back.x - world.x) < 1e-9 && abs(back.y - world.y) < 1e-9)
        #expect(camera.toScreen(camera.center, viewSize: view) == CGPoint(x: 400, y: 300))
    }

    @Test func zoomKeepsThePointUnderTheCursor() {
        var camera = Camera(center: .zero, zoom: 1)
        let cursor = CGPoint(x: 650, y: 120)
        let before = camera.toWorld(cursor, viewSize: view)
        camera.zoom(by: 2.5, about: cursor, viewSize: view)
        let after = camera.toWorld(cursor, viewSize: view)
        #expect(abs(before.x - after.x) < 1e-9 && abs(before.y - after.y) < 1e-9)
        #expect(camera.zoom == 2.5)
    }

    @Test func zoomIsClamped() {
        var camera = Camera(center: .zero, zoom: 1)
        camera.zoom(by: 1000, about: .zero, viewSize: view)
        #expect(camera.zoom == Camera.maxZoom)
        camera.zoom(by: 0.00001, about: .zero, viewSize: view)
        #expect(camera.zoom == Camera.minZoom)
    }

    @Test func panMovesOppositeToTheDrag() {
        var camera = Camera(center: .zero, zoom: 2)
        camera.pan(byScreen: CGSize(width: 100, height: -40))
        #expect(camera.center == CGPoint(x: -50, y: 20))
    }

    @Test func fitShowsTheWholeRect() {
        let rect = CGRect(x: -500, y: 100, width: 2000, height: 400)
        let camera = Camera.fitting(rect, in: view)
        let topLeft = camera.toScreen(CGPoint(x: rect.minX, y: rect.minY), viewSize: view)
        let bottomRight = camera.toScreen(CGPoint(x: rect.maxX, y: rect.maxY), viewSize: view)
        #expect(topLeft.x >= 0 && topLeft.y >= 0 && bottomRight.x <= view.width && bottomRight.y <= view.height)
        #expect(camera.center == CGPoint(x: rect.midX, y: rect.midY))
    }

    @Test func interpolationHitsBothEnds() {
        let a = Camera(center: .zero, zoom: 0.5), b = Camera(center: CGPoint(x: 100, y: 50), zoom: 2)
        #expect(Camera.interpolate(a, b, t: 0) == a)
        #expect(Camera.interpolate(a, b, t: 1) == b)
        #expect(abs(Camera.interpolate(a, b, t: 0.5).zoom - 1) < 1e-9)
    }

    // MARK: - The camera never goes non-finite

    private static func isFinite(_ camera: Camera) -> Bool {
        camera.center.x.isFinite && camera.center.y.isFinite && camera.zoom.isFinite
            && camera.zoom >= Camera.minZoom && camera.zoom <= Camera.maxZoom
    }

    @Test func zoomFactorsThatAreNotPositiveNumbersChangeNothing() {
        let start = Camera(center: CGPoint(x: 30, y: -12), zoom: 1.3)
        for factor: CGFloat in [0, -2, .nan, .infinity, -.infinity] {
            var camera = start
            camera.zoom(by: factor, about: CGPoint(x: 650, y: 120), viewSize: view)
            #expect(camera == start, "factor \(factor)")
        }
    }

    @Test func zoomAboutANonFinitePointOrViewChangesNothing() {
        let start = Camera(center: CGPoint(x: 30, y: -12), zoom: 1.3)
        let cases: [(CGPoint, CGSize)] = [
            (CGPoint(x: CGFloat.nan, y: 0), view),
            (CGPoint(x: 0, y: CGFloat.infinity), view),
            (CGPoint(x: 10, y: 10), CGSize(width: CGFloat.nan, height: 600)),
            (CGPoint(x: 10, y: 10), CGSize(width: 800, height: CGFloat.infinity)),
            (CGPoint(x: CGFloat.greatestFiniteMagnitude, y: 0), view),
        ]
        for (point, size) in cases {
            var camera = start
            camera.zoom(by: 0.5, about: point, viewSize: size)
            #expect(camera == start, "about \(point) in \(size)")
        }
    }

    @Test func zoomBeforeTheViewHasASizeStaysFinite() {
        var camera = Camera(center: CGPoint(x: 5, y: 5), zoom: 1)
        camera.zoom(by: 2, about: .zero, viewSize: .zero)
        #expect(camera.zoom == 2)
        #expect(camera.center == CGPoint(x: 5, y: 5))
    }

    @Test func panByANonFiniteOrOverflowingDeltaChangesNothing() {
        let start = Camera(center: CGPoint(x: 30, y: -12), zoom: Camera.minZoom)
        for delta in [CGSize(width: CGFloat.nan, height: 0), CGSize(width: 0, height: CGFloat.infinity),
                      CGSize(width: CGFloat.greatestFiniteMagnitude, height: 1)] {
            var camera = start
            camera.pan(byScreen: delta)
            #expect(camera == start, "delta \(delta)")
        }
    }

    @Test func constructionKeepsTheCameraFiniteAndInRange() {
        #expect(Camera() == Camera(center: .zero, zoom: 1))
        #expect(Camera(center: CGPoint(x: CGFloat.nan, y: 3), zoom: .nan) == Camera(center: .zero, zoom: 1))
        #expect(Camera(center: CGPoint(x: 1, y: CGFloat.infinity), zoom: 1).center == .zero)
        #expect(Camera(center: .zero, zoom: 0).zoom == Camera.minZoom)
        #expect(Camera(center: .zero, zoom: -3).zoom == Camera.minZoom)
        #expect(Camera(center: .zero, zoom: 100).zoom == Camera.maxZoom)
    }

    @Test func assignmentKeepsTheCameraFiniteAndInRange() {
        var camera = Camera(center: CGPoint(x: 7, y: 8), zoom: 1.5)
        camera.zoom = .nan
        #expect(camera.zoom == 1.5)
        camera.zoom = 0
        #expect(camera.zoom == Camera.minZoom)
        camera.zoom = 9
        #expect(camera.zoom == Camera.maxZoom)
        camera.center = CGPoint(x: CGFloat.infinity, y: 0)
        #expect(camera.center == CGPoint(x: 7, y: 8))
        camera.center.y = .nan
        #expect(camera.center == CGPoint(x: 7, y: 8))
    }

    @Test func toWorldBeforeTheViewHasASize() {
        let camera = Camera(center: CGPoint(x: 10, y: 20), zoom: 2)
        let world = camera.toWorld(.zero, viewSize: .zero)
        #expect(world == camera.center)
        #expect(camera.toWorld(CGPoint(x: 40, y: -6), viewSize: .zero) == CGPoint(x: 30, y: 17))
        #expect(camera.toScreen(camera.toWorld(CGPoint(x: 40, y: -6), viewSize: .zero), viewSize: .zero) == CGPoint(x: 40, y: -6))
    }

    @Test func fittingAnEmptyOrNonFiniteRectGivesTheDefaultCamera() {
        // An empty MapLayout's bounds are CGRect.null.
        for rect in [CGRect.null, CGRect.infinite, CGRect(x: CGFloat.nan, y: 0, width: 10, height: 10),
                     CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 10)] {
            let camera = Camera.fitting(rect, in: view)
            #expect(camera == Camera(), "rect \(rect)")
        }
    }

    @Test func fittingBeforeTheViewHasASizeCentresAtZoomOne() {
        let rect = CGRect(x: 0, y: 0, width: 300, height: 100)
        for size in [CGSize.zero, CGSize(width: 0, height: 600), CGSize(width: CGFloat.nan, height: 600),
                     CGSize(width: CGFloat.infinity, height: 600)] {
            let camera = Camera.fitting(rect, in: size)
            #expect(camera == Camera(center: CGPoint(x: 150, y: 50), zoom: 1), "view \(size)")
        }
    }

    @Test func fittingClampsTheZoom() {
        #expect(Camera.fitting(CGRect(x: 0, y: 0, width: 1, height: 1), in: view).zoom == Camera.maxZoom)
        #expect(Camera.fitting(CGRect(x: 0, y: 0, width: 1e7, height: 1e7), in: view).zoom == Camera.minZoom)
    }

    @Test func fittingAPointOrALine() {
        #expect(Camera.fitting(CGRect(x: 40, y: 60, width: 0, height: 0), in: view) == Camera(center: CGPoint(x: 40, y: 60), zoom: 1))
        let line = Camera.fitting(CGRect(x: 40, y: 0, width: 0, height: 400), in: view)
        #expect(line.center == CGPoint(x: 40, y: 200))
        #expect(abs(line.zoom - (600 - 112) / 400) < 1e-12)
    }

    @Test func marginsThatWouldEatTheViewAreDropped() {
        let small = CGSize(width: 100, height: 80)
        let rect = CGRect(x: 0, y: 0, width: 200, height: 100)
        let camera = Camera.fitting(rect, in: small)
        #expect(abs(camera.zoom - 0.5) < 1e-12)
        let wide = CGRect(x: 0, y: 0, width: 400, height: 300)
        for margin: CGFloat in [.nan, .infinity] {
            #expect(abs(Camera.fitting(wide, in: view, margin: margin).zoom - 2) < 1e-12, "margin \(margin)")
        }
    }

    @Test func interpolationWithAnOddTime() {
        let a = Camera(center: .zero, zoom: 0.5), b = Camera(center: CGPoint(x: 100, y: 50), zoom: 2)
        #expect(Camera.interpolate(a, b, t: -.infinity) == a)
        #expect(Camera.interpolate(a, b, t: .infinity) == b)
        // A zero-length animation gives 0 / 0: land on the target.
        #expect(Camera.interpolate(a, b, t: .nan) == b)
        let far = Camera(center: CGPoint(x: -CGFloat.greatestFiniteMagnitude, y: 0), zoom: 1)
        let farOther = Camera(center: CGPoint(x: CGFloat.greatestFiniteMagnitude, y: 0), zoom: 1)
        let between = Camera.interpolate(far, farOther, t: 0.25)
        #expect(Self.isFinite(between))
        #expect(abs(between.center.x + CGFloat.greatestFiniteMagnitude / 2) <= CGFloat.greatestFiniteMagnitude * 1e-15)
    }
}
#endif
