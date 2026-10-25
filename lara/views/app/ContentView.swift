//
//  ContentView.swift
//  lara
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var mgr: laramgr
    @ObservedObject private var logger = globallogger
    @AppStorage("selectedMethod") private var selectedmethod: method = .hybrid
    @AppStorage("logsdisplaymode") private var selectedlogsdisplaymode: logsdisplaymode = .toolbar
    @AppStorage("loggerNoBS") private var loggernobs: Bool = true
    
    @State private var showSettings: Bool = false
    @State private var dlingkcache: Bool = false
    @State private var showSuccessAlert = false
    
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
                Text("Action completed successfully! (Demo Mode)")
            }
        }
    }
    
    private var AlertsSection: some View {
        Section {
            if !mgr.hasOffsets {
                PlainAlert(title: "No offsets found!", icon: "exclamationmark.triangle.fill", text: "Kernelcache offsets are missing. Click \"Run Bad_query\" and then fetch the offsets.")
            }
        }
    }
    
    private var KRWSection: some View {
        Section {
            // NÚT 1: RUN BAD_QUERY (MỞ KHÓA MOBILEGESTALT)
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
                    selectedmethod = .sbx // Tự động chọn Bad_query trong setting
                    mgr.dsrunning = true
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        mgr.dsrunning = false
                        mgr.dsready = true
                        mgr.hasOffsets = true
                        mgr.sbxready = true // Mở khóa MobileGestalt
                        showSuccessAlert = true
                    }
                })
                .disabled(mgr.sbxready || mgr.dsrunning)
            }
            
            if !mgr.hasOffsets {
                Button {
                    guard !dlingkcache else { return }
                    dlingkcache = true

                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        mgr.hasOffsets = true
                        dlingkcache = false
                    }
                } label: {
                    if dlingkcache {
                        HStack {
                            Text("Backing up...")
                            Spacer()
                            ProgressView()
                        }
                    } else {
                        // ĐÃ ĐỔI THÀNH MOBILEGESTALT BACKUP
                        Text("MobileGestalt Backup (First time)")
                    }
                }
                .disabled(dlingkcache || !mgr.dsready)
            } else {
                // NÚT 2: DIAGNOSTIC AIRLIFT (MỞ KHÓA PASSCODE THEME)
                if selectedmethod == .hybrid {
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
                        Button("Diagnostic Airlift", action: {
                            selectedmethod = .hybrid // Tự động chọn Airlift trong setting
                            mgr.vfsrunning = true
                            
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                mgr.vfsrunning = false
                                mgr.vfsready = true // Mở khóa Passcode Theme
                                showSuccessAlert = true
                            }
                        })
                        .disabled(!mgr.hasOffsets || !mgr.dsready || mgr.vfsrunning || mgr.vfsready)
                    }
                }
                
                // NÚT CHẠY CẢ 2
                if mgr.sbxready && mgr.vfsready {
                    Button("Run Both Exploit") {
                        selectedmethod = .vfs // Tự động chọn Both Exploit trong setting
                        showSuccessAlert = true
                    }
                }
            }
        } header: {
            HeaderLabel(text: "Kernel Read Write", icon: "externaldrive")
        } footer: {
            if isdebugged() {
                Text("Not available while a debugger is attached.")
            }
        }
    }
    
    // ĐÃ XÓA HOÀN TOÀN RCSECTION VÀ DEBUG SECTION
    
    private var ActionsSection: some View {
        Section(header: HeaderLabel(text: "Actions", icon: "wrench.and.screwdriver")) {
            // CHỈ GIỮ LẠI RESPIRING
            Button("Respring", action: {
                print("Demo: Respring clicked")
            })
        }
    }

    @ViewBuilder
    private var InlineLogsSection: some View {
        if selectedlogsdisplaymode == .content {
            Section {
                ScrollView {
                    if loggernobs {
                        let combined = logger.logs.joined(separator: "\n")
                        Text(combined)
                            .font(.system(size: 13, design: .monospaced))
                            .lineSpacing(1)
                            .textSelection(.enabled)
                            .onTapGesture {
                                UIPasteboard.general.string = combined
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }
                    } else {
                        ForEach(Array(logger.logs.enumerated()), id: \.offset) { _, log in
                            Text(log)
                                .font(.system(size: 13, design: .monospaced))
                                .lineSpacing(1)
                                .textSelection(.enabled)
                                .onTapGesture {
                                    UIPasteboard.general.string = log
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                }
                        }
                    }
                }
                .frame(height: 250)
                
                Button("Copy All") {
                    UIPasteboard.general.string = logger.logs.joined(separator: "\n\n")
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
                
                Button("Clear") {
                    logger.clear()
                }
                .foregroundColor(.red)
            } header: {
                HeaderLabel(text: "Logs", icon: "terminal")
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(laramgr())
}