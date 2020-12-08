/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */


import QtQuick 2.0
import Mozilla.VPN 1.0
import "../components"

import "../themes/themes.js" as Theme

Item {
    id: root

    property var headlineText
    property var footerLinkIsVisible: true

    Component.onCompleted: fade.start()
    height: window.safeContentHeight
    width: parent.width

    VPNHeadline {
        id: headline

        anchors.top: root.top
        anchors.topMargin: root.height * 0.08
        anchors.horizontalCenter: root.horizontalCenter
        width: Math.min(Theme.maxTextWidth, root.width * .85)
        //% "Error confirming subscription…"
//        text: qsTrId("vpn.subscription.subscriptionValidationError")
        text: "Error confirming subscription…"
    }

    Rectangle {
        id: warningIconWrapper

        height: 48
        width: 48
        color: Theme.red
        radius: height / 2
        anchors.top: headline.bottom
        anchors.topMargin: Theme.windowMargin * 2
        anchors.horizontalCenter: parent.horizontalCenter

        Image {
            source: "../resources/warning-white.svg"
            antialiasing: true
            sourceSize.height: 20
            sourceSize.width: 20
            anchors.centerIn: parent
        }
    }

    VPNTextBlock {
        id: copyBlock1
        anchors.top: warningIconWrapper.bottom
        anchors.topMargin: Theme.windowMargin * 2
        anchors.horizontalCenter: parent.horizontalCenter
        horizontalAlignment: Text.AlignHCenter
        //% "Another Firefox Account has already subscribed using this Apple ID."
        text: "Another Firefox Account has already subscribed using this Apple ID."
    }

    VPNTextBlock {
        id: copyBlock2
        anchors.top: copyBlock1.bottom
        anchors.topMargin: Theme.windowMargin
        anchors.horizontalCenter: parent.horizontalCenter
        horizontalAlignment: Text.AlignHCenter
        //% "Visit our help center below to learn more about how to manage your subscriptions."
        text: "Visit our help center below to learn more about how to manage your subscriptions."
    }

    VPNButton {
        text: "Get help"
        anchors.bottom: signOff.top
        anchors.bottomMargin: Theme.windowMargin
        anchors.horizontalCenter: parent.horizontalCenter
    }

    VPNSignOut {
        id: signOff
        height: Theme.rowHeight
    }

}
