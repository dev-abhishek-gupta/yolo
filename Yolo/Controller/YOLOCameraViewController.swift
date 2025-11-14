//
//  YOLOCameraViewController.swift
//  Yolo
//
//  Created by Abhishek Gupta on 15/11/25.
//


import UIKit
import AVFoundation
import Vision
import CoreML

final class YOLOCameraViewController: UIViewController {
    private let cameraManager = CameraManager()

    override func viewDidLoad() {
        super.viewDidLoad()
        cameraManager.setup(with: view)
    }
}

