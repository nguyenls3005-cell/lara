//
//  EditorView.swift
//  lara
//

import SwiftUI
import Foundation
import Darwin

// ==========================================
// CẤU HÌNH ĐƯỜNG DẪN & HELPER GHI FILE AN TOÀN
// ==========================================
let mgCurrentPath = "/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist"

private func readAll(_ fd: Int32) throws -> Data {
    var res = Data()
    var buf = [UInt8](repeating: 0, count: 64 * 1024)
    while true {
        let count = buf.withUnsafeMutableBytes { rawBuffer in
            read(fd, rawBuffer.baseAddress, rawBuffer.count)
        }
        if count > 0 { res.append(buf, count: count); continue }
        if count == 0 { return res }
        if errno == EINTR { continue }
        throw NSError(domain: "writeHelper", code: 1, userInfo: [NSLocalizedDescriptionKey: "Read failed"])
    }
}

private func writeAll(_ fd: Int32, _ data: Data) throws {
    guard !data.isEmpty else { return }
    try data.withUnsafeBytes { rawBuffer in
        guard let base = rawBuffer.baseAddress else { throw NSError(domain: "writeHelper", code: 2) }
        var offset = 0
        while offset < data.count {
            let res = write(fd, base.advanced(by: offset), data.count - offset)
            if res > 0 { offset += res; continue }
            if res < 0 && errno == EINTR { continue }
            throw NSError(domain: "writeHelper", code: 3)
        }
    }
}

// Cơ chế ghi file nguyên tử, tự động rollback nếu lỗi (từ GestaltEdit/Erosion)
func writeFileAtomically(_ data: Data, to url: URL) -> (Bool, String) {
    guard let og = try? Data(contentsOf: url) else {
        return (false, "failed to get original file data!")
    }
    
    let fd = url.path.withCString { open($0, O_RDWR | O_CLOEXEC | O_NOFOLLOW) }
    guard fd >= 0 else { return (false, "Failed to open file (errno: \(errno))") }
    defer { close(fd) }
    
    do {
        guard ftruncate(fd, 0) == 0 else { return (false, "Failed to truncate (errno: \(errno))") }
        try writeAll(fd, data)
        guard fsync(fd) == 0 else { return (false, "Failed to fsync (errno: \(errno))") }
        guard lseek(fd, 0, SEEK_SET) >= 0 else { return (false, "Failed to lseek") }
        
        let verify = try readAll(fd)
        guard verify == data else { return (false, "Verification failed") }
    } catch {
        if ftruncate(fd, 0) == 0, lseek(fd, 0, SEEK_SET) >= 0 {
            _ = try? writeAll(fd, og)
            _ = fsync(fd)
        }
        return (false, "Write failed, rolled back: \(error.localizedDescription)")
    }
    return (true, "succeeded")
}

// ==========================================
// GIAO DIỆN CHÍNH (SỬ DỤNG KEY MỚI NHẤT)
// ==========================================
struct GestaltView: View {
    @AppStorage("gestaltwarn") private var gestaltwarn: Bool = true
    
    let mgr: laramgr
    @State private var mgCurrentDict: NSMutableDictionary = NSMutableDictionary()
    @State private var showgestaltwarn: Bool = false
    @State private var mgSubtype: Int = 0
    @State private var mgOriginalSubtype: Int = 0
    @State private var mgEnableDeviceName: Bool = false
    @State private var mgDeviceName: String = ""
    @State private var mgProductType: String = ""
    @State private var mgShowFileSheet: Bool = false
    
