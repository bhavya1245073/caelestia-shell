#pragma once

#include "configobject.hpp"

#include <qstring.h>
#include <qvariant.h>

namespace caelestia::config {

using Qt::StringLiterals::operator""_s;

// The launcher's GIF search mode.
//
// Provider-switchable, because the GIF API landscape is unstable: Google shut the
// Tenor API down on 30 June 2026, and Giphy's free tier has been progressively
// restricted. Klipy is the default - it is run by ex-Tenor people, is the migration
// target Bluesky and Zulip moved to, and its free tier is not time limited.
//
// Every provider needs a key, and none of them hand out a usable shared one any
// more, so keys are stored per provider. Switching provider therefore does not
// throw away the key you already pasted for the other one.
class GifConfig : public ConfigObject {
    Q_OBJECT
    QML_ANONYMOUS

    CONFIG_PROPERTY(bool, enabled, true)
    // "klipy" | "giphy" | "tenor". See Gifs.providers for what each needs.
    CONFIG_GLOBAL_PROPERTY(QString, provider, u"klipy"_s)
    // provider name -> API key. Not a secret: every provider expects the key to be
    // visible to clients, which is why this lives in shell.json rather than anywhere
    // guarded.
    CONFIG_GLOBAL_PROPERTY(QVariantMap, apiKeys, {})
    // How many results to request per search.
    CONFIG_PROPERTY(int, limit, 30)
    // "off" | "low" | "medium" | "high", mapped onto whatever vocabulary the active
    // provider uses.
    CONFIG_GLOBAL_PROPERTY(QString, contentFilter, u"medium"_s)
    // ms to wait after the last keystroke before searching. Every provider rate
    // limits, and a request per character burns a free tier quickly.
    CONFIG_PROPERTY(int, searchDebounce, 350)
    // Cap on the on-disk GIF cache, in MB. Oldest files are evicted first.
    CONFIG_PROPERTY(int, cacheSizeMb, 200)
    // Copy the file itself, so pasting into a chat uploads the GIF. Off copies only
    // the link, which is what most web chats actually want.
    CONFIG_PROPERTY(bool, copyFile, true)
    // Also put the URL on the clipboard as text/plain, for apps that ignore images.
    CONFIG_PROPERTY(bool, copyUrlAsText, true)
    // Locale for provider results, "xx_YY". Empty follows the system locale.
    CONFIG_GLOBAL_PROPERTY(QString, locale, u""_s)
    // Opaque per-install id. Klipy uses it to personalise and to attribute ad
    // revenue; it is generated once and never leaves the provider request.
    CONFIG_GLOBAL_PROPERTY(QString, customerId, u""_s)
    // Saved GIFs, newest first. Each entry is
    // {id, url, previewUrl, title, width, height, provider}.
    CONFIG_GLOBAL_PROPERTY(QVariantList, favourites, {})

public:
    explicit GifConfig(QObject* parent = nullptr)
        : ConfigObject(parent) {}
};

} // namespace caelestia::config
