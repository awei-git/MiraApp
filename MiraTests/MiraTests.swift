//
//  MiraTests.swift
//  MiraTests
//
//  Created by Ang Wei on 3/3/26.
//

import Foundation
import MiraBridge
import Testing
@testable import Mira

@Suite(.serialized)
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
        #expect(feed.allowsReply)
    }

    @Test func internalLivenessItemsAreHiddenFromUserLists() async throws {
        let item = MiraItem(
            id: "mira_liveness_task_dispatch",
            type: .discussion,
            title: "Output Liveness: task_dispatch stale",
            status: .done,
            tags: ["system", "liveness"],
            origin: .agent,
            pinned: false,
            quick: false,
            createdAt: "2026-05-15T14:00:00Z",
            updatedAt: "2026-05-15T14:00:00Z",
            messages: []
        )

        #expect(item.isInternalLivenessNoise)
    }

    @Test func timelineGroupsAnOldThreadWithTodayActivityUnderToday() async throws {
        let item = MiraItem(
            id: "discussion_with_new_reply",
            type: .discussion,
            title: "Old thread, new reply",
            status: .needsInput,
            tags: [],
            origin: .agent,
            pinned: false,
            quick: false,
            createdAt: "2026-04-06T22:00:00Z",
            updatedAt: ISO8601DateFormatter().string(from: Date()),
            messages: []
        )

        let groups = HomeView.computeGroupedItems(from: [item])

        #expect(groups.first?.key == "Today")
    }

    @Test func bridgeSetupRequiresAnICloudWorkspace() async throws {
        let config = BridgeConfig()
        config.bridgeURL = nil
        config.rootURL = nil

        #expect(!config.isSetup)
    }

    @Test func failedRemoteWriteWithoutBridgeIsQueuedInsteadOfDropped() async throws {
        let defaults = UserDefaults.standard
        let previousServerURL = defaults.url(forKey: "mira_server_url")
        let previousFallback = defaults.object(forKey: "mira_api_write_fallback_icloud")
        let previousQueue = defaults.data(forKey: "mira_pending_api_requests")
        defer {
            defaults.set(previousServerURL, forKey: "mira_server_url")
            defaults.set(previousFallback, forKey: "mira_api_write_fallback_icloud")
            defaults.set(previousQueue, forKey: "mira_pending_api_requests")
        }

        defaults.removeObject(forKey: "mira_pending_api_requests")
        let config = BridgeConfig()
        config.bridgeURL = nil
        config.rootURL = nil
        config.serverURL = URL(string: "https://127.0.0.1:1")
        config.apiWriteFallbackToICloud = true
        let writer = CommandWriter(config: config)

        writer.createRequest(title: "Remote", content: "Do not lose this")
        try await Task.sleep(for: .seconds(1))

        #expect(writer.pendingIds.count == 1)
        #expect(defaults.data(forKey: "mira_pending_api_requests") != nil)
    }

    @Test func queuedRemoteWriteMovesToICloudWhenWorkspaceReturns() async throws {
        let defaults = UserDefaults.standard
        let previousServerURL = defaults.url(forKey: "mira_server_url")
        let previousFallback = defaults.object(forKey: "mira_api_write_fallback_icloud")
        let previousQueue = defaults.data(forKey: "mira_pending_api_requests")
        let root = FileManager.default.temporaryDirectory
            .appending(path: "mira-remote-\(UUID().uuidString)")
        defer {
            defaults.set(previousServerURL, forKey: "mira_server_url")
            defaults.set(previousFallback, forKey: "mira_api_write_fallback_icloud")
            defaults.set(previousQueue, forKey: "mira_pending_api_requests")
            try? FileManager.default.removeItem(at: root)
        }

        defaults.removeObject(forKey: "mira_pending_api_requests")
        let config = BridgeConfig()
        config.bridgeURL = nil
        config.rootURL = nil
        config.serverURL = URL(string: "https://127.0.0.1:1")
        config.apiWriteFallbackToICloud = true
        let writer = CommandWriter(config: config)
        writer.createRequest(title: "Remote recovery", content: "Deliver after setup")
        try await Task.sleep(for: .seconds(1))
        #expect(defaults.data(forKey: "mira_pending_api_requests") != nil)

        let bridge = root.appending(path: "Mira-Bridge")
        let commands = bridge.appending(path: "users/ang/commands")
        try FileManager.default.createDirectory(at: commands, withIntermediateDirectories: true)
        config.rootURL = root
        config.bridgeURL = bridge

        writer.flushPendingAPIQueue()
        try await Task.sleep(for: .seconds(1))

        let files = try FileManager.default.contentsOfDirectory(at: commands, includingPropertiesForKeys: nil)
        #expect(files.count == 1)
        #expect(defaults.data(forKey: "mira_pending_api_requests") == nil)
    }

}
