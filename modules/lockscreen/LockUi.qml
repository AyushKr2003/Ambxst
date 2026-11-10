pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import "../components"
import "../corners"
import "../theme"
import "../widgets/dashboard/widgets"
import "../../config"

// Atoll's lock screen as a *view* for Omarchy's lock service.
//
// Loaded by URL from the `atoll.lock` clone of omarchy.lock (see
// assets/lock/LockView.qml and scripts/lock-handover). Omarchy's Service.qml
// keeps everything that must not break: the WlSessionLock, PAM (password and
// fingerprint), faillock, idle/suspend locking, stranded-lock recovery and
// the `lock` IPC. This file only draws Atoll's look (upstream Ambxst's
// LockScreen.qml) and reports what the user types back through `view`.
Item {
    id: root

    // The wrapper (LockView.qml in the clone) hands itself in: the
    // properties and signals Omarchy's service drives its view with.
    property var view: null

    readonly property bool authenticating: view ? view.authenticatingPassword : false
    readonly property string failureMessage: view ? view.failureMessage : ""
    readonly property bool inputEnabled: view ? view.inputEnabled : false
    readonly property bool fingerprint: view ? view.fingerprintConfigured : false
    readonly property string wallpaper: {
        if (!view || !view.loadBackground)
            return "";
        const video = /\.(mp4|webm|mkv|mov|avi|gif)$/i.test(view.backgroundPath || "");
        const path = video ? (view.videoPosterPath || "") : (view.backgroundPath || "");
        return path ? "file://" + path + "?v=" + view.backgroundVersion : "";
    }

    property bool startAnim: false
    readonly property int anim: Config.animDuration > 0 ? Config.animDuration * 2 : 0

    function wake() {
        if (view)
            view.wakeRequested();
    }

    function focusField() {
        if (root.inputEnabled && passwordInput.enabled && !passwordInput.activeFocus)
            passwordInput.forceActiveFocus();
    }

    // ----------------------------------------------------------- background

    Rectangle {
        anchors.fill: parent
        color: Colors.background
    }

    Image {
        id: wallpaperImage
        anchors.fill: parent
        source: root.wallpaper
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        opacity: startAnim && status === Image.Ready ? 1 : 0
        scale: startAnim ? 1.1 : 1.0

        layer.enabled: true
        layer.effect: MultiEffect {
            blurEnabled: true
            blur: 1
            blurMax: 64
        }

        Behavior on opacity {
            enabled: root.anim > 0
            NumberAnimation {
                duration: root.anim
                easing.type: Easing.OutQuint
            }
        }
        Behavior on scale {
            enabled: root.anim > 0
            NumberAnimation {
                duration: root.anim
                easing.type: Easing.OutExpo
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: startAnim ? 0.25 : 0
        Behavior on opacity {
            enabled: root.anim > 0
            NumberAnimation {
                duration: root.anim
                easing.type: Easing.OutQuint
            }
        }
    }

    // A click or mouse move wakes blanked displays and puts the cursor back
    // in the field, as Omarchy's own view does.
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onClicked: {
            root.wake();
            root.focusField();
        }
        onPositionChanged: root.wake()
    }

    // ---------------------------------------------------------------- clock

    Item {
        id: clockContainer
        anchors.centerIn: parent
        width: clockRow.width
        height: hoursText.height + (hoursText.height * 0.5)

        property date currentTime: new Date()

        Timer {
            interval: 1000
            running: true
            repeat: true
            onTriggered: clockContainer.currentTime = new Date()
        }

        Row {
            id: clockRow
            anchors.top: parent.top

            Text {
                id: hoursText
                text: Config.bar.use12hFormat ? (clockContainer.currentTime.getHours() % 12 || 12).toString() : Qt.formatTime(clockContainer.currentTime, "hh")
                font.family: "League Gothic"
                font.pixelSize: 240
                color: Colors.primaryFixed
                antialiasing: true
                opacity: startAnim ? 1 : 0
                property real slideOffset: startAnim ? 0 : -150
                transform: Translate {
                    y: hoursText.slideOffset
                }
                layer.enabled: true
                layer.effect: BgShadow {}
                Behavior on opacity {
                    enabled: root.anim > 0
                    NumberAnimation {
                        duration: root.anim
                        easing.type: Easing.OutExpo
                    }
                }
                Behavior on slideOffset {
                    enabled: root.anim > 0
                    NumberAnimation {
                        duration: root.anim
                        easing.type: Easing.OutExpo
                    }
                }
            }

            Text {
                id: minutesText
                text: Qt.formatTime(clockContainer.currentTime, "mm")
                font.family: "League Gothic"
                font.pixelSize: 240
                color: Colors.primaryFixedDim
                antialiasing: true
                anchors.top: hoursText.top
                anchors.topMargin: hoursText.height * 0.5
                opacity: startAnim ? 1 : 0
                property real slideOffset: startAnim ? 0 : 150
                transform: Translate {
                    y: minutesText.slideOffset
                }
                layer.enabled: true
                layer.effect: BgShadow {}
                Behavior on opacity {
                    enabled: root.anim > 0
                    NumberAnimation {
                        duration: root.anim
                        easing.type: Easing.OutExpo
                    }
                }
                Behavior on slideOffset {
                    enabled: root.anim > 0
                    NumberAnimation {
                        duration: root.anim
                        easing.type: Easing.OutExpo
                    }
                }
            }

            Text {
                renderType: Text.NativeRendering
                text: Config.bar.use12hFormat ? Qt.formatTime(clockContainer.currentTime, "ap").toLowerCase() : ""
                visible: Config.bar.use12hFormat
                font.family: "League Gothic"
                font.pixelSize: 100
                color: hoursText.color
                anchors.top: hoursText.top
                anchors.topMargin: hoursText.height * 0.35
                opacity: startAnim ? 1 : 0
                layer.enabled: true
                layer.effect: BgShadow {}
            }
        }
    }

    // -------------------------------------------------------- media player

    Item {
        id: playerContainer
        readonly property bool isTopPosition: Config.lockscreen.position === "top"
        anchors {
            left: parent.left
            leftMargin: startAnim ? 32 : -(playerContainer.width + 64)
            top: isTopPosition ? parent.top : undefined
            topMargin: isTopPosition ? 32 : 0
            bottom: !isTopPosition ? parent.bottom : undefined
            bottomMargin: !isTopPosition ? 32 : 0
        }
        width: 350
        height: playerContent.height
        opacity: startAnim ? 1 : 0

        Behavior on anchors.leftMargin {
            enabled: root.anim > 0
            NumberAnimation {
                duration: root.anim
                easing.type: Easing.OutExpo
            }
        }
        Behavior on opacity {
            enabled: root.anim > 0
            NumberAnimation {
                duration: root.anim
                easing.type: Easing.OutQuad
            }
        }

        LockPlayer {
            id: playerContent
            width: parent.width
        }
    }

    // ------------------------------------------------------------- password

    Item {
        id: passwordContainer
        readonly property bool isTopPosition: Config.lockscreen.position === "top"
        anchors {
            horizontalCenter: parent.horizontalCenter
            top: isTopPosition ? parent.top : undefined
            topMargin: isTopPosition ? (startAnim ? 32 : -80) : 0
            bottom: !isTopPosition ? parent.bottom : undefined
            bottomMargin: !isTopPosition ? (startAnim ? 32 : -80) : 0
        }
        width: 350
        height: 96 + (statusText.visible ? statusText.height + 8 : 0)
        opacity: startAnim ? 1 : 0
        scale: startAnim ? 1 : 0.92

        Behavior on anchors.topMargin {
            enabled: root.anim > 0
            NumberAnimation {
                duration: root.anim
                easing.type: Easing.OutExpo
            }
        }
        Behavior on anchors.bottomMargin {
            enabled: root.anim > 0
            NumberAnimation {
                duration: root.anim
                easing.type: Easing.OutExpo
            }
        }
        Behavior on opacity {
            enabled: root.anim > 0
            NumberAnimation {
                duration: root.anim
                easing.type: Easing.OutQuad
            }
        }
        Behavior on scale {
            enabled: root.anim > 0
            NumberAnimation {
                duration: root.anim
                easing.type: Easing.OutBack
                easing.overshoot: 1.2
            }
        }

        // Omarchy's failure text (wrong password, faillock countdown,
        // fingerprint notices) under the pill.
        Text {
            renderType: Text.NativeRendering
            id: statusText
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: passwordContainer.isTopPosition ? undefined : passwordInputBox.top
            anchors.top: passwordContainer.isTopPosition ? passwordInputBox.bottom : undefined
            anchors.margins: 8
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: root.failureMessage
            visible: text.length > 0
            color: Colors.error
            font.family: Config.theme.font
            font.pixelSize: Styling.fontSize(-1)
            layer.enabled: true
            layer.effect: BgShadow {}
        }

        StyledRect {
            id: passwordInputBox
            variant: "bg"
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: passwordContainer.isTopPosition ? undefined : parent.bottom
            anchors.top: passwordContainer.isTopPosition ? parent.top : undefined
            width: parent.width
            height: 96
            radius: Config.roundness > 0 ? (height / 2) * (Config.roundness / 16) : 0

            property real shakeOffset: 0
            property bool showError: false
            transform: Translate {
                x: passwordInputBox.shakeOffset
            }

            Row {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 24
                spacing: 12

                Item {
                    id: avatarContainer
                    width: 64
                    height: 64
                    anchors.verticalCenter: parent.verticalCenter

                    Image {
                        id: userAvatar
                        anchors.fill: parent
                        source: `file://${Quickshell.env("HOME")}/.face.icon`
                        fillMode: Image.PreserveAspectCrop
                        mipmap: true
                        asynchronous: true
                        visible: status === Image.Ready
                        layer.enabled: true
                        layer.effect: MultiEffect {
                            maskEnabled: true
                            maskThresholdMin: 0.5
                            maskSpreadAtMin: 1.0
                            maskSource: ShaderEffectSource {
                                sourceItem: Rectangle {
                                    width: userAvatar.width
                                    height: userAvatar.height
                                    radius: Config.roundness > 0 ? (height / 2) * (Config.roundness / 16) : 0
                                }
                            }
                        }
                    }

                    StyledRect {
                        id: avatarFallback
                        anchors.fill: parent
                        variant: "primary"
                        visible: userAvatar.status !== Image.Ready
                        radius: Config.roundness > 0 ? (height / 2) * (Config.roundness / 16) : 0
                        Text {
                            renderType: Text.NativeRendering
                            anchors.centerIn: parent
                            text: Icons.user
                            font.family: Icons.font
                            font.pixelSize: 30
                            color: avatarFallback.item
                        }
                    }
                }

                StyledRect {
                    id: passwordFieldBg
                    width: parent.width - avatarContainer.width - parent.spacing
                    height: 48
                    anchors.verticalCenter: parent.verticalCenter
                    variant: passwordInputBox.showError || root.failureMessage.length > 0 ? "error" : "common"
                    radius: Config.roundness > 0 ? (height / 2) * (Config.roundness / 16) : 0

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 24
                        spacing: 8

                        Text {
                            renderType: Text.NativeRendering
                            id: userIcon
                            text: root.authenticating ? Icons.circleNotch : Icons.lock
                            font.family: Icons.font
                            font.pixelSize: 22
                            color: passwordFieldBg.item
                            Layout.preferredWidth: 24
                            Layout.alignment: Qt.AlignVCenter
                            RotationAnimator on rotation {
                                running: root.authenticating
                                from: 0
                                to: 360
                                duration: 900
                                loops: Animation.Infinite
                            }
                            onTextChanged: if (!root.authenticating) rotation = 0
                        }

                        TextField {
                            renderType: Text.NativeRendering
                            id: passwordInput
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            placeholderText: root.authenticating ? "Checking…" : (root.fingerprint ? "Password or fingerprint" : (Quickshell.env("USER") || "Password"))
                            placeholderTextColor: Qt.rgba(passwordFieldBg.item.r, passwordFieldBg.item.g, passwordFieldBg.item.b, 0.5)
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(0)
                            color: passwordFieldBg.item
                            background: null
                            echoMode: TextInput.Password
                            verticalAlignment: TextInput.AlignVCenter
                            enabled: root.inputEnabled && !root.authenticating

                            property bool syncing: false

                            onTextChanged: {
                                if (!syncing && root.view)
                                    root.view.passwordTextEdited(text);
                                if (text.length > 0) {
                                    root.wake();
                                    if (root.failureMessage.length > 0 && root.view)
                                        root.view.clearFailureRequested();
                                }
                            }

                            onAccepted: {
                                const submitted = text;
                                if (submitted.length === 0 || !root.view)
                                    return;
                                root.view.passwordTextEdited("");
                                root.view.submitPassword(submitted);
                            }

                            onEnabledChanged: if (enabled) Qt.callLater(root.focusField)

                            Keys.onPressed: event => {
                                root.wake();
                                // A key held while a blanked display wakes
                                // must not type into the password.
                                if (event.isAutoRepeat && event.key !== Qt.Key_Backspace && event.key !== Qt.Key_Delete) {
                                    event.accepted = true;
                                    return;
                                }
                                if (event.key === Qt.Key_Escape || ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_U)) {
                                    if (root.view)
                                        root.view.passwordTextEdited("");
                                    event.accepted = true;
                                }
                            }
                        }
                    }
                }
            }

            SequentialAnimation {
                id: wrongPasswordAnim
                ScriptAction {
                    script: passwordInputBox.showError = true
                }
                NumberAnimation {
                    target: passwordInputBox
                    property: "shakeOffset"
                    to: 10
                    duration: 50
                    easing.type: Easing.InOutQuad
                }
                NumberAnimation {
                    target: passwordInputBox
                    property: "shakeOffset"
                    to: -10
                    duration: 100
                    easing.type: Easing.InOutQuad
                }
                NumberAnimation {
                    target: passwordInputBox
                    property: "shakeOffset"
                    to: 10
                    duration: 100
                    easing.type: Easing.InOutQuad
                }
                NumberAnimation {
                    target: passwordInputBox
                    property: "shakeOffset"
                    to: 0
                    duration: 50
                    easing.type: Easing.InOutQuad
                }
                ScriptAction {
                    script: passwordInputBox.showError = false
                }
            }
        }
    }

    // The service owns the typed text (it clears it after a submit or a
    // failure); keep the field in step without echoing the change back.
    function syncPassword() {
        const want = view ? view.passwordText : "";
        if (passwordInput.text === want)
            return;
        passwordInput.syncing = true;
        passwordInput.text = want;
        passwordInput.syncing = false;
    }

    Connections {
        target: root.view
        ignoreUnknownSignals: true
        function onPasswordTextChanged() {
            root.syncPassword();
        }
        function onFailedAttemptsChanged() {
            if (root.view && root.view.failedAttempts > 0 && Config.animDuration > 0)
                wrongPasswordAnim.restart();
        }
        function onInputEnabledChanged() {
            Qt.callLater(root.focusField);
        }
    }

    onViewChanged: syncPassword()

    // Focus can be refused while the session lock surface is still being
    // mapped; keep trying for a moment.
    Timer {
        interval: 150
        repeat: true
        running: root.inputEnabled && !passwordInput.activeFocus
        onTriggered: root.focusField()
    }

    // ----------------------------------------------------------- corners

    RoundCorner {
        size: Styling.radius(4)
        anchors.left: parent.left
        anchors.top: parent.top
        corner: RoundCorner.CornerEnum.TopLeft
    }
    RoundCorner {
        size: Styling.radius(4)
        anchors.right: parent.right
        anchors.top: parent.top
        corner: RoundCorner.CornerEnum.TopRight
    }
    RoundCorner {
        size: Styling.radius(4)
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        corner: RoundCorner.CornerEnum.BottomLeft
    }
    RoundCorner {
        size: Styling.radius(4)
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        corner: RoundCorner.CornerEnum.BottomRight
    }

    Component.onCompleted: {
        startAnim = true;
        syncPassword();
        Qt.callLater(focusField);
    }
}
