//
//  DebugView.swift
//  TukTuk
//
//  Created by Liem Eldert on 2026/07/16.
//

import SwiftUI

struct DebugView: View {
    @Environment(USBDeviceStore.self) private var usb
    @Environment(SidecarManager.self) private var sidecar
    @Environment(DeviceLinkStore.self) private var links
    @Environment(\.dismiss) private var dismiss

    @State private var dumpText = ""
    @State private var statusText: String?
    @State private var isError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView {
                HStack {
                    Text("Debug tools").font(.title2)
                    Text("Why are you here").font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Button("Done") { dismiss() }
                }
                
                usbSection
                Divider()
                sidecarSection
                Divider()
                linksSection
                Divider()
                Image("linus").resizable(resizingMode: .stretch).frame(width: 400, height: 400)
                Spacer()
            }
        }
        .padding()
        .frame(width: 460)
    }

    private var usbSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("USB devices").font(.headline)
            Text(usb.iPadIsConnected ? "iPad connected over USB" : "No iPad over USB")
                .font(.caption)
                .foregroundStyle(usb.iPadIsConnected ? Color.green : Color.secondary)
            if usb.connectedDevices.isEmpty {
                Text("None").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(usb.connectedDevices) { device in
                    Text("\(device.name)  ·  \(device.model ?? "—")  ·  \(device.serial ?? "no serial")")
                        .font(.system(.caption, design: .monospaced))
                }
            }
        }
    }

    private var sidecarSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Sidecar").font(.headline)
            HStack {
                Button("Inspect first device") { inspect() }
                Button("Probe & link current iPad") { probeAndLink() }
                    .disabled(!usb.iPadIsConnected || sidecar.isBusy)
            }
            if let statusText {
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(isError ? Color.red : Color.green)
            }
            if !dumpText.isEmpty {
                ScrollView {
                    Text(dumpText)
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 180)
            }
        }
    }

    private var linksSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Saved links").font(.headline)
            if links.links.isEmpty {
                Text("None yet").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(links.links) { link in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(link.sidecarName).font(.caption)
                            Text("\(link.usbSerial) → \(link.sidecarIdentifier)")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Remove") { links.remove(serial: link.usbSerial) }
                    }
                }
            }
        }
    }

    private func inspect() {
        isError = false
        statusText = nil
        do {
            try sidecar.refreshDevices()
            dumpText = try sidecar.debugDescribeFirstDevice()
        } catch {
            isError = true
            statusText = error.localizedDescription
        }
    }

    private func probeAndLink() {
        guard let ipad = usb.latestiPad else {
            isError = true
            statusText = "No iPad connected over USB."
            return
        }
        Task {
            isError = false
            statusText = "Probing... First detected device will connect..."
            do {
                let connected = try await sidecar.probeConnect(preferredModel: ipad.model)
                if let serial = ipad.serial {
                    links.save(DeviceLink(
                        usbSerial: serial,
                        sidecarIdentifier: connected.identifier,
                        sidecarName: connected.name,
                        model: connected.model
                    ))
                    statusText = "Linked and connected: \(connected.name)"
                } else {
                    statusText = "Connected \(connected.name), but the iPad reported no serial to save?"
                }
            } catch {
                isError = true
                statusText = error.localizedDescription
            }
        }
    }
}
