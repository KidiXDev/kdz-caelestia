pragma Singleton

import Quickshell

Singleton {
    readonly property list<string> validImageTypes: ["jpeg", "png", "webp", "tiff", "svg"]
    readonly property list<string> validImageExtensions: ["jpg", "jpeg", "png", "webp", "tif", "tiff", "svg"]
    readonly property list<string> validVideoExtensions: ["mp4", "webm", "mkv", "mov", "avi", "m4v"]

    function isValidImageByName(name: string): bool {
        return validImageExtensions.some(t => name.endsWith(`.${t}`));
    }

    function isVideo(path: string): bool {
        path = path.toLowerCase();
        return validVideoExtensions.some(t => path.endsWith(`.${t}`));
    }

    // Played with MediaPlayer instead of shown as a still image
    function isAnimated(path: string): bool {
        return isVideo(path) || path.toLowerCase().endsWith(".gif");
    }
}
