//
//  GestaltView.swift
//  lara
//

import SwiftUI
import Foundation
import Darwin

struct GestaltView: View {
    @AppStorage("gestaltwarn") private var gestaltwarn: Bool = true
    @AppStorage("mgDeviceName") private var mgDeviceName: String = ""
    
    let mgr: laramgr
    @StateObject private var store = GestaltStore.shared
    @State private var showgestaltwarn: Bool = false
    @State private var mgSubtype: Int = 0
    @State private var mgOriginalSubtype: Int = 0
    @State private var mgEnableDeviceName: Bool = false
    @State private var mgProductType: String = ""
    @State private var isApplying = false
    @State private var alertMsg = ""
    @State private var showAlert = false
    
    var body: some View {
        Form {
            Section(header: Text("Device Subtype")) {
                Picker("Preset", selection: $mgSubtype) {
                    Text("Default").tag(0)
                    Text("iPhone 14 Pro").tag(1)
                    Text("iPhone 14 Pro Max").tag(3)
                    Text("iPhone 15 Pro Max").tag(4)
                    Text("iPhone 16 Pro").tag(5)
                    Text("iPhone 16 Pro Max").tag(6)
                    Text("iPhone Air").tag(7)
                }
                .onChange(of: mgSubtype) { _ in applyDynamicIsland() }
                
                Toggle("Custom Model Name", isOn: $mgEnableDeviceName)
                if mgEnableDeviceName {
                    TextField("Model Name", text: $mgDeviceName)
                        .onChange(of: mgDeviceName) { _ in if mgEnableDeviceName && !mgDeviceName.isEmpty { applyModelName() } }
                }
            }
            
            Section(header: Text("Features")) {
                Toggle("Dynamic Island", isOn: store.mgKeyBinding([MGKey.island]))
                Toggle("Always On Display", isOn: store.mgKeyBinding([MGKey.AOD, MGKey.AOTime]))
                Toggle("AOD Vibrancy", isOn: store.mgKeyBinding([MGKey.AODVibrancy]))
                Toggle("Boot Chime", isOn: store.mgKeyBinding([MGKey.bootChime]))
                Toggle("Charge Limit (80%)", isOn: store.mgKeyBinding([MGKey.chargeLim]))
            }
            
            Section(header: Text("Eligibility")) {
                Toggle("Apple Intelligence", isOn: store.mgKeyBinding([MGKey.appIntell]))
                Toggle("Security Research Device", isOn: store.mgKeyBinding([MGKey.srd]))
                Toggle("Disable Region Restrictions", isOn: store.mgRegionRestrictionsBinding())
            }
            
            Section(header: Text("iPadOS Features")) {
                Toggle("Apple Pencil", isOn: store.mgKeyBinding([MGKey.appPencil]))
                if UIDevice.current.userInterfaceIdiom == .pad {
                    Toggle("Stage Manager", isOn: store.mgKeyBinding([MGKey.stageMgr]))
                }
                Toggle("Become iPadOS", isOn: store.mgTrollPadBinding())
            }
            
            Section(header: Text("Internal")) {
                Toggle("Internal Build", isOn: store.mgKeyBinding([MGKey.intBuild]))
                Toggle("Internal Install", isOn: store.mgKeyBinding([MGKey.intInstall]))
            }
            
            Section {
                Button(action: applyGestalt) {
                    HStack {
                        Spacer()
                        if isApplying { ProgressView().padding(.trailing, 8) }
                        Text("Apply Tweaks").bold()
                        Spacer()
                    }
                }
                .disabled(isApplying || !mgr.sbxready)
            } footer: {
                Text("Requires Bad_query. Will auto-rollback if write fails.")
            }
        }
        .navigationTitle("MobileGestalt")
        .onAppear { loadGestalt() }
        .alert("Notice", isPresented: $showAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMsg)
        }
    }
    
    private func loadGestalt() {
        do {
            let data = try Data(contentsOf: MGURL.fsGestaltURL)
            var format = PropertyListSerialization.PropertyListFormat.binary
            if let dict = try PropertyListSerialization.propertyList(from: data, options: [.mutableContainersAndLeaves], format: &format) as? NSMutableDictionary {
                store.mgCurrentDict = dict
                
                // Load lại tên máy hiện tại để không bị ghi đè rỗng
                if let cacheExtra = dict["CacheExtra"] as? [String: Any],
                   let currentProdType = cacheExtra[MGKey.prodType] as? String {
                    mgProductType = currentProdType
                }
            }
        } catch {
            alertMsg = "Failed to load: \(error.localizedDescription)"
            showAlert = true
        }
    }
    
    private func applyGestalt() {
        isApplying = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            do {
                if let cacheExtra = store.mgCurrentDict["CacheExtra"] as? NSMutableDictionary {
                    // Chỉ ghi đè nếu có giá trị (tránh ghi chuỗi rỗng làm hỏng máy)
                    if !mgProductType.isEmpty {
                        cacheExtra[MGKey.prodType] = mgProductType
                    }
                }
                
                // Serialize plist
                let data = try PropertyListSerialization.data(fromPropertyList: store.mgCurrentDict, format: .binary, options: 0)
                
                // Lấy quyền bad_query
                var pathC = Array(MGURL.fsGestaltURL.path.utf8CString)
                let handle = bad_query(&pathC, false, nil, false)
                guard handle > 0 else { throw "bad_query failed" }
                defer { bad_query_release(handle) }
                
                // Ghi file an toàn (Erosion's writeFileAtomically)
                let result = writeFileAtomically(data, to: MGURL.fsGestaltURL)
                if !result.0 { throw result.1 }
                
                self.isApplying = false
                
                // Tự động load lại UI sau khi ghi
                self.loadGestalt()
                
                self.alertMsg = "Applied successfully! Respring required."
                self.showAlert = true
            } catch {
                self.isApplying = false
                self.alertMsg = "Failed: \(error)"
                self.showAlert = true
            }
        }
    }
    
    // ĐÃ THÊM LOGIC: Map Subtype chuẩn cho từng dòng máy
    private func applyDynamicIsland() {
        guard let cacheExtra = store.mgCurrentDict["CacheExtra"] as? NSMutableDictionary else { return }
        
        if mgSubtype == 0 {
            cacheExtra.removeObject(forKey: MGKey.artwork)
        } else {
            // Map tag ID sang giá trị thực tế của iOS (dựa theo chuẩn của các tool khác)
            let subtypeValues: [Int: String] = [
                1: "2436", // 14 Pro
                3: "2796", // 14 Pro Max
                4: "2796", // 15 Pro Max
                5: "2556", // 16 Pro
                6: "2868", // 16 Pro Max
                7: "2556"  // Air (tạm dùng hệ số của 16 Pro)
            ]
            if let val = subtypeValues[mgSubtype] {
                cacheExtra[MGKey.artwork] = val
            }
        }
    }
    
    // ĐÃ THÊM LOGIC: Lưu tên máy do mày nhập vào dict
    private func applyModelName() {
        guard let cacheExtra = store.mgCurrentDict["CacheExtra"] as? NSMutableDictionary else { return }
        if mgDeviceName.isEmpty {
            cacheExtra.removeObject(forKey: MGKey.prodType)
        } else {
            cacheExtra[MGKey.prodType] = mgDeviceName
        }
    }
}