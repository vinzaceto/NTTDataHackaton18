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
import Firebase
import Charts

class ViewController: UIViewController {

  @IBOutlet weak var pieChart: PieChartView!
  @IBOutlet weak var topConstraint: NSLayoutConstraint!
  @IBOutlet weak var emoticonLabel: UILabel!
  @IBOutlet weak var previewView: UIView!
    @IBOutlet weak var predictionLabel: UILabel!
  @IBOutlet weak var sampleView: UIView!
  @IBOutlet weak var bottomView: UIView!
    
    
    var db: Firestore!

  
  private let distance: CGFloat = 420
  
    //let emotionalModel = CNNEmotions()
    let emotionalModel = EmotiClassifier()

    private var videoCapture: VideoCapture!
    private var requests = [VNRequest]()
    
    var useCoreML = false;

    override func viewDidLoad() {
        super.viewDidLoad()
        
        //setup firebase
        // [START setup]
        let settings = FirestoreSettings()
        
        Firestore.firestore().settings = settings
        // [END setup]
        db = Firestore.firestore()
        
        
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
      setChart()
      setDataCount(4, range: 30)
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
                    self.addEmotion(label: prediction.classLabel, precision: String(describing: prob))
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
            
            let classificationsLabelPercent = observations[0...3]
                .compactMap({ $0 as? VNClassificationObservation })
                .filter({ $0.confidence > 0.8 })
                .map({ "\($0.identifier) \($0.confidence)" })
            
            let classificationsPercent = observations[0...3]
                .compactMap({ $0 as? VNClassificationObservation })
                .filter({ $0.confidence > 0.8 })
                .map({ "\($0.confidence)" })
            
            DispatchQueue.main.async {
                self.predictionLabel.text = classificationsLabelPercent.first
                
                if (classificationsLabels.first != nil && classificationsPercent.first != nil) {
                    self.addEmotion(label: classificationsLabels.first!, precision: classificationsPercent.first!)
                    self.getMultiple()
                }

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
    
    
    private func addEmotion(label: String,precision: String) {
        // Add a new document with a generated ID
        var ref: DocumentReference? = nil
        ref = db.collection("track").addDocument(data: [
            "description": label,
            "precision": precision,
            "date": ViewController.createDateDescription(date: Date()),
            "time": ViewController.createTimeDescription(date: Date()),
        ]) { err in
            if let err = err {
                print("Error adding document: \(err)")
            } else {
                print("Document added with ID: \(ref!.documentID)")
            }
        }
    }
    
    private func simpleQueries() {
        // [START simple_queries]
        // Create a reference to the collection
        let trackRef = db.collection("track")
        
        // Create a query against the collection.
        let query = trackRef.whereField("emotion", isEqualTo: "Sad")
        // [END simple_queries]
        print(query)
    }
    
    private func getMultiple() {
        // [START get_multiple]
        db.collection("track").whereField("description", isEqualTo: "Happy")
            .getDocuments() { (querySnapshot, err) in
                if let err = err {
                    print("Error getting documents: \(err)")
                } else {
                    for document in querySnapshot!.documents {
                        print("\(document.documentID) => \(document.data())")
                    }
                }
        }
        // [END get_multiple]
    }
    
    private static func createDateDescription(date: Date) -> String
    {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale.current
        dateFormatter.dateFormat = "dd/MMMM/yyyy"
        
        return dateFormatter.string(from: date)
    }
    
    private static func createTimeDescription(date: Date) -> String
    {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale.current
        dateFormatter.dateFormat = "HH:mm"
        
        return dateFormatter.string(from: date)
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

// solo per la logica del grafico a torta
extension ViewController: ChartViewDelegate
{
  private func setChart()
  {
    let options: [Option] = [ .toggleValues,
                    .toggleXValues,
                    .togglePercent,
                    .toggleHole,
                    .toggleIcons,
                    .animateX,
                    .animateY,
                    .animateXY,
                    .spin,
                    .drawCenter,
                    .saveToGallery,
                    .toggleData]
    
    self.setup(pieChartView: pieChart)
    
    pieChart.delegate = self
    
    let l = pieChart.legend
    l.horizontalAlignment = .right
    l.verticalAlignment = .top
    l.orientation = .vertical
    l.xEntrySpace = 7
    l.yEntrySpace = 0
    l.yOffset = 0
    //        pieChart.legend = l
    // entry label styling
    pieChart.entryLabelColor = .white
    pieChart.entryLabelFont = .systemFont(ofSize: 12, weight: .light)
    

    pieChart.animate(xAxisDuration: 1.4, easingOption: .easeOutBack)
  }
  
  func setup(pieChartView pieChart: PieChartView)
  {
    pieChart.usePercentValuesEnabled = true
    pieChart.drawSlicesUnderHoleEnabled = false
    pieChart.holeRadiusPercent = 0.58
    pieChart.transparentCircleRadiusPercent = 0.61
    pieChart.chartDescription?.enabled = false
    pieChart.setExtraOffsets(left: 5, top: 10, right: 5, bottom: 5)
    
    pieChart.drawCenterTextEnabled = true
    
    let paragraphStyle = NSParagraphStyle.default.mutableCopy() as! NSMutableParagraphStyle
    paragraphStyle.lineBreakMode = .byTruncatingTail
    paragraphStyle.alignment = .center
    
    let centerText = NSMutableAttributedString(string: "Charts\nby Daniel Cohen Gindi")
    centerText.setAttributes([.font : UIFont(name: "HelveticaNeue-Light", size: 13)!,
                              .paragraphStyle : paragraphStyle], range: NSRange(location: 0, length: centerText.length))
    centerText.addAttributes([.font : UIFont(name: "HelveticaNeue-Light", size: 11)!,
                              .foregroundColor : UIColor.gray], range: NSRange(location: 10, length: centerText.length - 10))
    centerText.addAttributes([.font : UIFont(name: "HelveticaNeue-Light", size: 11)!,
                              .foregroundColor : UIColor(red: 51/255, green: 181/255, blue: 229/255, alpha: 1)], range: NSRange(location: centerText.length - 19, length: 19))
    pieChart.centerAttributedText = centerText;
    
    pieChart.drawHoleEnabled = true
    pieChart.rotationAngle = 0
    pieChart.rotationEnabled = true
    pieChart.highlightPerTapEnabled = true
    
    let l = pieChart.legend
    l.horizontalAlignment = .right
    l.verticalAlignment = .top
    l.orientation = .vertical
    l.drawInside = false
    l.xEntrySpace = 7
    l.yEntrySpace = 0
    l.yOffset = 0
    //        pieChart.legend = l
  }
  
  private func setDataCount(_ count: Int, range: UInt32)
  {
    let entries = (0..<count).map { (i) -> PieChartDataEntry in
      // IMPORTANT: In a PieChart, no values (Entry) should have the same xIndex (even if from different DataSets), since no values can be drawn above each other.
      return PieChartDataEntry(value: Double(arc4random_uniform(range) + range / 5),
                               label: "blablabla",
                               icon: #imageLiteral(resourceName: "happy-1"))
    }
    
    let set = PieChartDataSet(values: entries, label: "Election Results")
    set.drawIconsEnabled = false
    set.sliceSpace = 2
    
    
    set.colors = ChartColorTemplates.vordiplom()
      + ChartColorTemplates.joyful()
      + ChartColorTemplates.colorful()
      + ChartColorTemplates.liberty()
      + ChartColorTemplates.pastel()
      + [UIColor(red: 51/255, green: 181/255, blue: 229/255, alpha: 1)]
    
    let data = PieChartData(dataSet: set)
    
    let pFormatter = NumberFormatter()
    pFormatter.numberStyle = .percent
    pFormatter.maximumFractionDigits = 1
    pFormatter.multiplier = 1
    pFormatter.percentSymbol = " %"
    data.setValueFormatter(DefaultValueFormatter(formatter: pFormatter))
    
    data.setValueFont(.systemFont(ofSize: 11, weight: .light))
    data.setValueTextColor(.white)
    
    pieChart.data = data
    pieChart.highlightValues(nil)
  }
}
