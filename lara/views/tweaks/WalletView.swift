//
//  WalletView.swift
//  lara
//

import SwiftUI
import UniformTypeIdentifiers

// Định nghĩa kiểu callback log
typealias ALLogCallback = @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?) -> Void

struct WalletView: View {
    @State private var selectedImage: UIImage?
    @State private var showImagePicker = false
    @State private var isApplying = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    
    // Đường dẫn cache Passbook (từ AirCard-iOS)
    private let passbookCacheDir = "/var/mobile/Library/Passes/Cards"
    
    // File pairing đã lưu trong Documents
    private var pairingFilePath: String {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("airlift_pairing.plist").path
    }

    var body: some View {
        List {
            Section(header: Text("Card Artwork")) {
                if let image = selectedImage {
                    Image(uiImage: image)
                        .resizable().scaledToFit()
                        .frame(maxHeight: 200).cornerRadius(12)
                } else {
                    Text("No image selected").foregroundColor(.secondary)
                }
                Button("Select Image") { showImagePicker = true }
            }

            Section {
                Button(action: applyWalletSkin) {
                    HStack {
                        Spacer()
                        if isApplying { ProgressView().padding(.trailing, 8) }
                        Text("Apply to Wallet").bold()
                        Spacer()
                    }
                }
                .disabled(selectedImage == nil || isApplying)
            } footer: {
                Text("This will overwrite card background caches. Airlift must be available.")
            }
        }
        .navigationTitle("Apple Wallet")
        .sheet(isPresented: $showImagePicker) { WalletImagePicker(image: $selectedImage) }
        .alert("Result", isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: { Text(alertMessage) }
    }

    private func applyWalletSkin() {
        guard let image = selectedImage, let pngData = image.pngData() else {
            alertMessage = "Invalid image."
            showAlert = true
            return
        }
        
        // Kiểm tra pairing file
        guard FileManager.default.fileExists(atPath: pairingFilePath) else {
            alertMessage = "Pairing file not found. Please import it in the Home tab first."
            showAlert = true
            return
        }
        
        isApplying = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            // 1. Tạo thư mục tạm trong Documents
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let tempDir = docs.appendingPathComponent("airlift_wallet_temp", isDirectory: true)
            
            do {
                // Xóa thư mục cũ nếu tồn tại
                if FileManager.default.fileExists(atPath: tempDir.path) {
                    try FileManager.default.removeItem(at: tempDir)
                }
                try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                
                // 2. Ghi ảnh thành các file
                // Passbook thường cần @3x, @2x và có thể là .pdf cho thẻ transit.
                // Chúng ta sẽ tạo @3x và @2x từ ảnh người dùng chọn.
                let image3x = tempDir.appendingPathComponent("cardBackgroundCombined@3x.png")
                let image2x = tempDir.appendingPathComponent("cardBackgroundCombined@2x.png")
                
                try pngData.write(to: image3x)
                
                // Tạo ảnh 2x từ ảnh gốc (nếu cần)
                if let uiImage = UIImage(data: pngData) {
                    let size2x = CGSize(width: uiImage.size.width * 0.66, height: uiImage.size.height * 0.66)
                    UIGraphicsBeginImageContextWithOptions(size2x, false, 1.0)
                    uiImage.draw(in: CGRect(origin: .zero, size: size2x))
                    if let resized = UIGraphicsGetImageFromCurrentImageContext(), let data2x = resized.pngData() {
                        try data2x.write(to: image2x)
                    }
                    UIGraphicsEndImageContext()
                }
                
                // 3. Gọi hàm C để ghi thư mục vào cache Passbook
                let success = writeDirWithAirlift(
                    pairingPath: self.pairingFilePath,
                    sourceDir: tempDir.path,
                    targetDir: self.passbookCacheDir
                )
                
                // 4. Dọn dẹp
                try? FileManager.default.removeItem(at: tempDir)
                
                DispatchQueue.main.async {
                    self.isApplying = false
                    if success {
                        self.alertMessage = "Wallet skin applied successfully! Open Wallet to see changes."
                    } else {
                        self.alertMessage = "Failed to apply skin. Check pairing + tunnel status, and ensure Airlift can write to Passbook."
                    }
                    self.showAlert = true
                }
                
            } catch {
                DispatchQueue.main.async {
                    self.isApplying = false
                    self.alertMessage = "Error preparing files: \(error.localizedDescription)"
                    self.showAlert = true
                }
            }
        }
    }
    
    /// Gọi hàm C `al_exploit_write_dir` từ AirliftFFI
    private func writeDirWithAirlift(pairingPath: String, sourceDir: String, targetDir: String) -> Bool {
        var outError: UnsafeMutablePointer<CChar>? = nil
        
        // Callback nhận log từ thư viện Rust
        let logCallback: ALLogCallback = { ctx, msg in
            if let msg = msg {
                print("[Airlift] \(String(cString: msg))")
            }
        }
        
        let result = al_exploit_write_dir(
            pairingPath,
            sourceDir,
            targetDir,
            logCallback,
            nil,
            &outError
        )
        
        if let error = outError {
            print("[Airlift] write_dir error: \(String(cString: error))")
            al_string_free(error)
            return false
        }
        
        return result == 0
    }
}

// Image Picker đơn giản
struct WalletImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    
    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: WalletImagePicker
        init(_ parent: WalletImagePicker) { self.parent = parent }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.image = image
            }
            picker.dismiss(animated: true)
        }
    }
}