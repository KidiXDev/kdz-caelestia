//@ pragma Env QS_CRASHREPORT_URL=https://github.com/caelestia-dots/shell/issues/new?template=crash.yml
//@ pragma DefaultEnv QS_NO_RELOAD_POPUP=1
//@ pragma DefaultEnv QS_DROP_EXPENSIVE_FONTS=1
//@ pragma DefaultEnv QSG_RENDER_LOOP=threaded
//@ pragma DefaultEnv QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000
//@ pragma DefaultEnv QT_FFMPEG_DECODING_HW_DEVICE_TYPES=qsv,vaapi
// QT_FFMPEG_DECODING_HW_DEVICE_TYPES: animated wallpapers: decode on the iGPU (QSV, then VAAPI) so a hybrid laptop's dGPU can sleep. CUDA/VDPAU are left out because probing them wakes the dGPU

import "modules"
import "modules/drawers"
import "modules/background"
import "modules/areapicker"
import "modules/lock"
import QtQuick
import Quickshell
import qs.services

ShellRoot {
    id: root

    settings.watchFiles: true

    Binding {
        target: ShellState
        property: "shellRoot"
        value: root
    }

    GSFLoader {}
    ServiceLoader {}

    Background {
        // Not lock.locked: Quickshell never emits its change signal on unlock
        locked: lock.lock.secure
    }
    Drawers {}
    AreaPicker {}
    DisplayOverlay {}
    Lock {
        id: lock
    }

    Shortcuts {}
    BatteryMonitor {}
    IdleMonitors {
        lock: lock
    }
}
