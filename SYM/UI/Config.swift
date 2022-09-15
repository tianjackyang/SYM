// The MIT License (MIT)
//
// Copyright (c) 2017 - present zqqf16
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import Cocoa

extension String {
    static let downloadFolderKey = "dsymDownloadFolder"
    static let editorFontNameKey = "editorFontName"
    static let editorFontSizeKey = "editorFontSize"
    static let editorHighlightColorKey = "editorHighlightColorKey"
}

extension Notification.Name {
    static let configFontChanged = Notification.Name("sym.config.fontChanged")
    static let configColorChanged = Notification.Name("sym.config.colorChanged")
}

enum Config {
    static var downloadScriptURL: URL {
        let dir = FileManager.default.appSupportDirectory() ?? NSTemporaryDirectory()
        var url = URL(fileURLWithPath: dir)
        url.appendPathComponent("download.sh")
        return url
    }

    static func prepareDsymDownloadDirectory() {
        let path = dsymDownloadDirectory
        UserDefaults.standard.set(path, forKey: .downloadFolderKey)
    }

    static var dsymDownloadDirectory: String {
        let home = NSHomeDirectory()
        var path: String!
        if let stored = UserDefaults.standard.string(forKey: .downloadFolderKey) {
            if stored.hasPrefix("~/") {
                path = "\(home)/\(stored.dropFirst(2))"
            } else {
                path = stored
            }
        }

        if path == nil {
            let urls = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)
            path = urls.first?.path ?? home
        }

        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createDirectory(path)
        }

        return path
    }

    static var editorFont: NSFont {
        get {
            var fontSize: CGFloat = NSFont.systemFontSize

            let size = UserDefaults.standard.integer(forKey: .editorFontSizeKey)
            if size > 0 {
                fontSize = CGFloat(size)
            }

            var font: NSFont?
            if let name = UserDefaults.standard.string(forKey: .editorFontNameKey) {
                font = NSFont(name: name, size: fontSize)
            }

            return font ?? NSFont.userFixedPitchFont(ofSize: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
        }
        set(newFont) {
            let name = newFont.fontName
            let size = Int(newFont.pointSize)
            UserDefaults.standard.set(name, forKey: .editorFontNameKey)
            UserDefaults.standard.set(size, forKey: .editorFontSizeKey)
            NotificationCenter.default.post(name: .configFontChanged, object: newFont)
        }
    }

    static let highlightColors: [String] = [
        "#F44336",
        "#E91E63",
        "#9C27B0",
        "#673AB7",
        "#3F51B5",
        "#2196F3",
        "#03A9F4",
        "#00BCD4",
        "#009688",
        "#4CAF50",
        "#8BC34A",
        "#CDDC39",
        "#FFEB3B",
        "#FFC107",
        "#FF9800",
        "#FF5722",
        "#795548",
        "#9E9E9E",
        "#607D8B",
    ]

    static var highlightColor: String {
        get {
            return UserDefaults.standard.string(forKey: .editorHighlightColorKey) ?? highlightColors[0]
        }
        set(newColor) {
            UserDefaults.standard.set(newColor, forKey: .editorHighlightColorKey)
            NotificationCenter.default.post(name: .configColorChanged, object: newColor)
        }
    }
}
