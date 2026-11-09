import QtQuick
import "../../components"
import "../../theme"
import "../../services"

ToggleButton {
    id: powerButton
    buttonIcon: Icons.shutdown
    tooltipText: I18n.t("bar.tooltip.powermenu")
    onToggle: function () {
        if (Visibilities.currentActiveModule === "powermenu") {
            Visibilities.setActiveModule("");
        } else {
            Visibilities.setActiveModule("powermenu");
        }
    }
}
