import Foundation
import UIKit

// MARK: - C FFI surface from AirliftFFI.xcframework
// (Symbols match rust-core/include/airlift.h)

@_silgen_name("al_log_init")
func al_log_init(_ cb: (@convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?) -> Void)?,
                 _ ctx: UnsafeMutableRawPointer?) -> Int32

@_silgen_name("al_pairing_run_host")
func al_pairing_run_host(_ bindAddr: UnsafePointer<CChar>?,
                         _ port: UInt16,
                         _ name: UnsafePointer<CChar>?,
                         _ model: UnsafePointer<CChar>?,
                         _ outPath: UnsafePointer<CChar>?,
                         _ hostAltIrkHex: UnsafePointer<CChar>?,
                         _ readyCb: (@convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?, UInt16, UnsafePointer<UnsafePointer<CChar>?>?, UnsafePointer<UnsafePointer<CChar>?>?, Int) -> Void)?,
                         _ pinCb: (@convention(c) (UnsafePointer<CChar>?, UnsafeMutableRawPointer?) -> Void)?,
                         _ ctx: UnsafeMutableRawPointer?,
                         _ out: UnsafeMutablePointer<ALPairResult>?) -> Int32

@_silgen_name("al_exploit_run")
func al_exploit_run(_ pairingPath: UnsafePointer<CChar>?,
                    _ target: UnsafePointer<CChar>?,
                    _ logCb: (@convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?) -> Void)?,
                    _ ctx: UnsafeMutableRawPointer?,
                    _ outJson: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?,
                    _ outError: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?) -> Int32

@_silgen_name("al_exploit_write_dir")
func al_exploit_write_dir(_ pairingPath: UnsafePointer<CChar>?,
                          _ sourceDir: UnsafePointer<CChar>?,
                          _ targetDir: UnsafePointer<CChar>?,
                          _ logCb: (@convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?) -> Void)?,
                          _ ctx: UnsafeMutableRawPointer?,
                          _ outError: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?) -> Int32

@_silgen_name("al_string_free")
func al_string_free(_ p: UnsafeMutablePointer<CChar>?)

// MARK: - Pairing result struct (matches C header)
struct ALPairResult {
    var error: UnsafeMutablePointer<CChar>?
    var deviceName: UnsafeMutablePointer<CChar>?
    var deviceModel: UnsafeMutablePointer<CChar>?
    var deviceUdid: UnsafeMutablePointer<CChar>?
    var pairingFilePath: UnsafeMutablePointer<CChar>?
    var hostAltIrkHex: UnsafeMutablePointer<CChar>?
}

// MARK: - Airlift bridge for Lara
final class AirliftBridge {
    static let shared = AirliftBridge()
    private(set) var isPaired = false
    private(set) var pairingPath: String?

    private let tunnelHost = "10.7.0.1" // LocalDevVPN loopback
    private let rsdPort: UInt16 = 49152

    // Call this once at app launch.
    func configureLogging() {
        al_log_init({ _, msg in
            guard let msg = msg else { return }
            print("[Airlift] \(String(cString: msg))")
        }, nil)
    }

    // Runs the RPPairing host. Blocks—call on a background thread.
    func pairDevice(name: String = "Lara", model: String = "iPhone16,2") throws {
        var out = ALPairResult()
        let rc = name.withCString { nameC in
            model.withCString { modelC in
                "airlift_pairing.plist".withCString { outPathC in
                    al_pairing_run_host(
                        "0.0.0.0", 0,
                        nameC, modelC, outPathC, nil,
                        { _, serviceId, port, txtKeys, txtVals, count in
                            // TODO: advertise serviceId over Bonjour (NetService)
                            // so the device can pair via Settings → Developer Mode.
                            print("[Airlift] Ready: service=\(serviceId.map { String(cString: $0) } ?? "?") port=\(port)")
                        },
                        { pin, _ in
                            print("[Airlift] PIN: \(pin.map { String(cString: $0) } ?? "?")")
                        },
                        nil, &out
                    )
                }
            }
        }

        defer {
            // Free any heap strings allocated by the Rust side.
            for ptr in [out.error, out.deviceName, out.deviceModel, out.deviceUdid,
                        out.pairingFilePath, out.hostAltIrkHex] {
                if let p = ptr { al_string_free(p) }
            }
        }

        guard rc == 0 else {
            throw AirliftError.pairingFailed(code: rc,
                message: out.error.map { String(cString: $0) } ?? "unknown")
        }

        isPaired = true
        pairingPath = out.pairingFilePath.map { String(cString: $0) }
        print("[Airlift] Paired: \(out.deviceName.map { String(cString: $0) } ?? "?")")
    }

    // Inject a directory using the airlift AirTraffic escape.
    // `targetDir` must be an absolute iOS path (e.g. "/var/mobile/Library/SpringBoard").
    func injectDirectory(sourceDir: URL, targetDir: String) throws {
        guard let pairingPath = pairingPath else {
            throw AirliftError.notPaired
        }

        var errPtr: UnsafeMutablePointer<CChar>?
        let rc = pairingPath.withCString { pairC in
            sourceDir.path.withCString { srcC in
                targetDir.withCString { tgtC in
                    al_exploit_write_dir(pairC, srcC, tgtC, nil, nil, &errPtr)
                }
            }
        }

        defer {
            if let e = errPtr { al_string_free(e) }
        }

        guard rc == 0 else {
            throw AirliftError.writeFailed(code: rc,
                message: errPtr.map { String(cString: $0) } ?? "unknown")
        }

        print("[Airlift] Injected \(sourceDir.lastPathComponent) → \(targetDir)")
    }

    // Run the canary exploit to verify write access to a target directory.
    func verifyWriteAccess(to targetDir: String) throws -> Bool {
        guard let pairingPath = pairingPath else {
            throw AirliftError.notPaired
        }

        var jsonPtr: UnsafeMutablePointer<CChar>?
        var errPtr: UnsafeMutablePointer<CChar>?

        let rc = pairingPath.withCString { pairC in
            targetDir.withCString { tgtC in
                al_exploit_run(pairC, tgtC, nil, nil, &jsonPtr, &errPtr)
            }
        }

        defer {
            if let j = jsonPtr { al_string_free(j) }
            if let e = errPtr { al_string_free(e) }
        }

        if rc != 0 {
            let msg = errPtr.map { String(cString: $0) } ?? "canary write failed"
            throw AirliftError.writeFailed(code: rc, message: msg)
        }

        print("[Airlift] Canary confirmed: \(jsonPtr.map { String(cString: $0) } ?? "")")
        return true
    }
}

enum AirliftError: LocalizedError {
    case notPaired
    case pairingFailed(code: Int32, message: String)
    case writeFailed(code: Int32, message: String)

    var errorDescription: String? {
        switch self {
        case .notPaired: return "Airlift: device not paired yet."
        case .pairingFailed(let c, let m): return "Airlift pairing failed (\(c)): \(m)"
        case .writeFailed(let c, let m): return "Airlift write failed (\(c)): \(m)"
        }
    }
}