import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @AppStorage("selectedMethod") private var selectedmethod: method = .hybrid
    
    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("Exploit Method")) {
                    Picker("Method", selection: $selectedmethod) {
                        // Đã đổi tên theo yêu cầu
                        Text("Airlift").tag(method.hybrid)
                        Text("Bad_query").tag(method.sbx)
                        Text("Both Exploit").tag(method.vfs)
                    }
                    .pickerStyle(.inline)
                }
                
                // Các Setting khác giữ nguyên (nếu có)
                // Đã bỏ Kernelcache, FileManager, RemoteCall
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}