//
//  TweaksView.swift
//  lara
//

import SwiftUI

struct TweaksView: View {
    @AppStorage("logsdisplaymode") private var selectedlogsdisplaymode: logsdisplaymode = .toolbar
    @ObservedObject var mgr: laramgr
    
    var body: some View {
        NavigationStack {
            List {
                Section(header: HeaderLabel(text: "SpringBoard", icon: "house")) {
                    NavigationLink("Liquid Glass", destination: LiquidGlassView())
                        .disabled(!mgr.vfsready)
                }
                
                // ĐÃ ĐỔI TÊN VÀ THÊM APPLE WALLET
                Section(header: HeaderLabel(text: "Lock Screen & Theme", icon: "lock")) {
                    NavigationLink("Passcode Theme", destination: PasscodeView(mgr: mgr))
                        .disabled(!mgr.vfsready)
                    
                    NavigationLink("Apple Wallet", destination: WalletView())
                        .disabled(!mgr.vfsready)
                }
                
                Section(header: HeaderLabel(text: "Apps", icon: "app")) {
                    NavigationLink("JIT Enabler", destination: JitView())
                        .disabled(!mgr.sbxready)
                }
                
                Section(header: HeaderLabel(text: "User Interface", icon: "eye")) {
                    NavigationLink("MobileGestalt", destination: GestaltView(mgr: mgr))
                        .disabled(!mgr.sbxready)
                }
                
                Section(header: HeaderLabel(text: "System", icon: "gear")) {
                    NavigationLink("Daemons", destination: DaemonsView())
                        .disabled(!mgr.dsready)
                }
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

// View Daemons
struct DaemonsView: View {
    let daemons = ["com.apple.SpringBoard", "com.apple.backboardd", "com.apple.runningboardd"]
    var body: some View {
        List(daemons, id: \.self) { daemon in
            Text(daemon)
        }.navigationTitle("Daemons")
    }
}