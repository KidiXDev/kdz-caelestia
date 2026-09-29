#pragma once

#include <qjsvalue.h>
#include <qlocalsocket.h>
#include <qobject.h>
#include <qqmlintegration.h>
#include <qsharedpointer.h>
#include <qvariant.h>

namespace caelestia::services::hypr {

class HyprDevices;

class HyprExtras : public QObject {
    Q_OBJECT
    QML_ELEMENT
    Q_MOC_INCLUDE("hyprdevices.hpp")

    Q_PROPERTY(QVariantHash options READ options NOTIFY optionsChanged)
    Q_PROPERTY(QVariantList monitors READ monitors NOTIFY monitorsChanged)
    Q_PROPERTY(caelestia::services::hypr::HyprDevices* devices READ devices CONSTANT)
    Q_PROPERTY(bool usingLua MEMBER m_usingLua NOTIFY usingLuaChanged)

public:
    explicit HyprExtras(QObject* parent = nullptr);

    [[nodiscard]] QVariantHash options() const;
    [[nodiscard]] QVariantList monitors() const;
    [[nodiscard]] HyprDevices* devices() const;

    Q_INVOKABLE void message(const QString& message);
    Q_INVOKABLE void batchMessage(const QStringList& messages, const QJSValue& callback = {});
    Q_INVOKABLE void applyOptions(const QVariantHash& options);

    Q_INVOKABLE void refreshOptions();
    Q_INVOKABLE void refreshDevices();
    Q_INVOKABLE void refreshMonitors();

signals:
    void optionsChanged();
    void monitorsChanged();
    void usingLuaChanged();

private:
    using SocketPtr = QSharedPointer<QLocalSocket>;

    struct PendingReply {
        QByteArray data;
        bool finished = false;
    };

    QString m_requestSocket;
    QString m_eventSocket;
    QLocalSocket* m_socket;
    bool m_socketValid;
    bool m_usingLua = false;

    QVariantHash m_options;
    QVariantList m_monitors;
    HyprDevices* const m_devices;

    SocketPtr m_optionsRefresh;
    SocketPtr m_devicesRefresh;
    SocketPtr m_monitorsRefresh;

    void socketError(QLocalSocket::LocalSocketError error) const;
    void socketStateChanged(QLocalSocket::LocalSocketState state);
    void readEvent();
    void handleEvent(const QString& event);
    void cancelRequest(SocketPtr& socket);

    SocketPtr makeRequestJson(const QString& request, const std::function<void(bool, QJsonDocument)>& callback);
    SocketPtr makeRequest(const QString& request, const std::function<void(bool, QByteArray)>& callback);
};

} // namespace caelestia::services::hypr
