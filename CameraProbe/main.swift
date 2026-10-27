import Foundation

// This tool is launched only by the sandboxed host. It inherits the host's sandbox
// and does not initialize AppKit, RTC, physical capture, or the host's device list.
guard CommandLine.arguments.contains("--camera-discovery-probe") else {
    FileHandle.standardError.write(Data("This helper must be launched by FaceNow.\n".utf8))
    exit(EXIT_FAILURE)
}

Task {
    do { _ = try await VirtualCameraDiscovery.waitForSink(timeout: .seconds(2)) } catch {}
    do {
        let data = try JSONEncoder().encode(VirtualCameraDiscovery.snapshot())
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
        exit(EXIT_SUCCESS)
    } catch {
        FileHandle.standardError.write(Data("Camera discovery probe failed: \(error.localizedDescription)\n".utf8))
        exit(EXIT_FAILURE)
    }
}
dispatchMain()
