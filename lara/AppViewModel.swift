//
//  AppViewModel.swift
//  lara
//

import Foundation
import SwiftUI
import Combine

// Định nghĩa các kiểu dữ liệu (nếu chưa có)
enum AirliftStatus {
    case idle
    case connectingTunnel
    case tunnelConnected
    case runningExploit
    case exploitSuccess
    case exploitFailed(String)
}

class AppViewModel: ObservableObject {
    static let shared = AppViewModel()
    
    @Published var status: AirliftStatus = .idle
    @Published var logs: [String] = []
    
    private var pairingPath: String {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("airlift_pairing.plist").path
    }
    
    private let targetHost = "10.7.0.1"
    private let targetDir = "/var/mobile/Library/Passes/Cards" // Thư mục test
    
    private var logCallback: @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?) -> Void = { ctx, msg in
        if let msg = msg {
            let line = String(cString: msg)
            DispatchQueue.main.async {
                AppViewModel.shared.logs.append(line)
                print("[Airlift] \(line)")
            }
        }
    }
    
    private init() {}
    
    /// Kích hoạt exploit Airlift. Trả về true nếu thành công.
    func runAirliftExploit() -> Bool {
        // 1. Cấu hình target host (BẮT BUỘC)
        _ = targetHost.withCString { al_set_target_host($0) }
        // Thiết lập danh sách host dự phòng (tùy chọn nhưng nên có)
        // let hosts = ["10.7.0.1", "127.0.0.1"]
        // hosts.withUnsafeBufferPointer { buffer in
        //     al_set_target_hosts(buffer.baseAddress, UInt(buffer.count))
        // }
        
        // 2. Kiểm tra pairing file
        guard FileManager.default.fileExists(atPath: pairingPath) else {
            status = .exploitFailed("Pairing file not found.")
            return false
        }
        
        // 3. Chạy exploit
        status = .runningExploit
        var outJson: UnsafeMutablePointer<CChar>? = nil
        var outError: UnsafeMutablePointer<CChar>? = nil
        
        let result = pairingPath.withCString { pairingC in
            targetDir.withCString { targetC in
                al_exploit_run(
                    pairingC,
                    targetC,
                    logCallback,
                    nil,
                    &outJson,
                    &outError
                )
            }
        }
        
        // 4. Xử lý kết quả
        if let error = outError {
            let msg = String(cString: error)
            al_string_free(error)
            status = .exploitFailed(msg)
            return false
        }
        
        if let json = outJson {
            let msg = String(cString: json)
            al_string_free(json)
            print("[Airlift] Result JSON: \(msg)")
        }
        
        if result == 0 {
            status = .exploitSuccess
            return true
        } else {
            status = .exploitFailed("Exploit returned non-zero code: \(result)")
            return false
        }
    }
    
    /// Ghi một thư mục vào target (dùng cho Wallet hoặc Passcode Theme)
    func writeDirectory(sourceDir: String, targetDir: String) -> Bool {
        // Đảm bảo target host đã được set
        _ = targetHost.withCString { al_set_target_host($0) }
        
        var outError: UnsafeMutablePointer<CChar>? = nil
        
        let result = pairingPath.withCString { pairingC in
            sourceDir.withCString { sourceC in
                targetDir.withCString { targetC in
                    al_exploit_write_dir(
                        pairingC,
                        sourceC,
                        targetC,
                        logCallback,
                        nil,
                        &outError
                    )
                }
            }
        }
        
        if let error = outError {
            print("[Airlift] write_dir error: \(String(cString: error))")
            al_string_free(error)
            return false
        }
        return result == 0
    }
}