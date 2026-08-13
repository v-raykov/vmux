import CmuxPanes
import Foundation

/// Why a pane-sizing command did nothing, for callers that report failure.
enum PaneSizingRejection: Error, Equatable {
    case noWorkspace
    case unsupportedLayout
    case zoomed
    case noFocusedPane
    case noMatchingSplit
}

/// A pane-sizing command's outcome.
enum PaneSizingOutcome: Equatable {
    case resized
    case rejected(PaneSizingRejection)

    var didApply: Bool {
        switch self {
        case .resized:
            return true
        case .rejected:
            return false
        }
    }
}

extension TabManager {
    /// Equalize splits - not directly supported by bonsplit.
    func equalizeSplits(tabId: UUID) -> Bool {
        guard let tab = tabs.first(where: { $0.id == tabId }) else { return false }

        let result = equalizeSplitsOnce(in: tab)
        if result.foundSplit {
            tab.didProgrammaticallyChangeSplitGeometry()
        }
        return result.didFullyEqualize
    }

    @discardableResult
    private func equalizeSplitsOnce(in tab: Workspace) -> SplitEqualizeResult {
        paneLayout.equalizeSplits(
            in: tab.bonsplitController.treeSnapshot(),
            controller: tab.bonsplitController
        )
    }

    /// Moves the focused pane's boundary in `direction` by `amountPixels`.
    @discardableResult
    func resizeFocusedPane(direction: ResizeDirection, amountPixels: UInt16) -> PaneSizingOutcome {
        switch focusedPaneSizingTarget() {
        case .failure(let rejection):
            return .rejected(rejection)
        case .success(let target):
            let applied = paneLayout.resizeSplit(
                in: target.workspace.bonsplitController.treeSnapshot(),
                targetPaneId: target.paneId.uuidString,
                direction: direction,
                amountPixels: amountPixels,
                controller: target.workspace.bonsplitController
            )
            guard applied else { return .rejected(.noMatchingSplit) }
            target.workspace.didProgrammaticallyChangeSplitGeometry()
            return .resized
        }
    }

    private struct PaneSizingTarget {
        let workspace: Workspace
        let paneId: UUID
    }

    /// Resolves the pane a sizing command should act on.
    ///
    /// The split controller's focused pane is consulted first: arrow-key pane
    /// navigation moves that focus even when the destination pane cannot take
    /// panel focus, so keying off the focused panel alone would leave the
    /// command acting on the pane the user just navigated away from.
    private func focusedPaneSizingTarget() -> Result<PaneSizingTarget, PaneSizingRejection> {
        guard let workspace = selectedWorkspace else { return .failure(.noWorkspace) }
        guard workspace.layoutMode != .canvas, !workspace.isRemoteTmuxMirror else {
            return .failure(.unsupportedLayout)
        }
        guard !workspace.bonsplitController.isSplitZoomed else { return .failure(.zoomed) }

        if let focusedPane = workspace.bonsplitController.focusedPaneId {
            return .success(PaneSizingTarget(workspace: workspace, paneId: focusedPane.id))
        }
        guard let panelId = workspace.focusedPanelId,
              let paneId = workspace.paneId(forPanelId: panelId) else {
            return .failure(.noFocusedPane)
        }
        return .success(PaneSizingTarget(workspace: workspace, paneId: paneId.id))
    }
}
