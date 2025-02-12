//
//  Utils.swift
//  PicExpress
//
//  Created by Michaël ATTAL on 10/01/2025.
//

import AppKit
import Foundation

public class Utils {
    static func localizedDateString(from date: Date) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "fr_FR")
        dateFormatter.dateStyle = .medium
        return dateFormatter.string(from: date)
    }

    static func localizedTimeString(from date: Date) -> String {
        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "fr_FR")
        timeFormatter.timeStyle = .short
        return timeFormatter.string(from: date)
    }

    static func makeCGImageRGBA8(from buffer: [UInt8],
                                 width: Int,
                                 height: Int) -> CGImage?
    {
        guard width>0, height>0, buffer.count == width*height*4 else {
            return nil
        }
        let cs = CGColorSpaceCreateDeviceRGB()
        let bytesPerRow = width*4
        guard let ctx = CGContext(data: UnsafeMutableRawPointer(mutating: buffer),
                                  width: width,
                                  height: height,
                                  bitsPerComponent: 8,
                                  bytesPerRow: bytesPerRow,
                                  space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else {
            return nil
        }
        return ctx.makeImage()
    }
}
