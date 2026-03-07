import SwiftUI
import PhotosUI

struct CricketVideoPicker: UIViewControllerRepresentable {
    @Binding var videoURL: URL?

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .videos // Only show videos
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: CricketVideoPicker
        init(_ parent: CricketVideoPicker) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let provider = results.first?.itemProvider else { return }

            // Using the specific identifier for .mov files
            provider.loadFileRepresentation(forTypeIdentifier: "com.apple.quicktime-movie") { url, _ in
                if let url = url {
                    // Ensure the temporary file uses a lowercase .mov extension
                    let fileName = url.lastPathComponent.lowercased()
                    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
                    try? FileManager.default.removeItem(at: tempURL)
                    try? FileManager.default.copyItem(at: url, to: tempURL)
                    
                    DispatchQueue.main.async {
                        self.parent.videoURL = tempURL
                    }
                }
            }
        }
    }
}
