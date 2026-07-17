//
//  SettingsView.swift
//  tuktuk
//
//  Created by Liem Eldert on 07/16/2026.
//
import SwiftUI
import Combine
import UserNotifications
import ServiceManagement

class PreferencesState: ObservableObject {
    @AppStorage("global_hotkey_modifiers") var hotkeyModifiers: String = ""
    @AppStorage("use_hotkey") var useHotkey = true
    @AppStorage("first_launch") var firstLaunch = true
    @AppStorage("show_airplay_devices") var showAirplayDevices = false

    init() {
        if hotkeyModifiers.isEmpty {
            hotkeyModifiers = "command|shift"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var preferences: PreferencesState
    @State private var showingDebug = false

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchAtLoginError: String?

    private static let allModifiers = ["command", "option", "control", "shift"]

    var body: some View {
        Form {
            Section("General") {
                Toggle("Start Tuktuk at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        setLaunchAtLogin(enabled)
                    }
                if let launchAtLoginError {
                    Text(launchAtLoginError)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section("Hotkeys") {
                Toggle("Enable connect hotkeys", isOn: $preferences.useHotkey)
                VStack(alignment: .leading) {
                    Text("Modifiers:").font(Font.body.bold())
                    VStack {
                        Toggle("Command", isOn: modifierBinding("command"))
                        Toggle("Option", isOn: modifierBinding("option"))
                        Toggle("Control", isOn: modifierBinding("control"))
                        Toggle("Shift", isOn: modifierBinding("shift"))
                    }.padding(.leading, 20)
                }
                .disabled(!preferences.useHotkey)

                if preferences.useHotkey && modifierSymbols.isEmpty {
                    Text("Select at least one modifier for the hotkeys to be active.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Text("Press \(modifierSymbols) plus the number next to the device on the list to connect/disconnect.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section("App Controls") {
                VStack() {
                    Button("Open debug tools") {
                        showingDebug = true
                    }
                    Button("Quit Tuktuk NOW!!!!") {
                        NSApp.terminate(nil)
                    }.tint(Color.red)
                }.frame(maxWidth: .infinity)
            }
        }
        .formStyle(.grouped)
        .frame(width: 350)
        .sheet(isPresented: $showingDebug) {
            DebugView()
        }
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginError = nil
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            launchAtLoginError = error.localizedDescription
        }
    }

    private func modifierBinding(_ name: String) -> Binding<Bool> {
        Binding(
            get: { preferences.hotkeyModifiers.contains(name) },
            set: { enabled in
                var active = Set(preferences.hotkeyModifiers.split(separator: "|").map(String.init))
                if enabled { active.insert(name) } else { active.remove(name) }
                preferences.hotkeyModifiers = Self.allModifiers
                    .filter(active.contains)
                    .joined(separator: "|")
            }
        )
    }

    private var modifierSymbols: String {
        var symbols = ""
        if preferences.hotkeyModifiers.contains("control") { symbols += "⌃" }
        if preferences.hotkeyModifiers.contains("option") { symbols += "⌥" }
        if preferences.hotkeyModifiers.contains("shift") { symbols += "⇧" }
        if preferences.hotkeyModifiers.contains("command") { symbols += "⌘" }
        return symbols
    }

    init(preferences: PreferencesState) {
        self.preferences = preferences
    }
}

#Preview("Settings") {
    SettingsView(preferences: PreferencesState())
}
