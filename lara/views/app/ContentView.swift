//
//  ContentView.swift
//  lara
//

import SwiftUI
import UniformTypeIdentifiers
import Darwin

struct ContentView: View {
    @EnvironmentObject private var mgr: laramgr
    @ObservedObject private var logger = globallogger
    @AppStorage("selectedMethod") private var selectedmethod: method = .hybrid
    @AppStorage("logsdisplaymode") private var selectedlogsdisplaymode: logsdisplaymode = .toolbar
    @AppStorage("loggerNoBS") private var loggernobs: Bool = true
    
    @State private var showSettings: Bool = false
    @State private var showSuccessAlert = false
    @State private var alertMessage = "Action completed successfully."
    
    @State private var hasPairingFile = false
    @State private var isTunnelActive = false
    @State private var showPairingImporter = false
    @State private var pairingFileName = ""
    
    init() {
        globallogger.capture()
    }
    
    var body: some View {
        NavigationStack {
            List {
                AlertsSection
                KRWSection
                ActionsSection
                InlineLogsSection
            }
            .navigationTitle("lara")
            .toolbar {
                if selectedlogsdisplaymode == .toolbar {
                    Button(action: { mgr.showLogs.toggle() }) {
                        Image(systemName: "terminal")
                    }
                }
                Button(action: { showSettings.toggle() }) {
                    Image(systemName: "gear")
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .alert("Success", isPresented: $showSuccessAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(alertMessage)
            }
            .fileImporter(
                isPresented: $showPairingImporter,
                allowedContentTypes: [.propertyList, UTType(filenameExtension: "mobiledevicepairing")!, UTType(filenameExtension: "mobilepair")!],
                allowsMultipleSelection: false
            ) { result in
                handlePairingImport(result: result)
            }
        }
    }
    
    private var AlertsSection: some View {
        Section {
            if !mgr.hasOffsets && !mgr.sbxready {
                PlainAlert(title: "No offsets found!", icon: "exclamationmark.triangle.fill", text: "Kernelcache offsets are missing. Click \"Run Bad_query\" and then fetch the offsets.")
            }
        }
    }
    
    private var KRWSection: some View {
        Section {
            // 1. RUN BAD_QUERY
            LabeledContent(content: {
                if mgr.sbxready {
                    Image(systemName: "checkmark.circle")
                } else if mgr.dsrunning {
                    HStack {
                        Text("\(Int(mgr.dsprogress * 100))%")
                        ProgressView()
                    }
                }
            }) {
                Button("Run Bad_query", action: {
                    mgr.dsrunning = true
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        mgr.dsrunning = false
                        mgr.dsready = true
                        mgr.hasOffsets = true
                        mgr.sbxready = true
                        
                        if mgr.vfsready {
                            selectedmethod = .vfs
                            alertMessage = "Both Exploit activated successfully."
                        } else {
                            selectedmethod = .sbx
                            alertMessage = "Bad_query executed successfully."
                        }
                        showSuccessAlert = true
                    }
                })
                .disabled(mgr.sbxready || mgr.dsrunning)
            }
            
            // 2. RUN AIRLIFT (ĐÃ FIX)
            LabeledContent(content: {
                if mgr.vfsready {
                    Image(systemName: "checkmark.circle")
                } else if mgr.vfsrunning {
                    HStack {
                        Text("Running...")
                        ProgressView()
                    }
                }
            }) {
                Button("Run Airlift", action: {
                    mgr.vfsrunning = true
                    
                    // NẠP FRAMEWORK NGẦM ĐỂ LẤY GRAPPA TOKEN
                    let frameworks = [
                        "/System/Library/PrivateFrameworks/AirTraffic.framework/AirTraffic",
                        "/System/Library/PrivateFrameworks/MobileAsset.framework/MobileAsset",
                        "/System/Library/PrivateFrameworks/MobileSoftwareUpdate.framework/MobileSoftwareUpdate"
                    ]
                    for path in frameworks { dlopen(path, RTLD_NOW | RTLD_GLOBAL) }
                    
                    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    let pairingPath = docs.appendingPathComponent("airlift_pairing.plist").path
                    let targetDir = "/var/mobile/Library/Passes/Cards"
                    
                    DispatchQueue.global(qos: .userInitiated).async {
                        let logCallback: @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?) -> Void = { _, msg in
                            if let msg = msg { print("[Airlift Native] \(String(cString: msg))") }
                        }
                        
                        var outJson: UnsafeMutablePointer<CChar>? = nil
                        var outError: UnsafeMutablePointer<CChar>? = nil
                        
                        // SET HOST TRƯỚC KHI CHẠY
                        _ = "10.7.0.1".withCString { al_set_target_host($0) }
                        
                        let result = pairingPath.withCString { pairingC in
                            targetDir.withCString { targetC in
                                al_exploit_run(pairingC, targetC, logCallback, nil, &outJson, &outError)
                            }
                        }
                        
                        if let error = outError {
                            print("[Airlift Native] Exploit error: \(String(cString: error))")
                            al_string_free(error)
                        }
                        if let json = outJson {
                            print("[Airlift Native] Result: \(String(cString: json))")
                            al_string_free(json)
                        }
                        
                        DispatchQueue.main.async {
                            mgr.vfsrunning = false
                            if result == 0 {
                                mgr.vfsready = true
                                if mgr.sbxready {
                                    selectedmethod = .vfs
                                    alertMessage = "Both Exploit activated successfully."
                                } else {
                                    selectedmethod = .hybrid
                                    alertMessage = "Airlift executed successfully."
                                }
                            } else {
                                alertMessage = "Airlift exploit failed. Check Xcode logs."
                            }
                            showSuccessAlert = true
                        }
                    }
                })
                .disabled(!mgr.sbxready || mgr.vfsready || mgr.vfsrunning || !hasPairingFile || !isTunnelActive)
            }
            
            if !mgr.vfsready {
                if !hasPairingFile {
                    Button {
                        showPairingImporter = true
                    } label: {
                        Label(pairingFileName.isEmpty ? "Import Pairing File (.plist)" : "Pairing File: \(pairingFileName)", systemImage: "doc.badge.plus")
                    }
                }
                
                if !isTunnelActive {
                    Button {
                        checkTunnelStatus()
                    } label: {
                        Label("Scan Tunnel (LocalDevVPN)", systemImage: "network")
                    }
                }
            }
            
        } header: {
            HeaderLabel(text: "Kernel Read Write", icon: "externaldrive")
        } footer: {
            if isdebugged() { Text("Not available while a debugger is attached.") }
        }
        .onAppear {
            checkTunnelStatus()
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let pairingPath = docs.appendingPathComponent("airlift_pairing.plist").path
            hasPairingFile = FileManager.default.fileExists(atPath: pairingPath)
        }
    }
    
