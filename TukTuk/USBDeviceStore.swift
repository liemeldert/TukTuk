//
//  USBDeviceStore.swift
//  TukTuk
//
//  Created by Liem Eldert on 2026/07/16.
//

import Observation
import IOKit
import os.log
import Foundation

struct USBDevice: Identifiable, Hashable {
    var id: String { serial ?? name }
    let name: String
    let serial: String?
    let model: String?
    let isAppleMobile: Bool
}

@Observable
final class USBDeviceStore {
    private(set) var connectedDevices: [USBDevice] = []

    var iPadIsConnected: Bool {
        connectedDevices.contains { $0.isAppleMobile }
    }

    var latestiPad: USBDevice? {
        connectedDevices.last { $0.isAppleMobile }
    }

    private var watcher: USBWatcher?
    private let log = Logger(subsystem: "zip.liem.tuktuk", category: "usb")


    @ObservationIgnored private let sidecar: SidecarManager?
    @ObservationIgnored private let linkStore: DeviceLinkStore?

    @ObservationIgnored private var autoConnecting: Set<String> = []

    init(sidecar: SidecarManager? = nil, linkStore: DeviceLinkStore? = nil) {
        self.sidecar = sidecar
        self.linkStore = linkStore
        watcher = USBWatcher(delegate: self)
    }
}

extension USBDeviceStore: USBWatcherDelegate {
    func deviceAdded(_ device: io_object_t) {
        let isApple = device.isAppleMobileDevice
        let record = USBDevice(
            name: device.name() ?? "Unknown device",
            serial: device.usbSerialNumber,
            model: isApple ? device.appleModelIdentifier : nil,
            isAppleMobile: isApple
        )
        // sometimes it reports duplicates for whatever reason?
        if let serial = record.serial, connectedDevices.contains(where: { $0.serial == serial }) {
            return
        }
        connectedDevices.append(record)
        log.info("USB added: \(device.usbDebugSummary(), privacy: .public)")

        if isApple, let serial = record.serial,
           let link = linkStore?.link(forSerial: serial), link.autoConnect,
           !autoConnecting.contains(serial) {
            autoConnecting.insert(serial)
            let manager = sidecar
            let identifier = link.sidecarIdentifier
            let name = link.sidecarName
            Task { @MainActor in
                defer { self.autoConnecting.remove(serial) }
                do {
                    try await manager?.autoConnect(toIdentifier: identifier)
                } catch {
                    self.log.error("Auto-connect to \(name, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    func deviceRemoved(_ device: io_object_t) {
        if let serial = device.usbSerialNumber {
            connectedDevices.removeAll { $0.serial == serial }
        } else {
            let name = device.name() ?? "Unknown device"
            connectedDevices.removeAll { $0.name == name && $0.serial == nil }
        }
    }
}
