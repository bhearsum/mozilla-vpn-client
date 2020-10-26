/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

#include "serverdata.h"
#include "logger.h"
#include "servercountrymodel.h"
#include "settingsholder.h"

namespace {
Logger logger(LOG_MODEL, "ServerData");
}

bool ServerData::fromSettings(SettingsHolder &settingsHolder)
{
    if (!settingsHolder.hasCurrentServerCountry() || !settingsHolder.hasCurrentServerCity()) {
        return false;
    }

    logger.log() << m_countryCode << m_city;

    initializeInternal(settingsHolder.currentServerCountry(), settingsHolder.currentServerCity());
    return true;
}

void ServerData::writeSettings(SettingsHolder &settingsHolder)
{
    settingsHolder.setCurrentServerCountry(m_countryCode);
    settingsHolder.setCurrentServerCity(m_city);
}

void ServerData::initialize(const ServerCountry &country, const ServerCity &city)
{
    logger.log() << "Country:" << country.name() << "City:" << city.name();

    initializeInternal(country.code(), city.name());
    emit changed();
}

void ServerData::update(const QString &countryCode, const QString &city)
{
    initializeInternal(countryCode, city);
    emit changed();
}

void ServerData::initializeInternal(const QString &countryCode, const QString &city)
{
    m_initialized = true;
    m_countryCode = countryCode;
    m_city = city;
}
