import QtQuick
import "../../components"
import "../../services"
import "../../theme"
import Quickshell.Io

ActionGrid {
    id: root

    signal itemSelected

    layout: "row"
    buttonSize: 48
    iconSize: 20
    spacing: 8

    Process {
        id: actionProcess
        running: false
    }

    Component.onCompleted: {
        root.forceActiveFocus();
    }

    actions: [
        {
            icon: Icons.lock,
            tooltip: I18n.t("powermenu.lock_session"),
            command: "omarchy-system-lock" // Ambxst on Omarchy: Omarchy's System menu actions
        },
        {
            icon: Icons.suspend,
            tooltip: I18n.t("powermenu.suspend"),
            command: "systemctl suspend"
        },
        {
            icon: "",
            iconUrl: Qt.resolvedUrl("../../../assets/icons/snowflake-bold.svg"),
            tooltip: I18n.t("powermenu.hibernate"),
            command: "systemctl hibernate"
        },
        {
            icon: Icons.logout,
            tooltip: I18n.t("powermenu.exit_axctl"),
            command: "omarchy-system logout"
        },
        {
            icon: Icons.reboot,
            tooltip: I18n.t("powermenu.reboot"),
            command: "omarchy-system reboot"
        },
        {
            icon: Icons.shutdown,
            tooltip: I18n.t("powermenu.power_off"),
            command: "omarchy-system shutdown"
        }
    ]

    onActionTriggered: action => {
        console.log("Action triggered:", action.command);
        if (action.command) {
            actionProcess.command = ["/bin/bash", "-c", action.command];
            console.log("Starting process with command:", actionProcess.command);
            actionProcess.running = true;
        }
        root.itemSelected();
    }
}
