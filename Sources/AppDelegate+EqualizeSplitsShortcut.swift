import AppKit
import CmuxPanes

extension AppDelegate {
    /// Points a single keyboard resize step moves a pane boundary.
    private static let paneResizeStepPixels: UInt16 = 40

    static let paneResizeShortcutDirections: [(KeyboardShortcutSettings.Action, ResizeDirection)] = [
        (.resizePaneLeft, .left),
        (.resizePaneRight, .right),
        (.resizePaneUp, .up),
        (.resizePaneDown, .down),
    ]

    /// Moves the focused pane's boundary one step in `direction`.
    func performPaneResizeShortcut(direction: ResizeDirection) {
        performPaneSizingShortcut(name: "resizePane") { manager in
            manager.resizeFocusedPane(
                direction: direction,
                amountPixels: Self.paneResizeStepPixels
            )
        }
    }

    private func performPaneSizingShortcut(
        name: String,
        _ command: (TabManager) -> PaneSizingOutcome
    ) {
        guard let tabManager, tabManager.selectedWorkspace != nil else {
            NSSound.beep()
            return
        }
        if shouldSuppressSplitShortcutForTransientTerminalFocusState(tabManager: tabManager) {
            return
        }
        let outcome = command(tabManager)
        if !outcome.didApply {
            NSSound.beep()
        }
#if DEBUG
        cmuxDebugLog("shortcut.action name=\(name) result=\(outcome)")
#endif
    }

    func performEqualizeSplitsShortcut() {
        guard let tabManager, let workspace = tabManager.selectedWorkspace else {
#if DEBUG
            cmuxDebugLog("shortcut.action name=equalizeSplits result=noWorkspace")
#endif
            return
        }
#if DEBUG
        cmuxDebugLog("shortcut.action name=equalizeSplits workspaceId=\(workspace.id)")
#endif
        if workspace.layoutMode == .canvas {
            let executor = CanvasActionExecutor(workspace: workspace)
            let didEqualizeWidths = executor.perform(.alignment(.equalizeWidths))
            let didEqualizeHeights = executor.perform(.alignment(.equalizeHeights))
#if DEBUG
            if !didEqualizeWidths && !didEqualizeHeights {
                cmuxDebugLog("shortcut.action name=equalizeSplits result=noCanvasChange workspaceId=\(workspace.id)")
            }
#endif
            return
        }
        if shouldSuppressSplitShortcutForTransientTerminalFocusState(tabManager: tabManager) {
            return
        }
        let didEqualize = tabManager.equalizeSplits(tabId: workspace.id)
#if DEBUG
        if !didEqualize {
            cmuxDebugLog("shortcut.action name=equalizeSplits result=noSplitOrFailed workspaceId=\(workspace.id)")
        }
#endif
    }
}
