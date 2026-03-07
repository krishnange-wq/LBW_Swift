import SwiftUI
import AVKit

struct ContentView: View {
    @State private var videoURL: URL?
    @State private var showingPicker = false
    @State private var player = AVPlayer()
    @State private var nativeSize: CGSize = CGSize(width: 1, height: 1)

    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            if let url = videoURL {
                // Pass the actual local URL so we can upload the file later
                VideoAnalysisView(player: player, nativeSize: nativeSize, showingPicker: $showingPicker, videoURL: url)
            } else {
                VStack(spacing: 30) {
                    Image(systemName: "video.circle.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.blue)
                    
                    VStack(spacing: 12) {
                        Text("Click corners in this order:")
                            .font(.headline)
                            .foregroundColor(.gray)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            HStack { Circle().fill(Color.red).frame(width: 8, height: 8); Text("1. Top Left (Far Crease)") }
                            HStack { Circle().fill(Color.red).frame(width: 8, height: 8); Text("2. Top Right (Far Crease)") }
                            HStack { Circle().fill(Color.red).frame(width: 8, height: 8); Text("3. Bottom Right (Near Crease)") }
                            HStack { Circle().fill(Color.yellow).frame(width: 8, height: 8); Text("4. Bottom Left (Near Crease)") }
                        }
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundColor(.white)
                    }
                    .padding()
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(15)

                    Button(action: { self.showingPicker = true }) {
                        Text("Select .mov Video")
                            .font(Font.title2.bold())
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(15)
                    }
                }
            }
        }
        .sheet(isPresented: $showingPicker) {
            CricketVideoPicker(videoURL: $videoURL)
                .onDisappear { if let url = videoURL { setupVideo(url: url) } }
        }
    }

    func setupVideo(url: URL) {
        let asset = AVAsset(url: url)
        if let track = asset.tracks(withMediaType: .video).first {
            let size = track.naturalSize.applying(track.preferredTransform)
            self.nativeSize = CGSize(width: abs(size.width), height: abs(size.height))
            self.player = AVPlayer(url: url)
            self.player.play()
        }
    }
}

struct VideoAnalysisView: View {
    let player: AVPlayer
    let nativeSize: CGSize
    @Binding var showingPicker: Bool
    let videoURL: URL // Changed from videoName to videoURL
    
    @State private var points: [CGPoint] = []
    @State private var currentScale: CGFloat = 1.0
    @GestureState private var pinchScale: CGFloat = 1.0
    
    @State private var rawBackendData: [String: Any] = [:]
    @State private var showingResult = false
    @State private var isAnalyzing = false
    
    // Replace with your Mac's IP Address
    let apiURL = "http://127.0.0.1:5000/analyze"
    
    private let precisionX: CGFloat = 0.986
    private let precisionY: CGFloat = 1.018

