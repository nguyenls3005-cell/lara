// lara/lara/classes/AirliftBridge.swift
import Foundation

final class AirliftBridge {
    static let shared = AirliftBridge()
    private(set) var isPaired = false
    private(set) var pairingPath: String?

    private let tunnelHost = "10.7.0.1"
    private let rsdPort: UInt16 = 49152

    func configureLogging() {
        al_log_init({ _, msg in
            guard let msg = msg else { return }
            print("[Airlift] \(String(cString: msg))")
        }, nil)
    }

    func pairDevice(name: String = "Lara", model: String = "iPhone16,2") throws {
        var out = ALPairResult()
        let rc = name.withCString { nameC in
            model.withCString { modelC in
                "airlift_pairing.plist".withCString { outPathC in
                    al_pairing_run_host(
                        "0.0.0.0", 0,
                        nameC, modelC, outPathC, nil,
                        { _, serviceId, port, _, _, _ in
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
    }

    func verifyWriteAccess(to targetDir: String) throws {
        guard let pairingPath else { throw AirliftError.notPaired }
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

        guard rc == 0 else {
            throw AirliftError.writeFailed(code: rc,
                message: errPtr.map { String(cString: $0) } ?? "unknown")
        }
    }

    func injectDirectory(sourceDir: URL, targetDir: String) throws {
        guard let pairingPath else { throw AirliftError.notPaired }
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
    }
}

enum AirliftError: LocalizedError {
    case notPaired
    case pairingFailed(code: Int32, message: String)
    case writeFailed(code: Int32, message: String)

    var errorDescription: String? {
        switch self {
        case .notPaired: return "Airlift: device not paired."
        case .pairingFailed(let c, let m): return "Airlift pairing failed (\(c)): \(m)"
        case .writeFailed(let c, let m): return "Airlift write failed (\(c)): \(m)"
        }
    }
}