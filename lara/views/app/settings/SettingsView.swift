//
//  SettingsView.swift
//  lara
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    
    @AppStorage("selectedMethod") private var selectedmethod: method = .hybrid
    // ĐÃ ĐỔI TÊN BIẾN THÀNH logsMode ĐỂ KHÔNG BỊ TRÙNG VỚI TÊN ENUM
    @AppStorage("logsdisplaymode") private var logsMode: logsdisplaymode = .toolbar
    @AppStorage("loggerNoBS") private var loggernobs: Bool = true
    @AppStorage("keepAlive") private var keepalive: Bool = false
    
    @State private var showBackupAlert = false
    
    var body: some View {
        NavigationStack {
            List {
                // PHẦN EXPLOIT (ĐÃ ĐỔI TÊN THEO YÊU CẦU)
                Section(header: Text("Exploit Method")) {
                    Picker("Method", selection: $selectedmethod) {
                        Text("Airlift").tag(method.hybrid)
                        Text("Bad_query").tag(method.sbx)
                        Text("Both Exploit").tag(method.vfs)
                    }
                    .pickerStyle(.inline)
                }
                
                // PHẦN BACKUP (ĐÃ THÊM LẠI)
                Section(header: Text("Backup")) {
                    Button("MobileGestalt Backup (First time)") {
                        showBackupAlert = true
                    }
                }
                
                // CÁC CÀI ĐẶT KHÁC CỦA APP (GIỮ LẠI)
                Section(header: Text("Logs")) {
                    Picker("Display Mode", selection: $logsMode) {
                        // Sửa lại thành logsdisplaymode.toolbar (gọi trực tiếp từ enum)
                        Text("Toolbar").tag(logsdisplaymode.toolbar)
                        Text("Content").tag(logsdisplaymode.content)
                        Text("Tabs").tag(logsdisplaymode.tabs)
                    }
                    Toggle("No BS Logging", isOn: $loggernobs)
                }
                
                Section(header: Text("System")) {
                    Toggle("Keep Alive", isOn: $keepalive)
                    
                    // ĐÃ BỎ: Kernelcache, FileManager, RemoteCall
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            // Thông báo khi bấm Backup
            .alert("Backup Complete", isPresented: $showBackupAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("MobileGestalt Backup saved successfully (Demo Mode).")
            }
        }
    }
}