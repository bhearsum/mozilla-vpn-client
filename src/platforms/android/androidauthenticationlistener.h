/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

#ifndef ANDROIDAUTHENTICATIONLISTENER_H
#define ANDROIDAUTHENTICATIONLISTENER_H

#include "authenticationlistener.h"
#include "tasks/authenticate/desktopauthenticationlistener.h"

#include <QObject>

class AndroidAuthenticationListener final : public AuthenticationListener {
  Q_DISABLE_COPY_MOVE(AndroidAuthenticationListener)

 public:
  AndroidAuthenticationListener(QObject* parent);
  ~AndroidAuthenticationListener();

  void start(MozillaVPN* vpn, QUrl& url, QUrlQuery& query) override;

 private:
  DesktopAuthenticationListener* m_legacyAuth;
};

#endif  // ANDROIDAUTHENTICATIONLISTENER_H
