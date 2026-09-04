import QtQuick
import QtTest
import "../../plasma-plugin/contents/ui/WebViewport.js" as WebViewport

TestCase {
    name: "WebViewport"

    function closeEnough(actual, expected) {
        verify(Math.abs(actual - expected) < 0.01, actual + " != " + expected)
    }

    function test_fill_uses_one_centered_reference_canvas_transform() {
        const viewport = WebViewport.compute(3440, 1440, "fill", 1920, 1080)
        closeEnough(viewport.scaleX, 3440 / 1920)
        closeEnough(viewport.scaleY, 3440 / 1920)
        closeEnough(viewport.width, 3440)
        closeEnough(viewport.height, 1935)
        closeEnough(viewport.x, 0)
        closeEnough(viewport.y, -247.5)
    }

    function test_fit_letterboxes_the_same_reference_canvas() {
        const viewport = WebViewport.compute(3440, 1440, "fit", 1920, 1080)
        closeEnough(viewport.scaleX, 1440 / 1080)
        closeEnough(viewport.scaleY, 1440 / 1080)
        closeEnough(viewport.width, 2560)
        closeEnough(viewport.height, 1440)
        closeEnough(viewport.x, 440)
        closeEnough(viewport.y, 0)
    }

    function test_stretch_preserves_reference_coordinates_with_separate_scales() {
        const viewport = WebViewport.compute(1920, 1200, "stretch", 1920, 1080)
        closeEnough(viewport.scaleX, 1)
        closeEnough(viewport.scaleY, 1200 / 1080)
        closeEnough(viewport.width, 1920)
        closeEnough(viewport.height, 1200)
        closeEnough(viewport.x, 0)
        closeEnough(viewport.y, 0)
    }

    function test_invalid_dimensions_fall_back_safely() {
        const viewport = WebViewport.compute(0, 0, "fill", 0, 0)
        compare(viewport.width, 1)
        compare(viewport.height, 1)
        compare(viewport.scaleX, 1)
        compare(viewport.scaleY, 1)
    }
}