    // Các key mới nhất cho iOS 27 beta 1-4
    // Tham khảo từ MGKeys, GestaltEdit, Erosion, Ketamine
    private let keyDynamicIsland = "YlEtTtHlNesRBMal1CqRaA"
    private let keyAOD = "j8/Omm6s1lsmTDFsXjsBfA"
    private let keyAODVibrancy = "ykpu7qyhqFweVMKtxNylWA"
    private let keyChargeLimit = "37NVydb//GP/GrhuTN+exg"
    private let keyBootChime = "QHxt+hGLaBPbQJbXiUJX3w"
    private let keyCameraControl = "CwvKxM2cEogD3p+HYgaW0Q"
    private let keyActionButton = "cT44WE1EohiwRzhsZ8xEsw"
    private let keyCrashDetection = "HCzWusHQwZDea6nNhaKndw"
    private let keyTapToWake = "yZf3GTRMGTuwSV/lD7Cagw"
    private let keyStageManager = "qeaj75wk3HF4DwQ8qbIi7g"
    private let keyApplePencil = "yhHcB0iH0d1XzPO/CFd3ow"
    private let keyAllowIPadApps = "9MZ5AdH43csAUajl/dU+IQ"
    private let keyAppleIntelligence = "A62OafQ85EJAiiqKn4agtg"
    private let keyRegionRestrictionsUS = "h63QSdBCiT/z0WU6rdQv6Q"
    private let keyRegionRestrictionsLL = "zHeENZu+wbg7PUprwNwBWg"
    private let keySecurityResearch = "XYlJKKkj2hztRP1NWWnhlw"
    private let keyInternalStorage = "LBJfwOEzExRxzlAnSuI7eg"
    private let keyInternalFeatures = "EqrsVvjcYDdxHBiQmGhAWw"
    
