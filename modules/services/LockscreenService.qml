pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick
import "../globals"

QtObject {
    id: root

    // Ambxst on Omarchy: the session lock belongs to Omarchy's own lock service
    // (omarchy.lock: WlSessionLock, PAM, fingerprint, idle timers). Ambxst
    // asks it to lock rather than raising a second session lock.
    function toggle() {
        root.lock();
    }

    function lock() {
        Quickshell.execDetached(["omarchy-system-lock"]);
    }

    function unlock() {
        GlobalStates.lockscreenVisible = false;
    }

    property IpcHandler ipc: IpcHandler {
        target: "lockscreen"

        function toggle(): void {
            root.toggle();
        }

        function lock(): void {
            root.lock();
        }

        function unlock(): void {
            root.unlock();
        }
    }
}
