pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.modules.theme
import qs.modules.components
import qs.modules.services
import qs.config

Item {
    id: root

    property int maxContentWidth: 480
    readonly property int contentWidth: Math.min(width, maxContentWidth)
    readonly property real sideMargin: (width - contentWidth) / 2

    // Null-safe hardware availability (patrón Battery.available)
    readonly property bool btAvailable: BluetoothService ? (BluetoothService.available ?? false) : false

    Component.onCompleted: {
        // Only refresh device list, don't start scanning automatically
        if (btAvailable && BluetoothService && BluetoothService.enabled) {
            // Defer update to avoid blocking UI initialization
            initialUpdateTimer.start();
        }
    }

    Timer {
        id: initialUpdateTimer
        interval: 300
        repeat: false
        onTriggered: {
            if (root.btAvailable && BluetoothService) BluetoothService.updateDevices();
        }
    }

    Component.onDestruction: {
        if (BluetoothService) BluetoothService.stopDiscovery();
    }

    // No hardware placeholder (StyledRect, sin colores hardcodeados)
    StyledRect {
        visible: !root.btAvailable
        anchors.centerIn: parent
        variant: "common"
        implicitWidth: noBtText.implicitWidth + 32
        implicitHeight: noBtText.implicitHeight + 32
        radius: Styling.radius(0)

        Text {
            id: noBtText
            anchors.centerIn: parent
            text: "No Bluetooth hardware detected"
            font.family: Config.theme.font
            font.pixelSize: Config.theme.fontSize
            color: Colors.overSurfaceVariant
        }
    }

    // Device list - fills entire width for scroll/drag
    ListView {
        id: deviceList
        visible: root.btAvailable
        anchors.fill: parent
        clip: true
        spacing: 4
        cacheBuffer: 1000
        reuseItems: true

        model: BluetoothService ? BluetoothService.friendlyDeviceList : []

        header: Item {
            width: deviceList.width
            height: titlebar.height + 8

            PanelTitlebar {
                id: titlebar
                width: root.contentWidth
                anchors.horizontalCenter: parent.horizontalCenter
                title: "Bluetooth"
                showToggle: true
                toggleChecked: BluetoothService ? BluetoothService.enabled : false

                actions: [
                    {
                        icon: Icons.popOpen,
                        tooltip: "Open Blueman",
                        onClicked: function () {
                            Quickshell.execDetached(["blueman-manager"]);
                        }
                    },
                    {
                        icon: Icons.sync,
                        tooltip: "Scan for devices",
                        enabled: BluetoothService ? BluetoothService.enabled : false,
                        loading: BluetoothService ? (BluetoothService.discovering || BluetoothService.isUpdating) : false,
                        onClicked: function () {
                            if (BluetoothService) BluetoothService.startDiscovery();
                        }
                    }
                ]

                onToggleChanged: checked => {
                    if (!BluetoothService) return;
                    BluetoothService.setEnabled(checked);
                    if (checked) {
                        BluetoothService.startDiscovery();
                    }
                }
            }
        }

        delegate: Item {
            required property var modelData
            width: deviceList.width
            height: deviceItem.height

            BluetoothDeviceItem {
                id: deviceItem
                width: root.contentWidth
                anchors.horizontalCenter: parent.horizontalCenter
                device: parent.modelData
            }
        }

        // Empty state (null-safety)
        Text {
            anchors.centerIn: parent
            visible: root.btAvailable && deviceList.count === 0 && !(BluetoothService ? BluetoothService.discovering : false)
            text: (BluetoothService && BluetoothService.enabled) ? "No devices found" : "Bluetooth is disabled"
            font.family: Config.theme.font
            font.pixelSize: Config.theme.fontSize
            color: Colors.overSurfaceVariant
        }
    }
}
