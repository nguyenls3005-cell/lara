//
//  SettingsView.swift
//  lara
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

// ĐÃ ĐỔI RAW VALUE ĐỂ NÚT TỰ ĐỘNG ĐỔI TÊN TRÊN UI
enum method: String, CaseIterable {
    case vfs = "Both Exploit"
    case sbx = "Bad_query"
    case hybrid = "Airlift"
}

enum fmAppsDisplayMode: String, CaseIterable {
    case UUID = "UUID"
    case bundleID = "Bundle ID"
    case appName = "App Name"
}

enum logsdisplaymode: String, CaseIterable {
    case tabs = "In Tabs"
    case toolbar = "In Toolbar"
    case content = "Directly in ContentView"
}

struct SettingsView: View {
    @EnvironmentObject var mgr: laramgr
    
    @AppStorage("selectedMethod") private var selectedMethod: method = .hybrid
    @AppStorage("keepAlive") private var keepAlive: Bool = false
    
    @State private var showBackupAlert = false
    
    @AppStorage("logsdisplaymode") private var selectedlogdisplaymode: logsdisplaymode = .toolbar
    @AppStorage("loggerNoBS") private var loggerNoBS: Bool = true
    
    // Các biến cũ giữ nguyên đề phòng code khác gọi đến
    @AppStorage("showFMInTabs") private var showFMInTabs: Bool = true
    @AppStorage("selectedFMAppsDisplayMode") private var selectedFMAppsDisplayMode: fmAppsDisplayMode = .appName
    @AppStorage("fmRecursiveSearch") private var fmRecursiveSearch: Bool = false
    @AppStorage("rcDockUnlimited") private var rcDockUnlimited: Bool = false
    
    var body: some View {
        NavigationStack {
            List {
                Section(header: HeaderLabel(text: "About", icon: "info.circle")) {
                    AppInfoCell()
                    NavigationLink("Credits", destination: CreditsView())
                }
                
                Section(header: HeaderLabel(text: "Exploit", icon: "ant")) {
                    // Picker này sẽ tự động hiển thị Both Exploit, Bad_query, Airlift
                    Picker("", selection: $selectedMethod) {
                        ForEach(method.allCases, id: \.self) { method in
                            Text(method.rawValue).tag(method)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    NavigationLink("Modify Offsets", destination: OffsetManagementView())
                }
                
                // ĐÃ THAY KERNELCACHE BẰNG MOBILEGESTALT BACKUP
                Section {
                    Button("MobileGestalt Backup (First time)") {
                        showBackupAlert = true
                    }
                } header: {
                    HeaderLabel(text: "Backup", icon: "cpu")
                }
                
                // APP SETTINGS
                Section(header: HeaderLabel(text: "App", icon: "gearshape"), footer: Text("If keep alive is enabled, the app will continue running even if it is minimized.")) {
                    Toggle("Keep Alive", isOn: $keepAlive)
                        .onChange(of: keepAlive) { _ in
                            if keepAlive {
                                if !kaenabled { toggleka() }
                            } else {
                                if kaenabled { toggleka() }
                            }
                        }
                    Toggle("Disable Log Dividers", isOn: $loggerNoBS)
                    Picker("Logs Display", selection: $selectedlogdisplaymode) {
                        ForEach(logsdisplaymode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                }
                
                // ĐÃ XÓA FILE MANAGER VÀ REMOTECALL Ở ĐÂY
            }
            .navigationTitle("Settings")
            .alert("Backup Complete", isPresented: $showBackupAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("MobileGestalt Backup saved successfully (Demo Mode).")
            }
        }
    }
}