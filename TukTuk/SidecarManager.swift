//
//  SidecarManager.swift
//  TukTuk
//
//  Created by Liem Eldert on 2026/07/16.
//
// Based off the lovely work found here: https://github.com/Ocasio-J/SidecarLauncher/blob/main/SidecarLauncher/main.swift

import Foundation
import os.log
import ObjectiveC.runtime

enum SidecarError: LocalizedError {
    case frameworkUnavailable
    case managerUnavailable
    case deviceQueryFailed
    case deviceNotFound(String)
    case connectionFailed(Error)

    var errorDescription: String? {
        switch self {
        case .frameworkUnavailable:
            return "The SidecarCore framework could not be loaded."
        case .managerUnavailable:
            return "The Sidecar display manager was not available."
        case .deviceQueryFailed:
            return "Could not read the list of Sidecar devices."
        case .deviceNotFound(let name):
            return "No reachable Sidecar device is named \"\(name)\"."
        case .connectionFailed(let underlying):
            return "Sidecar reported an error: \(underlying.localizedDescription)"
        }
    }
}

struct SidecarDevice: Identifiable, Hashable {
    var id: String { identifier }
    let identifier: String
    let name: String
    let model: String?
}

@MainActor
@Observable
final class SidecarManager {
    /// Reachable Sidecar-capable devices from the most recent refresh
    private(set) var devices: [SidecarDevice] = []

    /// last connected device
    private(set) var connectedDeviceName: String?

    private(set) var isBusy = false

    @ObservationIgnored private var cachedManager: NSObject?
    @ObservationIgnored private let log = Logger(subsystem: "zip.liem.tuktuk", category: "sidecar")

    // Records discovered devices so they can keep the same hotkey
    @ObservationIgnored private let registry: DeviceRegistry?

    nonisolated init(registry: DeviceRegistry? = nil) {
        self.registry = registry
    }

    // MARK: Framework access

    private func sharedManager() throws -> NSObject {
        if let cachedManager { return cachedManager }

        guard dlopen("/System/Library/PrivateFrameworks/SidecarCore.framework/SidecarCore", RTLD_LAZY) != nil else {
            throw SidecarError.frameworkUnavailable
        }
        guard let managerClass = NSClassFromString("SidecarDisplayManager") as? NSObject.Type,
              let manager = managerClass.perform(Selector(("sharedManager")))?.takeUnretainedValue() as? NSObject else {
            throw SidecarError.managerUnavailable
        }

        cachedManager = manager
        return manager
    }

    private func name(of device: NSObject) -> String {
        (device.perform(Selector(("name")))?.takeUnretainedValue() as? String) ?? "Unknown device"
    }

    private func stringValue(_ device: NSObject, _ key: String) -> String? {
        guard device.responds(to: Selector((key))), let value = device.value(forKey: key) else { return nil }
        if let string = value as? String { return string }
        if let uuid = value as? UUID { return uuid.uuidString }
        if let uuid = value as? NSUUID { return uuid.uuidString }
        return "\(value)"
    }

    private func rawDevices(from manager: NSObject) throws -> [NSObject] {
        guard let raw = manager.perform(Selector(("devices")))?.takeUnretainedValue() as? [NSObject] else {
            throw SidecarError.deviceQueryFailed
        }
        return raw
    }

    private func matchingDevice(named deviceName: String, in manager: NSObject) throws -> NSObject {
        let target = deviceName.lowercased()
        guard let match = try rawDevices(from: manager).first(where: { name(of: $0).lowercased() == target }) else {
            throw SidecarError.deviceNotFound(deviceName)
        }
        return match
    }

    private func device(withIdentifier identifier: String, in manager: NSObject) throws -> NSObject {
        guard let match = try rawDevices(from: manager).first(where: { stringValue($0, "identifier") == identifier }) else {
            throw SidecarError.deviceNotFound(identifier)
        }
        return match
    }

    // MARK: Public API


    @discardableResult
    func refreshDevices() throws -> [SidecarDevice] {
        let manager = try sharedManager()
        let found = try rawDevices(from: manager).map { raw in
            SidecarDevice(
                identifier: stringValue(raw, "identifier") ?? name(of: raw),
                name: name(of: raw),
                model: stringValue(raw, "model")
            )
        }
        devices = found
        registry?.record(found.map(\.identifier))
        return found
    }

    func toggleConnection(identifier: String) async throws {
        let manager = try sharedManager()
        let device = try device(withIdentifier: identifier, in: manager)
        let deviceName = stringValue(device, "name") ?? identifier
        if connectedDeviceName == deviceName {
            try await disconnect(from: deviceName)
        } else {
            try await connect(toIdentifier: identifier)
        }
    }

    func connect(to deviceName: String, wired: Bool = false) async throws {
        let manager = try sharedManager()
        let device = try matchingDevice(named: deviceName, in: manager)
        try await connect(to: device, in: manager, wired: wired)
        connectedDeviceName = deviceName
        log.info("Connected to Sidecar device \(deviceName, privacy: .public)")
    }

    func connect(toIdentifier identifier: String, wired: Bool = false) async throws {
        let manager = try sharedManager()
        let device = try device(withIdentifier: identifier, in: manager)
        let resolvedName = stringValue(device, "name") ?? identifier
        try await connect(to: device, in: manager, wired: wired)
        connectedDeviceName = resolvedName
        log.info("Connected to Sidecar device \(resolvedName, privacy: .public)")
    }

