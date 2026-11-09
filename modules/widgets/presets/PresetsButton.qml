import QtQuick
import "../../globals"
import "../../services"
import "../../../config"
import "../../components"
import "../../theme"

ToggleButton {
    buttonIcon: Icons.magicWand
    tooltipText: I18n.t("bar.tooltip.presets")

    onToggle: function () {
        if (GlobalStates.presetsOpen) {
            Visibilities.setActiveModule("");
        } else {
            Visibilities.setActiveModule("presets");
        }
    }
}