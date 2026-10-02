@testable import GhosttyTerminal
import Testing

/// A rebuilt surface starts at the configured font size, so the UIKit pinch
/// counter resets from `onSurfaceRebuild`. It must fire for every rebuild,
/// not only for a changed `fontSize`.
@Suite("TerminalSurfaceRebuildHook", .serialized)
struct TerminalSurfaceRebuildHookTests {
    @Test
    @MainActor
    func `every rebuild reports itself`() async {
        let harness = await GhosttySurfaceHarness.make()
        defer { harness.tearDown() }
        let coordinator = harness.coordinator
        var rebuilds = 0
        coordinator.onSurfaceRebuild = { rebuilds += 1 }

        coordinator.controller = TerminalController()
        #expect(rebuilds == 1)

        coordinator.configuration.workingDirectory = "/tmp"
        #expect(rebuilds == 2)

        coordinator.viewSize = { (0, 0) }
        coordinator.configuration.workingDirectory = "/"
        #expect(coordinator.testHooks_pendingRebuild)
        #expect(rebuilds == 2)
        coordinator.viewSize = { (800, 500) }
        coordinator.synchronizeMetrics()
        #expect(rebuilds == 3)
        #expect(coordinator.surface != nil)
    }

    @Test
    @MainActor
    func `an equivalent configuration does not rebuild`() async {
        let harness = await GhosttySurfaceHarness.make()
        defer { harness.tearDown() }
        let coordinator = harness.coordinator
        var rebuilds = 0
        coordinator.onSurfaceRebuild = { rebuilds += 1 }

        let unchanged = coordinator.configuration
        coordinator.configuration = unchanged
        coordinator.synchronizeMetrics()

        #expect(rebuilds == 0)
    }
}
