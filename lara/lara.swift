//
//  lara.swift
//  lara
//

import SwiftUI
import UniformTypeIdentifiers

enum method: String, CaseIterable { case hybrid, vfs, sbx }
enum logsdisplaymode: String, CaseIterable { case toolbar, content, tabs }
enum taboptions { case applying, tweaks, files, logs }

var weonadebugbuild_pjbweouttahereexclamationmark: Bool = false

@main
struct lara: App {
    @StateObject private var mgr = laramgr.shared
    @StateObject private var iconthememgr = IconThemeManager.shared
    @Environment(\.scenePhase) var scenephase
    @AppStorage("selectedMethod") private var selectedMethod: method = .hybrid
    @AppStorage("keepAlive") private var keepalive: Bool = false
    @AppStorage("logsdisplaymode") private var logsdisplaymode: logsdisplaymode = .toolbar
    @State private var selectedtab: taboptions = .applying
    
    init() {
        #if DEBUG
        weonadebugbuild_pjbweouttahereexclamationmark = true
        #endif
        
        let fixMethod = class_getInstanceMethod(UIDocumentPickerViewController.self, #selector(UIDocumentPickerViewController.fix_init(forOpeningContentTypes:asCopy:)))!
        let origMethod = class_getInstanceMethod(UIDocumentPickerViewController.self, #selector(UIDocumentPickerViewController.init(forOpeningContentTypes:asCopy:)))!
        method_exchangeImplementations(origMethod, fixMethod)
        
        if keepalive { toggleka() }
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
                    .tabItem { Image(systemName: "wrench.and.screwdriver.fill") }
                    .tag(taboptions.applying)
                
                TweaksView(mgr: mgr)
                    .tabItem { Image(systemName: "ant.fill") }
                    .tag(taboptions.tweaks)
                
                if logsdisplaymode == .tabs {
                    LogsView(logger: globallogger)
                        .tabItem { Image(systemName: "terminal") }
                        .tag(taboptions.logs)
                }
            }
            .environmentObject(mgr)
            .overlay {
                if mgr.showrespring {
                    respringview().brightness(-1.0).ignoresSafeArea()
                }
            }
            .sheet(isPresented: Binding(
                get: { logsdisplaymode == .toolbar && mgr.showLogs },
                set: { mgr.showLogs = $0 }
            )) { LogsView(logger: globallogger) }
            .sheet(isPresented: $iconthememgr.showFixupSheet) { IconThemeFixupView() }
            .onAppear {
                mgr.hasOffsets = false
            }
            .onChange(of: scenephase, perform: handleScenePhase)
            .onChange(of: mgr.sbxready) { ready in
                if ready { iconthememgr.startPendingFixupIfPossible() }
            }
        }
    }
    
    private func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .inactive, .background: break
        case .active: globallogger.capture()
        @unknown default: break
        }
    }
}

extension UIDocumentPickerViewController {
    @objc func fix_init(forOpeningContentTypes contentTypes: [UTType], asCopy: Bool) -> UIDocumentPickerViewController {
        return fix_init(forOpeningContentTypes: contentTypes, asCopy: true)
    }
}
extension String: @retroactive Error {}