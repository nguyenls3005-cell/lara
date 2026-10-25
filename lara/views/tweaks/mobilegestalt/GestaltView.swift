//
//  GestaltView.swift
//  lara
//

import SwiftUI
import UniformTypeIdentifiers
import Foundation
import Darwin

// ==========================================
// KHAI BÁO BIẾN TOÀN CỤC (ĐỂ CÁC FILE KHÁC DÙNG CHUNG)
// ==========================================
let mgCurrentPath = "/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist"

func verifyPlist(_ plist: Any, targetPath: String) throws -> Data {
    let fm = FileManager.default
    if fm.fileExists(atPath: targetPath) {
        let attrs = try fm.attributesOfItem(atPath: targetPath)
        if let current = attrs[.size] as? NSNumber, current.intValue == 0 {
            throw "Current MobileGestalt file is 0 bytes."
        }
    }
    
    guard PropertyListSerialization.propertyList(plist, isValidFor: .binary) else {
        throw "Invalid plist structure."
    }
    
    let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
    if data.isEmpty {
        throw "Serialized plist data is empty."
    }
    return data
}

enum fileloc: String, CaseIterable {
    case springboard = "/var/Managed Preferences/mobile/com.apple.springboard.plist"
    case footnote = "/var/containers/Shared/SystemGroup/systemgroup.com.apple.configurationprofiles/Library/ConfigurationProfiles/SharedDeviceConfiguration.plist"
    case airdrop = "/var/Managed Preferences/mobile/com.apple.sharingd.plist"
    case nanoregistry = "/var/mobile/Library/Preferences/com.apple.NanoRegistry.plist"
    case globalprefs = "/var/Managed Preferences/mobile/.GlobalPreferences.plist"
    case appstore = "/var/Managed Preferences/mobile/com.apple.AppStore.plist"
    case backboardd = "/var/Managed Preferences/mobile/com.apple.backboardd.plist"
    case coremotion = "/var/Managed Preferences/mobile/com.apple.CoreMotion.plist"
    case pasteboard = "/var/Managed Preferences/mobile/com.apple.Pasteboard.plist"
    case notes = "/var/Managed Preferences/mobile/com.apple.mobilenotes.plist"
    case uikit = "/var/Managed Preferences/mobile/com.apple.UIKit.plist"
}

