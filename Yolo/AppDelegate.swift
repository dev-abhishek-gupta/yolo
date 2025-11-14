//
//  AppDelegate.swift
//  Yolo
//
//  Created by Abhishek Gupta on 15/11/25.
//

import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?


    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
        
        let controller = YOLOCameraViewController()
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = controller
        self.window = window
        self.window?.makeKeyAndVisible()
        return true
    }
}

