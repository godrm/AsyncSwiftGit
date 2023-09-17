// Copyright © 2023 Jung Kim. Available under the MIT License, see LICENSE for details.

import Clibgit2
import Foundation

/// The patch object to wrap and take ownership of
public final class Patch : Hashable {
    public static func == (lhs: Patch, rhs: Patch) -> Bool {
        return lhs.hashValue == rhs.hashValue
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(patchPointer.hashValue)
    }
    
    private let patchPointer: OpaquePointer
    
    /// The delta corresponding to this patch.
    private let delta: Diff.Delta
    
    /// The number of added lines in this patch.
    public private(set) var addedLinesCount: UInt
    
    /// The number of deleted lines in this patch.
    public private(set) var deletedLinesCount: UInt
    
    /// The number of context lines in this patch.
    public private(set) var contextLinesCount: UInt
        
    public init(_ patchPointer: OpaquePointer, delta: Diff.Delta) {
        self.patchPointer = patchPointer
        self.delta = delta
        self.addedLinesCount = 0
        self.deletedLinesCount = 0
        self.contextLinesCount = 0
        
        git_patch_line_stats(&contextLinesCount, &addedLinesCount, &deletedLinesCount, patchPointer)
    }
    
    deinit {
        git_patch_free(patchPointer)
    }
    
    public func sizeWithContext(includeContext: Bool, includeHunkHeaders: Bool, includeFileHeaders: Bool) -> UInt {
        let size = UInt( git_patch_size(self.patchPointer, (includeContext) ? 1 : 0, (includeHunkHeaders) ? 1 : 0, (includeFileHeaders) ? 1 : 0))
        return size
    }
    
    /// The binary diff for this patch.
    public func patchData() -> Data {
        var buf = git_buf()
        git_patch_to_buf(&buf, self.patchPointer)
        let buffer = Data.init(bytes: buf.ptr, count: buf.size)
        git_buf_dispose(&buf)
        return buffer
    }
    
    /// The number of hunks in this patch.
    public var hunkCount: UInt {
        return UInt(git_patch_num_hunks(self.patchPointer))
    }

    /// enumerate by hunk
    public func enumerateHunks(with block:@escaping (_ hunk: Hunk, _ isStop: inout Bool )->()) -> Bool {
        
        for index in 0..<self.hunkCount {
            guard let hunk = Hunk(with: self, index: Int(index)) else {
                return false
            }
            var shouldStop = false
            block(hunk, &shouldStop)
            if shouldStop { break }
        }
        return true
    }
    
    public func hunk(at index: Int) -> Hunk? {
        guard index >= 0 && index <= self.hunkCount-1 else { return nil }
        let hunk = Hunk(with: self, index: index)
        return hunk
    }
    
    public class Hunk {
        enum HunkError: Error {
            case FailExtractingLine
        }
        
        private var patch : Patch
        private var index : Int
        private(set) var git_hunk: UnsafePointer<git_diff_hunk>?
        
        public private(set) var header: String
        public private(set) var lineCount: UInt
        public private(set) var oldStart: UInt
        public private(set) var oldLines: UInt
        public private(set) var newStart: UInt
        public private(set) var newLines: UInt
        
        init?(with patch: Patch, index: Int) {
            self.patch = patch
            self.index = index
            self.lineCount = 0
            
            let result = git_patch_get_hunk(&git_hunk, &self.lineCount, patch.patchPointer, index)
            guard result == GIT_OK.rawValue,
                  let hunk = git_hunk else { return nil }
            self.header = ""
            self.oldStart = UInt(hunk.pointee.old_start)
            self.oldLines = UInt(hunk.pointee.old_lines)
            self.newStart = UInt(hunk.pointee.new_start)
            self.newLines = UInt(hunk.pointee.new_lines)
            if hunk.pointee.header_len > 0 {
                self.header = withUnsafePointer(to: hunk.pointee.header) {
                    $0.withMemoryRebound(to: UInt8.self, capacity: hunk.pointee.header_len) {
                        String(cString: $0)
                    }
                }
            }
        }
        
        public func line(at lineIndex: Int) -> Line? {
            guard self.lineCount > 1 && lineIndex >= 0 && lineIndex <= self.lineCount-1 else { return nil }
            let line = try? makeLine(at: UInt(lineIndex))
            return line
        }

        private func makeLine(at lineIndex: UInt) throws -> Line {
            var gitLine : UnsafePointer<git_diff_line>? = nil
            let result = git_patch_get_line_in_hunk(&gitLine, patch.patchPointer, index, Int(lineIndex))
            guard result == GIT_OK.rawValue,
                let linePointer = gitLine else {
                throw HunkError.FailExtractingLine
            }
            let line = Line(with: linePointer)
            return line
        }
        
        public func enumerateLinesInHunk(with block:@escaping (_ line: Line, _ isStop: inout Bool )->()) throws -> Bool {
            for lineIndex in 0..<lineCount {
                let line = try makeLine(at: lineIndex)
                var shouldStop = false
                block(line, &shouldStop)
                if shouldStop { break }
            }
            return true
        }
    }
    
    public class Line {
        private let linePointer : UnsafePointer<git_diff_line>
        public private(set) var content : String
        public private(set) var oldLineNumber: Int
        public private(set) var newLineNumber: Int
        public private(set) var origin: Origin
        public private(set) var lineCount: Int
        
        public enum Origin : String {
            case CONTEXT = " "
            case ADDITION = "+"
            case DELETION = "-"
            
            case CONTEXT_EOFNL = "="
            case ADD_EOFNL = ">"
            case DEL_EOFNL = "<"
            
            case FILE_HDR = "F"
            case HUNK_HDR = "H"
            case BINARY = "B"
        }
        
        init(with linePointer: UnsafePointer<git_diff_line>) {
            self.linePointer = linePointer
            let lineData = Data(bytes: linePointer.pointee.content, count: linePointer.pointee.content_len)
            self.content = String(data: lineData, encoding: .utf8)?.trimmingCharacters(in: .newlines) ?? ""
            self.oldLineNumber = Int(linePointer.pointee.old_lineno)
            self.newLineNumber = Int(linePointer.pointee.new_lineno)
            self.lineCount = Int(linePointer.pointee.num_lines)
            self.origin = Origin(rawValue: String(UnicodeScalar(UInt8(linePointer.pointee.origin)))) ?? .CONTEXT
        }
    }
}
