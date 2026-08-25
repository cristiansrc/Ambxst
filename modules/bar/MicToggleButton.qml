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

    readonly property bool micMuted: Audio.source?.audio?.muted ?? false

    buttonIcon: micMuted ? Icons.micSlash : Icons.mic
    tooltipText: micMuted ? "Unmute microphone" : "Mute microphone"
    iconTint: micMuted
    iconFullTint: micMuted

    onToggle: function () {
        Audio.toggleMicMute();
    }
}
