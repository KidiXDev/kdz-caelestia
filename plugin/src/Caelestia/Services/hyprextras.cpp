#include "hyprextras.hpp"

#include <qdir.h>
#include <qjsonarray.h>
#include <qjsondocument.h>
#include <qlocalsocket.h>
#include <qloggingcategory.h>
#include <qvariant.h>

#include "hyprdevices.hpp"

namespace {

Q_LOGGING_CATEGORY(lcHypr, "caelestia.services.hypr", QtInfoMsg)

} // namespace

namespace caelestia::services::hypr {

using Qt::StringLiterals::operator""_s;

HyprExtras::HyprExtras(QObject* parent)
    : QObject(parent)
    , m_socket(nullptr)
    , m_socketValid(false)
    , m_devices(new HyprDevices(this)) {
    const auto his = qEnvironmentVariable("HYPRLAND_INSTANCE_SIGNATURE");
    if (his.isEmpty()) {
        qCWarning(lcHypr) << "$HYPRLAND_INSTANCE_SIGNATURE is unset. Unable to connect to Hyprland socket.";
        return;
    }

    auto hyprDir = u"%1/hypr/%2"_s.arg(qEnvironmentVariable("XDG_RUNTIME_DIR"), his);
    if (!QDir(hyprDir).exists()) {
        hyprDir = u"/tmp/hypr/"_s + his;

        if (!QDir(hyprDir).exists()) {
            qCWarning(lcHypr) << "Hyprland socket directory does not exist. Unable to connect to Hyprland socket.";
            return;
        }
    }

    m_requestSocket = hyprDir + u"/.socket.sock"_s;
    m_eventSocket = hyprDir + u"/.socket2.sock"_s;

    refreshOptions();
    refreshDevices();
    refreshMonitors();

    m_socket = new QLocalSocket(this);

    QObject::connect(m_socket, &QLocalSocket::errorOccurred, this, &HyprExtras::socketError);
    QObject::connect(m_socket, &QLocalSocket::stateChanged, this, &HyprExtras::socketStateChanged);
    QObject::connect(m_socket, &QLocalSocket::readyRead, this, &HyprExtras::readEvent);

    m_socket->connectToServer(m_eventSocket, QLocalSocket::ReadOnly);
}

QVariantHash HyprExtras::options() const {
    return m_options;
}

QVariantList HyprExtras::monitors() const {
    return m_monitors;
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

void HyprExtras::batchMessage(const QStringList& messages, const QJSValue& callback) {
    if (messages.isEmpty()) {
        return;
    }

    const auto request =
        makeRequest(u"[[BATCH]]"_s + messages.join(u";"_s), [callback](bool success, const QByteArray& res) {
            if (!success) {
                qCWarning(lcHypr) << "batchMessage: request error:" << QString::fromUtf8(res);
            }

            if (callback.isCallable()) {
                callback.call({ success, QString::fromUtf8(res) });
            }
        });

    // No socket to send it to, so it's never going to reply
    if (request.isNull() && callback.isCallable()) {
        callback.call({ false, QString() });
    }
}

void HyprExtras::applyOptions(const QVariantHash& options) {
    if (options.isEmpty()) {
        return;
    }

    QString request;
    request.reserve(12 + options.size() * 40);
    request += u"[[BATCH]]"_s;
    for (auto it = options.constBegin(); it != options.constEnd(); ++it) {
        if (!m_usingLua) {
            request += u"keyword "_s + it.key() + u' ' + it.value().toString() + u';';
        } else {
            auto parts = it.key().split(u':');
            request += u"eval hl.config({ "_s + parts.join(u" = { "_s) + u" = "_s + it.value().toString() +
                       u" }"_s.repeated(parts.size() - 1) + u" });"_s;
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

void HyprExtras::refreshOptions() {
    cancelRequest(m_optionsRefresh);

    m_optionsRefresh = makeRequestJson(u"descriptions"_s, [this](bool success, const QJsonDocument& response) {
        m_optionsRefresh.reset();
        if (!success) {
            return;
        }

        const auto options = response.array();
        bool dirty = false;

        for (const auto& o : std::as_const(options)) {
            const auto obj = o.toObject();
            const auto key = obj.value(u"value"_s).toString();
            const auto value = obj.value(u"data"_s).toObject().value(u"current"_s).toVariant();
            if (m_options.value(key) != value) {
                dirty = true;
                m_options.insert(key, value);
            }
        }

        if (dirty) {
            emit optionsChanged();
        }
    });
}

void HyprExtras::refreshDevices() {
    cancelRequest(m_devicesRefresh);

    m_devicesRefresh = makeRequestJson(u"devices"_s, [this](bool success, const QJsonDocument& response) {
        m_devicesRefresh.reset();
        if (success) {
            m_devices->updateLastIpcObject(response.object());
        }
    });
}

void HyprExtras::refreshMonitors() {
    cancelRequest(m_monitorsRefresh);

    m_monitorsRefresh = makeRequestJson(u"monitors all"_s, [this](bool success, const QJsonDocument& response) {
        m_monitorsRefresh.reset();
        if (!success || !response.isArray()) {
            return;
        }

        const auto monitors = response.array().toVariantList();
        if (m_monitors != monitors) {
            m_monitors = monitors;
            emit monitorsChanged();
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
        const auto sep = rawEvent.indexOf(">>");
        if (sep < 0) {
            qCWarning(lcHypr) << "readEvent: malformed event (no >> separator):" << rawEvent;
            continue;
        }
        handleEvent(QString::fromUtf8(QByteArrayView(rawEvent.data(), sep)));
    }
}

void HyprExtras::handleEvent(const QString& event) {
    if (event == u"configreloaded"_s) {
        refreshOptions();
        refreshMonitors();
    } else if (event == u"activelayout"_s) {
        refreshDevices();
    } else if (event == u"monitoradded"_s || event == u"monitorremoved"_s) {
        refreshMonitors();
    }
}

void HyprExtras::cancelRequest(SocketPtr& socket) {
    if (socket.isNull()) {
        return;
    }

    // Drop the handlers first so closing doesn't report a partial response
    socket->disconnect(this);
    socket->close();
    socket.reset();
}

HyprExtras::SocketPtr HyprExtras::makeRequestJson(
    const QString& request, const std::function<void(bool, QJsonDocument)>& callback) {
    return makeRequest(u"j/"_s + request, [callback](bool success, const QByteArray& response) {
        callback(success, QJsonDocument::fromJson(response));
    });
}

HyprExtras::SocketPtr HyprExtras::makeRequest(
    const QString& request, const std::function<void(bool, QByteArray)>& callback) {
    if (m_requestSocket.isEmpty()) {
        return {};
    }

    auto socket = SocketPtr::create(this);
    auto reply = QSharedPointer<PendingReply>::create();

    QObject::connect(socket.data(), &QLocalSocket::connected, this, [socket, request]() {
        socket->write(request.toUtf8());
        socket->flush();
    });

    // Large responses can arrive in several chunks, so only finish once Hyprland closes the connection
    QObject::connect(socket.data(), &QLocalSocket::readyRead, this, [socket, reply]() {
        reply->data += socket->readAll();
    });

    QObject::connect(socket.data(), &QLocalSocket::disconnected, this, [socket, reply, callback]() {
        if (reply->finished) {
            return;
        }

        reply->finished = true;
        reply->data += socket->readAll();
        callback(true, reply->data);
    });

    QObject::connect(socket.data(), &QLocalSocket::errorOccurred, this,
        [socket, reply, request, callback](QLocalSocket::LocalSocketError err) {
            if (err == QLocalSocket::PeerClosedError || reply->finished) {
                return;
            }

            reply->finished = true;
            qCWarning(lcHypr) << "makeRequest: error making request:" << err << "| request:" << request;
            callback(false, {});
            socket->close();
        });

    socket->connectToServer(m_requestSocket);

    return socket;
}

} // namespace caelestia::services::hypr
