//
//  main.swift
//  FaceNow
//

import CoreMediaIO
import Foundation

let queue = DispatchQueue(
    label: "ai.xmax.camera.extension",
    qos: .userInitiated
)
let source = try CameraProvider(queue: queue)
CMIOExtensionProvider.startService(provider: source.provider)
CFRunLoopRun()
