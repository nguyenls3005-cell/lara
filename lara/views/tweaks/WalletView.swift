import SwiftUI
import UniformTypeIdentifiers
import Darwin

// Biến toàn cục lưu con trỏ hàm (nếu tìm thấy)
private let alWriteFileFunc: (@convention(c) (UnsafePointer<CChar>, UnsafeRawPointer, Int, UnsafePointer<CChar>) -> Int32)? = {
    // Thử tìm hàm trong các tên có thể có
    let candidates = [
        "al_write_file",
        "airlift_write_file", 
        "write_file",
        "airlift_device_write_file",
        "al_device_write_file"
    ]
    for name in candidates {
        if let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) {
            print("[Airlift] Found symbol: \(name)")
            return unsafeBitCast(sym, to: (@convention(c) (UnsafePointer<CChar>, UnsafeRawPointer, Int, UnsafePointer<CChar>) -> Int32).self)
        }
    }
    print("[Airlift] WARNING: No write function found in library!")
    return nil
}()

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
                    Image(uiImage: image).resizable().scaledToFit()
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
            alertMessage = "Invalid image."; showAlert = true; return
        }
        
        guard let writeFunc = alWriteFileFunc else {
            alertMessage = "Airlift library missing write function. Check airlift.h for the correct symbol name."
            showAlert = true
            return
        }
        
        isApplying = true
        
        let success = pngData.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> Bool in
            guard let baseAddress = buffer.baseAddress else { return false }
            return passbookCacheDir.withCString { cacheDirC in
                "cardBackgroundCombined@3x.png".withCString { fileNameC in
                    pairingFilePath.withCString { pairingPathC in
                        // Gọi hàm với các tham số tùy biến
                        // (Tùy theo signature thực tế trong airlift.h có thể khác)
                        let result = writeFunc(cacheDirC, baseAddress, pngData.count, pairingPathC)
                        return result == 0
                    }
                }
            }
        }
        
        DispatchQueue.main.async {
            isApplying = false
            if success {
                alertMessage = "Wallet skin applied successfully!"
            } else {
                alertMessage = "Failed to apply skin. Check Pairing + Tunnel status."
            }
            showAlert = true
        }
    }
}

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
            if let image = info[.originalImage] as? UIImage { parent.selectedImageInternal = image }
            picker.dismiss(animated: true)
        }
    }
}

extension WalletImagePicker.Coordinator {
    var selectedImageInternal: UIImage? {
        get { return nil }
        set { }
    }
}