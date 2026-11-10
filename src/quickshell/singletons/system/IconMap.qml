pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../../"

// Icon name -> file path map. The image://icon provider renders blank in this
// shell, so icons are loaded by path instead (see launcher/icon_resolver.py).
Item {
    id: root

    property var map: ({})
    readonly property string mapPath: Caching.getCacheDir("launcher") + "/icon_map.json"

    // Returns a loadable URL for an icon name, path or URL ("" if none).
    function resolve(ic) {
        if (!ic) return "";
        ic = ic.toString();
        if (ic.startsWith("image://icon/")) {
            let name = ic.substring(13);
            return root.map[name] ? "file://" + root.map[name] : ic;
        }
        if (ic.startsWith("file://") || ic.startsWith("image://") || ic.startsWith("http://") || ic.startsWith("https://")) return ic;
        if (ic.startsWith("/")) return "file://" + ic;
        let baseName = ic.replace(/\.(png|svg|xpm|ico)$/i, "");
        let mapped = root.map[ic] || root.map[baseName];
        if (mapped) return "file://" + mapped;
        return "image://icon/" + baseName;
    }

    function refresh() {
        if (!resolverProc.running) resolverProc.running = true;
    }

    FileView {
        path: root.mapPath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try { root.map = JSON.parse(text()); } catch (e) {}
        }
    }

    Process {
        id: resolverProc
        command: ["python3", Caching.qsDir + "/launcher/icon_resolver.py", root.mapPath]
        running: true
    }
}
