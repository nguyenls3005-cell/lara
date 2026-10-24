import SwiftUI

struct TweaksView: View {
    @AppStorage("logsdisplaymode") private var selectedlogsdisplaymode: logsdisplaymode = .toolbar
    @ObservedObject var mgr: laramgr
    
    var body: some View {
        NavigationStack {
            List {
                Section(header: HeaderLabel(text: "SpringBoard", icon: "house")) {
                    // Đã xóa RemoteCall Customizer, SpringBoard Customizer
                    NavigationLink("Liquid Glass", destination: LiquidGlassView())
                        .disabled(!mgr.vfsready)
                }
                
                Section(header: HeaderLabel(text: "Lock Screen", icon: "lock")) {
                    // Giữ lại Passcode Theme (Mở khóa bởi Airlift)
                    NavigationLink("Passcode Theme", destination: PasscodeView(mgr: mgr))
                        .disabled(!mgr.vfsready)
                }
                
                Section(header: HeaderLabel(text: "Apps", icon: "app")) {
                    // Đã xóa Card Overwrite, App Decrypt, 3 App Bypass, Unblacklist
                    NavigationLink("JIT Enabler", destination: JitView())
                        .disabled(!mgr.sbxready)
                }
                
                Section(header: HeaderLabel(text: "User Interface", icon: "eye")) {
                    // Đã xóa dirtyZero, Show Hidden Icons, Font Overwrite, SystemColor Patcher
                    // Giữ lại MobileGestalt (Mở khóa bởi Bad_query)
                    NavigationLink("MobileGestalt", destination: GestaltView(mgr: mgr))
                        .disabled(!mgr.sbxready)
                }
                
                Section(header: HeaderLabel(text: "System", icon: "gear")) {
                    // Thêm Daemons (đã xóa hết các mục cũ)
                    NavigationLink("Daemons", destination: DaemonsView(mgr: mgr))
                        .disabled(!mgr.dsready)
                }
                
                // Đã xóa Broken và Extra Tools
            }
            .disabled(!mgr.dsready)
            .navigationTitle("Tweaks")
            .toolbar {
                if selectedlogsdisplaymode == .toolbar {
                    Button(action: { mgr.showLogs.toggle() }) {
                        Image(systemName: "terminal")
                    }
                }
            }
        }
    }
}

// ==========================================
// Giao diện Daemons (Full tính năng iOS)
// ==========================================
struct DaemonsView: View {
    @ObservedObject var mgr: laramgr
    
    // Danh sách các daemon của iOS từ OTA đến các daemon hệ thống
    let daemons = [
        "com.apple.OTATaskingAgent",
        "com.apple.mobile.softwareupdated",
        "com.apple.softwareupdateservicesd",
        "com.apple.SoftwareUpdateNotificationManager",
        "com.apple.backgroundtaskmanagement.agent",
        "com.apple.backboardd",
        "com.apple.SpringBoard",
        "com.apple.runningboardd",
        "com.apple.mediaserverd",
        "com.apple.audio.audiohald",
        "com.apple.wifi.WiFiManager",
        "com.apple.bluetoothd",
        "com.apple.symptomsd",
        "com.apple.sysdiagnose",
        "com.apple.watchdogd"
    ]
    
    @State private var disabledDaemons: Set<String> = []
    @State private var showAlert = false
    
    var body: some View {
        List {
            Section(header: HeaderLabel(text: "System Daemons", icon: "gearshape.2.fill")) {
                ForEach(daemons, id: \.self) { daemon in
                    HStack {
                        Text(daemon)
                            .font(.system(.footnote, design: .monospaced))
                        Spacer()
                        // Toggle tắt/bật daemon
                        Toggle("", isOn: Binding(
                            get: { disabledDaemons.contains(daemon) },
                            set: { isOn in
                                if isOn { disabledDaemons.insert(daemon) }
                                else { disabledDaemons.remove(daemon) }
                            }
                        ))
                    }
                }
            }
            
            Section {
                Button("Apply Daemon Changes") {
                    showAlert = true
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .foregroundColor(.blue)
            }
        }
        .navigationTitle("Daemons")
        .alert("Demo Mode", isPresented: $showAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Daemon settings saved (Demo). No actual system files were modified.")
        }
    }
}