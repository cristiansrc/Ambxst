pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
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
    readonly property bool wifiAvailable: NetworkService ? (NetworkService.wifiAvailable ?? false) : false

    Component.onCompleted: {
        // Defer scan to avoid blocking UI initialization (solo si hay hardware)
        if (wifiAvailable) initialScanTimer.start();
    }

    Timer {
        id: initialScanTimer
        interval: 300
        repeat: false
        onTriggered: {
            if (root.wifiAvailable && NetworkService) NetworkService.rescanWifi();
        }
    }

    // No hardware placeholder (StyledRect, sin colores hardcodeados)
    StyledRect {
        visible: !root.wifiAvailable
        anchors.centerIn: parent
        variant: "common"
        implicitWidth: noHardwareText.implicitWidth + 32
        implicitHeight: noHardwareText.implicitHeight + 32
        radius: Styling.radius(0)

        Text {
            id: noHardwareText
            anchors.centerIn: parent
            text: "No Wi-Fi hardware detected"
            font.family: Config.theme.font
            font.pixelSize: Config.theme.fontSize
            color: Colors.overSurfaceVariant
        }
    }

    // Network list - fills entire width for scroll/drag
    ListView {
        id: networkList
        visible: root.wifiAvailable
        anchors.fill: parent
        clip: true
        spacing: 4
        cacheBuffer: 1000
        reuseItems: true

        model: NetworkService ? NetworkService.friendlyWifiNetworks : []

        header: Item {
            width: networkList.width
            height: titlebar.height + 8

            PanelTitlebar {
                id: titlebar
                width: root.contentWidth
                anchors.horizontalCenter: parent.horizontalCenter
                title: "Wi-Fi"
                statusText: (NetworkService && NetworkService.wifiConnecting) ? "Connecting..." : (NetworkService && NetworkService.wifiStatus === "limited" ? "Limited" : "")
                statusColor: (NetworkService && NetworkService.wifiStatus === "limited") ? Colors.warning : Styling.srItem("overprimary")
                showToggle: true
                toggleChecked: NetworkService ? NetworkService.wifiStatus !== "disabled" : false

                actions: [
                    {
                        icon: Icons.globe,
                        tooltip: "Open captive portal",
                        enabled: NetworkService ? NetworkService.wifiStatus === "limited" : false,
                        onClicked: function () {
                            if (NetworkService) NetworkService.openPublicWifiPortal();
                        }
                    },
                    {
                        icon: Icons.popOpen,
                        tooltip: "Network settings",
                        onClicked: function () {
                            Quickshell.execDetached(["nm-connection-editor"]);
                        }
                    },
                    {
                        icon: Icons.sync,
                        tooltip: "Rescan networks",
                        enabled: NetworkService ? NetworkService.wifiEnabled : false,
                        loading: NetworkService ? (NetworkService.wifiScanning || NetworkService.isUpdating) : false,
                        onClicked: function () {
                            if (NetworkService) NetworkService.rescanWifi();
                        }
                    }
                ]

                onToggleChanged: checked => {
                    if (!NetworkService) return;
                    NetworkService.enableWifi(checked);
                    if (checked) {
                        NetworkService.rescanWifi();
                    }
                }
            }
        }

        delegate: Item {
            required property var modelData
            width: networkList.width
            height: networkItem.height

            WifiNetworkItem {
                id: networkItem
                width: root.contentWidth
                anchors.horizontalCenter: parent.horizontalCenter
                network: parent.modelData
            }
        }

        // Empty state (null-safety)
        Text {
            anchors.centerIn: parent
            visible: root.wifiAvailable && networkList.count === 0 && !(NetworkService ? NetworkService.wifiScanning : false)
            text: (NetworkService && NetworkService.wifiEnabled) ? "No networks found" : "Wi-Fi is disabled"
            font.family: Config.theme.font
            font.pixelSize: Config.theme.fontSize
            color: Colors.overSurfaceVariant
        }
    }
}
