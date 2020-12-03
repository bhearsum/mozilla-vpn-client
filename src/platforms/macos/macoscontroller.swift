/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import NetworkExtension
import SystemConfiguration
import SystemExtensions

let vpnName = "Mozilla VPN"
var vpnBundleID = "";

private class MacOSControllerImplDelegate : NSObject {
    private var impl: MacOSControllerImpl? = nil

    public func setImpl(impl: MacOSControllerImpl) {
        self.impl = impl;
    }
}

private let vpnDelegate = MacOSControllerImplDelegate()

@objc class VPNIPAddressRange : NSObject {
    public var address: NSString = ""
    public var networkPrefixLength: UInt8 = 0
    public var isIpv6: Bool = false

    @objc init(address: NSString, networkPrefixLength: UInt8, isIpv6: Bool) {
        super.init()

        self.address = address
        self.networkPrefixLength = networkPrefixLength
        self.isIpv6 = isIpv6
    }
}

public class MacOSControllerImpl : NSObject {

    private var tunnel: NETunnelProviderManager? = nil
    private var stateChangeCallback: ((Bool) -> Void?)? = nil
    private var privateKey : Data? = nil
    private var deviceIpv4Address: String? = nil
    private var deviceIpv6Address: String? = nil
    private var switchingServer: Bool = false
    private var switchingServerConfig: TunnelConfiguration? = nil
    private var switchingServerFailureCallback: (() -> Void)? = nil
    private var initClosure: ((ConnectionState, Date?) -> Void)? = nil

    @objc enum ConnectionState: Int { case Error, Connected, Disconnected }

    @objc init(bundleID: String, privateKey: Data, deviceIpv4Address: String, deviceIpv6Address: String, closure: @escaping (ConnectionState, Date?) -> Void, callback: @escaping (Bool) -> Void) {
        super.init()

        assert(privateKey.count == TunnelConfiguration.keyLength)

        Logger.configureGlobal(tagged: "APP", withFilePath: "")

        vpnBundleID = bundleID;
        precondition(!vpnBundleID.isEmpty)

        stateChangeCallback = callback
        self.privateKey = privateKey
        self.deviceIpv4Address = deviceIpv4Address
        self.deviceIpv6Address = deviceIpv6Address

        NotificationCenter.default.addObserver(self, selector: #selector(self.vpnStatusDidChange(notification:)), name: Notification.Name.NEVPNStatusDidChange, object: nil)

        let request = OSSystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: "org.mozilla.macos.FirefoxVPN.network-extension",
            queue: .main
        )

        self.initClosure = closure

        vpnDelegate.setImpl(impl: self)
        request.delegate = vpnDelegate

        OSSystemExtensionManager.shared.submitRequest(request)
        Logger.global?.log(message: "SystemExtension request submitted.")
    }