    /// Enumerates over USB to see what are eligable sidecar devices
    func autoConnect(toIdentifier identifier: String, attempts: Int = 5, delay: Duration = .seconds(1)) async throws {
        var lastError: Error?
        for attempt in 1...attempts {
            do {
                try await connect(toIdentifier: identifier, wired: false)
                return
            } catch {
                lastError = error
                log.info("Auto-connect attempt \(attempt) of \(attempts) failed: \(error.localizedDescription, privacy: .public)")
                if attempt < attempts { try? await Task.sleep(for: delay) }
            }
        }
        throw lastError ?? SidecarError.deviceNotFound(identifier)
    }

    private func connect(to device: NSObject, in manager: NSObject, wired: Bool) async throws {
        isBusy = true
        defer { isBusy = false }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let completion: @convention(block) (NSError?) -> Void = { error in
                if let error {
                    continuation.resume(throwing: SidecarError.connectionFailed(error))
                } else {
                    continuation.resume()
                }
            }

            guard wired else {
                _ = manager.perform(Selector(("connectToDevice:completion:")), with: device, with: completion)
                return
            }

            // Wired connection needs a config object + 3 arg selector thru raw method
            guard let configClass = NSClassFromString("SidecarDisplayConfig") as? NSObject.Type else {
                continuation.resume(throwing: SidecarError.managerUnavailable)
                return
            }
            let config = configClass.init()

            let setTransportSelector = Selector(("setTransport:"))
            let setTransport = unsafeBitCast(
                config.method(for: setTransportSelector),
                to: (@convention(c) (Any?, Selector, Int64) -> Void).self
            )
            setTransport(config, setTransportSelector, 2) // 2 == wired transport

            let connectSelector = Selector(("connectToDevice:withConfig:completion:"))
            let connectImp = unsafeBitCast(
                manager.method(for: connectSelector),
                to: (@convention(c) (Any?, Selector, Any?, Any?, Any?) -> Void).self
            )
            connectImp(manager, connectSelector, device, config, completion)
        }
    }

    /// enumerates wired-only until a device can connect successfully to find which sidecar device is actually connected
    func probeConnect(preferredModel: String?) async throws -> SidecarDevice {
        let candidates = try refreshDevices()
        guard !candidates.isEmpty else { throw SidecarError.deviceNotFound(preferredModel ?? "any") }

        let ordered = candidates.sorted { a, b in
            (a.model == preferredModel ? 0 : 1) < (b.model == preferredModel ? 0 : 1)
        }

        var lastError: Error?
        for candidate in ordered {
            do {
                try await connect(toIdentifier: candidate.identifier, wired: true)
                return candidate
            } catch {
                lastError = error
                log.info("Probe: \(candidate.name, privacy: .public) did not connect over cable; trying next.")
            }
        }
        throw lastError ?? SidecarError.deviceNotFound(preferredModel ?? "any")
    }

    func disconnect(from deviceName: String) async throws {
        let manager = try sharedManager()
        let device = try matchingDevice(named: deviceName, in: manager)

        isBusy = true
        defer { isBusy = false }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let completion: @convention(block) (NSError?) -> Void = { error in
                if let error {
                    continuation.resume(throwing: SidecarError.connectionFailed(error))
                } else {
                    continuation.resume()
                }
            }
            _ = manager.perform(Selector(("disconnectFromDevice:completion:")), with: device, with: completion)
        }

        if connectedDeviceName == deviceName { connectedDeviceName = nil }
        log.info("Disconnected from Sidecar device \(deviceName, privacy: .public)")
    }

    // MARK: Debug stuff

    @discardableResult
    func debugDescribeFirstDevice() throws -> String {
        let manager = try sharedManager()
        guard let device = try rawDevices(from: manager).first else {
            let message = "No reachable Sidecar devices to inspect."
            log.info("\(message, privacy: .public)")
            return message
        }

        let values = device.propertyNames().compactMap { key -> String? in
            guard device.responds(to: Selector((key))) else { return nil }
            let value = device.value(forKey: key)
            return "  \(key) = \(value.map { "\($0)" } ?? "nil")"
        }

        let text = """
        SidecarDevice class: \(String(describing: type(of: device)))

        Property values:
        \(values.isEmpty ? "  (no readable properties)" : values.joined(separator: "\n"))

        Ivars: \(device.ivarNames().joined(separator: ", "))
        """
        log.info("\(text, privacy: .public)")
        return text
    }
}

// MARK: - Objective-C runtime introspection

extension NSObject {
    func propertyNames() -> [String] {
        var count: UInt32 = 0
        guard let list = class_copyPropertyList(type(of: self), &count) else { return [] }
        defer { free(list) }
        return (0..<Int(count)).map { String(cString: property_getName(list[$0])) }
    }

    func ivarNames() -> [String] {
        var count: UInt32 = 0
        guard let list = class_copyIvarList(type(of: self), &count) else { return [] }
        defer { free(list) }
        return (0..<Int(count)).compactMap { ivar_getName(list[$0]).map { String(cString: $0) } }
    }
}
