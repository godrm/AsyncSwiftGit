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
        var originURL = URL(string: "https://gist.github.com/02bc016ba7908e82a552fba85a0ad50d.git")!
        let repository = try await Repository.clone(from: originURL, to: location)
        guard let commitLists = try? await repository.allCommits(revspec: "origin/master") else {
            XCTAssert(false)
            return
        }
        for commit in commitLists {
            for patch in try commit.changedPatches {
                let description = String(data: patch.patchData(), encoding: .utf8) ?? ""
                print(description)
            }
        }
    }
}