    var body: some View {
        GeometryReader { geo in
            let videoRect = self.calculateVideoRect(containerSize: geo.size, videoSize: self.nativeSize)
            let totalScale = self.currentScale * self.pinchScale
            
            ZStack {
                ZStack {
                    VideoPlayer(player: self.player)
                        .disabled(true)
                        .frame(width: videoRect.width, height: videoRect.height)

                    if let pathData = rawBackendData["path_data"] as? [String: Any] {
                        if let tracked = pathData["tracked_points"] as? [[CGFloat]] {
                            BallPathShape(points: tracked.map { CGPoint(x: $0[0], y: $0[1]) }, videoRect: videoRect, nativeSize: nativeSize, pX: precisionX, pY: precisionY)
                                .stroke(Color.yellow, lineWidth: 3)
                        }
                        if let future = pathData["future_points"] as? [[CGFloat]] {
                            BallPathShape(points: future.map { CGPoint(x: $0[0], y: $0[1]) }, videoRect: videoRect, nativeSize: nativeSize, pX: precisionX, pY: precisionY)
                                .stroke(Color.red, style: StrokeStyle(lineWidth: 3, dash: [5]))
                        }
                    }

                    ZStack(alignment: .topLeading) {
                        if points.count == 4 {
                            PitchShape(points: points.map { self.getDrawPoint(for: $0, in: videoRect) })
                                .fill(Color.blue.opacity(0.3))
                        }
                        Color.white.opacity(0.001)
                            .gesture(DragGesture(minimumDistance: 0).onEnded { self.handleTap(location: $0.location, rect: videoRect) })
                        
                        ForEach(0..<points.count, id: \.self) { i in
                            Circle().stroke(Color.white, lineWidth: 2)
                                .background(Circle().fill(i == self.points.count - 1 ? Color.yellow : Color.red))
                                .frame(width: 20, height: 20)
                                .position(self.getDrawPoint(for: self.points[i], in: videoRect))
                        }
                    }
                    .frame(width: videoRect.width, height: videoRect.height)
                }
                .frame(width: videoRect.width, height: videoRect.height)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
                .scaleEffect(totalScale)
                
                VStack {
                    Spacer()
                    if showingResult {
                        VStack(spacing: 12) {
                            Text(rawBackendData["final_DRS_verdict"] as? String ?? "N/A")
                                .font(.system(size: 36, weight: .black, design: .rounded))
                                .foregroundColor(.white)
                            
                            if let stages = rawBackendData["stages"] as? [String: Any] {
                                HStack(spacing: 20) {
                                    VerdictCapsule(label: "PITCH", val: (stages["pitching"] as? [String: Any])?["verdict"] as? String ?? "-")
                                    VerdictCapsule(label: "IMPACT", val: (stages["impact"] as? [String: Any])?["verdict"] as? String ?? "-")
                                    VerdictCapsule(label: "WICKETS", val: (stages["wickets"] as? [String: Any])?["verdict"] as? String ?? "-")
                                }
                            }
                        }
                        .padding(25)
                        .background(BlurView(style: .systemUltraThinMaterialDark).cornerRadius(20))
                        .padding(.bottom, 60)
                        .onTapGesture { withAnimation(.easeOut) { self.showingResult = false } }
                        .transition(AnyTransition.move(edge: .bottom).combined(with: .opacity))
                    }
                }

                VStack {
                    HStack {
                        Button("Reset") {
                            self.points = []; self.showingResult = false; self.currentScale = 1.0; self.rawBackendData = [:]; self.isAnalyzing = false
                        }
                        .padding().background(Color.red).foregroundColor(.white).cornerRadius(10)
                        
                        Spacer()
                        
                        if points.count == 4 {
                            Button(action: { self.uploadToBackend() }) {
                                Text(isAnalyzing ? "..." : "SEND TO PYTHON")
                                    .font(.system(size: 12, weight: .bold))
                                    .padding().background(isAnalyzing ? Color.gray : Color.green)
                                    .foregroundColor(.white).cornerRadius(10)
                            }
                            .disabled(isAnalyzing)
                        }
                        
                        Spacer()
                        
                        Button("New Video") {
                            self.points = []; self.rawBackendData = [:]; self.isAnalyzing = false; self.showingPicker = true
                        }
                        .padding().background(Color.blue).foregroundColor(.white).cornerRadius(10)
                    }
                    .padding(.top, 44).padding(.horizontal)
                    Spacer()
                }
            }
            .gesture(MagnificationGesture().updating($pinchScale) { val, state, _ in state = val }
                .onEnded { val in self.currentScale = min(max(self.currentScale * val, 1.0), 5.0) })
        }
        .edgesIgnoringSafeArea(.all)
    }

    // --- REPLACED: Web Server Upload Logic ---
    func uploadToBackend() {
        self.isAnalyzing = true
        self.showingResult = false
        
        // 1. Prepare Coordinates
        let coordData = points.map { ["x": Int($0.x), "y": Int($0.y)] }
        guard let jsonData = try? JSONSerialization.data(withJSONObject: coordData),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return }