    public func continueInit(status: Bool) {
        if (!status) {
            Logger.global?.log(message: "Failed to register the system extension")
            if (self.initClosure != nil) {
                self.initClosure!(ConnectionState.Error, nil)
                self.initClosure = nil
            }
            return
        }

        NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, error in
            if self == nil || self!.initClosure == nil {
                Logger.global?.log(message: "We are shutting down.")
                return
            }

            if let error = error {
                Logger.global?.log(message: "Loading from preference failed: \(error)")
                self!.initClosure!(ConnectionState.Error, nil)
                self!.initClosure = nil
                return
            }

            let nsManagers = managers ?? []
            Logger.global?.log(message: "We have received \(nsManagers.count) managers.")

            let tunnel = nsManagers.first(where: MacOSControllerImpl.isOurManager(_:))
            if tunnel == nil {
                Logger.global?.log(message: "Creating the tunnel")
                self!.tunnel = NETunnelProviderManager()
                self!.initClosure!(ConnectionState.Disconnected, nil)
                self!.initClosure = nil
                return
            }

            Logger.global?.log(message: "Tunnel already exists")

            self!.tunnel = tunnel
            if tunnel?.connection.status == .connected {
                self!.initClosure!(ConnectionState.Connected, tunnel?.connection.connectedDate)
            } else {
                self!.initClosure!(ConnectionState.Disconnected, nil)
            }

            self!.initClosure = nil
        }
    }

    @objc private func vpnStatusDidChange(notification: Notification) {
        guard let session = (notification.object as? NETunnelProviderSession), tunnel?.connection == session else { return }

        switch session.status {
        case .connected:
            Logger.global?.log(message: "STATE CHANGED: connected")
        case .connecting:
            Logger.global?.log(message: "STATE CHANGED: connecting")
        case .disconnected:
            Logger.global?.log(message: "STATE CHANGED: disconnected")
        case .disconnecting:
            Logger.global?.log(message: "STATE CHANGED: disconnecting")
        case .invalid:
            Logger.global?.log(message: "STATE CHANGED: invalid")
        case .reasserting:
            Logger.global?.log(message: "STATE CHANGED: reasserting")
        default:
            Logger.global?.log(message: "STATE CHANGED: unknown status")
        }

        // We care about "unknown" state changes.
        if (session.status != .connected && session.status != .disconnected) {
            return
        }

        // No notifications when switching server
        if (switchingServer) {
            if (switchingServerConfig == nil || switchingServerFailureCallback == nil) {
                Logger.global?.log(message: "Internal error! No switching-server data found")
            } else {
                configureTunnel(config: switchingServerConfig!, failureCallback: switchingServerFailureCallback!)
                switchingServerConfig = nil
                switchingServerFailureCallback = nil
            }
            return
        }

        stateChangeCallback?(session.status == .connected)
    }

    private static func isOurManager(_ manager: NETunnelProviderManager) -> Bool {
        guard
            let proto = manager.protocolConfiguration,
            let tunnelProto = proto as? NETunnelProviderProtocol
        else {
            Logger.global?.log(message: "Ignoring manager because the proto is invalid.")
            return false
        }

        if (tunnelProto.providerBundleIdentifier == nil) {
            Logger.global?.log(message: "Ignoring manager because the bundle identifier is null.")
            return false
        }

        if (tunnelProto.providerBundleIdentifier != vpnBundleID) {
            Logger.global?.log(message: "Ignoring manager because the bundle identifier doesn't match.")
            return false;
        }

        Logger.global?.log(message: "Found the manager with the correct bundle identifier: \(tunnelProto.providerBundleIdentifier!)")
        return true
    }

    @objc func connect(serverIpv4Gateway: String, serverIpv6Gateway: String, serverPublicKey: String, serverIpv4AddrIn: String, serverPort: Int,  allowedIPAddressRanges: Array<VPNIPAddressRange>, ipv6Enabled: Bool, forSwitching: Bool, failureCallback: @escaping () -> Void) {
        Logger.global?.log(message: "Connecting")
        assert(tunnel != nil)

        // Let's remove the previous config if it exists.
        (tunnel!.protocolConfiguration as? NETunnelProviderProtocol)?.destroyConfigurationReference()

        let keyData = Data(base64Key: serverPublicKey)!
        let ipv4GatewayIP = IPv4Address(serverIpv4Gateway)
        let ipv6GatewayIP = IPv6Address(serverIpv6Gateway)

        var peerConfiguration = PeerConfiguration(publicKey: keyData)
        peerConfiguration.endpoint = Endpoint(from: serverIpv4AddrIn + ":\(serverPort )")
        peerConfiguration.allowedIPs = []

        allowedIPAddressRanges.forEach {
            if (!$0.isIpv6) {
                peerConfiguration.allowedIPs.append(IPAddressRange(address: IPv4Address($0.address as String)!, networkPrefixLength: $0.networkPrefixLength))
            } else if (ipv6Enabled) {
                peerConfiguration.allowedIPs.append(IPAddressRange(address: IPv6Address($0.address as String)!, networkPrefixLength: $0.networkPrefixLength))
            }
        }

        var peerConfigurations: [PeerConfiguration] = []
        peerConfigurations.append(peerConfiguration)

        var interface = InterfaceConfiguration(privateKey: privateKey!)

        if let ipv4Address = IPAddressRange(from: deviceIpv4Address!),
           let ipv6Address = IPAddressRange(from: deviceIpv6Address!) {
            interface.addresses = [ipv4Address]
            if (ipv6Enabled) {
                interface.addresses.append(ipv6Address)
            }
        }
        interface.dns = [ DNSServer(address: ipv4GatewayIP!)]

        if (ipv6Enabled) {
            interface.dns.append(DNSServer(address: ipv6GatewayIP!))
        }

        let config = TunnelConfiguration(name: vpnName, interface: interface, peers: peerConfigurations)

        if (forSwitching) {
            switchingServer = true
            switchingServerConfig = config
            switchingServerFailureCallback = failureCallback
            (tunnel!.connection as? NETunnelProviderSession)?.stopTunnel()
            return;
        }

        self.configureTunnel(config: config, failureCallback: failureCallback)
    }

    func configureTunnel(config: TunnelConfiguration, failureCallback: @escaping () -> Void) {
        let proto = NETunnelProviderProtocol(tunnelConfiguration: config)
        proto!.providerBundleIdentifier = vpnBundleID

        tunnel!.protocolConfiguration = proto
        tunnel!.localizedDescription = vpnName
        tunnel!.isEnabled = true

        tunnel!.saveToPreferences { [unowned self] saveError in
            if let error = saveError {
                Logger.global?.log(message: "Connect Tunnel Save Error: \(error)")
                failureCallback()
                return
            }

            Logger.global?.log(message: "Saving the tunnel succeeded")

            self.tunnel!.loadFromPreferences { error in
                if let error = error {
                    Logger.global?.log(message: "Connect Tunnel Load Error: \(error)")
                    failureCallback()
                    return
                }

                Logger.global?.log(message: "Loading the tunnel succeeded")

                // If we were switching server, now it's time to consider the operation completed.
                switchingServer = false

                do {
                    try (self.tunnel!.connection as? NETunnelProviderSession)?.startTunnel()
                } catch let error {
                    Logger.global?.log(message: "Something went wrong: \(error)")
                    failureCallback()
                    return
                }
            }
        }
    }

    @objc func disconnect() {
        Logger.global?.log(message: "Disconnecting")
        assert(tunnel != nil)
        (tunnel!.connection as? NETunnelProviderSession)?.stopTunnel()
    }

    @objc func checkStatus(callback: @escaping (String, String) -> Void) {
        Logger.global?.log(message: "Check status")
        assert(tunnel != nil)

        let proto = tunnel!.protocolConfiguration as? NETunnelProviderProtocol
        if proto == nil {
            callback("", "")
            return
        }

        let tunnelConfiguration = proto?.asTunnelConfiguration()
        if tunnelConfiguration == nil {
            callback("", "")
            return
        }

        let serverIpv4Gateway = tunnelConfiguration?.interface.dns[0].address
        if serverIpv4Gateway == nil {
            callback("", "")
            return
        }

        guard let session = tunnel?.connection as? NETunnelProviderSession
        else {
            callback("", "")
            return
        }

        do {
            try session.sendProviderMessage(Data([UInt8(0)])) { [callback] data in
                guard let data = data,
                      let configString = String(data: data, encoding: .utf8)
                else {
                    Logger.global?.log(message: "Failed to convert data to string")
                    callback("", "")
                    return
                }

                callback("\(serverIpv4Gateway!)", configString)
            }
        } catch {
            Logger.global?.log(message: "Failed to retrieve data from session")
            callback("", "")
        }
    }
}

