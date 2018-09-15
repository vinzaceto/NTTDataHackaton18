//
//  ViewController.swift
//  swiftHackaton18
//
//  Created by Aceto Vincenzo on 14/09/18.
//  Copyright © 2018 Aceto Vincenzo. All rights reserved.
//
import UIKit
import CoreMedia
import Vision
import UIKit
import Alamofire

class ViewController: UIViewController {

  @IBOutlet weak var topConstraint: NSLayoutConstraint!
  @IBOutlet weak var emoticonLabel: UILabel!
  @IBOutlet weak var previewView: UIView!
    @IBOutlet weak var predictionLabel: UILabel!
  @IBOutlet weak var sampleView: UIView!
  @IBOutlet weak var bottomView: UIView!
  
  private let distance: CGFloat = 420
  
    //let emotionalModel = CNNEmotions()
    let emotionalModel = EmotiClassifier()

    private var videoCapture: VideoCapture!
    private var requests = [VNRequest]()
    
    var useCoreML = false;

    override func viewDidLoad() {
        super.viewDidLoad()
        setupVision()
      bottomView.layer.cornerRadius = 20
        
        let spec = VideoSpec(fps: 5, size: CGSize(width: 299, height: 299))
        videoCapture = VideoCapture(cameraType: .front,
                                    preferredSpec: spec,
                                    previewContainer: previewView.layer)
        
        videoCapture.imageBufferHandler = {[unowned self] (imageBuffer) in
            if self.useCoreML {
                // Use Core ML
                self.handleImageBufferWithCoreML(imageBuffer: imageBuffer)
            }
            else {
                // Use Vision
                self.handleImageBufferWithVision(imageBuffer: imageBuffer)
            }
        }
      
      topConstraint.constant = distance
      addSwipes()
    }
  
  private func addSwipes()
  {
    addSwipeUp()
    addSwipeDown()
  }
  
