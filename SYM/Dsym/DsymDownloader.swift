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
import Combine

class DsymDownloadTask {
    var crashInfo: Crash

    enum Status {
        case waiting
        case running
        case canceled
        case failed(code: Int, message: String?)
        case success

        func shouldRetry() -> Bool {
            switch self {
            case .waiting, .running:
                return false
            default:
                return true
            }
        }
    }

    struct Progress {
        var percentage: Int = 0
        var totalSize: String = "0"
        var downloadedSize: String = "0"
        var timeLeft: String = "Unknow"
        var speed: String = "0"

        mutating func update(fromConsoleOutput output: String) {
            /*
             curl
             % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
             Dload  Upload   Total   Spent    Left  Speed
             10  286M   10 30.2M    0     0   830k      0  0:05:53  0:00:37  0:05:16 1660k
             */
            let title = "% Total    % Received % Xferd  Average Speed   Time    Time     Time  Current"
            guard let range = output.range(of: title) else {
                return
            }

            let content = output[range.upperBound...]
            let lines = content.components(separatedBy: "\r")
            let count = lines.count
            if count < 3 {
                return
            }

            var items: [String] = []
            for index in (count - 2 ..< count).reversed() {
                let lastLine = lines[index]
                items = lastLine.components(separatedBy: " ").filter { string -> Bool in
                    string != ""
                }
                if items.count >= 12 {
                    break
                }
            }

            if items.count != 12 || !items[10].contains(":") {
                return
            }

            percentage = Int(items[0]) ?? 0
            totalSize = items[1]
            downloadedSize = items[3]
            timeLeft = items[10]
            speed = items[11]
            // print(self)
        }
    }

    @Published var status: Status = .waiting
    @Published var progress: Progress = .init()

    var statusCode: Int = 0
    var message: String?
    var dsymFiles: [DsymFile]?

    private var process: SubProcess!
    private var fileURL: URL?
    private var scriptURL: URL

    init(crashInfo: Crash, scriptURL: URL, fileURL: URL?) {
        self.crashInfo = crashInfo
        self.fileURL = fileURL
        self.scriptURL = scriptURL
    }

    func run() {
        defer {
            self.process = nil
        }

        if process != nil {
            process?.terminate()
            process = nil
        }

        let crashPath = fileURL?.path ?? FileManager.default.temporaryPath()
        do {
            try crashInfo.content.write(toFile: crashPath, atomically: true, encoding: .utf8)
        } catch {
            statusCode = -1001
            status = .failed(code: statusCode, message: "Failed to save file")
            return
        }

        let dir = Config.dsymDownloadDirectory
        let env = crashInfoToEnv(crashInfo)
        process = SubProcess(cmd: scriptURL.path, args: [crashPath, dir], env: env)
        process.errorHandler = { [weak self] _ in
            if let this = self {
                this.progress.update(fromConsoleOutput: this.process.error)
            }
        }
        status = .running
        process.run()

        parse(output: process.output)
        statusCode = process.exitCode
        message = process.output

        if statusCode != 0 {
            status = .failed(code: statusCode, message: message)
        } else {
            status = .success
        }
    }

    func cancel() {
        process?.terminate()
        status = .canceled
    }

    private func crashInfoToEnv(_ crashInfo: Crash) -> [String: String] {
        var env: [String: String] = [:]
        env["APP_NAME"] = crashInfo.appName ?? ""
        env["UUID"] = crashInfo.uuid ?? ""
        env["BUNDLE_ID"] = crashInfo.bundleID ?? ""

        let versionString = crashInfo.appVersion ?? ""
        env["APP_VERSION"] = versionString

        // compatible with older versions
        // convert 1.1.1 (123) to 123 (1.1.1)
        let components = versionString.components(separatedBy: " ")
        if components.count == 2 {
            let part1 = components[0]
            let part2 = components[1].replacingOccurrences(of: "(", with: "").replacingOccurrences(of: ")", with: "")
            if part1.contains("."), !part2.contains(".") {
                env["APP_VERSION"] = "\(part2) (\(part1))"
            }
        }

        return env
    }

    private func parse(output: String) {
        guard let matches = Regex.dwarfdump.matches(in: output) else {
            return
        }

        var uuids: [String] = [crashInfo.uuid ?? ""]
        if crashInfo.embeddedBinaries.count > 0 {
            uuids = crashInfo.embeddedBinaries.compactMap { binary -> String? in
                binary.uuid
            }
        }

        var dsymFiles: [DsymFile] = []
        for match in matches {
            let uuid = match.captures![0]
            if !uuids.contains(uuid) {
                continue
            }
            let path = match.captures![1]
            var name = ""
            for component in path.components(separatedBy: "/") {
                if component.hasSuffix(".dSYM") {
                    name = component
                    break
                }
            }
            let file = DsymFile(name: name, path: path, binaryPath: path,
                                uuids: [uuid], isApp: uuid == crashInfo.uuid)
            dsymFiles.append(file)
        }
        self.dsymFiles = dsymFiles
    }
}

class DsymDownloader {
    static let shared = DsymDownloader()

    @Published var tasks: [String: DsymDownloadTask] = [:]
    let scriptURL = Config.downloadScriptURL

    init() {
        prepareDownloadScript()
    }

    func prepareDownloadScript() {
        let scriptPath = scriptURL.path
        let fileManager = FileManager.default

        defer {
            if fileManager.fileExists(atPath: scriptPath) {
                fileManager.chmod(scriptPath, permissions: 0o777)
            }
        }

        // check user imported script
        if fileManager.fileExists(atPath: scriptPath) {
            let script = try? String(contentsOf: scriptURL, encoding: .utf8)
            if script != nil, script!.count > 0 {
                return
            }
        }

        // check buildin script
        if let buildinPath = Bundle.main.path(forResource: "download", ofType: "sh") {
            fileManager.cp(fromPath: buildinPath, toPath: scriptPath)
        }
    }

    func canDownload() -> Bool {
        let script = try? String(contentsOf: scriptURL, encoding: .utf8)
        if script == nil || script!.count == 0 {
            return false
        }

        return FileManager.default.chmod(scriptURL.path, permissions: 0o777)
    }

    @discardableResult
    func download(crashInfo: Crash, fileURL: URL?) -> DsymDownloadTask? {
        guard let uuid = crashInfo.uuid, canDownload() else {
            return nil
        }

        if let task = tasks[uuid], !task.status.shouldRetry() {
            return task
        }

        let task = DsymDownloadTask(crashInfo: crashInfo, scriptURL: scriptURL, fileURL: fileURL)
        tasks[uuid] = task
        DispatchQueue.global().async {
            task.run()
        }

        return task
    }
}
