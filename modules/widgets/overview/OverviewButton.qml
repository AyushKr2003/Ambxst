import QtQuick
import "../../globals"
import "../../services"
import "../../../config"
import "../../components"
import "../../theme"

ToggleButton {
    buttonIcon: Icons.overview
    tooltipText: I18n.t("bar.tooltip.overview")

    onToggle: function () {
        if (AxctlService.nativeOverviewSupported) {
            AxctlService.dispatch("overview toggle");
            return;
        }
        if (GlobalStates.overviewOpen) {
            Visibilities.setActiveModule("");
        } else {
            Visibilities.setActiveModule("overview");
        }
    }
}
