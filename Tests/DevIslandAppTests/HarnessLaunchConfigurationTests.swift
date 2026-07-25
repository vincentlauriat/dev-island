import Foundation
import Testing
@testable import DevIslandApp

struct HarnessLaunchConfigurationTests {
    @Test
    func defaultsMatchNormalAppLaunch() {
        let configuration = HarnessLaunchConfiguration(environment: [:])

        #expect(configuration.scenario == nil)
        #expect(!configuration.presentOverlay)
        #expect(configuration.shouldStartBridge)
        #expect(configuration.shouldPerformBootAnimation)
        #expect(configuration.captureDelay == nil)
        #expect(configuration.autoExitAfter == nil)
        #expect(configuration.artifactDirectoryURL == nil)
    }

    @Test
    func parsesScenarioFlagsAndAutoExit() {
        let configuration = HarnessLaunchConfiguration(
            environment: [
                "DEV_ISLAND_HARNESS_SCENARIO": "approvalcard",
                "DEV_ISLAND_HARNESS_PRESENT_OVERLAY": "true",
                "DEV_ISLAND_HARNESS_START_BRIDGE": "no",
                "DEV_ISLAND_HARNESS_BOOT_ANIMATION": "off",
                "DEV_ISLAND_HARNESS_CAPTURE_DELAY_SECONDS": "1.5",
                "DEV_ISLAND_HARNESS_AUTO_EXIT_SECONDS": "2.5",
                "DEV_ISLAND_HARNESS_ARTIFACT_DIR": "/tmp/dev-island-artifacts",
            ]
        )

        #expect(configuration.scenario == .approvalCard)
        #expect(configuration.presentOverlay)
        #expect(!configuration.shouldStartBridge)
        #expect(!configuration.shouldPerformBootAnimation)
        #expect(configuration.captureDelay == 1.5)
        #expect(configuration.autoExitAfter == 2.5)
        #expect(configuration.artifactDirectoryURL?.path == "/tmp/dev-island-artifacts")
    }

    @Test
    func ignoresInvalidInputs() {
        let configuration = HarnessLaunchConfiguration(
            environment: [
                "DEV_ISLAND_HARNESS_SCENARIO": "missing",
                "DEV_ISLAND_HARNESS_PRESENT_OVERLAY": "unexpected",
                "DEV_ISLAND_HARNESS_CAPTURE_DELAY_SECONDS": "0",
                "DEV_ISLAND_HARNESS_AUTO_EXIT_SECONDS": "-1",
                "DEV_ISLAND_HARNESS_ARTIFACT_DIR": "   ",
            ]
        )

        #expect(configuration.scenario == nil)
        #expect(!configuration.presentOverlay)
        #expect(configuration.captureDelay == nil)
        #expect(configuration.autoExitAfter == nil)
        #expect(configuration.artifactDirectoryURL == nil)
    }
}
