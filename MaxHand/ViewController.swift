//
//  ViewController.swift
//  knowWhere
//
//  Created by 권영호 on 14/01/2019.
//  Copyright © 2019 0ho_kwon. All rights reserved.
//

import UIKit
import SceneKit
import ARKit
import CoreML
import Vision

class ViewController: UIViewController {

    @IBOutlet weak var sceneView: ARSCNView!
    @IBOutlet weak var sessionInfoLabel: UILabel!
    @IBOutlet weak var handLabel: UILabel!
    
    let handDetector = HandDetector()//class
    let handClassification = HandClassification()
    
    private var timer = Timer()
    var currentBuffer: CVPixelBuffer?
    var currentCameraTransform:simd_float4x4?
    var handPreviewView = UIImageView()
    
    var isMax = false
    
    @IBAction func resetButton(){
        resetTracking();
        let rootnode = self.sceneView.scene.rootNode
        rootnode.enumerateChildNodes { (node, stop) in
//            if (node.name == "planeNode"){
                node.removeFromParentNode()
//            }
        }
    }
}
extension ViewController {
    //시스템에의해 자동으로 호출, 리소스 초기화나 초기 화면 구성용도, 화면 처음 만들어질 때 한 번만 실행.
    override func viewDidLoad() {
        super.viewDidLoad()
        // Set the view's delegate
        self.sceneView.delegate = self
    }
    // 뷰가 이제 나타날 거라는 신호
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setUpSceneView()
        self.timer = Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(self.loopCoreMLUpdate), userInfo: nil, repeats: true)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Pause the view's session
        sceneView.session.pause()
    }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
    }
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Release any cached data, images, etc that aren't in use.
    }
    
    @objc
    private func loopCoreMLUpdate() {
        DispatchQueue.main.async{
            self.findHandClassification()
        }
    }
    
}
extension ViewController: ARSCNViewDelegate {
    // MARK: - ARSCNViewDelegate

//    func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
//        return nil
//    }
    
    /// - Tag: PlaceARContent
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        if self.isMax { return }
        guard let planeAnchor = anchor as? ARPlaneAnchor else { return }
        DispatchQueue.main.async {
            let generator = UIImpactFeedbackGenerator(style: .heavy)
            generator.impactOccurred()
        }
        let max = Max()
        let pos = planeAnchor.transform.columns.3
        max.position = SCNVector3(pos.x,pos.y, pos.z)
        max.look(at: SCNVector3((currentCameraTransform?.columns.3.x)!, pos.y, (currentCameraTransform?.columns.3.z)!))
        self.sceneView.scene.rootNode.addChildNode(max)
        self.isMax = true
        
    }
    
//    func renderer(_ renderer: SCNSceneRenderer, willUpdate node: SCNNode, for anchor: ARAnchor) {
//
//    }
    
    // - Tag: UpdateARContent
//    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
//
//
//    }
}

extension ViewController: ARSessionDelegate{
    
    func session(_ session: ARSession, didUpdate frame: ARFrame){
        //currentBuffer가 nil이아니거나 camera의 state가 normal이 아니면 리턴.
        guard currentBuffer == nil, case .normal = frame.camera.trackingState else {
            return
        }
        currentCameraTransform = frame.camera.transform
        currentBuffer = frame.capturedImage
        findOverLapPixel()
        
    }
    
    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        guard let frame = session.currentFrame else { return }
        updateSessionInfoLabel(for: frame, trackingState: frame.camera.trackingState)
    }
    
    func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        guard let frame = session.currentFrame else { return }
        updateSessionInfoLabel(for: frame, trackingState: frame.camera.trackingState)
    }
    
    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        updateSessionInfoLabel(for: session.currentFrame!, trackingState: camera.trackingState)
    }
    // MARK: - ARSessionObserver
    
    func sessionWasInterrupted(_ session: ARSession) {
        // Inform the user that the session has been interrupted, for example, by presenting an overlay.
        sessionInfoLabel.text = "Session was interrupted"
    }
    
    func sessionInterruptionEnded(_ session: ARSession) {
        // Reset tracking and/or remove existing anchors if consistent tracking is required.
        sessionInfoLabel.text = "Session interruption ended"
        resetTracking()
    }
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        sessionInfoLabel.text = "Session failed: \(error.localizedDescription)"
        guard error is ARError else { return }
        
        let errorWithInfo = error as NSError
        let messages = [
            errorWithInfo.localizedDescription,
            errorWithInfo.localizedFailureReason,
            errorWithInfo.localizedRecoverySuggestion
        ]
        
        // Remove optional error messages.
        let errorMessage = messages.compactMap({ $0 }).joined(separator: "\n")
        
        DispatchQueue.main.async {
            // Present an alert informing about the error that has occurred.
            let alertController = UIAlertController(title: "The AR session failed.", message: errorMessage, preferredStyle: .alert)
            let restartAction = UIAlertAction(title: "Restart Session", style: .default) { _ in
                alertController.dismiss(animated: true, completion: nil)
                self.resetTracking()
            }
            alertController.addAction(restartAction)
            self.present(alertController, animated: true, completion: nil)
        }
    }
    
    // MARK: - Private methods
    
    private func updateSessionInfoLabel(for frame: ARFrame, trackingState: ARCamera.TrackingState) {
        // Update the UI to provide feedback on the state of the AR experience.
        let message: String
        
        switch trackingState {
        case .normal where frame.anchors.isEmpty:
            // No planes detected; provide instructions for this app's AR interactions.
            message = "Move the device around to detect horizontal and vertical surfaces."
            
        case .notAvailable:
            message = "Tracking unavailable."
            
        case .limited(.excessiveMotion):
            message = "Tracking limited - Move the device more slowly."
            
        case .limited(.insufficientFeatures):
            message = "Tracking limited - Point the device at an area with visible surface detail, or improve lighting conditions."
            
        case .limited(.initializing):
            message = "Initializing AR session."
            
        default:
            // No feedback needed when tracking is normal and planes are visible.
            // (Nor when in unreachable limited-tracking states.)
            message = ""
            
        }
        sessionInfoLabel.text = message
        
    }
    
    private func resetTracking() {
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal]
        self.sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        self.sceneView.session.run(configuration)
