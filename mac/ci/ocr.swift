// Prints the text that macOS itself can read in an image, top to bottom.
// Used in CI to put what the app really drew on screen into the log.
import AppKit
import Vision

let path = CommandLine.arguments[1]
guard let image = NSImage(contentsOfFile: path),
      let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    FileHandle.standardError.write("cannot read \(path)\n".data(using: .utf8)!)
    exit(1)
}
let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.usesLanguageCorrection = false
try VNImageRequestHandler(cgImage: cgImage).perform([request])
for observation in request.results ?? [] {
    if let text = observation.topCandidates(1).first {
        print("    | \(text.string)")
    }
}
