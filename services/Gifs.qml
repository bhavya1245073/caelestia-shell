pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia
import Caelestia.Config
import qs.utils

// GIF search for the launcher.
//
// Provider-agnostic by design. Google killed the Tenor API on 30 June 2026 and
// Giphy's free tier keeps shrinking, so treating "which service" as configuration
// rather than a hardcoded choice is the only thing that ages well. Adding a provider
// means adding one entry to `providers` below - a URL builder and a parser - and
// nothing else in the shell changes.
//
// Every provider normalises to one shape, so the launcher never asks who answered:
//
//   { id, url, previewUrl, title, width, height, provider }
//
// `url` is the full-size GIF that gets copied; `previewUrl` is a small looping GIF
// for the picker row. Keeping them apart matters - full-size GIFs routinely run to
// several MB, and a row of nine of those makes the launcher stutter.
Singleton {
    id: root

    // No provider ships a usable public key any more, so all three need one. The
    // signup links are surfaced in the UI rather than buried in docs.
    readonly property var providers: ({
            klipy: {
                label: "Klipy",
                keyUrl: "https://klipy.com/developers",
                // Recommended default: free tier with no time limit, run by ex-Tenor staff,
                // and the service Bluesky and Zulip moved to after the Tenor shutdown.
                note: qsTr("Free, no expiry. Recommended."),
                search: (q, limit) => `https://api.klipy.com/api/v1/${encodeURIComponent(root.apiKey)}/gifs/search?q=${encodeURIComponent(q)}&per_page=${Math.max(8, Math.min(50, limit))}&page=1&locale=${encodeURIComponent(root.localeTag)}&content_filter=${encodeURIComponent(root.filterLevel)}&customer_id=${encodeURIComponent(root.customerId)}`,
                trending: limit => `https://api.klipy.com/api/v1/${encodeURIComponent(root.apiKey)}/gifs/trending?per_page=${Math.max(8, Math.min(50, limit))}&page=1&locale=${encodeURIComponent(root.localeTag)}&content_filter=${encodeURIComponent(root.filterLevel)}&customer_id=${encodeURIComponent(root.customerId)}`,
                parse: data => root.parseKlipy(data)
            },
            giphy: {
                label: "Giphy",
                keyUrl: "https://developers.giphy.com/dashboard/",
                note: qsTr("Free beta keys are rate limited."),
                search: (q, limit) => `https://api.giphy.com/v1/gifs/search?api_key=${encodeURIComponent(root.apiKey)}&q=${encodeURIComponent(q)}&limit=${limit}&rating=${root.giphyRating}&bundle=messaging_non_clips`,
                trending: limit => `https://api.giphy.com/v1/gifs/trending?api_key=${encodeURIComponent(root.apiKey)}&limit=${limit}&rating=${root.giphyRating}&bundle=messaging_non_clips`,
                parse: data => root.parseGiphy(data)
            },
            tenor: {
                label: "Tenor",
                keyUrl: "https://console.cloud.google.com/apis/library/tenor.googleapis.com",
                // Kept only so an existing enterprise key still works. Google shut the
                // public API down on 30 June 2026 and issues no new keys.
                note: qsTr("Discontinued by Google in June 2026."),
                deprecated: true,
                search: (q, limit) => `https://tenor.googleapis.com/v2/search?key=${encodeURIComponent(root.apiKey)}&q=${encodeURIComponent(q)}&limit=${limit}&contentfilter=${root.filterLevel}&media_filter=gif,tinygif&locale=${encodeURIComponent(root.localeTag)}&client_key=caelestia`,
                trending: limit => `https://tenor.googleapis.com/v2/featured?key=${encodeURIComponent(root.apiKey)}&limit=${limit}&contentfilter=${root.filterLevel}&media_filter=gif,tinygif&locale=${encodeURIComponent(root.localeTag)}&client_key=caelestia`,
                parse: data => root.parseTenor(data)
            }
        })

    readonly property list<string> providerNames: ["klipy", "giphy", "tenor"]
    readonly property string providerName: providers.hasOwnProperty(GlobalConfig.gifs.provider) ? GlobalConfig.gifs.provider : "klipy"
    readonly property var provider: providers[providerName]
    readonly property string providerLabel: provider.label

    readonly property string apiKey: `${GlobalConfig.gifs.apiKeys[providerName] ?? ""}`.trim()
    readonly property bool needsKey: !apiKey

    readonly property string filterLevel: {
        const f = GlobalConfig.gifs.contentFilter.toLowerCase();
        return ["off", "low", "medium", "high"].includes(f) ? f : "medium";
    }

    // Giphy uses MPAA-ish letters; map the shared four-level setting onto them so one
    // setting covers every provider.
    readonly property string giphyRating: {
        switch (filterLevel) {
        case "off":
            return "r";
        case "low":
            return "pg-13";
        case "medium":
            return "pg";
        default:
            return "g";
        }
    }

    // Providers want "xx_YY". Qt gives "en_GB" already, but a bare "C" locale would
    // be rejected, so fall back to something valid.
    readonly property string localeTag: {
        const set = GlobalConfig.gifs.locale.trim();
        if (set)
            return set;

        const name = Qt.locale().name;
        return /^[a-z]{2}_[A-Z]{2}$/.test(name) ? name : "en_US";
    }

    readonly property string cacheDir: `${Paths.cache}/gifs`

    // Current search state. `list` is what the launcher renders.
    property string query
    property list<var> results: []
    property bool loading
    property string error

    // Saved GIFs, newest first. Lives in shell.json so it survives restarts and can
    // be edited or synced with the rest of the config.
    readonly property var favourites: GlobalConfig.gifs.favourites

    // An empty query shows saved GIFs, so `>gif` alone is a usable "my GIFs" view.
    // With nothing saved yet it falls through to the provider's trending list, which
    // is more useful than an empty box.
    readonly property bool showingFavourites: !query.trim() && favourites.length > 0
    readonly property bool showingTrending: !query.trim() && favourites.length === 0
    readonly property list<var> list: showingFavourites ? favourites : results

    // Opaque per-install id. Klipy personalises results with it and attributes ad
    // revenue by it; the other providers ignore it. Generated once, imperatively -
    // as a binding that writes the config it reads, this would be a binding loop.
    readonly property string customerId: GlobalConfig.gifs.customerId

    // Download, put the file on the clipboard, then trim the cache.
    //
    // wl-copy has to stay alive to serve paste requests, so it is deliberately
    // backgrounded and left running - it exits once the clipboard moves on.
    // `--type image/gif` is what makes chat apps treat this as an animation to upload
    // rather than a still frame.
    readonly property string copyScript: `
        shift
        url=$1; dir=$2; name=$3; alsotext=$4; maxmb=$5
        mkdir -p "$dir" || exit 1
        f="$dir/$name"
        if [ ! -s "$f" ]; then
            curl -fsSL --max-time 30 -o "$f.part" "$url" || { rm -f "$f.part"; exit 1; }
            mv -f "$f.part" "$f"
        else
            touch "$f"
        fi
        if [ "$alsotext" = 1 ]; then
            printf '%s' "$url" | wl-copy --type text/plain
        fi
        wl-copy --type image/gif < "$f" &
        # Trim oldest-first once over budget. Newline-delimited, so a cache name with a
        # space in it cannot make this delete the wrong file.
        used=$(du -sm "$dir" 2>/dev/null | cut -f1)
        if [ "\${used:-0}" -gt "$maxmb" ]; then
            ls -1t "$dir" | tail -n +2 | while IFS= read -r old; do
                rm -f -- "$dir/$old"
                used=$(du -sm "$dir" 2>/dev/null | cut -f1)
                [ "\${used:-0}" -le "$maxmb" ] && break
            done
        fi
        printf '%s' "$f"
    `

    signal copied(item: var)
    signal copyFailed(reason: string)

    function setProvider(name: string): void {
        if (!providers.hasOwnProperty(name))
            return;

        GlobalConfig.gifs.provider = name;
        // Results from the old provider are meaningless now, and a stale error message
        // about the previous key is actively misleading.
        results = [];
        error = "";
        const q = query;
        query = "";
        search(q);
    }

    function setKey(key: string): void {
        // QVariantMap arrives as a plain JS object; mutating it in place will not trip
        // the config property's change detection, so always assign a fresh copy.
        const next = Object.assign({}, GlobalConfig.gifs.apiKeys);
        next[providerName] = key.trim();
        GlobalConfig.gifs.apiKeys = next;

        if (key.trim())
            refresh();
    }

    function openKeyPage(): void {
        Quickshell.execDetached(["xdg-open", provider.keyUrl]);
    }

    function search(q: string): void {
        q = q.trim();
        if (q === query && (results.length > 0 || loading))
            return;

        query = q;
        error = "";

        if (needsKey) {
            results = [];
            loading = false;
            debounce.stop();
            error = qsTr("Add a %1 API key to search").arg(providerLabel);
            return;
        }

        loading = true;
        debounce.restart();
    }

    function refresh(): void {
        if (needsKey)
            return;

        loading = true;
        debounce.restart();
    }

    function fetch(q: string): void {
        const limit = Math.max(1, Math.min(50, GlobalConfig.gifs.limit));

        // Tag the request with what it was made for, so a slow response to an
        // abandoned search cannot overwrite a newer one.
        const requestedFor = q;
        const forProvider = providerName;
        const url = q ? provider.search(q, limit) : provider.trending(limit);

        Requests.get(url, text => {
            if (root.query.trim() !== requestedFor || root.providerName !== forProvider)
                return;

            root.loading = false;

            try {
                const data = JSON.parse(text);
                root.results = root.provider.parse(data);
                root.error = root.results.length === 0 ? qsTr("No GIFs found") : "";
            } catch (e) {
                root.error = qsTr("Could not read the response from %1").arg(root.providerLabel);
                root.results = [];
                console.warn(logCat, "Failed to parse response:", e);
            }
        }, (err, metadata) => {
            if (root.query.trim() !== requestedFor || root.providerName !== forProvider)
                return;

            root.loading = false;
            root.results = [];

            const status = metadata?.statusCode ?? 0;
            // "Search failed" is useless to someone who can fix this in ten seconds, so
            // name the actual problem.
            if (status === 401 || status === 403)
                root.error = qsTr("%1 rejected the API key").arg(root.providerLabel);
            else if (status === 429)
                root.error = qsTr("Rate limited by %1. Try again shortly.").arg(root.providerLabel);
            else if (status === 0)
                root.error = qsTr("No connection to %1").arg(root.providerLabel);
            else
                root.error = qsTr("%1 returned an error (%2)").arg(root.providerLabel).arg(status);

            console.warn(logCat, "GIF search failed:", err, status);
        });
    }

    // Klipy: { result, data: { data: [ { id, slug, title, file: { hd|md|sm|xs: {
    //   gif|webp|mp4|...: { url, width, height } } } } ] } }
    //
    // Pick `md` for copying: `hd` is frequently several MB for no visible gain at chat
    // size, and `sm` is the largest tier that stays smooth as a preview.
    function parseKlipy(data: var): var {
        const items = data.data?.data ?? data.data ?? [];
        return items.map(r => {
            // The docs say `file`; some responses and older docs say `files`.
            const f = r.file ?? r.files ?? {};
            const full = f.md?.gif ?? f.hd?.gif ?? f.sm?.gif;
            const tiny = f.sm?.gif ?? f.xs?.gif ?? full;
            if (!full?.url)
                return null;

            return {
                id: `klipy:${r.id ?? r.slug}`,
                url: full.url,
                previewUrl: tiny?.url ?? full.url,
                title: r.title || r.slug || "GIF",
                width: full.width ?? 0,
                height: full.height ?? 0,
                provider: "klipy"
            };
        }).filter(r => r !== null);
    }

    function parseTenor(data: var): var {
        return (data.results ?? []).map(r => {
            const full = r.media_formats?.gif;
            const tiny = r.media_formats?.tinygif ?? full;
            if (!full?.url)
                return null;

            return {
                id: `tenor:${r.id}`,
                url: full.url,
                previewUrl: tiny?.url ?? full.url,
                title: r.content_description || r.title || "GIF",
                width: full.dims?.[0] ?? 0,
                height: full.dims?.[1] ?? 0,
                provider: "tenor"
            };
        }).filter(r => r !== null);
    }

    function parseGiphy(data: var): var {
        return (data.data ?? []).map(r => {
            const full = r.images?.original;
            const tiny = r.images?.fixed_width ?? r.images?.downsized ?? full;
            if (!full?.url)
                return null;

            return {
                id: `giphy:${r.id}`,
                // Giphy appends tracking params; the bare URL is what belongs on a clipboard.
                url: full.url.split("?")[0],
                previewUrl: tiny?.url ?? full.url,
                title: r.title || "GIF",
                width: parseInt(full.width) || 0,
                height: parseInt(full.height) || 0,
                provider: "giphy"
            };
        }).filter(r => r !== null);
    }

    // Copy to clipboard. The GIF has to be downloaded first: wl-copy can only serve
    // bytes it has, and handing an app a URL as image/gif gets you a broken image.
    function copy(item: var): void {
        if (!item?.url)
            return;

        if (!GlobalConfig.gifs.copyFile) {
            copyUrlOnly(item);
            return;
        }

        copyProc.item = item;
        copyProc.command = ["sh", "-c", copyScript, "caelestia-gif", item.url, root.cacheDir, cacheName(item), GlobalConfig.gifs.copyUrlAsText ? "1" : "0", `${Math.max(1, GlobalConfig.gifs.cacheSizeMb)}`];
        copyProc.running = true;
    }

    function copyUrlOnly(item: var): void {
        Quickshell.execDetached(["wl-copy", "--", item.url]);
        copied(item);
    }

    // A stable, filesystem-safe cache name. The extension matters: some apps sniff
    // the name rather than the mime type they were handed.
    function cacheName(item: var): string {
        return `${item.id}`.replace(/[^a-zA-Z0-9_-]/g, "-") + ".gif";
    }

    function isFavourite(item: var): bool {
        return favourites.some(f => f.id === item?.id);
    }

    function toggleFavourite(item: var): void {
        if (!item?.id)
            return;

        if (isFavourite(item)) {
            GlobalConfig.gifs.favourites = favourites.filter(f => f.id !== item.id);
        } else {
            GlobalConfig.gifs.favourites = [
                {
                    id: item.id,
                    url: item.url,
                    previewUrl: item.previewUrl,
                    title: item.title,
                    width: item.width,
                    height: item.height,
                    provider: item.provider
                },
                ...favourites];
        }
    }

    function clearFavourites(): void {
        GlobalConfig.gifs.favourites = [];
    }

    Component.onCompleted: {
        if (!GlobalConfig.gifs.customerId)
            GlobalConfig.gifs.customerId = `${Math.random().toString(36).slice(2)}${Date.now().toString(36)}`;
    }

    LoggingCategory {
        id: logCat

        name: "caelestia.gifs"
        defaultLogLevel: LoggingCategory.Info
    }

    Timer {
        id: debounce

        interval: Math.max(0, GlobalConfig.gifs.searchDebounce)
        onTriggered: root.fetch(root.query.trim())
    }

    Process {
        id: copyProc

        property var item

        stdout: StdioCollector {}

        onExited: code => {
            if (code === 0) {
                root.copied(copyProc.item);
            } else {
                // A failed download should still leave something pasteable.
                console.warn(logCat, "Failed to copy GIF, falling back to URL");
                root.copyUrlOnly(copyProc.item);
                root.copyFailed(qsTr("Copied the link instead"));
            }
        }
    }

    IpcHandler {
        function search(query: string): string {
            root.search(query);
            return `Searching ${root.providerLabel} for: ${query}`;
        }

        function provider(name: string): string {
            if (!name)
                return root.providerName;
            if (!root.providers.hasOwnProperty(name))
                return `Unknown provider: ${name}. Available: ${root.providerNames.join(", ")}`;
            root.setProvider(name);
            return `Provider set to ${root.providerLabel}`;
        }

        function providers(): string {
            return root.providerNames.map(n => `${n === root.providerName ? "* " : "  "}${n}${root.providers[n].deprecated ? " (discontinued)" : ""}${`${GlobalConfig.gifs.apiKeys[n] ?? ""}` ? " [key set]" : " [no key]"}`).join("\n");
        }

        function setKey(key: string): string {
            root.setKey(key);
            return key.trim() ? `Key set for ${root.providerLabel}` : `Key cleared for ${root.providerLabel}`;
        }

        function favourites(): string {
            return root.favourites.map(f => `${f.title}\t${f.url}`).join("\n");
        }

        target: "gifs"
    }
}