// ==========================================
// HELPER GHI FILE AN TOÀN (EROSION)
// ==========================================
private func readAll(_ fd: Int32) throws -> Data {
    var res = Data()
    var buf = [UInt8](repeating: 0, count: 64 * 1024)
    while true {
        let count = buf.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
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

func writeFileAtomically(_ data: Data, to url: URL) -> (Bool, String) {
    guard let og = try? Data(contentsOf: url) else { return (false, "failed to get original file data!") }
    let fd = url.path.withCString { open($0, O_RDWR | O_CLOEXEC | O_NOFOLLOW) }
    guard fd >= 0 else { return (false, "Failed to open file (errno: \(errno))") }
    defer { close(fd) }
    do {
        guard ftruncate(fd, 0) == 0 else { return (false, "Failed to truncate") }
        try writeAll(fd, data)
        guard fsync(fd) == 0 else { return (false, "Failed to fsync") }
        guard lseek(fd, 0, SEEK_SET) >= 0 else { return (false, "Failed to lseek") }
        let verify = try readAll(fd)
        guard verify == data else { return (false, "Verification failed") }
    } catch {
        if ftruncate(fd, 0) == 0, lseek(fd, 0, SEEK_SET) >= 0 {
            _ = try? writeAll(fd, og); _ = fsync(fd)
        }
        return (false, "Rolled back: \(error.localizedDescription)")
    }
    return (true, "succeeded")
}

// ==========================================
// GIAO DIỆN EROSION (ĐÃ ĐỔI SANG LARA)
// ==========================================
struct GestaltView: View {
    let mgr: laramgr // Đã đổi từ @EnvironmentObject sang let để khớp với TweaksView
    @StateObject private var store = GestaltStore.shared
    @AppStorage("mgOverrideGates") private var mgOverrideGates = false
    @AppStorage("mgWriteAtomically") private var mgWriteAtomically = true
    @AppStorage("autoRespring") var autoRespring = false
    @AppStorage("hasShownSheet") private var hasShownSheet = false
    @Environment(\.dismiss) private var dismiss
    
    @State private var mgSubtype = 0
    @State private var mgOgSubtype = 0
    @State private var mgOgDeviceName = ""
    @State private var mgEnableDeviceName = false
    @AppStorage("mgDeviceName") private var mgDeviceName = ""
    @AppStorage("ogMachineName") private var ogMachineName = ""
    @AppStorage("showRegionTweak") private var showRegionTweak = false
    @State private var mgProductType = ""
    @State private var showInfoSheet = false
    @State private var idiotButtonTimerComplete = false
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Picker("Subtype", selection: $mgSubtype) {
                            Text("Original (\(mgOgSubtype))").tag(mgOgSubtype)
                            Text("iPhone 14 Pro").tag(2436)
                            Text("iPhone 14 Pro Max").tag(2796)
                            Text("iPhone 15 Pro Max").tag(2976)
                            if doubleSysVrs() >= 18.0 {
                                Text("iPhone 16 Pro").tag(2622)
                                Text("iPhone 16 Pro Max").tag(2868)
                            }
                            if doubleSysVrs() >= 26.0 { Text("iPhone Air").tag(2736) }
                        }
                        Spacer()
                        Button { Alertinator.shared.alert(title: "Subtype Info", body: MGMsg.subtype) } label: {
                            Image(systemName: "info.circle").frame(width: 24, height: 22)
                        }.buttonStyle(.plain)
                    }
                    Toggle("Custom Device Name", isOn: $mgEnableDeviceName)
                    if mgEnableDeviceName { TextField("Device Name", text: $mgDeviceName) }
                } header: {
                    HeaderLabel(text: "Artwork", icon: "paintbrush.pointed")
                }
                
                Section {
                    PlainToggle(text: "Enable Dynamic Island", icon: "platter.filled.top.iphone", minSupportedVersion: 19.0, isOn: store.mgKeyBinding([MGKey.island]))
                    PlainToggle(text: "Enable AOD", icon: "sun.max", minSupportedVersion: 18.0, isOn: store.mgKeyBinding([MGKey.AOD, MGKey.AOTime]))
                    if store.isEnabled([MGKey.AOD]) {
                        PlainToggle(text: "Enable AOD Vibrancy", icon: "rays", minSupportedVersion: 18.0, isOn: store.mgKeyBinding([MGKey.AODVibrancy]))
                    }
                    PlainToggle(text: "Enable Boot Chime", icon: "speaker.wave.3", isOn: store.mgKeyBinding([MGKey.bootChime]))
                } header: {
                    HeaderLabel(text: "Hardware Features", icon: "gearshape")
                }
                
                Section {
                    PlainToggle(text: "Enable Internal Install", icon: "terminal", infoType: .info, infoMessage: MGMsg.intInstall, isOn: store.mgKeyBinding([MGKey.intInstall]))
                    PlainToggle(text: "Enable Internal Build", icon: "terminal", infoType: .info, infoMessage: MGMsg.intBuild, isOn: store.mgKeyBinding([MGKey.intBuild]))
                } header: {
                    HeaderLabel(text: "Internal", icon: "ant")
                }
                
                Section {
                    PlainToggle(text: "Enable SRD UI", icon: "terminal", minSupportedVersion: 26.0, isOn: store.mgKeyBinding([MGKey.srd]))
                    if showRegionTweak {
                        PlainToggle(text: "Disable Region Restrictions", icon: "globe", isOn: store.mgRegionRestrictionsBinding())
                    }
                    PlainToggle(text: "Enable Apple Intelligence", icon: "apple.intelligence", minSupportedVersion: 18.1, isOn: store.mgKeyBinding([MGKey.appIntell]))
                } header: {
                    HeaderLabel(text: "Eligibility", icon: "flag")
                }
                
                Section {
                    PlainToggle(text: "Crash Detection", icon: "car", isOn: store.mgKeyBinding([MGKey.crashDet]))
                    PlainToggle(text: "Pulse Width Modulation", icon: "eye", minSupportedVersion: 19.0, isOn: store.mgKeyBinding([MGKey.pwm]))
                    PlainToggle(text: "Apple Pencil", icon: "pencil", isOn: store.mgKeyBinding([MGKey.appPencil]))
                    PlainToggle(text: "Camera Control", icon: "camera.shutter.button", minSupportedVersion: 18.0, isOn: store.mgKeyBinding([MGKey.camButton, MGKey.grapPefr]))
                    PlainToggle(text: "Action Button", icon: "button.vertical.left.press", minSupportedVersion: 17.0, isOn: store.mgKeyBinding([MGKey.actButton]))
                } header: {
                    HeaderLabel(text: "Preference Bundles", icon: "gear")
                }
                
                Section {
                    PlainToggle(text: "Enable Stage Manager", icon: "squares.leading.rectangle", isOn: store.mgKeyBinding([MGKey.stageMgr]))
                    PlainToggle(text: "Enable iPadOS UI", icon: "ipad", infoType: .warning, infoMessage: MGMsg.ipadOS, isOn: store.mgTrollPadBinding())
                } header: {
                    HeaderLabel(text: "iPadOS", icon: "ipad")
                }
            }
            .navigationTitle("MobileGestalt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Apply", role: .destructive) {
                        if !hasShownSheet { showInfoSheet = true }
                        else { mgApply() }
                    }
                }
            }
            .sheet(isPresented: $showInfoSheet) {
                NavigationStack {
                    VStack {
                        Text("Warning").font(.title).padding()
                        Text(MGMsg.support).padding()
                        Button("Apply") {
                            showInfoSheet = false
                            hasShownSheet = true
                            idiotButtonTimerComplete = false
                            mgApply(isFromSheet: true)
                        }.padding().disabled(!idiotButtonTimerComplete)
                    }
                    .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 4) { idiotButtonTimerComplete = true } }
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Cancel") { showInfoSheet = false; idiotButtonTimerComplete = false }
                        }
                    }
                }
            }
            .onAppear {
                store.mgCurrentDict = mgLoadData()
            }
        }
    }
    
    // ==========================================
    // LOGIC CỦA EROSION (ĐÃ TÍCH HỢP BAD_QUERY)
    // ==========================================
    private func mgWrite(_ data: Data) -> Bool {
        var pathC = Array(MGURL.fsGestaltURL.path.utf8CString)
        let handle = bad_query(&pathC, false, nil, false)
        guard handle > 0 else { return false }
        defer { bad_query_release(handle) }
        
        if mgWriteAtomically {
            let res = writeFileAtomically(data, to: MGURL.fsGestaltURL)
            return res.0
        } else {
            do { try data.write(to: MGURL.fsGestaltURL); return true }
            catch { return false }
        }
    }
    
    private func mgLoadData() -> NSMutableDictionary {
        do {
            let mgData = try Data(contentsOf: MGURL.fsGestaltURL)
            if !FileManager.default.fileExists(atPath: MGURL.savedGestaltURL.path) {
                try mgData.write(to: MGURL.savedGestaltURL)
                if let locale = Locale.current.region?.identifier { showRegionTweak = locale != "US" }
            }
            
            if let ogDict = NSDictionary(contentsOf: MGURL.savedGestaltURL),
               let ogCacheExtra = ogDict["CacheExtra"] as? NSDictionary,
               let ogArtwork = ogCacheExtra[MGKey.artwork] as? NSDictionary {
                mgOgSubtype = ogArtwork["ArtworkDeviceSubType"] as? Int ?? 0
                mgOgDeviceName = ogArtwork["ArtworkDeviceProductDescription"] as? String ?? ""
            }
            
            guard let currentDict = NSMutableDictionary(contentsOf: MGURL.fsGestaltURL) else { throw "failed to get dict" }
            if let cacheExtra = currentDict["CacheExtra"] as? NSDictionary,
               let artwork = cacheExtra[MGKey.artwork] as? NSDictionary {
                mgSubtype = artwork["ArtworkDeviceSubType"] as? Int ?? 0
                mgDeviceName = artwork["ArtworkDeviceProductDescription"] as? String ?? ""
                if mgDeviceName != mgOgDeviceName { mgEnableDeviceName = true }
                mgProductType = cacheExtra[MGKey.prodType] as? String ?? machineName()
            }
            return currentDict
        } catch {
            Alertinator.shared.alert(title: "Failed to get MobileGestalt!", body: "\(error.localizedDescription)", showCancel: false, actionLabel: "Exit", action: { dismiss() })
        }
        return [:]
    }
    
    private func mgApply(isFromSheet: Bool = false) {
        do {
            let mgDictToApply = store.mgCurrentDict
            if let cacheExtra = mgDictToApply["CacheExtra"] as? NSMutableDictionary,
               let artwork = cacheExtra[MGKey.artwork] as? NSMutableDictionary {
                artwork["ArtworkDeviceSubType"] = mgSubtype
                if mgEnableDeviceName { artwork["ArtworkDeviceProductDescription"] = mgDeviceName }
                cacheExtra[MGKey.prodType] = mgProductType
            } else {
                throw "failed to write keys!"
            }
            
            let data = try PropertyListSerialization.data(fromPropertyList: mgDictToApply, format: .binary, options: 0)
            let res = mgWrite(data)
            
            if res {
                if autoRespring || isFromSheet { mgr.respring() }
                else { Alertinator.shared.alert(title: "Successfully applied!", body: "Respring to see changes.", actionLabel: "Respring", action: { mgr.respring() }) }
            } else {
                throw "overwrite failed!"
            }
        } catch {
            Alertinator.shared.alert(title: "Failed to apply!", body: "Error: \(error.localizedDescription)")
        }
    }
}

// ==========================================
// HÀM HỖ TRỢ
// ==========================================
func machineName() -> String {
    var systemInfo = utsname()
    uname(&systemInfo)
    let machineMirror = Mirror(reflecting: systemInfo.machine)
    return machineMirror.children.reduce("") { identifier, element in
        guard let value = element.value as? Int8, value != 0 else { return identifier }
        return identifier + String(UnicodeScalar(UInt8(value)))
    }
}

func doubleSysVrs() -> Double {
    return Double(UIDevice.current.systemVersion.split(separator: ".").first ?? "0") ?? 0.0
}