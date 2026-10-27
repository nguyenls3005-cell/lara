//
//  TweaksView.swift
//  lara
//
//  Created by lunginspector on 5/3/26.
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
                
                Section(header: HeaderLabel(text: "Lock Screen", icon: "lock")) {
                    NavigationLink("Passcode Theme", destination: PasscodeView(mgr: mgr))
                        .disabled(!mgr.sbxready)
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
                    NavigationLink("Daemons", destination: OTAView(mgr: mgr)) 
                    // ^ Lưu ý: Tao đổi tên hiển thị thành "Daemons". 
                    // Nếu mày đã tạo file giao diện mới (vd: DaemonsView.swift), hãy đổi chữ OTAView thành DaemonsView.
                }
                
                // Đã xóa toàn bộ Section "Broken" (DarkBoard)
                // Đã xóa "Extra Tools"
            }
            .disabled(!mgr.dsready)
            .navigationTitle("Tweaks")
            .toolbar {
                if selectedlogsdisplaymode == .toolbar {
                    Button(action: {
                        mgr.showLogs.toggle()
                    }) {
                        Image(systemName: "terminal")
                    }
                }
            }
        }
    }
}