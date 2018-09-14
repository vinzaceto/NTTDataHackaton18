//
//  VideoCameraType.swift
//  swiftHackaton18
//
//  Created by Aceto Vincenzo on 14/09/18.
//  Copyright © 2018 Aceto Vincenzo. All rights reserved.
//

import AVFoundation


enum CameraType : Int {
    case back
    case front
    
    func captureDevice() -> AVCaptureDevice {
        switch self {
        case .front:
            let devices = AVCaptureDevice.DiscoverySession(deviceTypes: [], mediaType: AVMediaType.video, position: .front).devices
            print("devices:\(devices)")
            for device in devices where device.position == .front {
                return device
            }
        default:
            let devices = AVCaptureDevice.DiscoverySession(deviceTypes: [], mediaType: AVMediaType.video, position: .back).devices
            print("devices:\(devices)")
            for device in devices where device.position == .back {
                return device
            }
        }
        return AVCaptureDevice.default(for: AVMediaType.video)!
    }
}

