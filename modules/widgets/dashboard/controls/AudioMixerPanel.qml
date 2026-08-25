pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import qs.modules.theme
import qs.modules.components
import qs.modules.services
import qs.config

Item {
    id: root

    property int maxContentWidth: 480
    readonly property int contentWidth: Math.min(width, maxContentWidth)
    readonly property real sideMargin: (width - contentWidth) / 2

    property bool showOutput: true  // true = output, false = input

    // ── F3 inline ToggleRow ──
    component ToggleRow: RowLayout {
        id: toggleRowRoot
        property string label: ""
        property bool checked: false
        signal toggled(bool value)
        property bool _updating: false
        onCheckedChanged: {
            if (!_updating && toggleSwitch.checked !== checked) {
                _updating = true;
                toggleSwitch.checked = checked;
                _updating = false;
            }
        }
        Layout.fillWidth: true
        spacing: 8
        Text {
            text: toggleRowRoot.label
            font.family: Config.theme.font
            font.pixelSize: Styling.fontSize(0)
            color: Colors.overBackground
            Layout.fillWidth: true
        }
        Switch {
            id: toggleSwitch
            checked: toggleRowRoot.checked
            onCheckedChanged: {
                if (!toggleRowRoot._updating && checked !== toggleRowRoot.checked) {
                    toggleRowRoot.toggled(checked);
                }
            }
            indicator: Rectangle {
                implicitWidth: 40
                implicitHeight: 20
                x: toggleSwitch.leftPadding
                y: parent.height / 2 - height / 2
                radius: height / 2
                color: toggleSwitch.checked ? Styling.srItem("overprimary") : Colors.surfaceBright
                border.color: toggleSwitch.checked ? Styling.srItem("overprimary") : Colors.outline
                Behavior on color { enabled: Config.animDuration > 0; ColorAnimation { duration: Config.animDuration / 2 } }
                Rectangle {
                    x: toggleSwitch.checked ? parent.width - width - 2 : 2
                    y: 2
                    width: parent.height - 4
                    height: width
                    radius: width / 2
                    color: toggleSwitch.checked ? Colors.background : Colors.overSurfaceVariant
                    Behavior on x { enabled: Config.animDuration > 0; NumberAnimation { duration: Config.animDuration / 2; easing.type: Easing.OutCubic } }
                }
            }
            background: null
        }
    }

    // Scrollable content - fills entire width for scroll/drag
    Flickable {
        id: flickable
        anchors.fill: parent
        contentHeight: contentColumn.implicitHeight
        clip: true

        ColumnLayout {
            id: contentColumn
            width: flickable.width
            spacing: 8

            // Header wrapper
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: titlebar.height

                PanelTitlebar {
                    id: titlebar
                    width: root.contentWidth
                    anchors.horizontalCenter: parent.horizontalCenter
                    title: "Sound"

                    actions: [
                        {
                            icon: Audio.protectionEnabled ? Icons.shieldCheck : Icons.shield,
                            tooltip: Audio.protectionEnabled ? "Volume protection enabled" : "Volume protection disabled",
                            onClicked: function () {
                                Audio.setProtectionEnabled(!Audio.protectionEnabled);
                            }
                        },
                        {
                            icon: Icons.popOpen,
                            tooltip: "Open PipeWire Volume Control",
                            onClicked: function () {
                                Quickshell.execDetached(["pavucontrol"]);
                            }
                        }
                    ]

                    // Output/Input toggle buttons
                    RowLayout {
                        spacing: 4

                        // Output Button
                        StyledRect {
                            id: outputBtn
                            property bool isSelected: root.showOutput
                            property bool isHovered: false

                            variant: isSelected ? "primary" : (isHovered ? "focus" : "common")
                            Layout.preferredHeight: 32
                            Layout.preferredWidth: outputContent.width + 24
                            radius: isSelected ? Styling.radius(-4) : Styling.radius(0)

                            Row {
                                id: outputContent
                                anchors.centerIn: parent
                                spacing: 8

                                Text {
                                    text: Icons.speakerHigh
                                    font.family: Icons.font
                                    font.pixelSize: 14
                                    color: outputBtn.item
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                Text {
                                    text: "Output"
                                    font.family: Config.theme.font
                                    font.pixelSize: Styling.fontSize(-1)
                                    font.weight: Font.Medium
                                    color: outputBtn.item
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onEntered: outputBtn.isHovered = true
                                onExited: outputBtn.isHovered = false
                                onClicked: root.showOutput = true
                            }
                        }

                        // Input Button
                        StyledRect {
                            id: inputBtn
                            property bool isSelected: !root.showOutput
                            property bool isHovered: false

                            variant: isSelected ? "primary" : (isHovered ? "focus" : "common")
                            Layout.preferredHeight: 32
                            Layout.preferredWidth: inputContent.width + 24
                            radius: isSelected ? Styling.radius(-4) : Styling.radius(0)

                            Row {
                                id: inputContent
                                anchors.centerIn: parent
                                spacing: 8

                                Text {
                                    text: Icons.mic
                                    font.family: Icons.font
                                    font.pixelSize: 14
                                    color: inputBtn.item
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                Text {
                                    text: "Input"
                                    font.family: Config.theme.font
                                    font.pixelSize: Styling.fontSize(-1)
                                    font.weight: Font.Medium
                                    color: inputBtn.item
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onEntered: inputBtn.isHovered = true
                                onExited: inputBtn.isHovered = false
                                onClicked: root.showOutput = false
                            }
                        }
                    }
                }
            }

            // Content wrapper - centered
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: innerContent.implicitHeight

                ColumnLayout {
                    id: innerContent
                    width: root.contentWidth
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 8

                    // Section: Devices
                    Text {
                        text: root.showOutput ? "Output Device" : "Input Device"
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(-1)
                        font.weight: Font.Medium
                        color: Colors.overSurfaceVariant
                    }

                    // Device list
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        Repeater {
                            model: root.showOutput ? Audio.outputDevices : Audio.inputDevices

                            delegate: AudioDeviceItem {
                                required property var modelData
                                Layout.fillWidth: true
                                node: modelData
                                isOutput: root.showOutput
                                isSelected: (root.showOutput ? Audio.sink : Audio.source) === modelData
                            }
                        }
                    }

                    // ── F3: Bar Toggles Settings ──
                    Text {
                        text: "Bar Toggles"
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(-1)
                        font.weight: Font.Medium
                        color: Colors.overSurfaceVariant
                        Layout.topMargin: 8
                    }

                    ToggleRow {
                        label: "Show Mic Mute in bar"
                        checked: Config.bar ? (Config.bar.mixerMicToggle ?? true) : true
                        onToggled: value => {
                            if (Config.bar && value !== Config.bar.mixerMicToggle) {
                                Config.bar.mixerMicToggle = value;
                            }
                        }
                    }

                    ToggleRow {
                        label: "Show Output Toggle in bar"
                        checked: Config.bar ? (Config.bar.mixerOutputToggle ?? true) : true
                        onToggled: value => {
                            if (Config.bar && value !== Config.bar.mixerOutputToggle) {
                                Config.bar.mixerOutputToggle = value;
                            }
                        }
                    }

                    Text {
                        text: "Output Devices"
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(-1)
                        font.weight: Font.Medium
                        color: Colors.overSurfaceVariant
                        Layout.topMargin: 8
                    }

                    // Speakers selector
                    RowLayout {
                        id: speakersRow
                        Layout.fillWidth: true
                        spacing: 8
                        opacity: (Config.bar ? (Config.bar.mixerOutputToggle ?? true) : true) ? 1.0 : 0.5
                        Text {
                            text: "Speakers"
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(0)
                            color: Colors.overBackground
                            Layout.preferredWidth: 80
                        }
                        StyledRect {
                            id: speakersRect
                            variant: "common"
                            Layout.fillWidth: true
                            Layout.preferredHeight: 32
                            radius: Styling.radius(-2)
                            enabled: Config.bar ? (Config.bar.mixerOutputToggle ?? true) : true
                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 8
                                Text {
                                    text: (Config.audio && Config.audio.speakersNode) ? Config.audio.speakersNode : (Audio.outputDevices.length > 0 ? "Select device" : "No devices")
                                    font.family: Config.theme.font
                                    font.pixelSize: Styling.fontSize(0)
                                    color: Colors.overBackground
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                    verticalAlignment: Text.AlignVCenter
                                }
                                Text {
                                    text: Icons.caretDown
                                    font.family: Icons.font
                                    font.pixelSize: 14
                                    color: Colors.overSurfaceVariant
                                    Layout.alignment: Qt.AlignVCenter
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                enabled: speakersRect.enabled
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    speakersMenu.updateItems();
                                    speakersMenu.popup(speakersRect);
                                }
                            }
                        }
                        OptionsMenu {
                            id: speakersMenu
                            function updateItems() {
                                var devs = Audio.outputDevices;
                                var list = [];
                                if (devs.length === 0) {
                                    list.push({ text: "No output devices" });
                                } else {
                                    for (var i = 0; i < devs.length; i++) {
                                        var d = devs[i];
                                        var name = d.nickname || d.description || d.name || "Unknown";
                                        var friendly = Audio.friendlyDeviceName(d);
                                        list.push({
                                            text: friendly,
                                            icon: Icons.speakerHigh,
                                            onTriggered: (function(n){ return function(){ if (Config.audio) Config.audio.speakersNode = n; }; })(name)
                                        });
                                    }
                                    list.push({ isSeparator: true });
                                    list.push({ text: "Clear", icon: Icons.trash, onTriggered: function(){ if (Config.audio) Config.audio.speakersNode = ""; } });
                                }
                                speakersMenu.items = list;
                            }
                        }
                    }

                    // Headphones selector
                    RowLayout {
                        id: headphonesRow
                        Layout.fillWidth: true
                        spacing: 8
                        opacity: (Config.bar ? (Config.bar.mixerOutputToggle ?? true) : true) ? 1.0 : 0.5
                        Text {
                            text: "Headphones"
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(0)
                            color: Colors.overBackground
                            Layout.preferredWidth: 80
                        }
                        StyledRect {
                            id: headphonesRect
                            variant: "common"
                            Layout.fillWidth: true
                            Layout.preferredHeight: 32
                            radius: Styling.radius(-2)
                            enabled: Config.bar ? (Config.bar.mixerOutputToggle ?? true) : true
                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 8
                                Text {
                                    text: (Config.audio && Config.audio.headphonesNode) ? Config.audio.headphonesNode : (Audio.outputDevices.length > 0 ? "Select device" : "No devices")
                                    font.family: Config.theme.font
                                    font.pixelSize: Styling.fontSize(0)
                                    color: Colors.overBackground
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                    verticalAlignment: Text.AlignVCenter
                                }
                                Text {
                                    text: Icons.caretDown
                                    font.family: Icons.font
                                    font.pixelSize: 14
                                    color: Colors.overSurfaceVariant
                                    Layout.alignment: Qt.AlignVCenter
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                enabled: headphonesRect.enabled
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    headphonesMenu.updateItems();
                                    headphonesMenu.popup(headphonesRect);
                                }
                            }
                        }
                        OptionsMenu {
                            id: headphonesMenu
                            function updateItems() {
                                var devs = Audio.outputDevices;
                                var list = [];
                                if (devs.length === 0) {
                                    list.push({ text: "No output devices" });
                                } else {
                                    for (var i = 0; i < devs.length; i++) {
                                        var d = devs[i];
                                        var name = d.nickname || d.description || d.name || "Unknown";
                                        var friendly = Audio.friendlyDeviceName(d);
                                        list.push({
                                            text: friendly,
                                            icon: Icons.headphones,
                                            onTriggered: (function(n){ return function(){ if (Config.audio) Config.audio.headphonesNode = n; }; })(name)
                                        });
                                    }
                                    list.push({ isSeparator: true });
                                    list.push({ text: "Clear", icon: Icons.trash, onTriggered: function(){ if (Config.audio) Config.audio.headphonesNode = ""; } });
                                }
                                headphonesMenu.items = list;
                            }
                        }
                    }

                    // Separator
                    Separator {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 2
                        Layout.topMargin: 8
                        Layout.bottomMargin: 8
                    }

                    // Section: Volume Mixer
                    Text {
                        text: "Volume Mixer"
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(-1)
                        font.weight: Font.Medium
                        color: Colors.overSurfaceVariant
                    }

                    // Main volume control
                    AudioVolumeEntry {
                        Layout.fillWidth: true
                        node: root.showOutput ? Audio.sink : Audio.source
                        icon: root.showOutput ? Icons.speakerHigh : Icons.mic
                        isMainDevice: true
                    }

                    // App volume controls
                    Repeater {
                        model: root.showOutput ? Audio.outputAppNodes : Audio.inputAppNodes

                        delegate: AudioVolumeEntry {
                            required property var modelData
                            Layout.fillWidth: true
                            node: modelData
                            isMainDevice: false
                        }
                    }

                    // Empty state for apps
                    Text {
                        visible: (root.showOutput ? Audio.outputAppNodes : Audio.inputAppNodes).length === 0
                        text: "No applications using audio"
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(-1)
                        color: Colors.outline
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: 16
                    }
                }
            }
        }
    }
}