extension MacOSControllerImplDelegate: OSSystemExtensionRequestDelegate {
    @available(OSX 10.15, *)
    func request(_ request: OSSystemExtensionRequest, actionForReplacingExtension existing: OSSystemExtensionProperties, withExtension replacement: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        Logger.global?.log(message: "allowing replacement of \(existing.bundleVersion) with \(replacement.bundleVersion)");
        return .replace
    }
    
    @available(OSX 10.15, *)
    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        Logger.global?.log(message: "activation request needs user approval")
    }
    
    @available(OSX 10.15, *)
    func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        if (self.impl == nil) {
            return;
        }

        switch result {
        case .completed:
            Logger.global?.log(message: "activation request succeeded")
            self.impl!.continueInit(status: true);
        case .willCompleteAfterReboot:
            Logger.global?.log(message: "activation request succeeded, requires restart")
        @unknown default:
            Logger.global?.log(message: "activation request succeeded, weird result: \(result.rawValue)")
            self.impl!.continueInit(status: true);
        }

        self.impl = nil
    }
    
    @available(OSX 10.15, *)
    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        let nsError = error as NSError
        Logger.global?.log(message: "activation request failed, error: \(nsError.domain) - \(nsError.localizedDescription)")
        if (self.impl == nil) {
            self.impl!.continueInit(status: false)
            self.impl = nil
        }
    }
}
