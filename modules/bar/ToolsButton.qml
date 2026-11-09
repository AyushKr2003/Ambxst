import QtQuick
import "../components"
import "../theme"
import "../services"

ToggleButton {
    id: toolsButton
    buttonIcon: Icons.toolbox
    tooltipText: I18n.t("bar.tooltip.tools")
    onToggle: function () {
        if (Visibilities.currentActiveModule === "tools") {
            Visibilities.setActiveModule("");
        } else {
            Visibilities.setActiveModule("tools");
        }
    }
}
