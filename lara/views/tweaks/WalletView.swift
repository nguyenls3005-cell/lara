//
//  WalletView.swift
//  lara
//

import SwiftUI
import UniformTypeIdentifiers

struct WalletView: View {
    @State private var selectedImage: UIImage?
    @State private var showImagePicker = false
    @State private var isApplying = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    
    // Đường dẫn cache Passbook (chuẩn AirCard-iOS)
    private let passbookCacheDir = "/var/mobile/Library/Passes/Cards"
    
    // File pairing đã import
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
        .sheet(isPresented: $showImagePicker) { ImagePicker(image: $selectedImage) }
        .alert("Result", isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: { Text(alertMessage) }
    }

    private func applyWalletSkin() {
        guard let image = selectedImage, let pngData = image.pngData() else {
            alertMessage = "Invalid image."; showAlert = true; return
        }
        isApplying = true
        
        // Gọi AirliftFFI
        let success = pngData.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> Bool in
            guard let baseAddress = buffer.baseAddress else { return false }
            
            // Tên hàm C từ AirliftFFI (thường là al_write_file hoặc airlift_write_file)
            // Nếu build báo lỗi "cannot find al_write_file", bạn cần mở file airlift.h trong thư mục Frameworks ra xem tên chính xác.
            return al_write_file(passbookCacheDir, "cardBackgroundCombined@3x.png", baseAddress, Int32(pngData.count), pairingFilePath)
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