//        self.sceneView.showsStatistics = true
//        self.sceneView.debugOptions = [ARSCNDebugOptions.showFeaturePoints, ARSCNDebugOptions.showWireframe]
        self.sceneView.debugOptions = [ARSCNDebugOptions.showFeaturePoints]

        self.sceneView.delegate = self
        self.sceneView.session.delegate = self
    }
    private func setUpSceneView() {
        view = self.sceneView
        self.sceneView.delegate = self
        // Start the view's AR session with a configuration that uses the rear camera,
        // device position and orientation tracking, and plane detection.
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal]
        self.sceneView.session.run(configuration)
        
        // Set a delegate to track the number of plane anchors for providing UI feedback.
        self.sceneView.session.delegate = self
        
        // Prevent the screen from being dimmed after a while as users will likely
        // have long periods of interaction without touching the screen or buttons.
        UIApplication.shared.isIdleTimerDisabled = true
        
        // Show debug UI to view performance metrics (e.g. frames per second).
//        self.sceneView.showsStatistics = true
        
//        self.sceneView.debugOptions = [ARSCNDebugOptions.showFeaturePoints]
        
        view.addSubview(self.handPreviewView)
        
        self.handPreviewView.translatesAutoresizingMaskIntoConstraints = false
        self.handPreviewView.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
        self.handPreviewView.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
    }
}

extension ViewController {
    func maxExtent(a: Float,b: Float) -> Float{
        if a>b {return a}
        else {return b}
    }
    func minExtent(a: Float,b: Float) -> Float{
        if a<b {return a}
        else {return b}
    }
    
    private func findOverLapPixel() {
        guard let buffer = currentBuffer else { return }
        guard let cameraTransform = self.sceneView.session.currentFrame?.camera.transform else {return}
        let cameraPosition = SCNVector3Make(cameraTransform.columns.3.x, cameraTransform.columns.3.y, cameraTransform.columns.3.z)
        handDetector.performDetection(inputBuffer: buffer) {(outputBuffer, _) in
            var previewImage: UIImage?
            var normalizedFingerTip: CGPoint?
            
            defer{
                DispatchQueue.main.async {
                    self.handPreviewView.image = previewImage
                    //현재 버퍼 처리가 완료되면 다음 부터 데이터로 프로세싱하기 위해.
                    self.currentBuffer = nil

                    guard let tipPoint = normalizedFingerTip else {
                        return
                    }
                    
                    let imageFingerPoint = VNImagePointForNormalizedPoint(tipPoint, Int(self.view.bounds.size.width), Int(self.view.bounds.size.height))
                    
                    guard let hitTest = self.sceneView.hitTest(imageFingerPoint).first else {return}

                    let hitNode = hitTest.node
                    
                    if let maxNode = hitNode.topmost(until: self.sceneView.scene.rootNode) as? Max{
                        print(maxNode.position.distance(receiver: cameraPosition))
                        if maxNode.position.distance(receiver: cameraPosition) < 2{
                            DispatchQueue.main.async {
                                let generator = UIImpactFeedbackGenerator(style: .heavy)
                                generator.impactOccurred()
                            }
                            print(maxNode)
                            maxNode.spin()
                        }
                    }
                }
            }
            guard let outBuffer = outputBuffer else {
                return
            }
            previewImage = UIImage(ciImage: CIImage(cvPixelBuffer: outBuffer))
            normalizedFingerTip = outBuffer.searchTopPoint()
        }
    }
    private func findHandClassification() {
        guard let buffer = self.currentBuffer else {return}
        guard let cameraTransform = self.sceneView.session.currentFrame?.camera.transform else {return}
        let cameraPosition = SCNVector3Make(cameraTransform.columns.3.x, cameraTransform.columns.3.y, cameraTransform.columns.3.z)

        self.handClassification.perfomrClassification(inputBuffer: buffer) { (topPredictionName, _) in
//            print(topPredictionName)
//            print("fefefefefaefasefjawfea")
            guard let childNode = self.sceneView.scene.rootNode.childNode(withName: "Max", recursively: true) else{print("vvvv");return;}
            guard let maxNode = childNode.topmost(until: self.sceneView.scene.rootNode) as? Max else{print("efefef");return;}
            DispatchQueue.main.async {
                self.handLabel.text = topPredictionName
            }
            if(maxNode.isPaused) {print("paused")}
            
            if(topPredictionName == "hand_open"){
                maxNode.maxHeadMove(look: cameraPosition )
            }
            else if(topPredictionName == "hand_fist"){
                guard let cameraTransform = self.sceneView.session.currentFrame?.camera.transform else {return}
                let cameraPosition = SCNVector3Make(cameraTransform.columns.3.x, cameraTransform.columns.3.y, cameraTransform.columns.3.z)
                maxNode.maxCome(camera: cameraPosition)

            }
            else if(topPredictionName == "hand_two"){
                
            }
            else{

            }
        }
        
    }
}
