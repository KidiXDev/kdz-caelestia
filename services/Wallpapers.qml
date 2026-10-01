pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia
import Caelestia.Config
import Caelestia.I18n
import Caelestia.Models
import qs.services
import qs.utils

Searcher {
    id: root

    readonly property string currentNamePath: `${Paths.state}/wallpaper/path.txt`
    readonly property list<string> smartArg: GlobalConfig.services.smartScheme ? [] : ["--no-smart"]
    readonly property string fallback: Quickshell.shellPath("assets/wallpaper.webp")
    readonly property string posterDir: `${Paths.cache}/animated`
    // The CLI only takes images, so videos get a poster frame to derive colours from
    // Args: video, poster, file to write the video path to on success ("" for none), then the CLI command
    readonly property string posterScript: 'v=$1 p=$2 s=$3; shift 3; mkdir -p "${p%/*}" && ffmpeg -y -loglevel error -i "$v" -frames:v 1 "$p" && "$@" && { [ -z "$s" ] || printf %s "$v" > "$s"; }'

    property bool showPreview: false
    readonly property string current: showPreview ? previewPath : actualCurrent
    property string previewPath
    property string actualCurrent
    property bool previewColourLock
    property bool pendingPreviewClear

    // QT_FFMPEG_DECODING_HW_DEVICE_TYPES per videoDecoder option. The ones after the choice are fallbacks,
    // and Qt decodes in software if none work. "auto" keeps the shell.qml default (qsv,vaapi)
    readonly property var decoderEnv: ({
            qsv: "qsv,vaapi",
            vaapi: "vaapi,qsv",
            cuda: "cuda,qsv,vaapi",
            vulkan: "vulkan,qsv,vaapi",
            software: ","
        })
    // Qt reads the env var once per process, so a changed option only applies after a restart
    property string appliedDecoder
    property string lastFailedVideo

    function getCategoryFor(w: FileSystemEntry): string {
        let category = w.parentDir.slice(Paths.wallsdir.length + 1);
        if (category.includes("/"))
            category = category.slice(0, category.indexOf("/"));
        return category;
    }

    function posterFor(path: string): string {
        return `${posterDir}/${Qt.md5(path)}.png`;
    }

    function reportVideoFailure(path: string, reason: string): void {
        console.warn(`Animated wallpaper ${path} failed: ${reason}`);
        if (path === lastFailedVideo)
            return; // Once per video, not once per monitor
        lastFailedVideo = path;
        Toaster.toast(Tr.tr("Animated wallpaper failed"), Tr.tr("Showing a still frame instead. You can try another video decoder in Wallpaper & style"), "broken_image");
    }

    function setRandom(): void {
        Quickshell.execDetached(["caelestia", "wallpaper", "-r", ...smartArg]);
    }

    function setWallpaper(path: string): void {
        actualCurrent = path;
        if (Images.isVideo(path))
            Quickshell.execDetached(["sh", "-c", posterScript, "sh", path, posterFor(path), currentNamePath, "caelestia", "wallpaper", "-f", posterFor(path), ...smartArg]);
        else
            Quickshell.execDetached(["caelestia", "wallpaper", "-f", path, ...smartArg]);
    }

    function preview(path: string): void {
        previewPath = path;
        showPreview = true;

        if (Colours.scheme === "dynamic")
            getPreviewColoursProc.running = true;
    }

    function stopPreview(): void {
        showPreview = false;
        if (previewColourLock)
            pendingPreviewClear = true;
        else
            Colours.showPreview = false;
    }

    onPreviewColourLockChanged: {
        if (!previewColourLock && pendingPreviewClear)
            Colours.showPreview = false;
    }

    list: [...wallpapers.entries, ...videos.entries]

    // Runs before the background creates any video player, since it binds to this service
    Component.onCompleted: {
        appliedDecoder = GlobalConfig.background.videoDecoder;
        if (decoderEnv[appliedDecoder])
            CUtils.setEnv("QT_FFMPEG_DECODING_HW_DEVICE_TYPES", decoderEnv[appliedDecoder]);
    }
    key: "relativePath"
    useFuzzy: GlobalConfig.launcher.useFuzzy.wallpapers
    extraOpts: useFuzzy ? ({}) : ({
            forward: false
        })

    IpcHandler {
        function get(): string {
            return root.actualCurrent;
        }

        function set(path: string): void {
            root.setWallpaper(path);
        }

        function list(): string {
            return root.list.map(w => w.path).join("\n");
        }

        target: "wallpaper"
    }

    FileView {
        path: root.currentNamePath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            let wall = text().trim();
            if (wall.startsWith(root.posterDir))
                return; // Intermediate state while setting a video, the video path is written right after
            if (!wall) {
                wall = root.fallback;
                Quickshell.execDetached(["caelestia", "wallpaper", "-f", root.fallback, ...root.smartArg]);
            }
            root.actualCurrent = wall;
            root.previewColourLock = false;
        }
        onLoadFailed: {
            root.actualCurrent = root.fallback;
            root.previewColourLock = false;
            Quickshell.execDetached(["caelestia", "wallpaper", "-f", root.fallback, ...root.smartArg]);
        }
    }

    FileSystemModel {
        id: wallpapers

        recursive: true
        path: Paths.wallsdir
        filter: FileSystemModel.Images
    }

    FileSystemModel {
        id: videos

        recursive: true
        path: Paths.wallsdir
        filter: FileSystemModel.Files
        nameFilters: Images.validVideoExtensions.map(e => `*.${e}`)
    }

    Process {
        id: getPreviewColoursProc

        command: Images.isVideo(root.previewPath) ? ["sh", "-c", root.posterScript, "sh", root.previewPath, root.posterFor(root.previewPath), "", "caelestia", "wallpaper", "-p", root.posterFor(root.previewPath), ...root.smartArg] : ["caelestia", "wallpaper", "-p", root.previewPath, ...root.smartArg]
        stdout: StdioCollector {
            onStreamFinished: {
                Colours.load(text, true);
                Colours.showPreview = true;
            }
        }
    }
}
