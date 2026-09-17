import QtQuick
import QtTest

import "../../plasma-plugin/contents/ui" as Ui

/* The wallpaper reads its favourites/playlists from a base64 config string.
   An unset value (a fresh profile, or a user who never favourited anything)
   used to be parsed as JSON anyway, which logged "JSON.parse: Parse error" for
   every screen on every wallpaper load. */
TestCase {
    id: testCase
    name: "CustomConf"
    when: windowShown

    function test_empty_configuration_yields_an_usable_default() {
        const conf = Ui.Common.loadCustomConf("")
        verify(conf !== null)
        verify(conf.favor instanceof Set)
        compare(conf.favor.size, 0)
    }

    function test_unset_and_blank_configuration_are_both_accepted() {
        for (const value of [undefined, null, "", "   "]) {
            const conf = Ui.Common.loadCustomConf(value)
            verify(conf !== null, "configuration " + JSON.stringify(value) + " must not break the loader")
            verify(conf.favor instanceof Set)
        }
    }

    function test_favourites_round_trip_through_the_configuration_string() {
        const saved = Ui.Common.loadCustomConf("")
        saved.favor.add("1882328803")
        saved.favor.add("3308516304")

        const encoded = Ui.Common.prepareCustomConf({ favor: saved.favor })
        const restored = Ui.Common.loadCustomConf(encoded)

        verify(restored.favor instanceof Set)
        compare(restored.favor.size, 2)
        verify(restored.favor.has("1882328803"))
        verify(restored.favor.has("3308516304"))
    }

    function test_corrupt_configuration_falls_back_instead_of_throwing() {
        const conf = Ui.Common.loadCustomConf(Qt.btoa("not json at all"))
        verify(conf !== null)
        verify(conf.favor instanceof Set)
        compare(conf.favor.size, 0)
    }
}
