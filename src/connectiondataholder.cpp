/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

#include "connectiondataholder.h"
#include "logger.h"
#include "mozillavpn.h"
#include "networkrequest.h"

#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonValue>
#include <QSplineSeries>
#include <QValueAxis>

namespace {
Logger logger(LOG_NETWORKING, "ConnectionDataHolder");
}

constexpr int MAX_POINTS = 30;

// Let's refresh the IP address any 10 seconds.
constexpr int IPADDRESS_TIMER_MSEC = 10000;

// Let's check the connection status any second.
constexpr int CHECKSTATUS_TIMER_MSEC = 1000;
//% "Unknown"
//: Context - "The current ip-address is: unknown"
ConnectionDataHolder::ConnectionDataHolder() : m_ipAddress(qtTrId("vpn.connectionInfo.unknown"))
{
    emit ipAddressChanged();

    connect(&m_ipAddressTimer, &QTimer::timeout, [this]() { updateIpAddress(); });
    connect(&m_checkStatusTimer, &QTimer::timeout, [this]() {
        MozillaVPN::instance()->controller()->getStatus(
            [this](const QString &serverIpv4Gateway, uint64_t txBytes, uint64_t rxBytes) {
                if (!serverIpv4Gateway.isEmpty()) {
                    add(txBytes, rxBytes);
                }
            });
    });
}

void ConnectionDataHolder::enable()
{
    m_ipAddressTimer.start(IPADDRESS_TIMER_MSEC);
}

void ConnectionDataHolder::disable()
{
    m_ipAddressTimer.stop();
}

void ConnectionDataHolder::add(uint64_t txBytes, uint64_t rxBytes)
{
    logger.log() << "New connection data:" << txBytes << rxBytes;

    Q_ASSERT(!!m_txSeries == !!m_rxSeries);

    if (!m_txSeries) {
        return;
    }

    Q_ASSERT(m_txSeries->count() == MAX_POINTS);
    Q_ASSERT(m_rxSeries->count() == MAX_POINTS);

    // This is the first time we receive data. We need at least 2 calls in order to count the delta.
    if (m_initialized == false) {
        m_initialized = true;
        m_txBytes = txBytes;
        m_rxBytes = rxBytes;
        return;
    }

    // Normalize the value and store the previous max.
    uint64_t tmpTxBytes = txBytes;
    uint64_t tmpRxBytes = rxBytes;
    txBytes -= m_txBytes;
    rxBytes -= m_rxBytes;
    m_txBytes = tmpTxBytes;
    m_rxBytes = tmpRxBytes;

    m_maxBytes = std::max(m_maxBytes, std::max(txBytes, rxBytes));
    m_data.append(QPair(txBytes, rxBytes));

    while (m_data.length() > MAX_POINTS) {
        m_data.removeAt(0);
    }

    int i = 0;
    for (; i < MAX_POINTS - m_data.length(); ++i) {
        m_txSeries->replace(i, i, 0);
        m_rxSeries->replace(i, i, 0);
    }

    for (int j = 0; j < m_data.length(); ++j) {
        m_txSeries->replace(i, i, m_data.at(j).first);
        m_rxSeries->replace(i, i, m_data.at(j).second);
        ++i;
    }

    computeAxes();
    emit bytesChanged();
}

