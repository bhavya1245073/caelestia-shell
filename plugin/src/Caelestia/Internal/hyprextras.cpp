#include "hyprextras.hpp"
#include "hyprdevices.hpp"

#include <qdir.h>
#include <qjsonarray.h>
#include <qjsonobject.h>
#include <qlocalsocket.h>
#include <qloggingcategory.h>
#include <qregularexpression.h>
#include <qvariant.h>

Q_LOGGING_CATEGORY(lcHypr, "caelestia.internal.hypr", QtInfoMsg)

namespace caelestia::internal::hypr {

namespace {

// The JSON type of an option's default, as a name QML can switch on, refined into
// the types Hyprland's lua config actually distinguishes.
//
// `hyprctl descriptions` does not report a declared type, so this infers one from
// the shape of the reported value. That is reliable because Hyprland's own
// reporting is consistent per type, and it is the only way to tell
// `general:gaps_in` (css_gaps, "5 5 5 5") from `general:layout` (str, "dwindle")
// when both arrive as JSON strings.
//
// Matters because the lua config is typed where the old conf syntax was not:
//   https://wiki.hypr.land/Configuring/Basics/Variables/
//   gradient -> a color, or { colors = { "rgba(..)" , ... }, angle? = 45 }
//   vec2     -> { 20, 20 }
//   css_gaps -> an integer, or { top?, left?, right?, bottom? }
// Handing any of those the space-separated string Hyprland reports gets it parsed
// as a single colour or silently ignored.
QString inferType(const QString& name, const QJsonValue& value) {
    // font_weight is the one type the reported value cannot distinguish: it comes
    // back as the string "400", but the lua config wants either an integer 100-1000
    // or a named preset ("bold", "normal", ...). Keyed off the name because every
    // such option is spelled font_weight*.
    if (name.contains(QLatin1String("font_weight"))) {
        return QStringLiteral("font_weight");
    }

    switch (value.type()) {
    case QJsonValue::Bool:
        return QStringLiteral("bool");
    case QJsonValue::Double:
        return QStringLiteral("number");
    case QJsonValue::Array:
        return QStringLiteral("vec2");
    case QJsonValue::String:
        break;
    default:
        return QStringLiteral("unknown");
    }

    const auto s = value.toString().trimmed();

    // Gradients always come back with a trailing angle, e.g. "ff444444 0deg" or
    // "ff0000ff 0000ffff 45deg".
    static const QRegularExpression gradientRe(QStringLiteral("^(?:[0-9a-fA-F]{6,8}\\s+)+\\d+(?:\\.\\d+)?deg$"));
    if (gradientRe.match(s).hasMatch()) {
        return QStringLiteral("gradient");
    }

    // Two or four bare numbers, e.g. "5 5 5 5".
    static const QRegularExpression gapsRe(QStringLiteral("^-?\\d+(?:\\s+-?\\d+)+$"));
    if (gapsRe.match(s).hasMatch()) {
        return QStringLiteral("css_gaps");
    }

    return QStringLiteral("string");
}

// A value as Hyprland's own config syntax wants it. QVariant::toString gives
// "true"/"false" for bools, which is already what `keyword` expects, but a double
// that happens to be integral must not come out as "1e+06".
QString confValue(const QVariant& value) {
    if (value.typeId() == QMetaType::Double || value.typeId() == QMetaType::Float) {
        const auto d = value.toDouble();
        if (qFuzzyCompare(d, qRound(d)))
            return QString::number(qRound(d));
        return QString::number(d, 'f', 6);
    }
    return value.toString();
}

// One colour token as the `rgba(RRGGBBAA)` string form the lua docs use inside a
// gradient's `colors` list.
//
// The digit orders differ and this is the whole reason gradients broke: Hyprland
// *reports* colours as bare AARRGGBB (and accepts 0xAARRGGBB), but rgba() takes
// RRGGBBAA. Anything with a comma is a decimal rgb()/rgba() literal, which is
// already valid lua-side, so it is passed through untouched.
QString luaColour(QString token) {
    token = token.trimmed();
    if (token.isEmpty()) {
        return QStringLiteral("\"rgba(00000000)\"");
    }
    if (token.contains(QLatin1Char(','))) {
        return QLatin1Char('"') + token + QLatin1Char('"');
    }

    // Already in an explicitly-ordered form: keep the order, only normalise 6-digit
    // values to a full alpha.
    const auto rgbaPrefixed = token.startsWith(QLatin1String("rgba(")) || token.startsWith(QLatin1String("rgb(")) ||
                              token.startsWith(QLatin1Char('#'));

    static const QRegularExpression hexRe(QStringLiteral("([0-9a-fA-F]{3,8})"));
    const auto match = hexRe.match(token);
    if (!match.hasMatch()) {
        return QLatin1Char('"') + token + QLatin1Char('"');
    }

    auto hex = match.captured(1);

    if (rgbaPrefixed) {
        // #rgb / #rgbа shorthand is web syntax; leave those to Hyprland's own parser.
        if (hex.length() < 6) {
            return QLatin1Char('"') + token + QLatin1Char('"');
        }
        if (hex.length() == 6) {
            hex += QLatin1String("ff");
        }
        return QStringLiteral("\"rgba(%1)\"").arg(hex);
    }

    // Bare or 0x-prefixed: AARRGGBB, so rotate the alpha to the end.
    if (hex.length() == 8) {
        return QStringLiteral("\"rgba(%1%2)\"").arg(hex.mid(2), hex.left(2));
    }
    if (hex.length() == 6) {
        return QStringLiteral("\"rgba(%1ff)\"").arg(hex);
    }
    return QLatin1Char('"') + token + QLatin1Char('"');
}

// "ff0000ff 0000ffff 45deg" -> { colors = { "rgba(ff0000ff)", "rgba(0000ffff)" }, angle = 45 }
//
// The table form is used even for a single stop: a gradient accepts a plain colour
// too, but one shape for every case means no branch that only runs for gradients
// someone happens to have set to one colour.
QString luaGradient(const QString& value) {
    static const QRegularExpression angleRe(QStringLiteral("([0-9]+(?:\\.[0-9]+)?)deg\\s*$"));
    const auto angleMatch = angleRe.match(value);

    auto colourPart = value;
    double angle = 0;
    if (angleMatch.hasMatch()) {
        angle = angleMatch.captured(1).toDouble();
        colourPart = value.left(angleMatch.capturedStart(0));
    }

    // Split on whitespace, but keep `rgba(1,2,3,0.5)` in one piece.
    QStringList colours;
    int depth = 0;
    QString current;
    for (const auto c : colourPart) {
        if (c == QLatin1Char('(')) {
            depth++;
        } else if (c == QLatin1Char(')')) {
            depth--;
        }

        if (c.isSpace() && depth <= 0) {
            if (!current.trimmed().isEmpty()) {
                colours.append(luaColour(current));
            }
            current.clear();
            continue;
        }
        current += c;
    }
    if (!current.trimmed().isEmpty()) {
        colours.append(luaColour(current));
    }

    if (colours.isEmpty()) {
        return QStringLiteral("{ colors = { \"rgba(00000000)\" }, angle = 0 }");
    }

    return QStringLiteral("{ colors = { %1 }, angle = %2 }")
        .arg(colours.join(QLatin1String(", ")), QString::number(angle, 'g', 6));
}

// The numbers in a reported value like "0 0" or "5 5 5 5", or a JSON array.
QList<double> numbersIn(const QVariant& value) {
    QList<double> out;

    if (value.typeId() == QMetaType::QVariantList) {
        for (const auto& v : value.toList()) {
            out.append(v.toDouble());
        }
        return out;
    }

    static const QRegularExpression sepRe(QStringLiteral("[\\s,]+"));
    const auto parts = value.toString().trimmed().split(sepRe, Qt::SkipEmptyParts);
    for (const auto& p : parts) {
        bool ok = false;
        const auto d = p.toDouble(&ok);
        if (ok) {
            out.append(d);
        }
    }
    return out;
}

// vec2 -> { x, y }
QString luaVec2(const QVariant& value) {
    const auto nums = numbersIn(value);
    const auto x = nums.size() > 0 ? nums[0] : 0;
    const auto y = nums.size() > 1 ? nums[1] : x;
    return QStringLiteral("{ %1, %2 }").arg(QString::number(x, 'g', 6), QString::number(y, 'g', 6));
}

// css_gaps -> an integer, or { top =, right =, bottom =, left = }
//
// Named keys rather than a positional table, since that is what the lua docs
// specify. The positions follow the CSS shorthand Hyprland's own reporting uses:
// 1 value is all sides, 2 is vertical/horizontal, 3 is top/horizontal/bottom, and
// 4 is top/right/bottom/left.
QString luaGaps(const QVariant& value) {
    const auto n = numbersIn(value);
    if (n.isEmpty()) {
        return QStringLiteral("0");
    }
    if (n.size() == 1) {
        return QString::number(n[0], 'g', 6);
    }

    double top = n[0];
    double right = n[0];
    double bottom = n[0];
    double left = n[0];

    if (n.size() == 2) {
        right = left = n[1];
    } else if (n.size() == 3) {
        right = left = n[1];
        bottom = n[2];
    } else {
        right = n[1];
        bottom = n[2];
        left = n[3];
    }

    return QStringLiteral("{ top = %1, right = %2, bottom = %3, left = %4 }")
        .arg(QString::number(top, 'g', 6), QString::number(right, 'g', 6), QString::number(bottom, 'g', 6),
            QString::number(left, 'g', 6));
}

// A value as a lua literal. Strings have to be quoted and escaped - the previous
// version of applyOptions interpolated them raw, which is a syntax error for
// every string option (layout, col.*, kb_layout, ...).
QString luaLiteral(const QVariant& value, const QString& type) {
    if (type == QLatin1String("gradient")) {
        return luaGradient(value.toString());
    }
    if (type == QLatin1String("vec2")) {
        return luaVec2(value);
    }
    if (type == QLatin1String("css_gaps")) {
        return luaGaps(value);
    }
    if (type == QLatin1String("font_weight")) {
        // A numeric weight has to go over as a number; a preset name as a string.
        bool ok = false;
        const auto n = value.toString().trimmed().toInt(&ok);
        if (ok) {
            return QString::number(n);
        }
    }

    switch (value.typeId()) {
    case QMetaType::Bool:
        return value.toBool() ? QStringLiteral("true") : QStringLiteral("false");
    case QMetaType::Int:
    case QMetaType::UInt:
    case QMetaType::LongLong:
    case QMetaType::ULongLong:
    case QMetaType::Double:
    case QMetaType::Float:
        return confValue(value);
    default:
        break;
    }

    auto s = value.toString();
    s.replace(QLatin1Char('\\'), QLatin1String("\\\\"));
    s.replace(QLatin1Char('"'), QLatin1String("\\\""));
    s.replace(QLatin1Char('\n'), QLatin1String("\\n"));
    return QLatin1Char('"') + s + QLatin1Char('"');
}

} // namespace

HyprExtras::HyprExtras(QObject* parent)
    : QObject(parent)
    , m_requestSocket("")
    , m_eventSocket("")
    , m_socket(nullptr)
    , m_socketValid(false)
    , m_devices(new HyprDevices(this)) {
    const auto his = qEnvironmentVariable("HYPRLAND_INSTANCE_SIGNATURE");
    if (his.isEmpty()) {
        qCWarning(lcHypr) << "$HYPRLAND_INSTANCE_SIGNATURE is unset. Unable to connect to Hyprland socket.";
        return;
    }

    auto hyprDir = QString("%1/hypr/%2").arg(qEnvironmentVariable("XDG_RUNTIME_DIR"), his);
    if (!QDir(hyprDir).exists()) {
        hyprDir = "/tmp/hypr/" + his;

        if (!QDir(hyprDir).exists()) {
            qCWarning(lcHypr) << "Hyprland socket directory does not exist. Unable to connect to Hyprland socket.";
            return;
        }
    }

    m_requestSocket = hyprDir + "/.socket.sock";
    m_eventSocket = hyprDir + "/.socket2.sock";

    refreshOptions();
    refreshDevices();

    m_socket = new QLocalSocket(this);

    QObject::connect(m_socket, &QLocalSocket::errorOccurred, this, &HyprExtras::socketError);
    QObject::connect(m_socket, &QLocalSocket::stateChanged, this, &HyprExtras::socketStateChanged);
    QObject::connect(m_socket, &QLocalSocket::readyRead, this, &HyprExtras::readEvent);

    m_socket->connectToServer(m_eventSocket, QLocalSocket::ReadOnly);
}

QVariantHash HyprExtras::options() const {
    return m_options;
}

QVariantList HyprExtras::optionDescriptions() const {
    return m_optionDescriptions;
}

HyprDevices* HyprExtras::devices() const {
    return m_devices;
}

void HyprExtras::message(const QString& message) {
    if (message.isEmpty()) {
        return;
    }

    makeRequest(message, [](bool success, const QByteArray& res) {
        if (!success) {
            qCWarning(lcHypr) << "message: request error:" << QString::fromUtf8(res);
        }
    });
}

void HyprExtras::batchMessage(const QStringList& messages) {
    if (messages.isEmpty()) {
        return;
    }

    makeRequest("[[BATCH]]" + messages.join(";"), [](bool success, const QByteArray& res) {
        if (!success) {
            qCWarning(lcHypr) << "batchMessage: request error:" << QString::fromUtf8(res);
        }
    });
}

void HyprExtras::applyOptions(const QVariantHash& options) {
    if (options.isEmpty()) {
        return;
    }

    QString request;
    request.reserve(12 + options.size() * 48);
    request += QLatin1String("[[BATCH]]");
    for (auto it = options.constBegin(); it != options.constEnd(); ++it) {
        if (!m_usingLua) {
            request +=
                QLatin1String("keyword ") + it.key() + QLatin1Char(' ') + confValue(it.value()) + QLatin1Char(';');
        } else {
            // `general:col.active_border` is `general.col.active_border` in lua, so
            // the path splits on both separators - Hyprland's own colon-and-dot
            // spelling is flat, the lua API is nested all the way down.
            const auto parts = it.key().split(QRegularExpression(QStringLiteral("[:.]")), Qt::SkipEmptyParts);
            if (parts.isEmpty()) {
                continue;
            }
            request += QLatin1String("eval hl.config({ ") + parts.join(QLatin1String(" = { ")) + QLatin1String(" = ") +
                       luaLiteral(it.value(), m_optionTypes.value(it.key())) +
                       QStringLiteral(" }").repeated(parts.size()) + QLatin1String(");");
        }
    }

    makeRequest(request, [this](bool success, const QByteArray& res) {
        if (success) {
            refreshOptions();
        } else {
            qCWarning(lcHypr) << "applyOptions: request error" << QString::fromUtf8(res);
        }
    });
}

void HyprExtras::reloadConfig() {
    // The only way back to a value the config *file* sets: `keyword` overrides are
    // in-memory only, and there is no "unset keyword".
    makeRequest(QStringLiteral("reload"), [this](bool success, const QByteArray& res) {
        if (success) {
            refreshOptions();
        } else {
            qCWarning(lcHypr) << "reloadConfig: request error" << QString::fromUtf8(res);
        }
    });
}

void HyprExtras::refreshOptions() {
    if (!m_optionsRefresh.isNull()) {
        m_optionsRefresh->close();
    }

    m_optionsRefresh = makeRequestJson("descriptions", [this](bool success, const QJsonDocument& response) {
        m_optionsRefresh.reset();
        if (!success) {
            return;
        }

        const auto options = response.array();
        bool dirty = false;
        QVariantList descriptions;
        descriptions.reserve(options.size());

        for (const auto& o : std::as_const(options)) {
            const auto obj = o.toObject();

            // Two schemas in the wild. Hyprland >=0.45 flattens the entry:
            //   { name, description, default, current, min, max, map }
            // older builds nested the value:
            //   { value, description, data: { current, ... } }
            // Accept both, so this keeps working across a Hyprland bump either way.
            const auto data = obj.value(QStringLiteral("data")).toObject();
            const auto key = obj.contains(QStringLiteral("name")) ? obj.value(QStringLiteral("name")).toString()
                                                                  : obj.value(QStringLiteral("value")).toString();
            if (key.isEmpty()) {
                continue;
            }

            const auto pick = [&obj, &data](const char* name) -> QJsonValue {
                const auto k = QLatin1String(name);
                return obj.contains(k) ? obj.value(k) : data.value(k);
            };

            const auto current = pick("current");
            const auto def = pick("default");

            // vec2 arrives as a JSON array; flatten it to the same space-separated form
            // every other multi-value option reports, so QML has one shape to render and
            // parse back.
            const auto flatten = [](const QJsonValue& v) -> QVariant {
                if (!v.isArray()) {
                    return v.toVariant();
                }
                QStringList parts;
                for (const auto& e : v.toArray()) {
                    parts.append(QString::number(e.toDouble()));
                }
                return parts.join(QLatin1Char(' '));
            };

            const auto currentVar = flatten(current);
            if (m_options.value(key) != currentVar) {
                dirty = true;
                m_options.insert(key, currentVar);
            }

            const auto type = inferType(key, def.isUndefined() || def.isNull() ? current : def);
            m_optionTypes.insert(key, type);

            // Enum maps arrive as an array of single-entry objects; flatten to one
            // map so QML can just iterate it.
            QVariantMap map;
            for (const auto& e : pick("map").toArray()) {
                const auto entry = e.toObject();
                for (auto it = entry.constBegin(); it != entry.constEnd(); ++it) {
                    map.insert(it.key(), it.value().toVariant());
                }
            }

            const auto sep = key.lastIndexOf(QLatin1Char(':'));
            descriptions.append(QVariantMap{
                { QStringLiteral("name"), key },
                // "input:touchpad:scroll_factor" -> category "input:touchpad", key "scroll_factor".
                // Splitting on the *last* colon keeps nested sections as their own
                // category rather than lumping them under the top-level one.
                { QStringLiteral("category"), sep < 0 ? QString() : key.left(sep) },
                { QStringLiteral("key"), sep < 0 ? key : key.mid(sep + 1) },
                { QStringLiteral("description"), pick("description").toString() },
                { QStringLiteral("type"), type },
                { QStringLiteral("default"), flatten(def) },
                { QStringLiteral("current"), currentVar },
                { QStringLiteral("min"), pick("min").toVariant() },
                { QStringLiteral("max"), pick("max").toVariant() },
                { QStringLiteral("map"), map },
            });
        }

        if (dirty || descriptions != m_optionDescriptions) {
            m_optionDescriptions = std::move(descriptions);
            emit optionsChanged();
        }
    });
}

void HyprExtras::refreshDevices() {
    if (!m_devicesRefresh.isNull()) {
        m_devicesRefresh->close();
    }

    m_devicesRefresh = makeRequestJson("devices", [this](bool success, const QJsonDocument& response) {
        m_devicesRefresh.reset();
        if (success) {
            m_devices->updateLastIpcObject(response.object());
        }
    });
}

void HyprExtras::socketError(QLocalSocket::LocalSocketError error) const {
    if (!m_socketValid) {
        qCWarning(lcHypr) << "socketError: unable to connect to Hyprland event socket:" << error;
    } else {
        qCWarning(lcHypr) << "socketError: Hyprland event socket error:" << error;
    }
}

void HyprExtras::socketStateChanged(QLocalSocket::LocalSocketState state) {
    if (state == QLocalSocket::UnconnectedState && m_socketValid) {
        qCWarning(lcHypr) << "socketStateChanged: Hyprland event socket disconnected.";
    }

    m_socketValid = state == QLocalSocket::ConnectedState;
}

void HyprExtras::readEvent() {
    while (true) {
        auto rawEvent = m_socket->readLine();
        if (rawEvent.isEmpty()) {
            break;
        }
        rawEvent.truncate(rawEvent.length() - 1); // Remove trailing \n
        const auto event = QByteArrayView(rawEvent.data(), rawEvent.indexOf(">>"));
        handleEvent(QString::fromUtf8(event));
    }
}

void HyprExtras::handleEvent(const QString& event) {
    if (event == "configreloaded") {
        refreshOptions();
    } else if (event == "activelayout") {
        refreshDevices();
    }
}

HyprExtras::SocketPtr HyprExtras::makeRequestJson(
    const QString& request, const std::function<void(bool, QJsonDocument)>& callback) {
    return makeRequest("j/" + request, [callback](bool success, const QByteArray& response) {
        callback(success, QJsonDocument::fromJson(response));
    });
}

HyprExtras::SocketPtr HyprExtras::makeRequest(
    const QString& request, const std::function<void(bool, QByteArray)>& callback) {
    if (m_requestSocket.isEmpty()) {
        return SocketPtr();
    }

    auto socket = SocketPtr::create(this);

    QObject::connect(socket.data(), &QLocalSocket::connected, this, [=, this]() {
        QObject::connect(socket.data(), &QLocalSocket::readyRead, this, [socket, callback]() {
            const auto response = socket->readAll();
            callback(true, std::move(response));
            socket->close();
        });

        socket->write(request.toUtf8());
        socket->flush();
    });

    QObject::connect(socket.data(), &QLocalSocket::errorOccurred, this, [=](QLocalSocket::LocalSocketError err) {
        qCWarning(lcHypr) << "makeRequest: error making request:" << err << "| request:" << request;
        callback(false, {});
        socket->close();
    });

    socket->connectToServer(m_requestSocket);

    return socket;
}

} // namespace caelestia::internal::hypr
