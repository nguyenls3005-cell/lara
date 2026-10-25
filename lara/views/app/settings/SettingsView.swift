//
//  SettingsView.swift
//  lara
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

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
    
    @AppStorage("logsdisplaymode") private var selectedlogdisplaymode: logsdisplaymode = .toolbar
    @AppStorage("loggerNoBS") private var loggerNoBS: Bool = true
    
    // TRẠNG THÁI BACKUP
    @AppStorage("isBackedUp") private var isBackedUp: Bool = false
    @AppStorage("backupDate") private var backupDate: String = ""
    @AppStorage("backupSize") private var backupSize: String = ""
    
    @State private var showkcacheimport: Bool = false
    
    var body: some View {
        NavigationStack {
            List {
                Section(header: HeaderLabel(text: "About", icon: "info.circle")) {
                    AppInfoCell()
                    NavigationLink("Credits", destination: CreditsView())
                }
                
                Section(header: HeaderLabel(text: "Exploit", icon: "ant")) {
                    Picker("", selection: $selectedMethod) {
                        ForEach(method.allCases, id: \.self) { method in
                            Text(method.rawValue).tag(method)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    NavigationLink("Modify Offsets", destination: OffsetManagementView())
                }
                
                // PHẦN MOBILEGESTALT BACKUP (GIỐNG ẢNH 2 VÀ 3)
                Section(header: HeaderLabel(text: "MobileGestalt Backup", icon: "cpu")) {
                    if isBackedUp {
                        // TRẠNG THÁI: ĐÃ CÓ BACKUP (ẢNH 3)
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.shield.fill")
                                .foregroundColor(.green)
                                .font(.title2)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Backup available")
                                    .font(.headline)
                                Text("Date: \(backupDate)")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                                Text("Size: \(backupSize)")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                            }
                        }
                        .padding(.vertical, 8)
                        
                        Button(action: {
                            performBackup()
                        }) {
                            Label("Backup now", systemImage: "square.and.arrow.down")
                                .foregroundColor(.orange)
                        }
                        
                        Button(action: {
                            showkcacheimport = true
                        }) {
                            Label("Import backup", systemImage: "square.and.arrow.down.on.square")
                                .foregroundColor(.orange)
                        }
                        
                        Button(action: {
                            isBackedUp = false
                        }) {
                            Label("Delete backup", systemImage: "trash")
                                .foregroundColor(.red)
                        }
                        
                    } else {
                        // TRẠNG THÁI: CHƯA CÓ BACKUP (ẢNH 2)
                        HStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.title2)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("No backup available")
                                    .font(.headline)
                                Text("Create a backup to restore your settings later.")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                            }
                        }
                        .padding(.vertical, 8)
                        
                        Button(action: {
                            performBackup()
                        }) {
                            Label("Backup now", systemImage: "square.and.arrow.down")
                                .foregroundColor(.orange)
                        }
                        
                        Button(action: {
                            showkcacheimport = true
                        }) {
                            Label("Import backup", systemImage: "square.and.arrow.down.on.square")
                                .foregroundColor(.orange)
                        }
                    }
                }
                
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
            }
            .navigationTitle("Settings")
            .fileImporter(isPresented: $showkcacheimport, allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
                switch result {
                case .success(_):
                    // Giả lập import thành công
                    performBackup()
                case .failure:
                    break
                }
            }
        }
    }
    
    // HÀM GIẢ LẬP QUÁ TRÌNH BACKUP
    private func performBackup() {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy 'at' h:mm a"
        backupDate = formatter.string(from: Date())
        backupSize = "16,914 bytes"
        isBackedUp = true
        
        // Rung nhẹ báo hiệu thành công
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
}