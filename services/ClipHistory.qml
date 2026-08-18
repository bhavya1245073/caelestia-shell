pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.utils

// Clipboard history, backed by cliphist.
//
// Replaces the separate fuzzel picker that `caelestia clipboard` used to open. That
// picker was limited to cliphist's own one-line summary of an entry, which for an
// image is the literal text "[[ binary data 210 KiB png 1918x1033 ]]" - so the one
// thing worth seeing before pasting was the one thing it could not show. Here an
// image entry is decoded and shown, and a text entry can be read in full.
Singleton {
    id: root

    readonly property string lc: "ClipHistory"

    // Newest first, which is cliphist's own order and the one that matters.
    property list<var> entries: []
    property bool loading
    property string error

    // Decoded images live in the cache, not the state dir: cliphist is the source of
    // truth and every file here can be regenerated from it.
    readonly property string cacheDir: `${Paths.cache}/clipboard`

    readonly property int maxPreviewBytes: Math.max(0, GlobalConfig.clipboard.maxPreviewSizeMb) * 1024 * 1024

    // cliphist has no "unlimited", so a limit of 0 becomes a number larger than any
    // real history rather than being passed through as 0 - which cliphist would read
    // as "keep nothing".
    readonly property int storeLimit: GlobalConfig.clipboard.historyLimit > 0 ? GlobalConfig.clipboard.historyLimit : 1000000

    readonly property list<string> storeCommand: ["cliphist", "store", "-max-items", `${storeLimit}`, "-max-dedupe-search", `${Math.max(1, GlobalConfig.clipboard.dedupeSearch)}`, "-min-store-length", `${Math.max(0, GlobalConfig.clipboard.minStoreLength)}`, "-preview-width", `${Math.max(20, GlobalConfig.clipboard.previewWidth)}`]

    // Decode an entry to a file, reusing it if already there. Written to a .part first
    // so a half-written image is never handed to an Image element, and touched on
    // reuse so the cache evicts by actual use rather than by first sight.
    readonly property string decodeScript: `
        id=$1; dir=$2; out=$3; maxmb=$4
        mkdir -p "$dir" || exit 1
        if [ ! -s "$out" ]; then
            cliphist decode "$id" > "$out.part" 2>/dev/null || { rm -f "$out.part"; exit 1; }
            mv -f "$out.part" "$out"
        else
            touch "$out"
        fi
        used=$(du -sm "$dir" 2>/dev/null | cut -f1)
        if [ "\${used:-0}" -gt "$maxmb" ]; then
            ls -1t "$dir" | tail -n +2 | while IFS= read -r old; do
                [ "$dir/$old" = "$out" ] && continue
                rm -f -- "$dir/$old"
                used=$(du -sm "$dir" 2>/dev/null | cut -f1)
                [ "\${used:-0}" -le "$maxmb" ] && break
            done
        fi
        printf '%s' "$out"
    `

    signal copied(entry: var)

    function refresh(): void {
        listProc.running = false;
        listProc.running = true;
    }

    // Substring match, not fuzzy, and recency order is preserved.
    //
    // Clipboard history is the one list where order carries real meaning - the thing
    // you want is nearly always among the last few - so scoring by similarity would
    // bury an exact recent match under older near-misses.
    function query(search: string): var {
        const s = search.trim().toLowerCase();
        if (!s)
            return [...entries];
        return entries.filter(e => e.searchText.includes(s));
    }

    function copy(entry: var): void {
        if (!entry)
            return;

        // Piped through sh so the decode streams into wl-copy: an image entry can be
        // megabytes, and passing it through QML would mean holding and re-encoding it.
        const paste = GlobalConfig.clipboard.pasteOnAccept ? " && (sleep 0.15; wtype -M ctrl -P v -p v -m ctrl >/dev/null 2>&1 &)" : "";
        Quickshell.execDetached(["sh", "-c", `cliphist decode "$1" | wl-copy${paste}`, "caelestia-clip", `${entry.id}`]);
        copied(entry);
    }

    function remove(entry: var): void {
        if (!entry)
            return;

        // cliphist delete takes the list line on stdin, id and preview both, so the
        // raw line is kept on every entry rather than reconstructed here.
        deleteProc.command = ["sh", "-c", 'printf "%s\\n" "$1" | cliphist delete', "caelestia-clip", entry.raw];
        deleteProc.running = true;

        // Drop it locally too, so the row goes away on keypress instead of after the
        // reload that follows.
        entries = entries.filter(e => e.id !== entry.id);
    }

    function wipe(): void {
        if (!GlobalConfig.clipboard.allowWipe)
            return;

        wipeProc.running = true;
        entries = [];
    }

    // Where an entry's decoded bytes will be once decodeFor has run. Deterministic, so
    // a delegate rebuilt on scroll finds the existing file instead of decoding again.
    function pathFor(entry: var): string {
        if (!entry)
            return "";
        return `${cacheDir}/${entry.id}${entry.ext}`;
    }

    function shouldPreview(entry: var): bool {
        if (!entry?.isImage || !GlobalConfig.clipboard.imagePreviews)
            return false;
        return maxPreviewBytes <= 0 || entry.bytes <= maxPreviewBytes;
    }

    function decodeCommand(entry: var): var {
        return ["sh", "-c", decodeScript, "caelestia-clip", `${entry.id}`, cacheDir, pathFor(entry), `${Math.max(1, GlobalConfig.clipboard.cacheSizeMb)}`];
    }

    // cliphist reports image entries as "[[ binary data 210 KiB png 1918x1033 ]]".
    // Nothing else in its output has that shape, so this is what distinguishes an
    // image from text that happens to mention binary data.
    function parseLine(line: string): var {
        const tab = line.indexOf("\t");
        if (tab < 1)
            return null;

        const id = line.slice(0, tab);
        const preview = line.slice(tab + 1);
        const m = /^\[\[\s*binary data\s+([\d.]+)\s*([KMGT]?i?B)\s+(\S+)\s+(\d+)x(\d+)\s*\]\]$/.exec(preview);

        if (m) {
            const size = parseFloat(m[1]);
            const unit = m[2].toUpperCase();
            const mult = unit.startsWith("T") ? 1024 ** 4 : unit.startsWith("G") ? 1024 ** 3 : unit.startsWith("M") ? 1024 ** 2 : unit.startsWith("K") ? 1024 : 1;
            const type = m[3].toLowerCase();

            return {
                id,
                raw: line,
                preview,
                isImage: true,
                type,
                ext: `.${type === "jpeg" ? "jpg" : type}`,
                bytes: Math.round(size * mult),
                sizeText: `${m[1]} ${m[2]}`,
                width: parseInt(m[4], 10),
                height: parseInt(m[5], 10),
                // An image has no text to match on, so searching for "png" or "image"
                // finds them - which is the only sensible query for one.
                searchText: `image ${type} ${m[4]}x${m[5]}`
            };
        }

        return {
            id,
            raw: line,
            preview,
            isImage: false,
            type: "text",
            ext: ".txt",
            bytes: preview.length,
            sizeText: "",
            width: 0,
            height: 0,
            searchText: preview.toLowerCase()
        };
    }

    Component.onCompleted: refresh()

    Process {
        id: listProc

        command: ["cliphist", "list"]
        onRunningChanged: if (running)
            root.loading = true

        stdout: StdioCollector {
            onStreamFinished: {
                const max = GlobalConfig.clipboard.maxEntries;
                const lines = text.split("\n");
                const out = [];

                for (const line of lines) {
                    if (!line)
                        continue;
                    const e = root.parseLine(line);
                    if (e)
                        out.push(e);
                    if (max > 0 && out.length >= max)
                        break;
                }

                root.entries = out;
                root.error = "";
                root.loading = false;
            }
        }

        stderr: StdioCollector {
            onStreamFinished: {
                if (!text.trim())
                    return;

                // A missing cliphist is the one failure worth naming, because the fix is
                // installing it rather than anything about the shell.
                root.error = text.trim().split("\n")[0];
                root.loading = false;
                console.warn(root.lc, `cliphist list failed: ${root.error}`);
            }
        }

        onExited: (code, status) => {
            root.loading = false;
            if (code !== 0 && !root.error)
                root.error = qsTr("cliphist exited with %1").arg(code);
        }
    }

    Process {
        id: deleteProc

        onExited: code => {
            if (code !== 0)
                console.warn(root.lc, `cliphist delete failed with ${code}`);
            root.refresh();
        }
    }

    Process {
        id: wipeProc

        command: ["cliphist", "wipe"]
        onExited: code => {
            if (code !== 0)
                console.warn(root.lc, `cliphist wipe failed with ${code}`);
            root.refresh();
        }
    }

    // The watchers that populate the history.
    //
    // Owned here so the store limits are live: changing one restarts these, where the
    // usual `exec-once` in the compositor config would need a logout. Two are needed
    // because wl-paste watches one mime type at a time.
    Process {
        id: textWatcher

        running: GlobalConfig.clipboard.enabled && GlobalConfig.clipboard.manageWatcher
        command: ["wl-paste", "--type", "text", "--watch", ...root.storeCommand]
    }

    Process {
        id: imageWatcher

        running: GlobalConfig.clipboard.enabled && GlobalConfig.clipboard.manageWatcher
        command: ["wl-paste", "--type", "image", "--watch", ...root.storeCommand]
    }

    // Reload after a copy lands, so the entry moves to the top the way it has actually
    // moved in the history. Debounced because a copy triggers the watcher too.
    Timer {
        id: reloadTimer

        interval: 400
        onTriggered: root.refresh()
    }

    Connections {
        function onCopied(): void {
            reloadTimer.restart();
        }

        target: root
    }

    IpcHandler {
        function list(): string {
            return root.entries.map(e => `${e.id}\t${e.preview}`).join("\n");
        }

        function copy(id: string): string {
            const entry = root.entries.find(e => e.id === id);
            if (!entry)
                return `No entry ${id}`;
            root.copy(entry);
            return "Copied";
        }

        function remove(id: string): string {
            const entry = root.entries.find(e => e.id === id);
            if (!entry)
                return `No entry ${id}`;
            root.remove(entry);
            return "Deleted";
        }

        function wipe(): string {
            if (!GlobalConfig.clipboard.allowWipe)
                return "Wiping is disabled in settings";
            root.wipe();
            return "Wiped";
        }

        function refresh(): void {
            root.refresh();
        }

        target: "clipboard"
    }
}
