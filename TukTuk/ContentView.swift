//
//  ContentView.swift
//  tuktuk
//
//  Created by Liem Eldert on 07/16/2026
//
import SwiftUI
import ServiceManagement
import Security
import UserNotifications
import os.log

let logger = Logger(subsystem: "zip.liem.tuktuk", category: "app")

struct ContentView: View {
    @ObservedObject var preferencesState: PreferencesState
    @Environment(USBDeviceStore.self) private var usb
    @Environment(SidecarManager.self) private var sidecar
    @Environment(DeviceRegistry.self) private var registry
    @Environment(\.openSettings) private var openSettings

    @State private var refreshError: String?

    private var sortedDevices: [SidecarDevice] {
        sidecar.devices.sorted { a, b in
            let indexA = registry.discoveryOrder.firstIndex(of: a.identifier) ?? Int.max
            let indexB = registry.discoveryOrder.firstIndex(of: b.identifier) ?? Int.max
            if indexA != indexB { return indexA < indexB }
            return a.name < b.name
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tuktuk")
                .font(.title)
                .frame(maxWidth: .infinity, alignment: .center)

            Text(usb.iPadIsConnected ? "Detected an iPad connected over USB!" : "I did not detect an iPad over USB ;(")
                .font(.caption)
                .foregroundStyle(usb.iPadIsConnected ? Color.green : Color.secondary)

            Divider()

            Text("Sidecar devices").font(.headline)
            if sidecar.devices.isEmpty {
                Text("None reachable")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sortedDevices) { device in
                    SidecarDeviceRow(device: device)
                }
            }

            if let refreshError {
                Text(refreshError)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack {
                Button("Settings…") {
                    NSApp.activate(ignoringOtherApps: true)
                    openSettings()
                }
                Spacer()
                Button("Refresh") { refresh() }
                    .disabled(sidecar.isBusy)
            }
        }
        .padding()
        .frame(width: 320)
        .task { refresh() }
    }

    private func refresh() {
        do {
            try sidecar.refreshDevices()
            refreshError = nil
        } catch {
            refreshError = error.localizedDescription
        }
    }

    init(preferences: PreferencesState) {
        self.preferencesState = preferences
    }
}

struct SidecarDeviceRow: View {
    let device: SidecarDevice

    @Environment(USBDeviceStore.self) private var usb
    @Environment(SidecarManager.self) private var sidecar
    @Environment(DeviceLinkStore.self) private var links
    @Environment(DeviceRegistry.self) private var registry

    @State private var isExpanded = false
    @State private var notice: String?

    private var link: DeviceLink? {
        links.links.first { $0.sidecarIdentifier == device.identifier }
    }

    private var isConnected: Bool {
        sidecar.connectedDeviceName == device.name
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {

                Toggle("Auto-connect over USB", isOn: autoConnectBinding)
                    .toggleStyle(.switch)

//                if let link {
//                    LabeledContent("Linked iPad", value: link.usbSerial)
//                        .font(.caption)
//                        .foregroundStyle(.secondary)
//                }

                if let notice {
                    Text(notice)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    Button(isConnected ? "Reconnect" : "Connect now") { connect() }
                    Button("Disconnect") { disconnect() }
                        .disabled(!isConnected)
                    Spacer()
                }
                .disabled(sidecar.isBusy)
            }
            .padding(.top, 6)
            .padding(.leading, 6)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "ipad.landscape")
                    .foregroundStyle(isConnected ? Color.green : Color.secondary)
                Text(device.name)
                Spacer()
                if isLinkedIPadOnUSB {
                    Image(systemName: "cable.connector")
                        .foregroundStyle(.secondary)
                        .help("This iPad is connected to USB")
                }
                if link?.autoConnect == true {
                    Image(systemName: "link")
                        .foregroundStyle(.secondary)
                        .help("Connects automatically when plugged in")
                }
                if let number = registry.keyNumber(for: device.identifier) {
                    Text("\(number)")
                        .font(.caption2.monospacedDigit())
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.secondary.opacity(0.2)))
                        .help("Hotkey number for this device")
                }
            }
        }
    }

    private var isLinkedIPadOnUSB: Bool {
        guard let link else { return false }
        return usb.connectedDevices.contains { $0.serial == link.usbSerial }
    }

    private var autoConnectBinding: Binding<Bool> {
        Binding(
            get: { link?.autoConnect == true },
            set: { setAutoConnect($0) }
        )
    }

    // first run needs capture of USB SN, so device must be connected first.
    private func setAutoConnect(_ enabled: Bool) {
        if let existing = link {
            var updated = existing
            updated.autoConnect = enabled
            links.save(updated)
            notice = nil
            return
        }

        guard enabled else { return }

        guard let iPad = usb.connectedDevices.first(where: {
            $0.isAppleMobile && (device.model == nil || $0.model == device.model)
        }), let serial = iPad.serial else {
            notice = "Connect this iPad over USB first, so I can learn which one it is."
            return
        }

        links.save(DeviceLink(
            usbSerial: serial,
            sidecarIdentifier: device.identifier,
            sidecarName: device.name,
            model: device.model,
            autoConnect: true
        ))
        notice = nil
    }

    private func connect() {
        Task {
            notice = nil
            do {
                try await sidecar.connect(toIdentifier: device.identifier)
            } catch {
                notice = error.localizedDescription
            }
        }
    }

    private func disconnect() {
        Task {
            notice = nil
            do {
                try await sidecar.disconnect(from: device.name)
            } catch {
                notice = error.localizedDescription
            }
        }
    }
}
