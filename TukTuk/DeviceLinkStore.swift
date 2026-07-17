//
//  DeviceLinkStore.swift
//  TukTuk
//
//  Created by Liem Eldert on 2026/07/16.
//

import Observation
import Foundation

struct DeviceLink: Codable, Identifiable, Hashable {
    var id: String { usbSerial }
    let usbSerial: String
    var sidecarIdentifier: String
    var sidecarName: String
    var model: String?
    var autoConnect: Bool = true
}

@Observable
final class DeviceLinkStore {
    private(set) var links: [DeviceLink] = []

    @ObservationIgnored private let defaultsKey = "device_links"

    init() {
        loadFromDefaults()
    }

    func link(forSerial serial: String) -> DeviceLink? {
        links.first { $0.usbSerial == serial }
    }

    func save(_ link: DeviceLink) {
        if let index = links.firstIndex(where: { $0.usbSerial == link.usbSerial }) {
            links[index] = link
        } else {
            links.append(link)
        }
        persist()
    }

    func remove(serial: String) {
        links.removeAll { $0.usbSerial == serial }
        persist()
    }

    private func loadFromDefaults() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([DeviceLink].self, from: data) else { return }
        links = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(links) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}
