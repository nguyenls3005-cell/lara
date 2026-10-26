//
//  lara.swift
//  lara
//

import SwiftUI
import UniformTypeIdentifiers
import Darwin

// BẮT BUỘC PHẢI CÓ ENUM NÀY ĐỂ ShowHiddenIconsView HOẠT ĐỘNG
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

// HÀM GHI FILE AN TOÀN ĐỂ ROLLBACK KHI BOOTLOOP
func writeFileAtomically(_ data: Data, to url: URL) -> (Bool, String) {
    let fd = url.path.withCString { open($0, O_RDWR | O_CLOEXEC | O_NOFOLLOW) }
    guard fd >= 0 else { return (false, "Failed to open file (errno: \(errno))") }
    defer { close(fd) }
    
    guard ftruncate(fd, 0) == 0 else { return (false, "Failed to truncate (errno: \(errno))") }
    guard lseek(fd, 0, SEEK_SET) >= 0 else { return (false, "Failed to lseek") }
    
    var bytesWritten = 0
    let totalBytes = data.count
    let success = data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> Bool in
        guard let baseAddress = buffer.baseAddress else { return false }
        while bytesWritten < totalBytes {
            let result = write(fd, baseAddress + bytesWritten, totalBytes - bytesWritten)
            if result <= 0 { return false }
            bytesWritten += result
        }
        return true
    }
    
    if success {
        guard fsync(fd) == 0 else { return (false, "Failed to fsync (errno: \(errno))") }
    }
    
    return (success, success ? "succeeded" : "Write failed")
}

// ĐÃ XÓA HOÀN TOÀN 2 ENUM method VÀ logsdisplaymode (ĐỂ TRÁNH TRÙNG VỚI SettingsView)

enum taboptions {
    case applying, tweaks, files, logs
}

var weonadebugbuild_pjbweouttahereexclamationmark: Bool = false

@main
struct lara: App {
    @StateObject private var mgr = laramgr.shared
    @StateObject private var iconthememgr = IconThemeManager.shared
    @Environment(\.scenePhase) var scenephase
    @AppStorage("selectedMethod") private var selectedMethod: method = .hybrid
    @AppStorage("keepAlive") private var keepalive: Bool = false
    @AppStorage("showFMInTabs") private var showfmintabs: Bool = true
    @AppStorage("logsdisplaymode") private var logsdisplaymode: logsdisplaymode = .toolbar
    @State private var selectedtab: taboptions = .applying
    
    init() {
        #if DEBUG
        weonadebugbuild_pjbweouttahereexclamationmark = true
        #endif
        
        // fix file picker
        let fixMethod = class_getInstanceMethod(UIDocumentPickerViewController.self, #selector(UIDocumentPickerViewController.fix_init(forOpeningContentTypes:asCopy:)))!
        let origMethod = class_getInstanceMethod(UIDocumentPickerViewController.self, #selector(UIDocumentPickerViewController.init(forOpeningContentTypes:asCopy:)))!
        method_exchangeImplementations(origMethod, fixMethod)
        
        if keepalive {
            toggleka()
        }
        
        globallogger.capture()
        
        // ==========================================
        // FIX BOOTLOOP: TỰ ĐỘNG ROLLBACK MOBILEGESTALT KHI APP KHỞI ĐỘNG
        // ==========================================
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let backupPath = docs.appendingPathComponent("OriginalGestalt.plist").path
        let currentPath = "/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist"
        
        if FileManager.default.fileExists(atPath: backupPath) {
            var pathC = Array(currentPath.utf8CString)
            let handle = bad_query(&pathC, false, nil, false)
            
            if handle > 0 {
                defer { bad_query_release(handle) }
                // Nếu file hiện tại bị rỗng (0 byte) thì mới rollback để tránh mất tweak đang dùng
                if let attrs = try? FileManager.default.attributesOfItem(atPath: currentPath),
                   let size = attrs[.size] as? NSNumber, size.intValue == 0 {
                    
                    if let originalData = try? Data(contentsOf: URL(fileURLWithPath: backupPath)) {
                        let url = URL(fileURLWithPath: currentPath)
                        let result = writeFileAtomically(originalData, to: url)
                        print("[Lara] Bootloop detected! Auto-rollback: \(result.0 ? "Success" : "Failed")")
                    }
                }
            }
        }
    }
    
    var body: some Scene {
        WindowGroup {
            TabView(selection: $selectedtab) {
                ContentView()
                    .tabItem {
                        Image(systemName: "wrench.and.screwdriver.fill")
                    }
                    .tag(taboptions.applying)
                
                TweaksView(mgr: mgr)
                    .tabItem {
                        Image(systemName: "ant.fill")
                    }
                    .tag(taboptions.tweaks)
                
                if showfmintabs {
                    SantanderView(startPath: "/")
                        .tabItem {
                            Image(systemName: "folder.fill")
                        }
                        .tag(taboptions.files)
                }
                
                if logsdisplaymode == .tabs {
                    LogsView(logger: globallogger)
                        .tabItem {
                            Image(systemName: "terminal")
                        }
                        .tag(taboptions.logs)
                }
            }
            .environmentObject(mgr)
            .overlay {
                if mgr.showrespring {
                    respringview()
                        .brightness(-1.0)
                        .ignoresSafeArea()
                }
            }
            .sheet(isPresented: Binding(
                get: { logsdisplaymode == .toolbar && mgr.showLogs },
                set: { mgr.showLogs = $0 }
            )) {
                LogsView(logger: globallogger)
            }
            .sheet(isPresented: $iconthememgr.showFixupSheet) {
                IconThemeFixupView()
            }
            .onAppear {
                mgr.hasOffsets = false
            }
            .onChange(of: scenephase, perform: handleScenePhase)
            .onChange(of: mgr.sbxready) { ready in
                if ready {
                    iconthememgr.startPendingFixupIfPossible()
                }
            }
        }
    }
    
    private func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .inactive, .background:
            handlebg()
            globallogger.stopcapture()
        case .active:
            globallogger.capture()
            iconthememgr.startPendingFixupIfPossible()
        @unknown default:
            break
        }
    }

    private func handlebg() {
        guard mgr.rcready else { return }
        let keepSpringBoardRemoteCallAlive = UserDefaults.standard.bool(forKey: "keepSpringBoardRemoteCallAliveIOS16")
        if isIOS16() && keepSpringBoardRemoteCallAlive {
            return
        }

        var bgTask: UIBackgroundTaskIdentifier = .invalid
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "RemoteCallCleanup") {
            endbgtask(&bgTask)
        }
        mgr.rcdestroy {
            self.endbgtask(&bgTask)
        }
    }

    private func endbgtask(_ task: inout UIBackgroundTaskIdentifier) {
        guard task != .invalid else { return }
        UIApplication.shared.endBackgroundTask(task)
        task = .invalid
    }
}

extension UIDocumentPickerViewController {
    @objc func fix_init(forOpeningContentTypes contentTypes: [UTType], asCopy: Bool) -> UIDocumentPickerViewController {
        return fix_init(forOpeningContentTypes: contentTypes, asCopy: true)
    }
}
extension String: @retroactive Error {}