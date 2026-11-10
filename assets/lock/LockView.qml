// atoll:lock-view v1
//
// Written into `atoll.lock`, a clone of Omarchy's lock plugin, by
// scripts/lock-handover. Omarchy's view is kept beside it as
// StockLockView.qml and its Service.qml is untouched, so PAM, fingerprint,
// faillock, the blanking timers, stranded-lock recovery and the `lock` IPC
// that `omarchy system lock` / sleep-lock / the lid call are all Omarchy's.
//
// This file only chooses who draws. It imports nothing from Atoll: Atoll's
// UI is loaded by URL, so a missing or broken Atoll still leaves a working
// lock screen (Omarchy's own) behind.
import QtQuick

Item {
  id: root

  // The contract Omarchy's Service.qml drives, copied from its LockView.qml.
  property string backgroundPath: ""
  property string videoPosterPath: ""
  property int backgroundVersion: 0
  property bool fingerprintConfigured: false
  property bool fingerprintUnavailable: false
  property bool authenticatingPassword: false
  property string failureMessage: ""
  property int failedAttempts: 0
  property bool inputEnabled: true
  property bool loadBackground: true
  property bool displaysBlank: false
  property bool powerSaverActive: false
  property string passwordText: ""
  property bool syncingPasswordText: false

  signal submitPassword(string password)
  signal passwordTextEdited(string password)
  signal clearFailureRequested
  signal wakeRequested

  function forcePasswordFocus() {
    if (atoll.item && atoll.item.focusField) atoll.item.focusField()
  }
  function clearPassword() { passwordTextEdited("") }

  readonly property url atollUi: Qt.resolvedUrl("../atoll.bar/modules/lockscreen/LockUi.qml")

  Loader {
    id: atoll
    anchors.fill: parent
    source: root.atollUi
    onLoaded: item.view = root
  }

  // Atoll missing or a QML error in its UI: Omarchy's view instead.
  Loader {
    anchors.fill: parent
    active: atoll.status === Loader.Error
    sourceComponent: stock
  }

  // Only bind what the installed stock view actually has; assigning a
  // property it lacks is a load error that would take the lock down.
  readonly property var stockOptional: ["displaysBlank", "fingerprintUnavailable", "powerSaverActive", "videoPosterPath"]

  Component {
    id: stock

    StockLockView {
      id: stockView

      backgroundPath: root.backgroundPath
      backgroundVersion: root.backgroundVersion
      fingerprintConfigured: root.fingerprintConfigured
      authenticatingPassword: root.authenticatingPassword
      failureMessage: root.failureMessage
      failedAttempts: root.failedAttempts
      inputEnabled: root.inputEnabled
      loadBackground: root.loadBackground
      passwordText: root.passwordText

      onSubmitPassword: password => root.submitPassword(password)
      onPasswordTextEdited: password => root.passwordTextEdited(password)
      onClearFailureRequested: root.clearFailureRequested()
      onWakeRequested: root.wakeRequested()

      Component.onCompleted: {
        for (const name of root.stockOptional)
          if (name in stockView)
            stockView[name] = Qt.binding(() => root[name])
      }
    }
  }
}
