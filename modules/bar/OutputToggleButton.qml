pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.modules.components
import qs.modules.theme
import qs.modules.services
import qs.config

ToggleButton {
    id: root
    required property var bar

    readonly property string currentOutput: Audio.currentOutputType()

    buttonIcon: currentOutput === "headphones" ? Icons.headphones : Icons.speakerHigh
    tooltipText: currentOutput === "headphones" ? "Switch to speakers" : "Switch to headphones"
    iconTint: currentOutput === "headphones"
    iconFullTint: currentOutput === "headphones"

    onToggle: function () {
        Audio.toggleOutput();
    }
}
