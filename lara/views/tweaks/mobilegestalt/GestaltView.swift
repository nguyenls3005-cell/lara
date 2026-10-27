//
//  GestaltView.swift
//  lara
//

import SwiftUI
import UniformTypeIdentifiers
import Foundation
import Darwin

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
// GIAO DIỆN CHÍNH (LARA UI CŨ)
// ==========================================
struct GestaltView: View {
    let mgr: laramgr
    @StateObject private var store = GestaltStore.shared
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
    @State private var mgProductType = ""
    @State private var showInfoSheet = false
    @State private var idiotButtonTimerComplete = false
    
    var body: some View {
        List {
            Section(header: HeaderLabel(text: "Applying", icon: "checkmark")) {
                Button {
                    if !hasShownSheet { showInfoSheet = true }
                    else { mgApply() }
                } label: {
                    Text("Apply Tweaks")
                }
                .disabled(!mgr.sbxready)
                
                Button {
                    mgRevert()
                } label: {
                    Text("Reset Tweaks")
                }
                .disabled(!mgr.sbxready)
            }
            
            Section(header: HeaderLabel(text: "Device Artwork", icon: "paintbrush.pointed")) {
                Picker(selection: $mgSubtype) {
                    Text("Original (\(mgOgSubtype))").tag(mgOgSubtype)
                    Text("iPhone 14 Pro").tag(2436)
                    Text("iPhone 14 Pro Max").tag(2796)
                    Text("iPhone 15 Pro Max").tag(2976)
                    if doubleSysVrs() >= 18.0 {
                        Text("iPhone 16 Pro").tag(2622)
                        Text("iPhone 16 Pro Max").tag(2868)
                    }
                    if doubleSysVrs() >= 26.0 { Text("iPhone Air").tag(2736) }
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
            
            Section(header: HeaderLabel(text: "Software-Oriented Features", icon: "gearshape")) {
                PlainToggle(text: "Dynamic Island", icon: "platter.filled.top.iphone", minSupportedVersion: 19.0, isOn: store.mgKeyBinding([MGKey.island]))
                PlainToggle(text: "Always On Display", icon: "sun.max", minSupportedVersion: 18.0, isOn: store.mgKeyBinding([MGKey.AOD, MGKey.AOTime]))
                if store.isEnabled([MGKey.AOD]) {
                    PlainToggle(text: "AOD Vibrancy", icon: "rays", minSupportedVersion: 18.0, isOn: store.mgKeyBinding([MGKey.AODVibrancy]))
                }
                PlainToggle(text: "Charge Limit", icon: "battery.100.bolt", minSupportedVersion: 17.0, isOn: store.mgKeyBinding([MGKey.chargeLim]))
                PlainToggle(text: "Boot Chime", icon: "speaker.wave.3", isOn: store.mgKeyBinding([MGKey.bootChime]))
            }
            
            Section(header: HeaderLabel(text: "Hardware-Oriented Features", icon: "iphone")) {
                PlainToggle(text: "Camera Control", icon: "camera.shutter.button", minSupportedVersion: 18.0, isOn: store.mgKeyBinding([MGKey.camButton, MGKey.grapPefr]))
                PlainToggle(text: "Action Button", icon: "button.vertical.left.press", minSupportedVersion: 17.0, isOn: store.mgKeyBinding([MGKey.actButton]))
                PlainToggle(text: "Crash Detection", icon: "car", isOn: store.mgKeyBinding([MGKey.crashDet]))
                if UIDevice._hasHomeButton() {
                    PlainToggle(text: "Enable Tap to Wake", icon: "hand.tap", isOn: store.mgKeyBinding([MGKey.tapToWake]))
                }
                PlainToggle(text: "Pulse Width Modulation", icon: "eye", minSupportedVersion: 19.0, isOn: store.mgKeyBinding([MGKey.pwm]))
            }
            
            Section(header: HeaderLabel(text: "Eligibility", icon: "checklist")) {
                PlainToggle(text: "Security Research Device UI", icon: "terminal", minSupportedVersion: 26.0, isOn: store.mgKeyBinding([MGKey.srd]))
                PlainToggle(text: "Disable Region Restrictions", icon: "globe", isOn: store.mgRegionRestrictionsBinding())
                PlainToggle(text: "Apple Intelligence", icon: "apple.intelligence", minSupportedVersion: 18.1, isOn: store.mgKeyBinding([MGKey.appIntell]))
            }
            
            Section(header: HeaderLabel(text: "iPadOS Features", icon: "ipad")) {
                PlainToggle(text: "Allow Installing iPadOS Apps", icon: "plus.app", isOn: store.mgKeyBinding(["9MZ5AdH43csAUajl/dU+IQ"]))
                PlainToggle(text: "Apple Pencil Settings", icon: "pencil", isOn: store.mgKeyBinding([MGKey.appPencil]))
                if UIDevice.current.userInterfaceIdiom == .pad {
                    PlainToggle(text: "Stage Manager", icon: "squares.leading.rectangle", isOn: store.mgKeyBinding([MGKey.stageMgr]))
                }
                PlainToggle(text: "iPadOS UI", icon: "ipad", infoType: .warning, infoMessage: MGMsg.ipadOS, isOn: store.mgTrollPadBinding())
            }
            
            Section(header: HeaderLabel(text: "Internal", icon: "ant")) {
                PlainToggle(text: "Internal Storage", icon: "externaldrive", isOn: store.mgKeyBinding([MGKey.intBuild]))
                PlainToggle(text: "Internal Features", icon: "gearshape", isOn: store.mgKeyBinding([MGKey.intInstall]))
            }
        }
        .navigationTitle("MobileGestalt")
        .navigationBarTitleDisplayMode(.inline)
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
    
    // ==========================================
    // LOGIC APPLY & RESET
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
                
                // FIX: Chỉ ghi đè nếu có giá trị, tránh ghi rỗng làm hỏng máy
                if !mgProductType.isEmpty {
                    cacheExtra[MGKey.prodType] = mgProductType
                }
            } else {
                throw "failed to write keys!"
            }
            
            let data = try PropertyListSerialization.data(fromPropertyList: mgDictToApply, format: .binary, options: 0)
            let res = mgWrite(data)
            
            if res {
                // FIX: Load lại UI ngay lập tức
                store.mgCurrentDict = mgDictToApply
                
                if autoRespring || isFromSheet { mgr.respring() }
                else { Alertinator.shared.alert(title: "Successfully applied!", body: "Respring to see changes.", actionLabel: "Respring", action: { mgr.respring() }) }
            } else {
                throw "overwrite failed!"
            }
        } catch {
            Alertinator.shared.alert(title: "Failed to apply!", body: "Error: \(error.localizedDescription)")
        }
    }
    
    private func mgRevert() {
        do {
            guard let mgDictToApply = NSMutableDictionary(contentsOf: MGURL.savedGestaltURL) else { throw "failed to get dict!" }
            let data = try PropertyListSerialization.data(fromPropertyList: mgDictToApply, format: .binary, options: 0)
            let res = mgWrite(data)
            
            if res {
                if let dict = NSMutableDictionary(contentsOf: MGURL.savedGestaltURL) {
                    store.mgCurrentDict = dict
                }
                Alertinator.shared.alert(title: "Successfully reverted!", body: MGMsg.revertComp, actionLabel: "Respring", action: { mgr.respring() })
            } else {
                throw "overwrite failed!"
            }
        } catch {
            Alertinator.shared.alert(title: "Failed to revert!", body: "Error: \(error.localizedDescription)")
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