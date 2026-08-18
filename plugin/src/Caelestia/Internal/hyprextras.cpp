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

// The JSON type of an option's default, as a name QML can switch on. Hyprland
// does not report a type field, so this is the only thing that says whether an
// option wants a toggle, a number box or a text field.
QString jsonTypeName(const QJsonValue& value) {
    switch (value.type()) {
        case QJsonValue::Bool: return QStringLiteral("bool");
        case QJsonValue::Double: return QStringLiteral("number");
        case QJsonValue::String: return QStringLiteral("string");
        case QJsonValue::Array: return QStringLiteral("array");
        default: return QStringLiteral("unknown");
    }
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

// A value as a lua literal. Strings have to be quoted and escaped - the previous
// version of applyOptions interpolated them raw, which is a syntax error for
// every string option (layout, col.*, kb_layout, ...).
QString luaLiteral(const QVariant& value) {
    switch (value.typeId()) {
        case QMetaType::Bool: return value.toBool() ? QStringLiteral("true") : QStringLiteral("false");
        case QMetaType::Int:
        case QMetaType::UInt:
        case QMetaType::LongLong:
        case QMetaType::ULongLong:
        case QMetaType::Double:
        case QMetaType::Float: return confValue(value);
        default: break;
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
            request += QLatin1String("keyword ") + it.key() + QLatin1Char(' ') + confValue(it.value()) +
                       QLatin1Char(';');
        } else {
            // `general:col.active_border` is `general.col.active_border` in lua, so
            // the path splits on both separators - Hyprland's own colon-and-dot
            // spelling is flat, the lua API is nested all the way down.
            const auto parts = it.key().split(QRegularExpression(QStringLiteral("[:.]")), Qt::SkipEmptyParts);
            if (parts.isEmpty()) {
                continue;
            }
            request += QLatin1String("eval hl.config({ ") + parts.join(QLatin1String(" = { ")) +
                       QLatin1String(" = ") + luaLiteral(it.value()) + QStringLiteral(" }").repeated(parts.size()) +
                       QLatin1String(");");
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

            if (m_options.value(key) != current.toVariant()) {
                dirty = true;
                m_options.insert(key, current.toVariant());
            }

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
                { QStringLiteral("type"), jsonTypeName(def.isUndefined() || def.isNull() ? current : def) },
                { QStringLiteral("default"), def.toVariant() },
                { QStringLiteral("current"), current.toVariant() },
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
