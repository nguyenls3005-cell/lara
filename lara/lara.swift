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
        
        if keepalive {
            toggleka()
        }
        globallogger.capture()
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
                
                // Đã bỏ Tab File Manager (SantanderView)
                
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
            )) {
                LogsView(logger: globallogger)
            }
            .sheet(isPresented: $iconthememgr.showFixupSheet) {
                IconThemeFixupView()
            }
            .onAppear {
                // Xóa bỏ kiểm tra thiết bị gây crash
                mgr.hasOffsets = false
            }
            .onChange(of: scenephase) { phase in
                if phase == .active { globallogger.capture() }
            }
        }
    }
}

extension UIDocumentPickerViewController {
    @objc func fix_init(forOpeningContentTypes contentTypes: [UTType], asCopy: Bool) -> UIDocumentPickerViewController {
        return fix_init(forOpeningContentTypes: contentTypes, asCopy: true)
    }
}
extension String: @retroactive Error {}