    var body: some View {
        NavigationStack {
            List {
                Section(header: HeaderLabel(text: "Applying", icon: "checkmark")) {
                    Button {
                        applyGestalt()
                    } label: {
                        Text("Apply Tweaks")
                    }
                    .disabled(!mgr.sbxready)
                    
                    Button {
                        restoreGestalt()
                    } label: {
                        Text("Reset Tweaks")
                    }
                    .disabled(!mgr.sbxready)
                }
                
                Section(header: HeaderLabel(text: "Device Artwork", icon: "paintbrush.pointed")) {
                    Picker(selection: $mgSubtype) {
                        Text("Original (\(mgOriginalSubtype))").tag(mgOriginalSubtype)
                        Text("iPhone 14 Pro").tag(2436)
                        Text("iPhone 14 Pro Max").tag(2796)
                        Text("iPhone 15 Pro Max").tag(2976)
                        Text("iPhone 16 Pro").tag(2622)
                        Text("iPhone 16 Pro Max").tag(2868)
                        Text("iPhone Air").tag(2736)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "iphone")
                                .frame(width: 20, alignment: .center)
                            Text("Subtype")
                            Spacer()
                        }
                    }
                    
                    Toggle("Custom Device Name", isOn: $mgEnableDeviceName)
                    if mgEnableDeviceName { TextField("Device Name", text: $mgDeviceName) }
                }
                
                // MARK: - Các tweak sử dụng key mới nhất
                Section(header: HeaderLabel(text: "Software Features", icon: "gearshape")) {
                    PlainToggle(text: "Dynamic Island", icon: "platter.filled.top.iphone", isOn: mgByteBinding(key: keyDynamicIsland))
                    PlainToggle(text: "Always On Display", icon: "sun.max", isOn: mgByteBinding(key: keyAOD))
                    PlainToggle(text: "AOD Vibrancy", icon: "rays", isOn: mgByteBinding(key: keyAODVibrancy))
                    PlainToggle(text: "Charge Limit", icon: "battery.100.bolt", isOn: mgByteBinding(key: keyChargeLimit))
                    PlainToggle(text: "Boot Chime", icon: "speaker.wave.3", isOn: mgByteBinding(key: keyBootChime))
                }
                
                Section(header: HeaderLabel(text: "Hardware Features", icon: "iphone")) {
                    PlainToggle(text: "Camera Control", icon: "camera.shutter.button", isOn: mgByteBinding(key: keyCameraControl))
                    PlainToggle(text: "Action Button", icon: "button.vertical.left.press", isOn: mgByteBinding(key: keyActionButton))
                    PlainToggle(text: "Crash Detection", icon: "car", isOn: mgByteBinding(key: keyCrashDetection))
                    if UIDevice._hasHomeButton() {
                        PlainToggle(text: "Enable Tap to Wake", icon: "hand.tap", isOn: mgByteBinding(key: keyTapToWake))
                    }
                }
                
                Section(header: HeaderLabel(text: "Eligibility", icon: "checklist")) {
                    PlainToggle(text: "Security Research Device UI", icon: "terminal", isOn: mgByteBinding(key: keySecurityResearch))
                    PlainToggle(text: "Disable Region Restrictions", icon: "globe", isOn: mgRegionRestrictionsBinding())
                    PlainToggle(text: "Apple Intelligence", icon: "apple.intelligence", isOn: mgByteBinding(key: keyAppleIntelligence))
                    
                    HStack(spacing: 10) {
                        Picker("Spoofing", selection: $mgProductType) {
                            Text("Default").tag(machineName())
                            Text("iPhone 15 Pro").tag("iPhone16,1")
                            Text("iPhone 15 Pro Max").tag("iPhone16,2")
                            Text("iPhone 16 Pro").tag("iPhone17,1")
                            Text("iPhone 16 Pro Max").tag("iPhone17,2")
                        }
                        Button(action: {
                            Alertinator.shared.alert(title: "Device Spoofing Info", body: "Only spoof your device model if you want to download Apple Intelligence.")
                        }) { Image(systemName: "info.circle") }.buttonStyle(.plain)
                    }
                }
                
                Section(header: HeaderLabel(text: "iPadOS Features", icon: "ipad")) {
                    PlainToggle(text: "Allow Installing iPadOS Apps", icon: "plus.app", isOn: mgKeyArrayBinding(key: keyAllowIPadApps, enableValue: [1, 2]))
                    PlainToggle(text: "Apple Pencil Settings", icon: "pencil", isOn: mgByteBinding(key: keyApplePencil))
                    if UIDevice.current.userInterfaceIdiom == .pad {
                        PlainToggle(text: "Stage Manager", icon: "squares.leading.rectangle", isOn: mgByteBinding(key: keyStageManager))
                    }
                }
                
                Section(header: HeaderLabel(text: "Internal", icon: "ant")) {
                    PlainToggle(text: "Internal Storage", icon: "externaldrive", isOn: mgByteBinding(key: keyInternalStorage))
                    PlainToggle(text: "Internal Features", icon: "gearshape", isOn: mgByteBinding(key: keyInternalFeatures))
                }
            }
            .navigationTitle("MobileGestalt")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { mgShowFileSheet.toggle() }) { Image(systemName: "doc") }
                }
            }
            .onAppear {
                loadCurrentGestalt()
                if gestaltwarn { showgestaltwarn = true }
            }
            .sheet(isPresented: $mgShowFileSheet) { GestaltFileView() }
            .alert("Warning", isPresented: $showgestaltwarn) {
                Button("Alright.", role: .cancel) {
                    showgestaltwarn = false
                    gestaltwarn = false
                }
            } message: {
                Text("This stuff is risky! You may temporarily break your device, cause it to crash, or even bootloop.")
            }
        }
    }
    
    // MARK: - Binding Helpers (GestaltEdit Style)
    private func mgByteBinding(key: String) -> Binding<Bool> {
        guard let cacheExtra = mgCurrentDict["CacheExtra"] as? NSMutableDictionary else {
            return .constant(false)
        }
        return Binding(
            get: {
                if let value = cacheExtra[key] as? Int { return value == 1 }
                return false
            },
            set: { enabled in
                if enabled { cacheExtra[key] = 1 }
                else { cacheExtra.removeObject(forKey: key) } // Xóa key khi tắt
            }
        )
    }
    
    private func mgKeyArrayBinding<T: Equatable>(key: String, enableValue: T) -> Binding<Bool> {
        guard let cacheExtra = mgCurrentDict["CacheExtra"] as? NSMutableDictionary else {
            return .constant(false)
        }
        return Binding(
            get: {
                if let value = cacheExtra[key] as? T { return value == enableValue }
                return false
            },
            set: { enabled in
                if enabled { cacheExtra[key] = enableValue }
                else { cacheExtra.removeObject(forKey: key) }
            }
        )
    }
    
    private func mgRegionRestrictionsBinding() -> Binding<Bool> {
        guard let cacheExtra = mgCurrentDict["CacheExtra"] as? NSMutableDictionary else {
            return .constant(false)
        }
        return Binding(
            get: {
                return cacheExtra[keyRegionRestrictionsUS] as? String == "US" &&
                       cacheExtra[keyRegionRestrictionsLL] as? String == "LL/A"
            },
            set: { enabled in
                if enabled {
                    Alertinator.shared.alert(title: "Warning!", body: "Please do not use this feature to bypass region restrictions.")
                    cacheExtra[keyRegionRestrictionsUS] = "US"
                    cacheExtra[keyRegionRestrictionsLL] = "LL/A"
                } else {
                    cacheExtra.removeObject(forKey: keyRegionRestrictionsUS)
                    cacheExtra.removeObject(forKey: keyRegionRestrictionsLL)
                }
            }
        )
    }
    
    // MARK: - Data Loading & Writing
    private func loadCurrentGestalt() {
        do {
            mgCurrentDict = try loadMutablePlistDictionary(from: URL(fileURLWithPath: mgCurrentPath))
            prepareGestaltData()
        } catch {
            var pathC = Array(mgCurrentPath.utf8CString)
            let handle = bad_query(&pathC, false, nil, false)
            if handle > 0 {
                defer { bad_query_release(handle) }
                do {
                    mgCurrentDict = try loadMutablePlistDictionary(from: URL(fileURLWithPath: mgCurrentPath))
                    prepareGestaltData()
                } catch {
                    Alertinator.shared.alert(title: "Failed to load!", body: "\(error)")
                }
            } else {
                Alertinator.shared.alert(title: "Failed to load!", body: "bad_query failed with code \(handle)")
            }
        }
    }
    
    private func prepareGestaltData() {
        let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let mgSavedURL = docsDir.appendingPathComponent("SavedGestalt.plist")
        let mgCurrentURL = URL(fileURLWithPath: mgCurrentPath)
        
        do {
            if !FileManager.default.fileExists(atPath: mgSavedURL.path) {
                try FileManager.default.copyItem(at: mgCurrentURL, to: mgSavedURL)
            }
            
            let mgSavedDict = try loadMutablePlistDictionary(from: mgSavedURL)
            let cacheExtra = mgSavedDict["CacheExtra"] as? NSMutableDictionary ?? NSMutableDictionary()
            let ArtworkDict = cacheExtra["oPeik/9e8lQWMszEjbPzng"] as? NSMutableDictionary ?? NSMutableDictionary()
            
            let currentCacheExtra = mgCurrentDict["CacheExtra"] as? NSMutableDictionary ?? NSMutableDictionary()
            let currentArtworkDict = currentCacheExtra["oPeik/9e8lQWMszEjbPzng"] as? NSMutableDictionary ?? NSMutableDictionary()
            let originalSubType = ArtworkDict["ArtworkDeviceSubType"] as? Int ?? currentArtworkDict["ArtworkDeviceSubType"] as? Int ?? 0
            mgOriginalSubtype = originalSubType
            mgSubtype = currentArtworkDict["ArtworkDeviceSubType"] as? Int ?? originalSubType
            
            if let productType = currentCacheExtra["h9jDsbgj7xIVeIQ8S3/X3Q"] as? String, !productType.isEmpty {
                mgProductType = productType
            } else {
                mgProductType = machineName()
            }
            
            let deviceName = ArtworkDict["ArtworkDeviceProductDescription"] as? String ?? currentArtworkDict["ArtworkDeviceProductDescription"] as? String ?? machineName()
            mgDeviceName = deviceName
        } catch {
            Alertinator.shared.alert(title: "Failed to load data!", body: "\(error)")
        }
    }
    
    private func applyGestalt() {
        do {
            let cacheExtra = mgCurrentDict["CacheExtra"] as? NSMutableDictionary ?? NSMutableDictionary()
            if !mgProductType.isEmpty { cacheExtra["h9jDsbgj7xIVeIQ8S3/X3Q"] = mgProductType }
            
            let ArtworkDict = cacheExtra["oPeik/9e8lQWMszEjbPzng"] as? NSMutableDictionary ?? NSMutableDictionary()
            ArtworkDict["ArtworkDeviceSubType"] = mgSubtype
            if mgEnableDeviceName { ArtworkDict["ArtworkDeviceProductDescription"] = mgDeviceName }
            
            if !vaildateCacheExtra(mgCurrentDict) { throw "MobileGestalt is not valid!" }
            let mgData = try verifyPlist(mgCurrentDict, targetPath: mgCurrentPath)
            
            // Lấy quyền ghi bằng bad_query
            var pathC = Array(mgCurrentPath.utf8CString)
            let handle = bad_query(&pathC, false, nil, false)
            guard handle > 0 else { throw "bad_query failed with code \(handle)." }
            defer { bad_query_release(handle) }
            
            // Ghi file an toàn (từ GestaltEdit/Erosion)
            let url = URL(fileURLWithPath: mgCurrentPath)
            let result = writeFileAtomically(mgData, to: url)
            if !result.0 { throw "Write failed: \(result.1)" }
            
            Alertinator.shared.alert(
                title: "Successfully applied!",
                body: "Respring to see any changes",
                actionLabel: "Respring",
                action: { mgr.respring() }
            )
        } catch {
            Alertinator.shared.alert(title: "Failed to overwrite!", body: "\(error)")
        }
    }
    
    private func restoreGestalt() {
        do {
            let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let mgSavedURL = docsDir.appendingPathComponent("SavedGestalt.plist")
            
            if FileManager.default.fileExists(atPath: mgSavedURL.path) {
                let restored = try loadMutablePlistDictionary(from: mgSavedURL)
                let mgData = try verifyPlist(restored, targetPath: mgCurrentPath)
                
                var pathC = Array(mgCurrentPath.utf8CString)
                let handle = bad_query(&pathC, false, nil, false)
                if handle > 0 {
                    defer { bad_query_release(handle) }
                    let result = writeFileAtomically(mgData, to: URL(fileURLWithPath: mgCurrentPath))
                    if !result.0 { throw "Restore failed: \(result.1)" }
                    mgCurrentDict = restored
                } else {
                    throw "bad_query failed with code \(handle)."
                }
            } else {
                throw "No MobileGestalt file found!"
            }
        } catch {
            Alertinator.shared.alert(title: "Failed to restore!", body: "\(error)")
        }
    }
    
    // MARK: - Helpers
    private func vaildateCacheExtra(_ dict: NSMutableDictionary) -> Bool {
        guard let cacheExtra = dict["CacheExtra"] as? NSMutableDictionary else { return false }
        return !cacheExtra.allKeys.isEmpty
    }
    
    func machineName() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        return machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
    }
}

// MARK: - Plist Helpers
func loadMutablePlistDictionary(from url: URL) throws -> NSMutableDictionary {
    let data = try Data(contentsOf: url)
    var format = PropertyListSerialization.PropertyListFormat.binary
    let plist = try PropertyListSerialization.propertyList(from: data, options: [.mutableContainersAndLeaves], format: &format)
    guard let dict = plist as? NSMutableDictionary else { throw "Property list root is not a dictionary." }
    return dict
}

func verifyPlist(_ plist: Any, targetPath: String) throws -> Data {
    let fm = FileManager.default
    if fm.fileExists(atPath: targetPath) {
        let attrs = try fm.attributesOfItem(atPath: targetPath)
        if let current = attrs[.size] as? NSNumber, current.intValue == 0 {
            throw "Current MobileGestalt file is 0 bytes."
        }
    }
    guard PropertyListSerialization.propertyList(plist, isValidFor: .binary) else { c throw "Invalid plist structure." }
    let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
    if data.isEmpty { throw "Serialized plist data is empty." }
    return data
}