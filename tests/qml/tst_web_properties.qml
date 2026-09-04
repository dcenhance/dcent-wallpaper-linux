import QtQuick
import QtTest
import "../../plasma-plugin/contents/ui/WebProperties.js" as WebProperties

TestCase {
    name: "WebProperties"

    readonly property var sourceSpec: ({
        name: "backgroundSource",
        type: "combo",
        default: "",
        presetValue: "",
        webValue: "slideshow"
    })
    readonly property var folderSpec: ({
        name: "slideshowFolder",
        type: "directory",
        webValue: "",
        condition: "backgroundSource.value == '' || backgroundSource.value == 'slideshow'"
    })

    function test_empty_slideshow_falls_back_to_builtin_background() {
        compare(WebProperties.effectiveValue(
            sourceSpec, [sourceSpec, folderSpec],
            {backgroundSource: "slideshow", slideshowFolder: ""}
        ), "")
    }

    function test_slideshow_with_selected_folder_is_preserved() {
        compare(WebProperties.effectiveValue(
            sourceSpec, [sourceSpec, folderSpec],
            {backgroundSource: "slideshow", slideshowFolder: "/tmp/pictures"}
        ), "slideshow")
    }

    function test_unrelated_choice_is_not_modified() {
        const spec = {name: "quality", type: "combo", default: "high", presetValue: "high", webValue: "low"}
        compare(WebProperties.effectiveValue(spec, [spec], {quality: "low"}), "low")
    }
}