        // 2. Prepare Multipart Request
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: URL(string: apiURL)!)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        
        // Add Coordinates part
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"coordinates\"\r\n\r\n\(jsonString)\r\n".data(using: .utf8)!)

        // Add Video part
        let filename = videoURL.lastPathComponent.lowercased().replacingOccurrences(of: ".mov", with: "") + ".mov"
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"video\"; filename=\"\(filename)\"\r\nContent-Type: video/quicktime\r\n\r\n".data(using: .utf8)!)
        if let videoData = try? Data(contentsOf: videoURL) {
            body.append(videoData)
        }
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        // 3. Send and Receive Response
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.isAnalyzing = false
                if let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    self.rawBackendData = json
                    withAnimation(.spring()) { self.showingResult = true }
                } else {
                    print("Upload failed: \(error?.localizedDescription ?? "Unknown error")")
                }
            }
        }.resume()
    }

    func handleTap(location: CGPoint, rect: CGRect) {
        if isAnalyzing { return }
        let rX = (nativeSize.width / rect.width) * precisionX
        let rY = (nativeSize.height / rect.height) * precisionY
        let offX = (nativeSize.width * (1 - precisionX)) / 2
        let offY = (nativeSize.height * (1 - precisionY)) / 2
        let mapped = CGPoint(x: (location.x * rX) + offX, y: (location.y * rY) + offY)
        if points.count < 4 { points.append(mapped) } else { points = [mapped] }
    }

    func getDrawPoint(for point: CGPoint, in rect: CGRect) -> CGPoint {
        let rX = (nativeSize.width / rect.width) * precisionX
        let rY = (nativeSize.height / rect.height) * precisionY
        let offX = (nativeSize.width * (1 - precisionX)) / 2
        let offY = (nativeSize.height * (1 - precisionY)) / 2
        return CGPoint(x: (point.x - offX) / rX, y: (point.y - offY) / rY)
    }

    func calculateVideoRect(containerSize: CGSize, videoSize: CGSize) -> CGRect {
        let ratio = videoSize.width / videoSize.height
        let renderWidth = containerSize.width
        let renderHeight = renderWidth / ratio
        return CGRect(x: 0, y: (containerSize.height - renderHeight) / 2, width: renderWidth, height: renderHeight)
    }
}

// --- KEEPING YOUR SHAPES & HELPERS INTACT ---
struct BallPathShape: Shape {
    var points: [CGPoint]; var videoRect: CGRect; var nativeSize: CGSize; var pX: CGFloat; var pY: CGFloat
    func path(in rect: CGRect) -> Path {
        var path = Path(); guard points.count > 1 else { return path }
        let rX = (nativeSize.width / videoRect.width) * pX
        let rY = (nativeSize.height / videoRect.height) * pY
        let offX = (nativeSize.width * (1 - pX)) / 2
        let offY = (nativeSize.height * (1 - pY)) / 2
        let mapped = points.map { CGPoint(x: ($0.x - offX) / rX, y: ($0.y - offY) / rY) }
        path.move(to: mapped[0])
        for i in 1..<mapped.count { path.addLine(to: mapped[i]) }
        return path
    }
}

struct VerdictCapsule: View {
    let label: String; let val: String
    var body: some View {
        VStack(spacing: 4) {
            Text(label).font(.system(size: 10, weight: .bold)).foregroundColor(.gray)
            Text(val).font(.system(size: 14, weight: .bold)).foregroundColor(.white).lineLimit(1)
        }
    }
}

struct BlurView: UIViewRepresentable {
    var style: UIBlurEffect.Style
    func makeUIView(context: Context) -> UIVisualEffectView { UIVisualEffectView(effect: UIBlurEffect(style: style)) }
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {}
}

struct PitchShape: Shape {
    var points: [CGPoint]
    func path(in rect: CGRect) -> Path {
        var path = Path(); guard points.count == 4 else { return path }
        path.move(to: points[0]); path.addLine(to: points[1]); path.addLine(to: points[2]); path.addLine(to: points[3]); path.closeSubpath()
        return path
    }
}
