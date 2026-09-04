import XCTest
@testable import BakoApp

final class AgentCatalogContractTests: XCTestCase {
    func testBundledCatalogMatchesReviewedContractFixture() throws {
        #if SWIFT_PACKAGE
        let fixtureBundle = Bundle.module
        #else
        let fixtureBundle = Bundle(for: AgentCatalogContractTests.self)
        #endif
        let url = try XCTUnwrap(fixtureBundle.url(forResource: "agent-catalog", withExtension: "json"))
        let fixture = try JSONDecoder().decode(CatalogFixture.self, from: Data(contentsOf: url))
        let actual = Dictionary(uniqueKeysWithValues: AgentCatalog.bundled.map { ($0.id, $0) })

        XCTAssertEqual(Set(actual.keys), Set(fixture.agents.map(\.id)))
        for expected in fixture.agents {
            let agent = try XCTUnwrap(actual[expected.id], "缺少 Agent：\(expected.id)")
            XCTAssertEqual(agent.status.rawValue, expected.status, expected.id)
            XCTAssertEqual(agent.detectionPaths, expected.detectionPaths, expected.id)
            XCTAssertEqual(agent.compatibilityEndpointIDs, expected.compatibility, expected.id)
            XCTAssertEqual(agent.nativeEndpoints.count, expected.endpoints.count, expected.id)
            for endpoint in expected.endpoints {
                let actualEndpoint = try XCTUnwrap(agent.nativeEndpoints.first { $0.id == endpoint.id })
                XCTAssertEqual(actualEndpoint.pathTemplate, endpoint.path, expected.id)
                XCTAssertEqual(Set(actualEndpoint.entryKinds.map(\.rawValue)), Set(endpoint.kinds), expected.id)
            }
        }
    }

    func testManagedCatalogContainsOnlyUserLevelEndpoints() {
        for agent in AgentCatalog.bundled where agent.status == .managed {
            XCTAssertFalse(agent.nativeEndpoints.isEmpty, "\(agent.id) 没有可管理端点")
            for endpoint in agent.nativeEndpoints {
                let lowercased = endpoint.pathTemplate.lowercased()
                XCTAssertFalse(lowercased.contains("project"), "\(agent.id) 意外指向项目目录")
                XCTAssertFalse(lowercased.contains("workspace"), "\(agent.id) 意外指向工作区目录")
                XCTAssertTrue(endpoint.pathTemplate.hasPrefix("~") || endpoint.pathTemplate.hasPrefix("${"))
            }
        }
    }

    func testManagedScanTargetsIncludeSharedSkillsDirectoryExactlyOnce() throws {
        let targets = AgentCatalog.managedScanTargets(for: AgentCatalog.bundled)
        let sharedTargets = targets.filter { $0.endpoint.id == AgentCatalog.sharedAgentsEndpoint.id }

        let shared = try XCTUnwrap(sharedTargets.first)
        XCTAssertEqual(sharedTargets.count, 1)
        XCTAssertEqual(shared.endpoint.pathTemplate, "~/.agents/skills")
        XCTAssertNil(shared.originAgentID)
        XCTAssertEqual(shared.groupName, "已导入 · 所有兼容 Agent")
        XCTAssertEqual(shared.groupTarget, .shared("shared-agents"))
    }

    func testManagedScanTargetsKeepNativeAgentOwnership() throws {
        let targets = AgentCatalog.managedScanTargets(for: AgentCatalog.bundled)
        let codex = try XCTUnwrap(targets.first { $0.endpoint.id == "codex-native" })

        XCTAssertEqual(codex.originAgentID, "codex")
        XCTAssertEqual(codex.groupTarget, .agent("codex"))
    }

    func testManagedScanTargetsExcludeDisabledAgentsButKeepSharedEndpoint() {
        let targets = AgentCatalog.managedScanTargets(
            for: AgentCatalog.bundled, excludingAgentIDs: ["codex", "claude"]
        )

        XCTAssertFalse(targets.contains { $0.originAgentID == "codex" })
        XCTAssertFalse(targets.contains { $0.originAgentID == "claude" })
        XCTAssertEqual(
            targets.filter { $0.endpoint.id == AgentCatalog.sharedAgentsEndpoint.id }.count,
            1
        )
    }
}

private struct CatalogFixture: Decodable {
    struct Agent: Decodable {
        struct Endpoint: Decodable {
            let id: String
            let path: String
            let kinds: [String]
        }
        let id: String
        let status: String
        let detectionPaths: [String]
        let endpoints: [Endpoint]
        let compatibility: [String]
    }
    let agents: [Agent]
}
