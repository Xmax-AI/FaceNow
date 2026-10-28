//
//  main.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
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