void ConnectionDataHolder::activate(const QVariant &a_txSeries,
                                    const QVariant &a_rxSeries,
                                    const QVariant &a_axisX,
                                    const QVariant &a_axisY)
{
    logger.log() << "Activated";

    QtCharts::QSplineSeries *txSeries = qobject_cast<QtCharts::QSplineSeries *>(
        a_txSeries.value<QObject *>());

    if (m_txSeries != txSeries) {
        m_txSeries = txSeries;
        connect(txSeries, &QObject::destroyed, [this]() { deactivate(); });
    }

    QtCharts::QSplineSeries *rxSeries = qobject_cast<QtCharts::QSplineSeries *>(
        a_rxSeries.value<QObject *>());

    if (m_rxSeries != rxSeries) {
        m_rxSeries = rxSeries;
        connect(rxSeries, &QObject::destroyed, [this]() { deactivate(); });
    }

    QtCharts::QValueAxis *axisX = qobject_cast<QtCharts::QValueAxis *>(a_axisX.value<QObject *>());

    if (m_axisX != axisX) {
        m_axisX = axisX;
        connect(axisX, &QObject::destroyed, [this]() { deactivate(); });
    }

    QtCharts::QValueAxis *axisY = qobject_cast<QtCharts::QValueAxis *>(a_axisY.value<QObject *>());

    if (m_axisY != axisY) {
        m_axisY = axisY;
        connect(axisY, &QObject::destroyed, [this]() { deactivate(); });
    }

    // Let's be sure we have all the x/y points.
    while (m_txSeries->count() < MAX_POINTS) {
        m_txSeries->append(m_txSeries->count(), 0);
        m_rxSeries->append(m_rxSeries->count(), 0);
    }

    m_checkStatusTimer.start(CHECKSTATUS_TIMER_MSEC);
}

void ConnectionDataHolder::deactivate()
{
    logger.log() << "Deactivated";

    reset();
    m_axisX = nullptr;
    m_axisY = nullptr;
    m_txSeries = nullptr;
    m_rxSeries = nullptr;

    m_checkStatusTimer.stop();
}

void ConnectionDataHolder::computeAxes()
{
    if (!m_axisX || !m_axisY) {
        return;
    }

    m_axisY->setRange(-1000, m_maxBytes * 1.5);
}

void ConnectionDataHolder::reset()
{
    logger.log() << "Resetting the data";

    m_initialized = false;
    m_txBytes = 0;
    m_rxBytes = 0;
    m_maxBytes = 0;
    m_data.clear();

    emit bytesChanged();

    if (m_txSeries) {
        Q_ASSERT(m_txSeries->count() == MAX_POINTS);
        Q_ASSERT(m_rxSeries->count() == MAX_POINTS);

        for (int i = 0; i < MAX_POINTS; ++i) {
            m_txSeries->replace(i, i, 0);
            m_rxSeries->replace(i, i, 0);
        }
    }

    updateIpAddress();
}

void ConnectionDataHolder::updateIpAddress()
{
    logger.log() << "Updating IP address";

    NetworkRequest *request = NetworkRequest::createForIpInfo(MozillaVPN::instance());
    connect(request, &NetworkRequest::requestFailed, [](QNetworkReply::NetworkError error) {
        logger.log() << "IP address request failed" << error;
    });

    connect(request, &NetworkRequest::requestCompleted, [this](const int &status, const QByteArray &data) {
        if (status == 200) {
            logger.log() << "IP address request completed";

            QJsonDocument json = QJsonDocument::fromJson(data);
            Q_ASSERT(json.isObject());
            QJsonObject obj = json.object();

            Q_ASSERT(obj.contains("ip"));
            QJsonValue value = obj.take("ip");
            Q_ASSERT(value.isString());

            m_ipAddress = value.toString();
            emit ipAddressChanged();
        } else {
            logger.logNon200Reply(status, data);
            return;
        }

    });
}

quint64 ConnectionDataHolder::txBytes() const
{
    return bytes(0);
}

quint64 ConnectionDataHolder::rxBytes() const
{
    return bytes(1);
}

quint64 ConnectionDataHolder::bytes(bool index) const
{
    uint64_t value = 0;
    for (const QPair<uint64_t, uint64_t> &pair : m_data) {
        value = std::max(value, (!index ? pair.first : pair.second));
    }

    return value;
}

void ConnectionDataHolder::connectionStateChanged()
{
    reset();

    if (m_txSeries && MozillaVPN::instance()->controller()->state() == Controller::StateOn) {
        m_checkStatusTimer.start();
    }
}
