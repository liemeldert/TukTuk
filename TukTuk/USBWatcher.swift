//
//  USBWatcher.swift
//  TukTuk
//
//  Created by Liem Eldert on 2026/07/16.
//
// Borrowed from (tysm), with a few changes to get working on newer MacOS versions:
// Source - https://stackoverflow.com/a/41279799
// Posted by jtbandes, modified by community. See post 'Timeline' for change history
// Retrieved 2026-07-16, License - CC BY-SA 3.0

import Foundation
import IOKit
import IOKit.usb

public protocol USBWatcherDelegate: AnyObject {
    /// Called on the main thread when a device is connected.
    func deviceAdded(_ device: io_object_t)

    /// Called on the main thread when a device is disconnected.
    func deviceRemoved(_ device: io_object_t)
}

/// An object which observes USB devices added and removed from the system.
/// Abstracts away most of the ugliness of IOKit APIs.
public class USBWatcher {
    private weak var delegate: USBWatcherDelegate?
    private let notificationPort = IONotificationPortCreate(kIOMainPortDefault)
    private var addedIterator: io_iterator_t = 0
    private var removedIterator: io_iterator_t = 0

    public init(delegate: USBWatcherDelegate) {
        self.delegate = delegate

        func handleNotification(instance: UnsafeMutableRawPointer?, _ iterator: io_iterator_t) {
            let watcher = Unmanaged<USBWatcher>.fromOpaque(instance!).takeUnretainedValue()
            let handler: ((io_iterator_t) -> Void)?
            switch iterator {
            case watcher.addedIterator: handler = watcher.delegate?.deviceAdded
            case watcher.removedIterator: handler = watcher.delegate?.deviceRemoved
            default: assertionFailure("received unexpected IOIterator"); return
            }
            while case let device = IOIteratorNext(iterator), device != IO_OBJECT_NULL {
                handler?(device)
                IOObjectRelease(device)
            }
        }

        let query = IOServiceMatching(kIOUSBDeviceClassName)
        let opaqueSelf = Unmanaged.passUnretained(self).toOpaque()

        // Watch for connected devices.
        IOServiceAddMatchingNotification(
            notificationPort, kIOMatchedNotification, query,
            handleNotification, opaqueSelf, &addedIterator)

        handleNotification(instance: opaqueSelf, addedIterator)

        // Watch for disconnected devices.
        IOServiceAddMatchingNotification(
            notificationPort, kIOTerminatedNotification, query,
            handleNotification, opaqueSelf, &removedIterator)

        handleNotification(instance: opaqueSelf, removedIterator)

        // Add the notification to the main run loop to receive future updates.
        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            IONotificationPortGetRunLoopSource(notificationPort).takeUnretainedValue(),
            .commonModes)
    }

    deinit {
        IOObjectRelease(addedIterator)
        IOObjectRelease(removedIterator)
        IONotificationPortDestroy(notificationPort)
    }
}

extension io_object_t {
    
    func name() -> String? {
        let buf = UnsafeMutablePointer<io_name_t>.allocate(capacity: 1)
        defer { buf.deallocate() }
        return buf.withMemoryRebound(to: CChar.self, capacity: MemoryLayout<io_name_t>.size) {
            if IORegistryEntryGetName(self, $0) == KERN_SUCCESS {
                return String(cString: $0)
            }
            return nil
        }
    }
    
    func numberProperty(_ key: String) -> Int? {
        guard let cf = IORegistryEntryCreateCFProperty(
            self, key as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() else { return nil }
        return (cf as? NSNumber)?.intValue
    }

    var isAppleMobileDevice: Bool {
        numberProperty("idVendor") == 0x05AC // Apple's vendor ID
    }

    func stringProperty(_ key: String) -> String? {
        guard let cf = IORegistryEntryCreateCFProperty(
            self, key as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() else { return nil }
        return cf as? String
    }
    // not the device's real SN but rather a USB specific one
    var usbSerialNumber: String? {
        stringProperty("USB Serial Number")
    }

    // Apple encodes the model identifier into the USB bcdDevice field, which is surprisingly friendly
    var appleModelIdentifier: String? {
        guard let bcd = numberProperty("bcdDevice") else { return nil }
        let hex = String(format: "%04X", bcd)
        guard let major = Int(hex.prefix(2)), let minor = Int(hex.suffix(2)) else { return nil }
        return "iPad\(major),\(minor)"
    }

    func usbDebugSummary() -> String {
        var parts: [String] = []
        if let name = name() { parts.append("name=\(name)") }
        if let vendor = numberProperty("idVendor") { parts.append(String(format: "idVendor=0x%04X", vendor)) }
        if let product = numberProperty("idProduct") { parts.append(String(format: "idProduct=0x%04X", product)) }
        if let bcd = numberProperty("bcdDevice") { parts.append(String(format: "bcdDevice=0x%04X", bcd)) }
        if isAppleMobileDevice, let model = appleModelIdentifier { parts.append("model=\(model)") }
        for key in ["USB Vendor Name", "USB Product Name", "USB Serial Number"] {
            if let value = stringProperty(key) { parts.append("\(key)=\(value)") }
        }
        return parts.joined(separator: ", ")
    }
}
