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

class DocumentController: NSDocumentController {
    override func openDocument(withContentsOf url: URL, display displayDocument: Bool, completionHandler: @escaping (NSDocument?, Bool, Error?) -> Void) {
        guard let doc = documents.first as? CrashDocument,
              doc.isReplaceable
        else {
            super.openDocument(withContentsOf: url, display: displayDocument, completionHandler: completionHandler)
            return
        }
        let type = (try? typeForContents(of: url)) ?? url.pathExtension
        try? doc.read(from: url, ofType: type)
        doc.fileURL = url
        if displayDocument {
            doc.showWindows()
        }
        completionHandler(doc, true, nil)
    }
}