    private var ActionsSection: some View {
        Section(header: HeaderLabel(text: "Actions", icon: "wrench.and.screwdriver")) {
            Button("Respring", action: { })
        }
    }

    @ViewBuilder
    private var InlineLogsSection: some View {
        if selectedlogsdisplaymode == .content {
            Section {
                ScrollView {
                    if loggernobs {
                        let combined = logger.logs.joined(separator: "\n")
                        Text(combined).font(.system(size: 13, design: .monospaced)).lineSpacing(1).textSelection(.enabled)
                    } else {
                        ForEach(Array(logger.logs.enumerated()), id: \.offset) { _, log in
                            Text(log).font(.system(size: 13, design: .monospaced)).lineSpacing(1).textSelection(.enabled)
                        }
                    }
                }
                .frame(height: 250)
                Button("Copy All") { UIPasteboard.general.string = logger.logs.joined(separator: "\n\n") }
                Button("Clear") { logger.clear() }.foregroundColor(.red)
            } header: {
                HeaderLabel(text: "Logs", icon: "terminal")
            }
        }
    }
    
    private func handlePairingImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            guard let data = try? Data(contentsOf: url), !data.isEmpty else {
                alertMessage = "Invalid pairing file."; showSuccessAlert = true; return
            }
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let destURL = docs.appendingPathComponent("airlift_pairing.plist")
            do {
                try data.write(to: destURL, options: .atomic)
                hasPairingFile = true
                pairingFileName = url.lastPathComponent
                alertMessage = "Pairing file imported successfully."; showSuccessAlert = true
            } catch {
                alertMessage = "Failed to save: \(error.localizedDescription)"; showSuccessAlert = true
            }
        case .failure(let error):
            alertMessage = "Import failed: \(error.localizedDescription)"; showSuccessAlert = true
        }
    }
    
    private func checkTunnelStatus() {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { isTunnelActive = false; return }
        defer { freeifaddrs(ifaddr) }
        
        var tunnelDetected = false
        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            guard let addr = interface.ifa_addr, addr.pointee.sa_family == sa_family_t(AF_INET) else { continue }
            let name = String(cString: interface.ifa_name).lowercased()
            if name.hasPrefix("utun") || name.hasPrefix("ipsec") || name.hasPrefix("ppp") || name.hasPrefix("tun") || name.hasPrefix("tap") {
                tunnelDetected = true
                break
            }
        }
        isTunnelActive = tunnelDetected
    }
}