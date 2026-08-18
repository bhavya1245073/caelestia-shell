#pragma once

#include "configobject.hpp"

#include <qstring.h>
#include <qvariant.h>

namespace caelestia::config {

using Qt::StringLiterals::operator""_s;

// The launcher's clipboard history mode, backed by cliphist.
//
// This replaces the separate fuzzel picker `caelestia clipboard` used to open. That
// picker could only ever show cliphist's own one-line summary of an entry, which for
// an image is the literal text "[[ binary data 210 KiB png 1918x1033 ]]" - so the one
// thing you most need to see before pasting was the one thing it could not show.
class ClipboardConfig : public ConfigObject {
    Q_OBJECT
    QML_ANONYMOUS

    CONFIG_PROPERTY(bool, enabled, true)

    // How many entries cliphist keeps. This is its `store -max-items`, so it governs
    // the history itself rather than what gets shown, and it only takes effect if the
    // watcher below is managed here. 0 means no practical limit.
    //
    // cliphist's own default is 750, which is low enough to lose things you still
    // wanted; the default here is large because the entries are small and the cost of
    // keeping them is a few MB of database, while the cost of losing one is retyping
    // it.
    CONFIG_PROPERTY(int, historyLimit, 100000)
    // Run the `wl-paste --watch cliphist store` pair from the shell.
    //
    // On because it is the only way the limits here can be applied without editing the
    // compositor config and logging out: changing one restarts the watchers. Off if
    // something else already starts them, in which case that owns the limits too.
    CONFIG_PROPERTY(bool, manageWatcher, true)
    // Shortest clip worth keeping, in characters (cliphist's `-min-store-length`).
    // Above 0 this stops single keystrokes and stray selections filling the history.
    CONFIG_PROPERTY(int, minStoreLength, 0)
    // How much of an entry cliphist puts in its own one-line summary
    // (`-preview-width`). That summary is what the list rows show, so this is the
    // length of a row before it elides, not a storage limit. Its default of 100 is
    // short enough that similar paragraphs look identical in the list.
    CONFIG_PROPERTY(int, previewWidth, 250)
    // How many recent entries cliphist checks for duplicates
    // (`-max-dedupe-search`). Higher keeps the history tidier when you copy the same
    // things repeatedly, at the cost of a longer look-back on every store.
    CONFIG_PROPERTY(int, dedupeSearch, 200)

    // How many entries the launcher lists. 0 shows the whole history.
    //
    // Only visible rows are built, so this is a cap on the parsed list rather than on
    // anything drawn, and searching stays over everything listed.
    CONFIG_PROPERTY(int, maxEntries, 0)
    // Decode image entries and show them, both as a row thumbnail and in the preview.
    // Off falls back to a description, which is all cliphist itself reports.
    CONFIG_PROPERTY(bool, imagePreviews, true)
    // Largest entry to decode for a preview, in MB. Past this the row shows the type
    // and size instead, because decoding runs on every focus change and a very large
    // image is both slow to write out and pointless to look at shrunk to a thumbnail.
    // 0 decodes regardless of size.
    CONFIG_PROPERTY(int, maxPreviewSizeMb, 32)
    // Show the side panel with the focused entry in full. Off leaves just the list,
    // where long text is necessarily truncated to its first line.
    CONFIG_PROPERTY(bool, showPreview, true)
    // Cap on the decoded-image cache, in MB. Oldest files are evicted first. This is
    // only a render cache - cliphist remains the source of truth, so a small value
    // costs redecoding rather than history.
    CONFIG_PROPERTY(int, cacheSizeMb, 500)
    // Copy on enter without pasting. On also sends a paste keystroke to the window
    // that had focus, which needs `wtype` installed.
    CONFIG_PROPERTY(bool, pasteOnAccept, false)
    // Wipe the entire history from the launcher. Off hides the shortcut, since it is
    // not undoable and sits one modifier away from deleting a single entry.
    CONFIG_PROPERTY(bool, allowWipe, true)

public:
    explicit ClipboardConfig(QObject* parent = nullptr)
        : ConfigObject(parent) {}
};

} // namespace caelestia::config
