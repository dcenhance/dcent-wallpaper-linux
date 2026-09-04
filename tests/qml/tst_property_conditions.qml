import QtQuick
import QtTest
import "../../plasma-plugin/contents/ui/PropertyConditions.js" as Conditions

TestCase {
    name: "WallpaperPropertyConditions"

    property var values: ({
        enabled: { value: true, min: 0, max: 1, text: "Enabled" },
        amount: { value: 7, min: 0, max: 10, text: "Amount" },
        mode: { value: "advanced", text: "Mode" }
    })

    function test_boolean_and_numeric_comparisons() {
        verify(Conditions.evaluate("enabled.value && amount.value >= 5", values))
        verify(!Conditions.evaluate("!enabled.value || amount.value < 5", values))
        verify(Conditions.evaluate("amount.value < 0.9 * amount.max", values))
    }

    function test_string_and_array_helpers() {
        verify(Conditions.evaluate("mode.value.startsWith('adv')", values))
        verify(Conditions.evaluate("['basic', 'advanced'].includes(mode.value)", values))
        verify(!Conditions.evaluate("['basic'].includes(mode.value)", values))
    }

    function test_parentheses_and_strict_equality() {
        verify(Conditions.evaluate("(enabled.value === true) && (mode.value !== 'basic')", values))
        verify(Conditions.evaluate("enabled.value == true;", values))
    }

    function test_unsupported_side_effects_fail_open_without_execution() {
        verify(!Conditions.isSupported("enabled.value ? amount.text = 'bad' : amount.text = 'worse'"))
        verify(Conditions.evaluate("enabled.value ? amount.text = 'bad' : amount.text = 'worse'", values))
        compare(values.amount.text, "Amount")
    }

    function test_unknown_global_is_not_executed() {
        verify(!Conditions.isSupported("Qt.quit()"))
        verify(Conditions.evaluate("Qt.quit()", values))
    }
}
