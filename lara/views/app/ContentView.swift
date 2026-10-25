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
    
    init() { globallogger.capture() }
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    if !mgr.hasOffsets && !mgr.sbxready {
                        PlainAlert(title: "No offsets found!", icon: "exclamationmark.triangle.fill", text: "Kernelcache offsets are missing. Click \"Run Bad_query\" and then fetch the offsets.")
                    }
                }
                
                Section {
                    // BAD_QUERY
                    LabeledContent(content: {
                        if mgr.sbxready { Image(systemName: "checkmark.circle") }
                        else if mgr.dsrunning { HStack { Text("\(Int(mgr.dsprogress * 100))%"); ProgressView() } }
                    }) {
                        Button("Run Bad_query", action: {
                            mgr.dsrunning = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                mgr.dsrunning = false
                                mgr.dsready = true
                                mgr.hasOffsets = true
                                mgr.sbxready = true
                                if mgr.vfsready { selectedmethod = .vfs; alertMessage = "Both Exploit activated!" }
                                else { selectedmethod = .sbx; alertMessage = "Bad_query executed!" }
                                showSuccessAlert = true
                            }
                        }).disabled(mgr.sbxready || mgr.dsrunning)
                    }
                    
                    // AIRLIFT
                    LabeledContent(content: {
                        if mgr.vfsready { Image(systemName: "checkmark.circle") }
                        else if mgr.vfsrunning { HStack { Text("Running..."); ProgressView() } }
                    }) {
                        Button("Run Airlift", action: {
                            mgr.vfsrunning = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                mgr.vfsrunning = false
                                mgr.vfsready = true
                                if mgr.sbxready { selectedmethod = .vfs; alertMessage = "Both Exploit activated!" }
                                else { selectedmethod = .hybrid; alertMessage = "Airlift executed!" }
                                showSuccessAlert = true
                            }
                        }).disabled(!mgr.sbxready || mgr.vfsready || mgr.vfsrunning || !hasPairingFile || !isTunnelActive)
                    }
                    
                    // PAIRING & TUNNEL
                    if !mgr.vfsready {
                        if !hasPairingFile {
                            Button { showPairingImporter = true } label: {
                                Label(pairingFileName.isEmpty ? "Import Pairing File (.plist)" : "Pairing File: \(pairingFileName)", systemImage: "doc.badge.plus")
                            }
                        }
                        if !isTunnelActive {
                            Button { checkTunnelStatus() } label: {
                                Label("Scan Tunnel (LocalDevVPN)", systemImage: "network")
                            }
                        }
                    }
                } header: {
                    HeaderLabel(text: "Kernel Read Write", icon: "externaldrive")
                }
                
                Section(header: HeaderLabel(text: "Actions", icon: "wrench.and.screwdriver")) {
                    Button("Respring") { mgr.respring() }
                }
            }
            .navigationTitle("lara")
            .toolbar {
                if selectedlogsdisplaymode == .toolbar {
                    Button(action: { mgr.showLogs.toggle() }) { Image(systemName: "terminal") }
                }
                Button(action: { showSettings.toggle() }) { Image(systemName: "gear") }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .alert("Success", isPresented: $showSuccessAlert) { Button("OK", role: .cancel) { } } message: { Text(alertMessage) }
            .fileImporter(
                isPresented: $showPairingImporter,
                allowedContentTypes: [.propertyList, UTType(filenameExtension: "mobiledevicepairing")!, UTType(filenameExtension: "mobilepair")!],
                allowsMultipleSelection: false
            ) { handlePairingImport($0) }
            .onAppear { checkTunnelStatus() }
        }
    }
    
    private func handlePairingImport(_ result: Result<[URL], Error>) {
        if case .success(let urls) = result, let url = urls.first {
            guard let data = try? Data(contentsOf: url), !data.isEmpty else {
                alertMessage = "Invalid pairing file. Empty file."; showSuccessAlert = true; return
            }
            let dest = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("airlift_pairing.plist")
            try? data.write(to: dest)
            hasPairingFile = true
            pairingFileName = url.lastPathComponent
            alertMessage = "Pairing file imported."; showSuccessAlert = true
        }
    }
    
    private func checkTunnelStatus() {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return }
        defer { freeifaddrs(ifaddr) }
        
        var tunnel = false
        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            guard let addr = interface.ifa_addr, addr.pointee.sa_family == sa_family_t(AF_INET) else { continue }
            let name = String(cString: interface.ifa_name).lowercased()
            if ["utun", "tun", "ppp", "ipsec", "tap"].contains(where: { name.hasPrefix($0) }) {
                tunnel = true; break
            }
        }
        isTunnelActive = tunnel
        if tunnel { alertMessage = "Tunnel detected." } else { alertMessage = "No tunnel detected. Please run LocalDevVPN." }
        showSuccessAlert = true
    }
}