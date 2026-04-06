//
//  MiraTests.swift
//  MiraTests
//
//  Created by Ang Wei on 3/3/26.
//

import MiraBridge
import Testing
@testable import Mira

struct MiraTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }

    @Test func discussionItemsAllowReplyButFeedsDoNot() async throws {
        let discussion = MiraItem(
            id: "disc_1",
            type: .discussion,
            title: "Discussion",
            status: .needsInput,
            tags: [],
            origin: .agent,
            pinned: false,
            quick: false,
            createdAt: "2026-04-06T22:00:00Z",
            updatedAt: "2026-04-06T22:00:00Z",
            messages: []
        )
        let feed = MiraItem(
            id: "feed_1",
            type: .feed,
            title: "Feed",
            status: .done,
            tags: [],
            origin: .agent,
            pinned: false,
            quick: false,
            createdAt: "2026-04-06T22:00:00Z",
            updatedAt: "2026-04-06T22:00:00Z",
            messages: []
        )

        #expect(discussion.allowsReply)
        #expect(!feed.allowsReply)
    }

}
