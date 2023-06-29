//
//  ContentView.swift
//  tt
//
//  Created by 이태웅 on 2023/06/27.
//

import SwiftUI
import RealityKit
import ARKit

struct ContentView: View {
    @StateObject private var arViewModel = ARViewModel()

    var body: some View {
        ZStack {
            ARViewContainer(arViewModel: arViewModel)
            
            VerticalProgressBar(value: min(max(Float(arViewModel.distance / 0.1), 0), 1))
                .frame(width: 12, height: 200)
                .position(x: UIScreen.main.bounds.width - 50, y: UIScreen.main.bounds.height / 2)
            
            VStack {
                Spacer()
                Button {
                    arViewModel.takeSnapshotAndPlaceMarker()
                    if let depthMapImage = arViewModel.snapshotDepthMapImage {
                        saveToGallery(image: depthMapImage)
                    }
                } label: {
                    Circle()
                        .stroke(arViewModel.isButtonDisabled ? Color.gray : Color.white, lineWidth: 2.5)
                        .frame(width: 60, height: 60)
                        .overlay(
                            AnyView(
                                Circle()
                                    .foregroundColor(arViewModel.isButtonDisabled ? Color.gray : Color.white)
                                    .frame(width: 50, height: 50)
                            )
                        )
                }.disabled(arViewModel.isButtonDisabled)
                Spacer()
                    .frame(height: 50)
            }
        }.ignoresSafeArea(.all)
    }
    
    func saveToGallery(image: UIImage) {
        let rotatedImage = image.rotate(radians: .pi / 2)

        UIImageWriteToSavedPhotosAlbum(rotatedImage, nil, nil, nil)
    }
}

struct VerticalProgressBar: View {
    var value: Float

    var body: some View {
        ZStack(alignment: .bottom) {
            Rectangle().frame(width: 20, height: 200)
                .opacity(0.3)
                .foregroundColor(.mint)

            Rectangle().frame(width: 20, height: CGFloat(self.value) * 200)
                .foregroundColor(.mint)
                .animation(.linear)
        }.cornerRadius(45.0)
    }
}

struct ARViewContainer: UIViewRepresentable {
    @ObservedObject var arViewModel: ARViewModel

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        arViewModel.arView = arView

        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            configuration.frameSemantics.insert(.sceneDepth)
        }

        arView.session.run(configuration, options: [])
        arView.session.delegate = context.coordinator

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(arViewModel: arViewModel)
    }

    class Coordinator: NSObject, ARSessionDelegate {
        var arViewModel: ARViewModel

        init(arViewModel: ARViewModel) {
            self.arViewModel = arViewModel
        }

        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            arViewModel.lastFrame = frame
            arViewModel.updateButtonStatus()
        }
    }
}

class ARViewModel: ObservableObject {
    @Published var snapshotImage: UIImage?
    @Published var snapshotDepthMapImage: UIImage?
    @Published var isButtonDisabled = false
    @Published var distance: Float = 0.0
    var lastFrame: ARFrame?
    var arView: ARView?
    var markerAnchor: AnchorEntity?
    var originalMarkerPosition: SIMD3<Float>?
    
    func takeSnapshotAndPlaceMarker() {
        guard let lastFrame = lastFrame,
              let arView = arView else {
            return
        }

        arView.snapshot(saveToHDR: false) { (image) in
            self.snapshotImage = image
        }

        guard let depthData = lastFrame.sceneDepth else {
            print("Depth data not available")
            let transform = lastFrame.camera.transform
            
            originalMarkerPosition = SIMD3<Float>(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
            
            print(originalMarkerPosition)

            let translation = SIMD3<Float>(0, 0, -0.1)
            let translationMatrix = simd_float4x4([
                simd_float4(1, 0, 0, 0),
                simd_float4(0, 1, 0, 0),
                simd_float4(0, 0, 1, 0),
                simd_float4(translation.x, translation.y, translation.z, 1)
            ])

            let updatedTransform = transform * translationMatrix

            let anchorEntity = AnchorEntity(world: updatedTransform)
            self.markerAnchor = anchorEntity
            let sphere = ModelEntity(mesh: .generatePlane(width: 0.01, height: 0.01), materials: [SimpleMaterial(color: .green, isMetallic: false)])
            anchorEntity.addChild(sphere)
            arView.scene.addAnchor(anchorEntity)
            
            distance = 0.0
            updateButtonStatus()
            return
        }

        let depthMap = depthData.depthMap
        let depthMapImage = depthMap.toUIImage()
        self.snapshotDepthMapImage = depthMapImage

        let transform = lastFrame.camera.transform
        
        originalMarkerPosition = SIMD3<Float>(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
        
        print(originalMarkerPosition)

        let translation = SIMD3<Float>(0, 0, -0.1)
        let translationMatrix = simd_float4x4([
            simd_float4(1, 0, 0, 0),
            simd_float4(0, 1, 0, 0),
            simd_float4(0, 0, 1, 0),
            simd_float4(translation.x, translation.y, translation.z, 1)
        ])

        let updatedTransform = transform * translationMatrix

        let anchorEntity = AnchorEntity(world: updatedTransform)
        self.markerAnchor = anchorEntity
        let sphere = ModelEntity(mesh: .generatePlane(width: 0.01, height: 0.01), materials: [SimpleMaterial(color: .green, isMetallic: false)])
        anchorEntity.addChild(sphere)
        arView.scene.addAnchor(anchorEntity)
        
        distance = 0.0
        updateButtonStatus()
    }
    
    func updateButtonStatus() {
        guard let originalMarkerPosition = originalMarkerPosition else {
            return
        }
        
        let deviceTransform = lastFrame?.camera.transform
        let devicePosition = SIMD3<Float>(deviceTransform!.columns.3.x, deviceTransform!.columns.3.y, 0)
        let distance = simd_distance(devicePosition, originalMarkerPosition)
        
//        print("Distance between marker and device: \(distance) meters")
        
        self.distance = Float(distance)
        
        isButtonDisabled = distance > 0.2
    }
}

extension CVPixelBuffer {
    func toUIImage() -> UIImage? {
        let ciImage = CIImage(cvPixelBuffer: self)
        let context = CIContext(options: nil)
        if let cgImage = context.createCGImage(ciImage, from: CGRect(x: 0, y: 0, width: CVPixelBufferGetWidth(self), height: CVPixelBufferGetHeight(self))) {
            return UIImage(cgImage: cgImage)
        }
        return nil
    }
}

extension UIImage {
    func rotate(radians: CGFloat) -> UIImage {
        let rotatedSize = CGRect(origin: .zero, size: size)
            .applying(CGAffineTransform(rotationAngle: radians))
            .integral.size
        UIGraphicsBeginImageContext(rotatedSize)
        if let context = UIGraphicsGetCurrentContext() {
            let origin = CGPoint(x: rotatedSize.width / 2.0, y: rotatedSize.height / 2.0)
            context.translateBy(x: origin.x, y: origin.y)
            context.rotate(by: radians)
            draw(in: CGRect(x: -size.width / 2.0, y: -size.height / 2.0, width: size.width, height: size.height))
            let rotatedImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()

            return rotatedImage ?? self
        }
        return self
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
