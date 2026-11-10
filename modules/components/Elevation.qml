import QtQuick
import QtQuick.Effects
import "../../config"

// A drop shadow for a raised rounded surface, in the theme's shadow colour,
// opacity, blur and offset. RectangularShadow is analytic (no offscreen
// layer, no blur pass), so it costs next to nothing while the surface
// animates, unlike a MultiEffect shadow on a layer. Omacale's Elevation is
// the same idea.
//
// Size and place it over the surface it belongs to and put it below it.
RectangularShadow {
    id: root

    // 0..1: fades the shadow in and out with the surface.
    property real strength: 1

    color: Config.resolveColor(Config.theme.shadowColor)
    opacity: Config.theme.shadowOpacity * strength
    // Theme blur is MultiEffect's 0..1 over a 32px blurMax.
    blur: Math.max(0, Config.theme.shadowBlur) * 24
    spread: 0
    offset.x: Config.theme.shadowXOffset
    offset.y: Config.theme.shadowYOffset
    visible: opacity > 0.001 && width > 0 && height > 0
}
