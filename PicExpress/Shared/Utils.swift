//
//  Utils.swift
//  PicExpress
//
//  Created by Michaël ATTAL on 10/01/2025.
//

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
}