  private func addSwipeDown()
  {
    let swipeGesture = UISwipeGestureRecognizer(target: self, action: #selector(swipeDownHappened(sender:)))
    swipeGesture.direction = .down
    self.view.addGestureRecognizer(swipeGesture)
  }
  
  private func addSwipeUp()
  {
      let swipeGesture = UISwipeGestureRecognizer(target: self, action: #selector(swipeUpHappened(sender:)))
      swipeGesture.direction = .up
      self.view.addGestureRecognizer(swipeGesture)
  }
  
  @objc private func swipeDownHappened(sender: UISwipeGestureRecognizer)
  {
    if topConstraint.constant == 0
    {
      self.topConstraint.constant = self.distance
      animate(self.view.layoutIfNeeded())
    }
  }
  
  @objc private func swipeUpHappened(sender: UISwipeGestureRecognizer)
  {
    if topConstraint.constant == distance
    {
      self.topConstraint.constant = 0
      animate(self.view.layoutIfNeeded())
    }
  }
  
  func animate(_ animation: @autoclosure @escaping () -> Void,
               duration: TimeInterval = 0.25)
  {
    UIView.animate(withDuration: duration, animations: animation)
  }

    func handleImageBufferWithCoreML(imageBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(imageBuffer) else {
            return
        }
        do {
            let prediction = try self.emotionalModel.prediction(data: self.resize(pixelBuffer: pixelBuffer)!)
            DispatchQueue.main.async {
                if let prob = prediction.prob[prediction.classLabel] {
                    self.predictionLabel.text = "\(prediction.classLabel) \(String(describing: prob))"
                }
            }
        }
        catch let error as NSError {
            fatalError("Unexpected error ocurred: \(error.localizedDescription).")
        }
    }
    
    func handleImageBufferWithVision(imageBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(imageBuffer) else {
            return
        }
        
        var requestOptions:[VNImageOption : Any] = [:]
        
        if let cameraIntrinsicData = CMGetAttachment(imageBuffer, kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix, nil) {
            requestOptions = [.cameraIntrinsics:cameraIntrinsicData]
        }
        
        let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: CGImagePropertyOrientation(rawValue: UInt32(self.exifOrientationFromDeviceOrientation))!, options: requestOptions)
        do {
            try imageRequestHandler.perform(self.requests)
        } catch {
            print(error)
        }
    }
    
    func setupVision() {
        guard let visionModel = try? VNCoreMLModel(for: emotionalModel.model) else {
            fatalError("can't load Vision ML model")
        }
        let classificationRequest = VNCoreMLRequest(model: visionModel) { (request: VNRequest, error: Error?) in
            guard let observations = request.results else {
                print("no results:\(error!)")
                return
            }
            
            let classificationsLabels = observations[0...3]
                .compactMap({ $0 as? VNClassificationObservation })
                .filter({ $0.confidence > 0.8 })
                //.map({ "\($0.identifier) \($0.confidence)" })
            .map({"\($0.identifier)"})
            
            let classificationsPercent = observations[0...3]
                .compactMap({ $0 as? VNClassificationObservation })
                .filter({ $0.confidence > 0.8 })
                .map({ "\($0.identifier) \($0.confidence)" })
            
            DispatchQueue.main.async {
                self.predictionLabel.text = classificationsPercent.first
              switch classificationsLabels.first
              {
              case "Sad":
                self.emoticonLabel.text = "😥"
              case "Happy":
                self.emoticonLabel.text = "😃"
              case "Neutral":
                self.emoticonLabel.text = "😑"
              case "Angry":
                self.emoticonLabel.text = "🤬"
              case "Fear":
                self.emoticonLabel.text = "😱"
              default:
                self.emoticonLabel.text = ""
              }
            }
        }
        classificationRequest.imageCropAndScaleOption = VNImageCropAndScaleOption.centerCrop
        
        self.requests = [classificationRequest]
    }
    
    
    /// only support back camera
    var exifOrientationFromDeviceOrientation: Int32 {
        let exifOrientation: DeviceOrientation
        enum DeviceOrientation: Int32 {
            case top0ColLeft = 1
            case top0ColRight = 2
            case bottom0ColRight = 3
            case bottom0ColLeft = 4
            case left0ColTop = 5
            case right0ColTop = 6
            case right0ColBottom = 7
            case left0ColBottom = 8
        }
        switch UIDevice.current.orientation {
        case .portraitUpsideDown:
            exifOrientation = .left0ColBottom
        case .landscapeLeft:
            exifOrientation = .top0ColLeft
        case .landscapeRight:
            exifOrientation = .bottom0ColRight
        default:
            exifOrientation = .right0ColTop
        }
        return exifOrientation.rawValue
    }
    
    
    /// resize CVPixelBuffer
    ///
    /// - Parameter pixelBuffer: CVPixelBuffer by camera output
    /// - Returns: CVPixelBuffer with size (299, 299)
    func resize(pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        let imageSide = 224
        var ciImage = CIImage(cvPixelBuffer: pixelBuffer, options: nil)
        let transform = CGAffineTransform(scaleX: CGFloat(imageSide) / CGFloat(CVPixelBufferGetWidth(pixelBuffer)), y: CGFloat(imageSide) / CGFloat(CVPixelBufferGetHeight(pixelBuffer)))
        ciImage = ciImage.transformed(by: transform).cropped(to: CGRect(x: 0, y: 0, width: imageSide, height: imageSide))
        let ciContext = CIContext()
        var resizeBuffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, imageSide, imageSide, CVPixelBufferGetPixelFormatType(pixelBuffer), nil, &resizeBuffer)
        ciContext.render(ciImage, to: resizeBuffer!)
        return resizeBuffer
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard let videoCapture = videoCapture else {return}
        videoCapture.startCapture()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard let videoCapture = videoCapture else {return}
        videoCapture.resizePreview()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        guard let videoCapture = videoCapture else {return}
        videoCapture.stopCapture()
        
        navigationController?.setNavigationBarHidden(false, animated: true)
        super.viewWillDisappear(animated)
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }
}

