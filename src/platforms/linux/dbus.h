#ifndef DBUS_H
#define DBUS_H

#include "dbus_interface.h"

#include <QObject>

class Server;
class Device;
class Keys;
class QDBusPendingCallWatcher;

class DBus : public QObject
{
    Q_OBJECT

public:
    DBus(QObject *parent);

    void activate(const Server &server, const Device *device, const Keys *keys);
    void deactivate(const Server &server, const Device *device, const Keys *keys);

signals:
    void failed();
    void succeeded();

private:
    void monitorReply(QDBusPendingReply<bool> &reply);

private:
    OrgMozillaVpnDbusInterface *m_dbus;
};

#endif // DBUS_H