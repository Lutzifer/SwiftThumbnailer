import Foundation
import AVFoundation
import AppKit

func printUsage() {
    print("Usage: SwiftThumbnailer <movie-file> [movie-file2 ...] [--rows=N] [--columns=N] [--width=N]")
}

func formatTime(seconds: Double) -> String {
    let hrs = Int(seconds) / 3600
    let mins = (Int(seconds) % 3600) / 60
    let secs = Int(seconds) % 60
    return String(format: "%02d:%02d:%02d", hrs, mins, secs)
}

// Parse command-line arguments
guard CommandLine.arguments.count >= 2 else {
    printUsage()
    exit(1)
}

var rows = 8
var columns = 2
var width: CGFloat = 1024

var filePaths: [String] = []

for argument in CommandLine.arguments.dropFirst(1) {
    if argument.hasPrefix("--rows="), let rowsArg = Int(argument.replacingOccurrences(of: "--rows=", with: "")) {
        rows = rowsArg
    } else if argument.hasPrefix("--columns="), let columnsArg = Int(argument.replacingOccurrences(of: "--columns=", with: "")) {
        columns = columnsArg
    } else if argument.hasPrefix("--width="), let widthArg = Double(argument.replacingOccurrences(of: "--width=", with: "")) {
        width = CGFloat(widthArg)
    } else {
        filePaths.append(argument)
    }
}

if filePaths.isEmpty {
    printUsage()
    exit(1)
}

for filePath in filePaths {
    // Load the movie
    let asset = AVURLAsset(url: URL(fileURLWithPath: filePath))
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true

    let duration = try! await asset.load(.duration)
    let filename = (filePath as NSString).lastPathComponent

    let totalFrames = rows * columns
    var times = [NSValue]()
    for i in 0..<totalFrames {
        let seconds = duration.seconds * Double(i) / Double(totalFrames - 1)
        times.append(NSValue(time: CMTimeMakeWithSeconds(seconds, preferredTimescale: 600)))
    }

    // Generate thumbnails
    var images: [(NSImage, String)] = []
    for time in times {
        do {
            let cgImage = try generator.copyCGImage(at: time.timeValue, actualTime: nil)
            let image = NSImage(cgImage: cgImage, size: NSZeroSize)
            let timestamp = formatTime(seconds: time.timeValue.seconds)
            images.append((image, timestamp))
        } catch {
            print("Warning: could not generate thumbnail at \(time)")
        }
    }

    // Assume all thumbnails are same size
    let thumbWidth = width / CGFloat(columns)
    let thumbHeight = thumbWidth * (images.first?.0.size.height ?? 1) / (images.first?.0.size.width ?? 1)
    let headerHeight: CGFloat = 120
    let totalHeight = headerHeight + CGFloat(rows) * thumbHeight

    let finalImage = NSImage(size: NSSize(width: width, height: totalHeight))
    finalImage.lockFocus()

    // Draw header
    let headerParagraphStyle = NSMutableParagraphStyle()
    headerParagraphStyle.alignment = .center

    let headerAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.boldSystemFont(ofSize: 28),
        .paragraphStyle: headerParagraphStyle
    ]

    let readableDuration = formatTime(seconds: duration.seconds)
    let headerText = "\(filename)\nDuration: \(readableDuration)"
    
    let headerRect = NSRect(x: 0, y: totalHeight - headerHeight, width: width, height: headerHeight)
    
    NSColor.white.drawSwatch(in: headerRect)
    
    (headerText as NSString).draw(in: headerRect, withAttributes: headerAttrs)

    // Draw thumbnails with timestamps
    let timestampAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 14),
        .foregroundColor: NSColor.white,
        .backgroundColor: NSColor.black.withAlphaComponent(0.6)
    ]

    for (index, (image, timestamp)) in images.enumerated() {
        let row = index / columns
        let column = index % columns
        let x = CGFloat(column) * thumbWidth
        let y = totalHeight - headerHeight - CGFloat(row + 1) * thumbHeight

        image.draw(in: NSRect(x: x, y: y, width: thumbWidth, height: thumbHeight))

        // Draw timestamp
        let tsSize = (timestamp as NSString).size(withAttributes: timestampAttrs)
        let tsRect = NSRect(
            x: x + thumbWidth - tsSize.width - 6,
            y: y + 6,
            width: tsSize.width,
            height: tsSize.height
        )
        (timestamp as NSString).draw(in: tsRect, withAttributes: timestampAttrs)
    }

    finalImage.unlockFocus()

    // Save final image
    let outputFilePath = filePath + ".jpg"
    if let tiffData = finalImage.tiffRepresentation,
       let bitmap = NSBitmapImageRep(data: tiffData),
       let jpgData = bitmap.representation(using: .jpeg, properties: [:]) {
        do {
            try jpgData.write(to: URL(fileURLWithPath: outputFilePath))
            print("Image saved to \(outputFilePath)")
        } catch {
            print("Failed to save image: \(error)")
        }
    }
}
