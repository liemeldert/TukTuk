//
//  DeviceRegistry.swift
//  TukTuk
//
//  Created by Liem Eldert on 2026/07/16.
//

import Observation
import Foundation

@Observable
final class DeviceRegistry {
    // contains sidecar ids
    private(set) var discoveryOrder: [String] = []

    @ObservationIgnored private let defaultsKey = "device_discovery_order"

    init() {
        discoveryOrder = UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []
    }

    /// Records any identifiers not seen before, preserving discovery order.
    func record(_ identifiers: [String]) {
        var changed = false
        for identifier in identifiers where !discoveryOrder.contains(identifier) {
            discoveryOrder.append(identifier)
            changed = true
        }
        if changed {
            UserDefaults.standard.set(discoveryOrder, forKey: defaultsKey)
        }
    }

    func identifier(forSlot slot: Int) -> String? {
        guard slot >= 0, slot < min(discoveryOrder.count, 10) else { return nil }
        return discoveryOrder[slot]
    }

    func keyNumber(for identifier: String) -> Int? {
        guard let index = discoveryOrder.firstIndex(of: identifier), index < 10 else { return nil }
        return (index + 1) % 10
    }
}
