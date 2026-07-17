//
//  tuktuk_menubarApp.swift
//  TukTuk
//
//  Created by Liem Eldert on 2026/07/16.
//
import SwiftUI
import UserNotifications
import os

@main
struct tuktuk_menubarApp: App {
    @Environment(\.openWindow) private var openWindow
    @StateObject private var preferencesState = PreferencesState()
    @State private var store: USBDeviceStore
    @State private var sidecar: SidecarManager
    @State private var linkStore: DeviceLinkStore
    @State private var registry: DeviceRegistry
    @State private var hotkeys: HotkeyManager

    var body: some Scene {
        MenuBarExtra(
            "Tuktuk",
            systemImage: store.iPadIsConnected ? "ipad.landscape" : "moped.fill"
        ) {
            ContentView(preferences: preferencesState)
                .environment(store)
                .environment(sidecar)
                .environment(linkStore)
                .environment(registry)
        }.menuBarExtraStyle(.window)
        Settings {
            SettingsView(preferences: preferencesState)
                .environment(store)
                .environment(sidecar)
                .environment(linkStore)
                .environment(registry)
        }
    }
    
    init() {
        let registry = DeviceRegistry()
        let sidecar = SidecarManager(registry: registry)
        let linkStore = DeviceLinkStore()
        _registry = State(initialValue: registry)
        _sidecar = State(initialValue: sidecar)
        _linkStore = State(initialValue: linkStore)
        _store = State(initialValue: USBDeviceStore(sidecar: sidecar, linkStore: linkStore))

        _hotkeys = State(initialValue: HotkeyManager { slot in
            Task { @MainActor in
                do {
                    try sidecar.refreshDevices()
                    guard let identifier = registry.identifier(forSlot: slot) else { return }
                    try await sidecar.toggleConnection(identifier: identifier)
                } catch {
                    logger.error("Hotkey slot \(slot) failed: \(error.localizedDescription)")
                }
            }
        })
    }
    
}

