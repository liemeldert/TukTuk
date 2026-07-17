//
//  HotkeyManager.swift
//  TukTuk
//
//  Created by Liem Eldert on 2026/07/16.
//


import AppKit
import Carbon.HIToolbox
import os.log

final class HotkeyManager {
    typealias SlotHandler = (Int) -> Void

    private static let slotKeyCodes: [UInt32] = [
        UInt32(kVK_ANSI_1), UInt32(kVK_ANSI_2), UInt32(kVK_ANSI_3),
        UInt32(kVK_ANSI_4), UInt32(kVK_ANSI_5), UInt32(kVK_ANSI_6),
        UInt32(kVK_ANSI_7), UInt32(kVK_ANSI_8), UInt32(kVK_ANSI_9),
        UInt32(kVK_ANSI_0),
    ]

    private struct Config: Equatable {
        var enabled: Bool
        var carbonModifiers: UInt32
    }

    private let signature: OSType = 0x544B_544B // "TKTK"
    private let onSlot: SlotHandler
    private let log = Logger(subsystem: "zip.liem.tuktuk", category: "hotkeys")

    private var eventHandler: EventHandlerRef?
    private var registered: [EventHotKeyRef] = []
    private var currentConfig: Config?
    private var defaultsObserver: NSObjectProtocol?

    init(onSlot: @escaping SlotHandler) {
        self.onSlot = onSlot
        installEventHandler()
        applyConfigFromDefaults()

        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.applyConfigFromDefaults()
        }
    }

    deinit {
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
        }
        unregisterAll()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    // MARK: Registration

    private func applyConfigFromDefaults() {
        let defaults = UserDefaults.standard
        let enabled = defaults.object(forKey: "use_hotkey") as? Bool ?? true
        let modifierString = defaults.string(forKey: "global_hotkey_modifiers") ?? ""
        let config = Config(
            enabled: enabled,
            carbonModifiers: Self.carbonModifiers(from: modifierString)
        )
        guard config != currentConfig else { return }
        currentConfig = config

        unregisterAll()
        guard config.enabled, config.carbonModifiers != 0 else { return }

        for (slot, keyCode) in Self.slotKeyCodes.enumerated() {
            var ref: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: signature, id: UInt32(slot))
            let status = RegisterEventHotKey(
                keyCode, config.carbonModifiers, hotKeyID,
                GetEventDispatcherTarget(), 0, &ref
            )
            if status == noErr, let ref {
                registered.append(ref)
            } else {
                log.error("Failed to register hotkey for slot \(slot): status \(status)")
            }
        }
    }

    private func unregisterAll() {
        registered.forEach { UnregisterEventHotKey($0) }
        registered.removeAll()
    }

    private static func carbonModifiers(from string: String) -> UInt32 {
        var modifiers: UInt32 = 0
        if string.contains("command") { modifiers |= UInt32(cmdKey) }
        if string.contains("option") { modifiers |= UInt32(optionKey) }
        if string.contains("control") { modifiers |= UInt32(controlKey) }
        if string.contains("shift") { modifiers |= UInt32(shiftKey) }
        return modifiers
    }

    // MARK: Event handling

    private func installEventHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let callback: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return noErr }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            if status == noErr {
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                manager.handlePress(hotKeyID)
            }
            return noErr
        }
        InstallEventHandler(
            GetEventDispatcherTarget(), callback, 1, &eventType,
            Unmanaged.passUnretained(self).toOpaque(), &eventHandler
        )
    }

    private func handlePress(_ hotKeyID: EventHotKeyID) {
        guard hotKeyID.signature == signature else { return }
        onSlot(Int(hotKeyID.id))
    }
}
