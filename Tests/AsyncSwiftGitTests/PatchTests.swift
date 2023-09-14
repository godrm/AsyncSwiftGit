//
//  PatchTests.swift
//  
//
//  Created by Jung Kim on 9/13/23.
//

import XCTest
import AsyncSwiftGit

final class PatchTests: XCTestCase {

    func testNewPatchSuccess() async throws {
        let location = FileManager.default.temporaryDirectory.appendingPathComponent("testGistClone")
        try? FileManager.default.removeItem(at: location)
        defer {
          try? FileManager.default.removeItem(at: location)
        }
        let originURL = URL(string: "https://gist.github.com/02bc016ba7908e82a552fba85a0ad50d.git")!
        let repository = try await Repository.clone(from: originURL, to: location)
        guard let commitLists = try? repository.allCommits(revspec: "origin/master") else {
            XCTAssert(false)
            return
        }
        for commit in commitLists {
            print("commit=\(commit.summary)")
            let diffs = try commit.changedDiffs
            for diff in diffs {  
                for (delta, patch) in diff {
                    print("\(delta.status.description) \(delta.oldFile.path) ==> \(delta.newFile.path)")
                    for hunkIndex in 0..<patch.hunkCount {
                        guard let hunk = patch.hunk(at: Int(hunkIndex)) else { break }
                        print("header=\(hunk.header)")
                        for lineIndex in 0..<hunk.lineCount  {
                            guard let line = hunk.line(at: Int(lineIndex)) else { break }
                            print("\(line.oldLineNumber), \(line.newLineNumber), \(line.content)")
                        }
                    }
                }
            }
        }
    }
}
