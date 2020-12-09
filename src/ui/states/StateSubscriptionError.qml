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

    height: window.safeContentHeight
    width: window.width

    VPNHeadline {
        id: headline

        anchors.top: root.top
        anchors.topMargin: root.height * 0.08
        anchors.horizontalCenter: root.horizontalCenter
        width: Math.min(Theme.maxTextWidth, root.width * .85)
        //% "Error confirming subscription…"
        text: qsTrId("vpn.subscription.subscriptionValidationError")

    }

    Item {
        height: root.height - (headline.y + headline.paintedHeight) - (footerItems.childrenRect.height) - Theme.rowHeight
        anchors.top: headline.bottom
        anchors.left: root.left
        anchors.right: root.right
        width: root.width

        Item {
            id: floatingContentWrapper

            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            anchors.left: parent.left
            height: childrenRect.height

            Rectangle {
                id: warningIconWrapper

                height: 48
                width: 48
                color: Theme.red
                radius: height / 2
                anchors.top: floatingContentWrapper.top
                anchors.horizontalCenter: floatingContentWrapper.horizontalCenter
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
                width: Theme.maxTextWidth
                font.pixelSize: Theme.fontSize
                lineHeight: 22
                //% "Another Firefox Account has already subscribed using this Apple ID."
                text:qsTrId("vpn.subscription.anotherFxaSubscribed")
            }

            VPNTextBlock {
                id: copyBlock2

                anchors.top: copyBlock1.bottom
                anchors.topMargin: Theme.windowMargin * 1.5
                anchors.horizontalCenter: parent.horizontalCenter
                horizontalAlignment: Text.AlignHCenter
                width: Theme.maxTextWidth
                font.pixelSize: Theme.fontSize
                lineHeight: 22
                //% "Visit our help center to learn more about managing your subscriptions."
                text: qsTrId("vpn.subscription.visitHelpCenter")
            }


        }
    }

    Item {
        id: footerItems

        anchors.bottom: root.bottom
        anchors.left: root.left
        anchors.right: root.right


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

}
