//
//  WalletView.swift
//  lara
//

import SwiftUI
import UniformTypeIdentifiers

// Khai báo trực tiếp hàm C từ thư viện AirliftFFI (Bỏ qua Bridging Header)
@_silgen_name("al_write_file")
func al_write_file(
    _ device_path: UnsafePointer<CChar>,
    _ data: UnsafeRawPointer,
    _ data_len: Int,
    _ pairing_file_path: UnsafePointer<CChar>
) -> Int32

struct WalletView: View {
    @State private var selectedImage: UIImage?
    @State private var showImagePicker = false
    @State private var isApplying = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    
    private let passbookCacheDir = "/var/mobile/Library/Passes/Cards"
    
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
        .sheet(isPresented: $showImagePicker) { 
            // Đã đổi tên thành WalletImagePicker để không trùng với Lara
            WalletImagePicker(image: $selectedImage) 
        }
        .alert("Result", isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: { Text(alertMessage) }
    }

    private func applyWalletSkin() {
        guard let image = selectedImage, let pngData = image.pngData() else {
            alertMessage = "Invalid image."; showAlert = true; return
        }
        isApplying = true
        
        // Gọi trực tiếp hàm C qua @_silgen_name
        let success = pngData.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> Bool in
            guard let baseAddress = buffer.baseAddress else { return false }
            
            // Chuyển đổi String sang CChar (UTF8 C-string)
            return passbookCacheDir.withCString { cacheDirC in
                "cardBackgroundCombined@3x.png".withCString { fileNameC in
                    pairingFilePath.withCString { pairingPathC in
                        
                        let result = al_write_file(cacheDirC, baseAddress, pngData.count, pairingPathC)
                        return result == 0 // Thường 0 là thành công trong Rust FFI
                    }
                }
            }
        }
        
        DispatchQueue.main.async {
            isApplying = false
            if success {
                alertMessage = "Wallet skin applied successfully. Open Wallet to see changes."
            } else {
                alertMessage = "Failed to apply skin. Make sure Airlift is running and Pairing File is valid."
            }
            showAlert = true
        }
    }
}

// Đổi tên ImagePicker để tránh xung đột với Lara
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