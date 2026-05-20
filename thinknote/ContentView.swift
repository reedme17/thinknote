//
//  ContentView.swift
//  thinknote
//
//  Created by 严汀 on 4/5/26.
//

import Combine
import SwiftUI
import UIKit

private let noteTransitionAnimation = Animation.timingCurve(0.2, 0.9, 0.1, 1.0, duration: 0.55)
private let noteMorphDuration: Double = 0.55
private let trashLabelText = "TRASH CAN"
private let detailDismissTopThreshold: CGFloat = 0.5
private let detailDismissCornerRadiusStart: CGFloat = 42
private let detailDismissCornerRadiusTravel: CGFloat = 96
private let detailPrimaryScrollAnchorID = "thought-label"
private let reorderScrollableDragHoldDuration: Double = 0.2
private let reorderHoverDwellDuration: TimeInterval = 0.59
private let reorderHoverJitterTolerance: CGFloat = 14
private let reorderGapActivationDistance: CGFloat = 42
private let reorderMinimumTravelDistance: CGFloat = 12
private let ungroupMinimumTravelDistance: CGFloat = 1
private let groupingOverlapThreshold: CGFloat = 0.6
private let ungroupingOverlapThreshold: CGFloat = 0.5
private let reorderExitSwipeMinimumDistance: CGFloat = 22
private let reorderExitSwipeMaximumHorizontalDrift: CGFloat = 88
private let noteAccentColor = Color(red: 0.53, green: 0.66, blue: 0.61)
private let noteBorderColor = Color(red: 0.88, green: 0.88, blue: 0.86)
private let noteShadowColor = Color.black.opacity(0.08)
private let noteSurfaceColor = Color(red: 0.992, green: 0.988, blue: 0.975)
private let debugDisableNoteSurfaceTransition = false
private let debugLogNoteTapFlow = false
let isRunningInPreviews = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"

func debugNoteLog(_ items: Any...) {
#if DEBUG
    guard debugLogNoteTapFlow else { return }
    print("[ThinknoteDebug]", items.map { String(describing: $0) }.joined(separator: " "))
#endif
}

private func noteDayPeriodLabel(for date: Date, calendar: Calendar = .current) -> String {
    let hour = calendar.component(.hour, from: date)

    switch hour {
    case 5..<12:
        return "morning"
    case 12..<18:
        return "afternoon"
    case 18..<24:
        return "evening"
    default:
        return "midnight"
    }
}

private func noteCardTimestampLabel(for date: Date, referenceDate: Date = Date(), calendar: Calendar = .current) -> String {
    if calendar.isDateInToday(date) {
        return "today"
    }

    let dayPeriod = noteDayPeriodLabel(for: date, calendar: calendar)

    if calendar.isDateInYesterday(date) {
        return "yesterday \(dayPeriod)"
    }

    let components = calendar.dateComponents([.year, .month, .day], from: date)
    guard let year = components.year,
          let month = components.month,
          let day = components.day else {
        return "today"
    }

    if year == calendar.component(.year, from: referenceDate) {
        return "\(month)/\(day) \(dayPeriod)"
    }

    return "\(year)/\(month)/\(day) \(dayPeriod)"
}

private func noteDetailTimestampLabel(for date: Date, referenceDate: Date = Date(), calendar: Calendar = .current) -> String {
    let shortLabel: String
    if calendar.isDateInToday(date) {
        shortLabel = "today"
    } else if calendar.isDateInYesterday(date) {
        shortLabel = "yesterday"
    } else {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year,
              let month = components.month,
              let day = components.day else {
            return "thought today \(date.formatted(date: .omitted, time: .shortened).lowercased())"
        }

        if year == calendar.component(.year, from: referenceDate) {
            shortLabel = "\(month)/\(day)"
        } else {
            shortLabel = "\(year)/\(month)/\(day)"
        }
    }

    let timeLabel = date.formatted(date: .omitted, time: .shortened).lowercased()

    if calendar.isDateInToday(date) || calendar.isDateInYesterday(date) {
        return "thought \(shortLabel) \(timeLabel)"
    }

    return "thought on \(shortLabel) \(timeLabel)"
}

private let noteCardHorizontalPadding: CGFloat = 18
private let noteCardVerticalPadding: CGFloat = 18
private let noteCardBodySpacing: CGFloat = 14
private let noteCardSummaryFontSize: CGFloat = 18
private let noteCardSummaryLineSpacing: CGFloat = 2
private let noteCardSummaryMaxLines = 5
private let noteCardMetaFontSize: CGFloat = 10

private func fallbackHomeColumnWidth() -> CGFloat {
    max((currentUIScreenBounds().width - 52) * 0.5, 0)
}

private func currentUIScreenBounds() -> CGRect {
    UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .map(\.screen.bounds)
        .first ?? CGRect(x: 0, y: 0, width: 390, height: 844)
}

private func noteCardContentWidth(for columnWidth: CGFloat) -> CGFloat {
    max(columnWidth - noteCardHorizontalPadding * 2, 0)
}

private func noteCardSummaryUIFont() -> UIFont {
    UIFont(name: "DavidLibre-Regular", size: noteCardSummaryFontSize)
    ?? UIFont.systemFont(ofSize: noteCardSummaryFontSize)
}

private func noteCardMetaUIFont() -> UIFont {
    UIFont(name: "GeistMono-Regular", size: noteCardMetaFontSize)
    ?? UIFont.monospacedSystemFont(ofSize: noteCardMetaFontSize, weight: .regular)
}

private func noteCardMetaLineHeight() -> CGFloat {
    ceil(noteCardMetaUIFont().lineHeight)
}

private func measuredHeadlineHeight(for note: APINote, columnWidth: CGFloat = fallbackHomeColumnWidth()) -> CGFloat {
    let font = noteCardSummaryUIFont()
    let availableWidth = noteCardContentWidth(for: columnWidth)
    guard availableWidth > 0 else { return ceil(font.lineHeight) }

    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.lineBreakMode = .byWordWrapping
    paragraphStyle.lineSpacing = noteCardSummaryLineSpacing

    let boundingRect = NSAttributedString(
        string: note.displayHeadline,
        attributes: [
            .font: font,
            .paragraphStyle: paragraphStyle
        ]
    )
    .boundingRect(
        with: CGSize(width: availableWidth, height: .greatestFiniteMagnitude),
        options: [.usesLineFragmentOrigin, .usesFontLeading],
        context: nil
    )

    let oneLineHeight = ceil(font.lineHeight)
    let maxHeight = ceil(
        CGFloat(noteCardSummaryMaxLines) * font.lineHeight
        + CGFloat(max(noteCardSummaryMaxLines - 1, 0)) * noteCardSummaryLineSpacing
    )

    return min(max(ceil(boundingRect.height), oneLineHeight), maxHeight)
}

private func measuredHeadlineLineCount(for note: APINote, columnWidth: CGFloat = fallbackHomeColumnWidth()) -> Int {
    let lineAdvance = noteCardSummaryUIFont().lineHeight + noteCardSummaryLineSpacing
    guard lineAdvance > 0 else { return 1 }
    let estimatedLines = Int(ceil((measuredHeadlineHeight(for: note, columnWidth: columnWidth) + noteCardSummaryLineSpacing) / lineAdvance))
    return min(max(estimatedLines, 1), noteCardSummaryMaxLines)
}

private func estimatedHomeNoteCardHeight(for note: APINote, columnWidth: CGFloat = fallbackHomeColumnWidth()) -> CGFloat {
    let summaryHeight = measuredHeadlineHeight(for: note, columnWidth: columnWidth)
    let metaHeight = ceil(noteCardMetaUIFont().lineHeight)
    return noteCardVerticalPadding * 2 + summaryHeight + noteCardBodySpacing + metaHeight
}

private let clusterReadableTopInset: CGFloat = 18
private let clusterReadableLineAdvance: CGFloat = 24
private let clusterVisibleBottomGap: CGFloat = 0
private let clusterAlternatingOffset: CGFloat = 4

private struct ClusterStackSlot {
    let note: APINote
    let isPlaceholder: Bool
    let originalIndex: Int?
    let topOffset: CGFloat

    var id: String {
        isPlaceholder ? "placeholder-\(note.id)" : note.id
    }
}

private func stackedClusterSlots(
    notes: [APINote],
    columnWidth: CGFloat = fallbackHomeColumnWidth(),
    previewPlaceholderNote: APINote? = nil,
    previewPlaceholderIndex: Int? = nil
) -> [ClusterStackSlot] {
    let clampedPlaceholderIndex = previewPlaceholderIndex.map { max(0, min($0, notes.count)) }
    let totalSlots = notes.count + (previewPlaceholderNote != nil ? 1 : 0)
    var slots: [ClusterStackSlot] = []
    var currentTop: CGFloat = 0
    var noteCursor = 0

    for slotIndex in 0..<totalSlots {
        if let placeholderNote = previewPlaceholderNote,
           let clampedPlaceholderIndex,
           slotIndex == clampedPlaceholderIndex {
            slots.append(
                ClusterStackSlot(
                    note: placeholderNote,
                    isPlaceholder: true,
                    originalIndex: nil,
                    topOffset: currentTop
                )
            )
            currentTop += stackedClusterVisibleStep(for: placeholderNote, columnWidth: columnWidth)
            continue
        }

        guard notes.indices.contains(noteCursor) else { continue }
        let note = notes[noteCursor]
        slots.append(
            ClusterStackSlot(
                note: note,
                isPlaceholder: false,
                originalIndex: noteCursor,
                topOffset: currentTop
            )
        )
        currentTop += stackedClusterVisibleStep(for: note, columnWidth: columnWidth)
        noteCursor += 1
    }

    return slots
}

private func stackedClusterVisibleStep(for note: APINote, columnWidth: CGFloat = fallbackHomeColumnWidth()) -> CGFloat {
    clusterReadableTopInset
        + CGFloat(measuredHeadlineLineCount(for: note, columnWidth: columnWidth)) * clusterReadableLineAdvance
        + clusterVisibleBottomGap
}

private func stackedClusterTopOffset(
    notes: [APINote],
    index: Int,
    columnWidth: CGFloat = fallbackHomeColumnWidth(),
    previewPlaceholderNote: APINote? = nil,
    previewPlaceholderIndex: Int? = nil
) -> CGFloat {
    let slots = stackedClusterSlots(
        notes: notes,
        columnWidth: columnWidth,
        previewPlaceholderNote: previewPlaceholderNote,
        previewPlaceholderIndex: previewPlaceholderIndex
    )
    return slots.first(where: { !$0.isPlaceholder && $0.originalIndex == index })?.topOffset ?? 0
}

private func stackedClusterBottomPadding(
    for notes: [APINote],
    columnWidth: CGFloat = fallbackHomeColumnWidth(),
    previewPlaceholderNote: APINote? = nil,
    previewPlaceholderIndex: Int? = nil
) -> CGFloat {
    let slots = stackedClusterSlots(
        notes: notes,
        columnWidth: columnWidth,
        previewPlaceholderNote: previewPlaceholderNote,
        previewPlaceholderIndex: previewPlaceholderIndex
    )
    guard !slots.isEmpty else { return 0 }

    let tallestCard = slots.map { estimatedHomeNoteCardHeight(for: $0.note, columnWidth: columnWidth) }.max() ?? 0
    let lowestBottom = slots.reduce(CGFloat.zero) { partialResult, slot in
        let candidateBottom = slot.topOffset
            + estimatedHomeNoteCardHeight(for: slot.note, columnWidth: columnWidth)
        return max(partialResult, candidateBottom)
    }

    return max(lowestBottom - tallestCard, 0)
}

private func estimatedStackedClusterHeight(
    for notes: [APINote],
    columnWidth: CGFloat = fallbackHomeColumnWidth(),
    previewPlaceholderNote: APINote? = nil,
    previewPlaceholderIndex: Int? = nil
) -> CGFloat {
    let slots = stackedClusterSlots(
        notes: notes,
        columnWidth: columnWidth,
        previewPlaceholderNote: previewPlaceholderNote,
        previewPlaceholderIndex: previewPlaceholderIndex
    )
    guard !slots.isEmpty else { return 0 }
    let maxHeight = slots.map { estimatedHomeNoteCardHeight(for: $0.note, columnWidth: columnWidth) }.max() ?? 0
    return maxHeight + stackedClusterBottomPadding(
        for: notes,
        columnWidth: columnWidth,
        previewPlaceholderNote: previewPlaceholderNote,
        previewPlaceholderIndex: previewPlaceholderIndex
    )
}

private func overlapRatio(of sourceFrame: CGRect, covering targetFrame: CGRect) -> CGFloat {
    let intersection = sourceFrame.intersection(targetFrame)
    guard !intersection.isNull else { return 0 }
    let overlapArea = intersection.width * intersection.height
    let targetArea = max(targetFrame.width * targetFrame.height, 1)
    return overlapArea / targetArea
}

private func overlapRatios(between lhs: CGRect, and rhs: CGRect) -> (lhs: CGFloat, rhs: CGFloat) {
    (
        lhs: overlapRatio(of: rhs, covering: lhs),
        rhs: overlapRatio(of: lhs, covering: rhs)
    )
}

private func overlapActivationRatio(between lhs: CGRect, and rhs: CGRect) -> CGFloat {
    let ratios = overlapRatios(between: lhs, and: rhs)
    return max(ratios.lhs, ratios.rhs)
}

private struct GlassCapsuleButtonChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    Capsule()
                        .fill(Color.white.opacity(0.78))

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.74),
                                    noteSurfaceColor.opacity(0.94)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
            }
            .overlay {
                Capsule()
                    .stroke(Color.white.opacity(0.88), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.028), radius: 8, x: 0, y: 5)
    }
}

private struct GlassCircleButtonChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.78))

                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.74),
                                    noteSurfaceColor.opacity(0.94)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
            }
            .overlay {
                Circle()
                    .stroke(Color.white.opacity(0.84), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.03), radius: 10, x: 0, y: 6)
    }
}

private extension View {
    func glassCapsuleButtonChrome() -> some View {
        modifier(GlassCapsuleButtonChrome())
    }

    func glassCircleButtonChrome() -> some View {
        modifier(GlassCircleButtonChrome())
    }
}

private enum AppFont {
    static func heading(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("Fraunces72pt-Regular", size: size)
    }

    static func body(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("DavidLibre-Regular", size: size)
    }

    static func meta(_ size: CGFloat) -> Font {
        .custom("GeistMono-Regular", size: size)
    }
}

@MainActor
struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel: ContentViewModel
    @State private var isAssistantPresented = false
    private let shouldBootstrap: Bool
    @Namespace private var noteTransitionNamespace
    @Namespace private var newThoughtNamespace

    init() {
        _viewModel = StateObject(wrappedValue: ContentViewModel())
        self.shouldBootstrap = true
    }

    init(viewModel: ContentViewModel, shouldBootstrap: Bool) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.shouldBootstrap = shouldBootstrap
    }

    var body: some View {
        ZStack {
            HomeScreen(
                state: homeState,
                transitionNamespace: noteTransitionNamespace,
                newThoughtNamespace: newThoughtNamespace,
                onOpenNote: { noteID in
                    viewModel.openNote(noteID: noteID)
                },
                onOpenNewNote: {
                    viewModel.openNewNote()
                },
                onPersistManualOrder: { noteIDs in
                    await viewModel.persistManualOrder(noteIDs)
                },
                onDeleteNote: { noteID in
                    await viewModel.deleteNote(noteID: noteID)
                },
                onShowAssistant: {
                    isAssistantPresented = true
                }
            )
            .equatable()
            .blur(radius: viewModel.screen == .newNote ? 12 : 0)
            .overlay {
                if viewModel.screen == .newNote {
                    Color.white.opacity(0.025)
                        .ignoresSafeArea()
                }
            }
            .allowsHitTesting(viewModel.screen == .home)
            .zIndex(0)

            if viewModel.screen == .newNote {
                NewNoteScreen(viewModel: viewModel, transitionNamespace: newThoughtNamespace)
                    .zIndex(1)
            }

            if let note = activeDetailNote {
                NoteFullPageScreen(
                    viewModel: viewModel,
                    note: note,
                    transitionNamespace: noteTransitionNamespace
                )
                .zIndex(2)
            }

            if let error = viewModel.activeError {
                VStack {
                    Spacer()

                    HStack(alignment: .center, spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(error.title)
                                .font(AppFont.meta(11))
                                .tracking(1.2)
                                .textCase(.uppercase)
                                .foregroundStyle(.black.opacity(0.68))

                            Text(error.message)
                                .font(AppFont.body(15))
                                .foregroundStyle(.black.opacity(0.82))
                        }

                        Spacer(minLength: 0)

                        if let actionTitle = error.actionTitle, error.action != nil {
                            Button(actionTitle) {
                                Task { await viewModel.performErrorAction() }
                            }
                            .font(AppFont.meta(11))
                            .tracking(1.2)
                            .foregroundStyle(noteAccentColor)
                            .buttonStyle(.plain)
                        }

                        Button("close") {
                            viewModel.dismissError()
                        }
                        .font(AppFont.meta(11))
                        .tracking(1.2)
                        .foregroundStyle(.black.opacity(0.5))
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(noteBorderColor.opacity(0.92), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.06), radius: 14, x: 0, y: 8)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 20)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(3)
            }
        }
        .sheet(isPresented: $isAssistantPresented) {
            AssistantSheet(viewModel: viewModel)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .task {
            guard shouldBootstrap else { return }
            await viewModel.bootstrap()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard shouldBootstrap, newPhase == .active else { return }
            Task {
                await viewModel.refreshForForeground()
            }
        }
    }

    private var homeState: HomeScreenState {
        HomeScreenState(
            notes: viewModel.notes,
            isPresentingNewNote: viewModel.screen == .newNote,
            expandedNoteID: activeDetailNote?.id,
            addMorphTargetNoteID: viewModel.addMorphTargetNoteID
        )
    }

    private var activeDetailNote: APINote? {
        guard case .detail(let noteID) = viewModel.screen else {
            debugNoteLog("activeDetailNote", "screen is not detail")
            return nil
        }

        let note = viewModel.note(for: noteID)
        debugNoteLog("activeDetailNote", "lookup", noteID, "found:", note != nil)
        return note
    }
}

private struct HomeScreenState: Equatable {
    let notes: [APINote]
    let isPresentingNewNote: Bool
    let expandedNoteID: String?
    let addMorphTargetNoteID: String?

    var isFeedVisible: Bool {
        expandedNoteID == nil && !isPresentingNewNote
    }
}

private struct HomeScreen: View {
    let state: HomeScreenState
    let transitionNamespace: Namespace.ID
    let newThoughtNamespace: Namespace.ID
    let onOpenNote: (String) -> Void
    let onOpenNewNote: () -> Void
    let onPersistManualOrder: ([String]) async -> Void
    let onDeleteNote: (String) async -> Bool
    let onShowAssistant: () -> Void
    @State private var orderedNoteIDs: [String] = []
    @State private var affinityGroups: [AffinityGroup] = []
    @State private var activeDragNoteID: String?
    @State private var isReorderMode = false
    @State private var dragTranslation: CGSize = .zero
    @State private var dragScaleAnchor: UnitPoint = .center
    @State private var dragTouchPointGlobal: CGPoint?
    @State private var noteFrames: [String: CGRect] = [:]
    @State private var noteHitFrames: [String: CGRect] = [:]
    @State private var noteTapTargets: [String: NoteTapTarget] = [:]
    @State private var measuredItemHeights: [String: CGFloat] = [:]
    @State private var hoverCandidate: HoverCandidate?
    @State private var activePreviewIntent: HoverIntent?
    @State private var jiggleProgress: CGFloat = 0
    @State private var homeContentHeight: CGFloat = 0
    @State private var homeDragOffset: CGFloat = 0
    @State private var homeScrollOffsetBaseline: CGFloat?
    @State private var frozenAnimationDate = Date()
    @State private var dragBaseOrder: [String] = []
    @State private var dragBaseAffinityGroups: [AffinityGroup] = []
    @State private var columnLayout = ColumnLayout()
    @State private var dragBaseColumnLayout = ColumnLayout()
    @State private var groupPreviewPlaceholder: GroupPreviewPlaceholder?
    @State private var dragStartFrame: CGRect? = nil
    @State private var isDroppingDraggedNote = false
    @State private var suppressedNoteOutlineIDs = Set<String>()
    @State private var suppressedNoteContentIDs = Set<String>()
    @State private var isSeedDecorationReady = true
    @State private var isSeedContentReady = true
    @State private var pendingOutlineRevealTask: Task<Void, Never>?
    @State private var pendingContentRevealTask: Task<Void, Never>?
    @State private var pendingSeedRevealTask: Task<Void, Never>?
    @State private var pendingExpandedCardZResetTask: Task<Void, Never>?
    @State private var elevatedTransitionNoteID: String?
    @State private var homeHeaderFrame: CGRect = .null
    @State private var trashTargetFrame: CGRect = .null
    @State private var frozenTrashTargetTopInset: CGFloat?
    @State private var deletePreviewProgress: CGFloat = 0
    @State private var isDeleteCommitReady = false
    @State private var deletingNoteID: String?
    @State private var deletingNoteSnapshot: APINote?
    @State private var pendingDeleteNoteID: String?
    @State private var isDeleteConfirmationPresented = false
    @State private var isDeleteConfirmationBusy = false

    var body: some View {
        GeometryReader { geometry in
            let homeTopPadding: CGFloat = 20
            let homeBottomPadding: CGFloat = isReorderMode ? 170 : 120
            let requiresDragHoldBeforeDragging = true
            let isScrollLockedForActiveDrag = isReorderMode && activeDragNoteID != nil
            let homeModalBlurRadius: CGFloat = isDeleteConfirmationPresented ? 12 : 0
            let homeHeaderHeight = homeHeaderFrame.isNull ? 14 : homeHeaderFrame.height
            let homeHeaderReserveHeight = homeHeaderHeight + 18
            let homeHeaderDisplacement = max(homeDragOffset, 0)
            let homeHeaderBlurProgress = min(max((homeHeaderDisplacement - 8) / 36, 0), 1)
            let homeHeaderFadeProgress = min(max((homeHeaderDisplacement - 22) / 24, 0), 1)
            let homeHeaderBlurRadius = homeHeaderBlurProgress * 12
            let homeHeaderOpacity = 1 - homeHeaderFadeProgress

            ZStack(alignment: .bottomTrailing) {
                HomeBackgroundView()
                    .blur(radius: homeModalBlurRadius)

                homeHeader
                    .padding(.horizontal, 18)
                    .padding(.top, homeTopPadding)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .opacity(homeHeaderOpacity)
                    .blur(radius: max(homeModalBlurRadius, homeHeaderBlurRadius))
                    .allowsHitTesting(false)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        ScrollOffsetObserverView { offset in
                            if let baseline = homeScrollOffsetBaseline {
                                homeDragOffset = offset - baseline
                            } else {
                                homeScrollOffsetBaseline = offset
                                homeDragOffset = 0
                            }
                        }
                        .frame(height: 0)

                        Color.clear
                            .frame(height: homeHeaderReserveHeight)

                        if state.isFeedVisible {
                            TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
                                homeLayout(
                                    containerWidth: max(geometry.size.width - 36, 0),
                                    animationDate: timeline.date,
                                    requiresDragHoldBeforeDragging: requiresDragHoldBeforeDragging
                                )
                            }
                        } else {
                            homeLayout(
                                containerWidth: max(geometry.size.width - 36, 0),
                                animationDate: frozenAnimationDate,
                                requiresDragHoldBeforeDragging: requiresDragHoldBeforeDragging
                            )
                        }
                    }
                    .background {
                        GeometryReader { proxy in
                            Color.clear
                                .preference(key: HomeContentHeightPreferenceKey.self, value: proxy.size.height)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: max(geometry.size.height - homeTopPadding - homeBottomPadding, 0), alignment: .topLeading)
                    .padding(.horizontal, 18)
                    .padding(.top, homeTopPadding)
                    .padding(.bottom, homeBottomPadding)
                    .coordinateSpace(name: "home-content")
                    .overlay(alignment: .topLeading) {
                        draggedNoteOverlay(animationDate: state.isFeedVisible ? Date() : frozenAnimationDate)
                    }
                    .simultaneousGesture(
                        SpatialTapGesture()
                            .onEnded { value in
                                guard !isReorderMode,
                                      let noteID = preciseNoteID(at: value.location) else { return }
                                handleTap(on: noteID)
                            }
                    )
                    .overlay {
                        if isReorderMode {
                            GlobalDragCaptureView(
                                isEnabled: true,
                                minimumHoldDuration: reorderScrollableDragHoldDuration,
                                onBegan: { point in
                                    guard let noteID = noteID(at: point) else { return }
                                    beginDragging(noteID, touchPoint: point)
                                    dragTouchPointGlobal = point
                                    dragTranslation = .zero
                                },
                                onChanged: { point, translation in
                                    guard let noteID = activeDragNoteID else { return }
                                    dragTouchPointGlobal = point
                                    dragTranslation = translation
                                    updateHoverIntent(for: noteID, translation: translation)
                                },
                                onEnded: { point, translation in
                                    guard let noteID = activeDragNoteID else { return }
                                    dragTouchPointGlobal = point
                                    endDragging(noteID: noteID, translation: translation)
                                },
                                onCancelled: {
                                    dragTouchPointGlobal = nil
                                    guard let noteID = activeDragNoteID else { return }
                                    endDragging(noteID: noteID, translation: dragTranslation)
                                }
                            )
                        }
                    }
                }
                .scrollBounceBehavior(.always)
                .scrollDisabled(isScrollLockedForActiveDrag)
                .coordinateSpace(name: "home-scroll")
                .onAppear {
                    homeScrollOffsetBaseline = nil
                    homeDragOffset = 0
                    synchronizeOrderingIfNeeded()
                }
                .onChange(of: state.notes.map(\.id)) { _, noteIDs in
                    let visibleIDs = Set(noteIDs)
                    if let deletingNoteID, !visibleIDs.contains(deletingNoteID) {
                        withAnimation(deleteCompactionSpring) {
                            deletingNoteSnapshot = nil
                            synchronizeOrderingIfNeeded()
                            suppressedNoteOutlineIDs = suppressedNoteOutlineIDs.intersection(visibleIDs)
                            suppressedNoteContentIDs = suppressedNoteContentIDs.intersection(visibleIDs)
                        }
                        self.deletingNoteID = nil
                        return
                    }

                    synchronizeOrderingIfNeeded()
                    suppressedNoteOutlineIDs = suppressedNoteOutlineIDs.intersection(visibleIDs)
                    suppressedNoteContentIDs = suppressedNoteContentIDs.intersection(visibleIDs)
                }
                .blur(radius: homeModalBlurRadius)
                .onPreferenceChange(NoteFramePreferenceKey.self) { frames in
                    noteFrames = frames
                }
                .onPreferenceChange(NoteHitFramePreferenceKey.self) { frames in
                    noteHitFrames = frames
                }
                .onPreferenceChange(NoteTapTargetPreferenceKey.self) { targets in
                    noteTapTargets = targets
                }
                .onPreferenceChange(HomeHeaderFramePreferenceKey.self) { frame in
                    guard !frame.isNull else { return }
                    homeHeaderFrame = frame
                    if !isReorderMode {
                        frozenTrashTargetTopInset = frame.minY
                    }
                }
                .onPreferenceChange(HomeItemHeightPreferenceKey.self) { heights in
                    guard !isReorderMode else { return }
                    measuredItemHeights.merge(heights) { _, new in new }
                }
                .onPreferenceChange(HomeContentHeightPreferenceKey.self) { height in
                    homeContentHeight = height
                }
                .onChange(of: state.expandedNoteID) { oldValue, newValue in
                    pendingOutlineRevealTask?.cancel()
                    pendingOutlineRevealTask = nil
                    pendingContentRevealTask?.cancel()
                    pendingContentRevealTask = nil
                    pendingExpandedCardZResetTask?.cancel()
                    pendingExpandedCardZResetTask = nil

                    if let expandedID = newValue {
                        elevatedTransitionNoteID = expandedID
                        suppressedNoteOutlineIDs.insert(expandedID)
                        suppressedNoteContentIDs.insert(expandedID)
                        return
                    }

                    guard let closingID = oldValue else { return }
                    elevatedTransitionNoteID = closingID

                    pendingOutlineRevealTask = Task {
                        try? await Task.sleep(nanoseconds: UInt64((noteMorphDuration + 0.08) * 1_000_000_000))
                        guard !Task.isCancelled else { return }
                        await MainActor.run {
                            _ = withAnimation(.easeOut(duration: 0.18)) {
                                suppressedNoteOutlineIDs.remove(closingID)
                            }
                            pendingOutlineRevealTask = nil
                        }
                    }

                    pendingContentRevealTask = Task {
                        try? await Task.sleep(nanoseconds: UInt64((noteMorphDuration + 0.18) * 1_000_000_000))
                        guard !Task.isCancelled else { return }
                        await MainActor.run {
                            _ = withAnimation(.easeOut(duration: 0.22)) {
                                suppressedNoteContentIDs.remove(closingID)
                            }
                            pendingContentRevealTask = nil
                        }
                    }

                    pendingExpandedCardZResetTask = Task {
                        try? await Task.sleep(nanoseconds: UInt64((noteMorphDuration + 0.22) * 1_000_000_000))
                        guard !Task.isCancelled else { return }
                        await MainActor.run {
                            elevatedTransitionNoteID = nil
                            pendingExpandedCardZResetTask = nil
                        }
                    }
                }
                .onChange(of: state.isPresentingNewNote) { _, isPresenting in
                    pendingSeedRevealTask?.cancel()
                    pendingSeedRevealTask = nil

                    if isPresenting {
                        isSeedDecorationReady = false
                        isSeedContentReady = false
                        return
                    }

                    pendingSeedRevealTask = Task {
                        try? await Task.sleep(nanoseconds: UInt64(noteMorphDuration * 1_000_000_000))
                        guard !Task.isCancelled else { return }
                        await MainActor.run {
                            withAnimation(.easeOut(duration: 0.22)) {
                                isSeedDecorationReady = true
                                isSeedContentReady = true
                            }
                            pendingSeedRevealTask = nil
                        }
                    }
                }
                .onChange(of: state.isFeedVisible) { _, isVisible in
                    if !isVisible {
                        frozenAnimationDate = Date()
                    }
                }
                .onChange(of: isReorderMode) { _, isActive in
                    if !isActive {
                        frozenTrashTargetTopInset = nil
                        trashTargetFrame = .null
                    }
                }
                .onTapGesture {
                    if isReorderMode {
                        cancelDragging()
                    }
                }

                Button {
                    onShowAssistant()
                } label: {
                    Text("AI")
                        .font(AppFont.heading(16, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(width: 58, height: 58)
                        .glassCircleButtonChrome()
                }
                .padding(.trailing, 22)
                .padding(.bottom, isReorderMode ? 148 : 26)
                .blur(radius: homeModalBlurRadius)

                if isDeleteConfirmationPresented {
                    Color.white.opacity(0.025)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }

                if isDeleteConfirmationPresented {
                    deleteConfirmationOverlay(
                        containerSize: geometry.size,
                        safeAreaInsets: geometry.safeAreaInsets
                    )
                    .transition(.opacity)
                }

                if isReorderMode && !isDeleteConfirmationPresented {
                    reorderExitSwipeCapture(bottomInset: geometry.safeAreaInsets.bottom)
                }

//                if isReorderMode {
//                    reorderInstruction(bottomInset: geometry.safeAreaInsets.bottom)
//                }
//
//                if isReorderMode {
//                    TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
//                        Text("DEBUG: \(debugJudgmentLabel(at: timeline.date))")
//                            .font(AppFont.meta(12))
//                            .foregroundStyle(.red)
//                            .padding(.horizontal, 10)
//                            .padding(.vertical, 4)
//                            .background(Color.white.opacity(0.85))
//                            .clipShape(RoundedRectangle(cornerRadius: 6))
//                            .frame(maxWidth: .infinity, alignment: .center)
//                            .padding(.bottom, max(geometry.safeAreaInsets.bottom, 10) + 60)
//                            .frame(maxHeight: .infinity, alignment: .bottom)
//                            .allowsHitTesting(false)
//                    }
//                }

            }
            .overlay(alignment: .topLeading) {
                if isReorderMode || trashVisibilityProgress > 0.001 {
                    ZStack(alignment: .topTrailing) {
                        Color.clear
                        trashTargetLabel
                            .padding(.top, homeTopPadding)
                            .padding(.trailing, 18)
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .opacity(trashVisibilityProgress)
                    .blur(radius: homeModalBlurRadius)
                    .allowsHitTesting(false)
                }
            }
            .coordinateSpace(name: "home-root")
            .onPreferenceChange(TrashTargetFramePreferenceKey.self) { frame in
                trashTargetFrame = frame
            }
        }
    }

    private func debugJudgmentLabel(at now: Date) -> String {
        guard let dragID = activeDragNoteID else { return "idle" }
        let overlapStr = debugOverlapString(for: dragID)
        if let candidate = hoverCandidate {
            let timerStr = debugHoverTimerString(for: candidate, now: now)
            if let intent = activePreviewIntent, intent == candidate.intent {
                return "\(debugIntentLabel(for: intent, dragID: dragID))\(timerStr)\(overlapStr)"
            }
            return "\(debugIntentLabel(for: candidate.intent, dragID: dragID)) pending\(timerStr)\(overlapStr)"
        }

        if let intent = activePreviewIntent {
            return "\(debugIntentLabel(for: intent, dragID: dragID))\(overlapStr)"
        }

        return "hold\(overlapStr)"
    }

    private func debugIntentLabel(for intent: HoverIntent, dragID: String) -> String {
        switch intent {
        case .group:
            if dragBaseAffinityGroups.contains(where: { $0.contains(dragID) }) {
                return "ungroup and group"
            }
            return "group and reorder"
        case .reorder:
            if dragBaseAffinityGroups.contains(where: { $0.contains(dragID) }) {
                return "ungroup and reorder"
            }
            return "reorder"
        case .delete:
            return "delete"
        }
    }

    private func debugHoverTimerString(for candidate: HoverCandidate, now: Date) -> String {
        let elapsed = max(0, now.timeIntervalSince(candidate.since))
        let clampedElapsed = min(elapsed, reorderHoverDwellDuration)
        return String(format: " | timer: %.2f/%.2f", clampedElapsed, reorderHoverDwellDuration)
    }

    private func debugOverlapString(for noteID: String) -> String {
        guard let start = dragStartFrame else { return "" }
        let fingerFrame = start.offsetBy(dx: dragTranslation.width, dy: dragTranslation.height)
        var best: (id: String, ratio: CGFloat)?
        for (otherID, otherFrame) in noteFrames where otherID != noteID {
            let ratio = overlapActivationRatio(between: fingerFrame, and: otherFrame)
            if ratio > (best?.ratio ?? 0) {
                best = (otherID, ratio)
            }
        }
        guard let best, best.ratio > 0.01 else { return "" }
        return " | overlap: \(Int(best.ratio * 100))%"
    }

    private var effectiveDragOffset: CGSize {
        guard let dragID = activeDragNoteID,
              let start = dragStartFrame,
              let current = noteFrames[dragID] else {
            return dragTranslation
        }
        return CGSize(
            width: dragTranslation.width + start.minX - current.minX,
            height: dragTranslation.height + start.minY - current.minY
        )
    }

    private var reorderSpring: Animation {
        .spring(response: 0.38, dampingFraction: 0.82)
    }

    private var deleteCompactionSpring: Animation {
        .spring(response: 0.49, dampingFraction: 0.86)
    }

    private var dropSettleSpring: Animation {
        .spring(response: 0.32, dampingFraction: 0.72)
    }

    private func pollHoverCandidateActivation() {
        guard let noteID = activeDragNoteID,
              let candidate = hoverCandidate,
              let startFrame = dragStartFrame ?? noteFrames[noteID] else {
            return
        }

        let finalFrame = startFrame.offsetBy(dx: dragTranslation.width, dy: dragTranslation.height)
        maybeActivatePreview(for: noteID, candidate: candidate, finalFrame: finalFrame)
    }

    private func isVisuallyDragging(_ noteID: String) -> Bool {
        activeDragNoteID == noteID
    }

    private var homeHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("MOSSLOG")
                .font(AppFont.meta(11))
                .tracking(1.8)
                .foregroundStyle(.black.opacity(0.5))

            Spacer(minLength: 0)

            if !state.isPresentingNewNote && !isReorderMode {
                HStack(spacing: 6) {
                    Circle()
                        .fill(noteAccentColor)
                        .frame(width: 7, height: 7)

                    Text("\(growingSeedCount) growing")
                        .font(AppFont.meta(11))
                        .tracking(1.8)
                        .textCase(.uppercase)
                        .foregroundStyle(noteAccentColor)
                }
                .transition(.identity)
            }
        }
        .onReceive(Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()) { _ in
            guard isReorderMode else { return }
            pollHoverCandidateActivation()
        }
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: HomeHeaderFramePreferenceKey.self,
                    value: proxy.frame(in: .named("home-root"))
                )
            }
        )
    }

    private var trashTargetLabel: some View {
        ZStack(alignment: .trailing) {
            Text(idleTrashLabelText)
                .opacity(0)

            Text(isDeletePreviewActive ? trashMaskText : idleTrashLabelText)
                .foregroundStyle(Color(red: 0.74, green: 0.17, blue: 0.14))
        }
        .font(AppFont.meta(11))
        .tracking(1.8)
        .textCase(.uppercase)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: TrashTargetFramePreferenceKey.self,
                    value: proxy.frame(in: .global)
                )
            }
        )
    }

    private func pinnedTrashTarget(fallbackTopInset: CGFloat) -> some View {
        trashTargetLabel
            .padding(.top, fallbackTopInset)
            .padding(.trailing, 18)
            .allowsHitTesting(false)
    }

    private var idleTrashLabelText: String {
        "[\(trashLabelText)]"
    }

    private var trashVisibilityProgress: Double {
        Double(min(max(jiggleProgress, 0), 1))
    }

    private func reorderExitSwipeCapture(bottomInset: CGFloat) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .frame(height: max(bottomInset, 10) + 86)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .gesture(
                DragGesture(minimumDistance: 6)
                    .onEnded { value in
                        guard isReorderMode else { return }
                        guard activeDragNoteID == nil else { return }
                        guard value.translation.height <= -reorderExitSwipeMinimumDistance else { return }
                        guard abs(value.translation.width) <= reorderExitSwipeMaximumHorizontalDrift else { return }
                        triggerReorderExitHaptic()
                        cancelDragging()
                    }
            )
            .zIndex(24_000)
    }

    private var trashMaskText: String {
        "[" + String(repeating: " ", count: trashLabelText.count) + "]"
    }

    private var isDeletePreviewActive: Bool {
        if case .delete? = activePreviewIntent {
            return true
        }
        return false
    }

    private var deletePreviewScale: CGFloat {
        1 - (deletePreviewProgress * 0.5)
    }

    private var shouldCommitDeleteOnRelease: Bool {
        deletePreviewScale <= 0.51
    }

    private func noteVisibilityOpacity(noteID: String, isDragged: Bool, baseOpacity: Double = 1) -> Double {
        if isDragged {
            return 0.001
        }
        if deletingNoteID == noteID {
            return 0.001
        }
        return baseOpacity
    }

    private func homeLayout(containerWidth: CGFloat, animationDate: Date, requiresDragHoldBeforeDragging: Bool) -> some View {
        let notesByID = Dictionary(uniqueKeysWithValues: displayNotes.map { ($0.id, $0) })
        let spacing: CGFloat = 16
        let columnWidth = max((containerWidth - spacing) / 2, 0)
        let columns = resolvedColumnLayout(notesByID: notesByID, columnWidth: columnWidth)
        let leftHeight = estimatedColumnHeight(columns.left, side: .left, notesByID: notesByID, columnWidth: columnWidth)
        let rightHeight = estimatedColumnHeight(columns.right, side: .right, notesByID: notesByID, columnWidth: columnWidth)
        let seedInLeftColumn = leftHeight <= rightHeight
        let positionedItems = positionedColumnItems(
            columns: columns,
            columnWidth: columnWidth,
            columnSpacing: spacing,
            notesByID: notesByID
        )
        let contentHeight = max(
            positionedItems.map { $0.origin.y + $0.height }.max() ?? 0,
            seedOrigin(
                placeInLeftColumn: seedInLeftColumn,
                leftHeight: leftHeight,
                rightHeight: rightHeight,
                columnWidth: columnWidth,
                columnSpacing: spacing
            ).y + 156
        )

        return ZStack(alignment: .topLeading) {
            ForEach(positionedItems) { placed in
                itemView(
                    placed.item,
                    notesByID: notesByID,
                    columnWidth: columnWidth,
                    indexSeed: placed.indexSeed,
                    previewPlaceholder: placed.previewPlaceholder,
                    animationDate: animationDate,
                    requiresDragHoldBeforeDragging: requiresDragHoldBeforeDragging
                )
                .frame(width: columnWidth, alignment: .topLeading)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: HomeItemHeightPreferenceKey.self,
                            value: [placed.item.id: proxy.size.height]
                        )
                    }
                )
                .offset(x: placed.origin.x, y: placed.origin.y)
            }

            seedCard()
                .frame(width: columnWidth, alignment: .topLeading)
                .offset(
                    x: seedOrigin(
                        placeInLeftColumn: seedInLeftColumn,
                        leftHeight: leftHeight,
                        rightHeight: rightHeight,
                        columnWidth: columnWidth,
                        columnSpacing: spacing
                    ).x,
                    y: seedOrigin(
                        placeInLeftColumn: seedInLeftColumn,
                        leftHeight: leftHeight,
                        rightHeight: rightHeight,
                        columnWidth: columnWidth,
                        columnSpacing: spacing
                    ).y
                )
                .zIndex(1_000)
        }
        .frame(width: containerWidth, height: contentHeight, alignment: .topLeading)
    }

    private func positionedColumnItems(
        columns: ColumnLayout,
        columnWidth: CGFloat,
        columnSpacing: CGFloat,
        notesByID: [String: APINote]
    ) -> [PositionedColumnItem] {
        var positioned: [PositionedColumnItem] = []
        var leftY: CGFloat = 0
        var rightY: CGFloat = 0

        for (index, item) in columns.left.enumerated() {
            let placeholder = groupPreviewPlaceholder?.side == .left && groupPreviewPlaceholder?.index == index
                ? groupPreviewPlaceholder
                : nil
            if let placeholder, placeholder.memberIndex == nil {
                leftY += placeholder.height + 16
            }
            let height = estimatedHeight(for: item, notesByID: notesByID, columnWidth: columnWidth, previewPlaceholder: placeholder)
            positioned.append(
                PositionedColumnItem(
                    item: item,
                    indexSeed: index * 2,
                    origin: CGPoint(x: 0, y: leftY),
                    height: height,
                    previewPlaceholder: placeholder
                )
            )
            leftY += height + 16
        }

        for (index, item) in columns.right.enumerated() {
            let placeholder = groupPreviewPlaceholder?.side == .right && groupPreviewPlaceholder?.index == index
                ? groupPreviewPlaceholder
                : nil
            if let placeholder, placeholder.memberIndex == nil {
                rightY += placeholder.height + 16
            }
            let height = estimatedHeight(for: item, notesByID: notesByID, columnWidth: columnWidth, previewPlaceholder: placeholder)
            positioned.append(
                PositionedColumnItem(
                    item: item,
                    indexSeed: index * 2 + 1,
                    origin: CGPoint(x: columnWidth + columnSpacing, y: rightY),
                    height: height,
                    previewPlaceholder: placeholder
                )
            )
            rightY += height + 16
        }

        return positioned
    }

    private func seedOrigin(
        placeInLeftColumn: Bool,
        leftHeight: CGFloat,
        rightHeight: CGFloat,
        columnWidth: CGFloat,
        columnSpacing: CGFloat
    ) -> CGPoint {
        if placeInLeftColumn {
            return CGPoint(x: 0, y: leftHeight + (leftHeight > 0 ? 16 : 0))
        }
        return CGPoint(x: columnWidth + columnSpacing, y: rightHeight + (rightHeight > 0 ? 16 : 0))
    }

    private func rotation(for noteID: String) -> Double {
        let scalarSum = noteID.unicodeScalars.reduce(0) { partialResult, scalar in
            partialResult &* 31 &+ Int(scalar.value)
        }
        let normalized = Double(abs(scalarSum % 1000)) / 999.0
        return -1.1 + (normalized * 2.2)
    }

    private func handleTap(on noteID: String) {
        debugNoteLog("handleTap", noteID, "isReorderMode:", isReorderMode)
        withAnimation(noteTransitionAnimation) {
            onOpenNote(noteID)
        }
    }

    private var displayNotes: [APINote] {
        guard let deletingNoteSnapshot,
              !state.notes.contains(where: { $0.id == deletingNoteSnapshot.id }) else {
            return state.notes
        }

        return state.notes + [deletingNoteSnapshot]
    }

    private var growingSeedCount: Int {
        state.notes.filter { ["queued", "retrying", "running"].contains($0.status) }.count
    }

    @ViewBuilder
    private func itemView(_ item: ColumnLayoutItem, notesByID: [String: APINote], columnWidth: CGFloat, indexSeed: Int, previewPlaceholder: GroupPreviewPlaceholder?, animationDate: Date, requiresDragHoldBeforeDragging: Bool) -> some View {
        let notes = item.noteIDs.compactMap { notesByID[$0] }

        if notes.count == 1,
           let note = notes.first,
           previewPlaceholder?.memberIndex == nil {
            noteCard(note, animationDate: animationDate, requiresDragHoldBeforeDragging: requiresDragHoldBeforeDragging)
        } else {
            if !notes.isEmpty {
            RelatedNoteCluster(
                notes: notes,
                columnWidth: columnWidth,
                rotations: notes.map { rotation(for: $0.id) },
                activeDragNoteID: activeDragNoteID,
                isDroppingDraggedNote: isDroppingDraggedNote,
                isInReorderMode: isReorderMode,
                requiresDragHoldBeforeDragging: requiresDragHoldBeforeDragging,
                dragTranslation: effectiveDragOffset,
                phaseSeed: phaseSeed,
                jiggleProgress: jiggleProgress,
                transitionNamespace: transitionNamespace,
                expandedNoteID: state.expandedNoteID,
                suppressedNoteOutlineIDs: suppressedNoteOutlineIDs,
                suppressedNoteContentIDs: suppressedNoteContentIDs,
                deletingNoteID: deletingNoteID,
                previewPlaceholderNote: previewPlaceholder.flatMap { $0.memberIndex != nil ? notesByID[$0.noteID] : nil },
                previewPlaceholderIndex: previewPlaceholder?.memberIndex,
                animationDate: animationDate
            ) { noteID in
                handleTap(on: noteID)
            } onEnterReorderMode: {
                enterReorderMode()
            } onDragChanged: { noteID, translation in
                guard isReorderMode else { return }
                beginDragging(noteID)
                dragTranslation = translation
                updateHoverIntent(for: noteID, translation: translation)
            } onDragEnded: { noteID, translation in
                guard isReorderMode else { return }
                endDragging(noteID: noteID, translation: translation)
            }
            }
        }
    }

    private func seedCard() -> some View {
        EmptyNoteCard(
            transitionNamespace: newThoughtNamespace,
            isExpanded: state.isPresentingNewNote,
            isAddMorphActive: state.addMorphTargetNoteID != nil,
            isVisible: !isReorderMode,
            isDecorationReady: isSeedDecorationReady,
            isContentReady: isSeedContentReady
        ) {
            withAnimation(noteTransitionAnimation) {
                onOpenNewNote()
            }
        }
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: NoteFramePreferenceKey.self,
                    value: ["seed": proxy.frame(in: .named("home-content"))]
                )
                .preference(
                    key: NoteHitFramePreferenceKey.self,
                    value: ["seed": proxy.frame(in: .global)]
                )
            }
        )
    }

    @ViewBuilder
    private func draggedNoteOverlay(animationDate: Date) -> some View {
        if let dragID = activeDragNoteID,
           let note = displayNotes.first(where: { $0.id == dragID }),
           let startFrame = dragStartFrame ?? noteFrames[dragID] {
            let isAddMorphTarget = state.addMorphTargetNoteID == note.id

            NoteCard(
                note: note,
                rotation: rotation(for: note.id),
                isReordering: true,
                isInReorderMode: isReorderMode,
                phaseSeed: phaseSeed(for: note.id),
                jiggleProgress: jiggleProgress,
                transitionNamespace: transitionNamespace,
                isExpanded: state.expandedNoteID == note.id,
                isOutlineReady: !suppressedNoteOutlineIDs.contains(note.id),
                isContentReady: !suppressedNoteContentIDs.contains(note.id),
                isTransitionSource: state.expandedNoteID == note.id,
                animationDate: animationDate,
                isSurfaceTransitionEnabled: false
            )
            .overlay {
                if isAddMorphTarget {
                    MorphingAddedNoteTarget(note: note, rotation: rotation(for: note.id), transitionNamespace: newThoughtNamespace)
                }
            }
            .frame(width: startFrame.width)
            .scaleEffect(deletePreviewScale, anchor: dragScaleAnchor)
            .offset(
                x: startFrame.minX + dragTranslation.width,
                y: startFrame.minY + dragTranslation.height
            )
            .allowsHitTesting(false)
            .zIndex(20_000)
            .transaction { t in
                if !isDroppingDraggedNote && !isDeletePreviewActive {
                    t.animation = nil
                }
            }
        }
    }

    private func noteID(at point: CGPoint) -> String? {
        noteHitFrames
            .filter { id, frame in
                id != "seed" && roundedRectContains(point: point, in: frame)
            }
            .max { lhs, rhs in
                layerPriority(for: lhs.key) < layerPriority(for: rhs.key)
            }?
            .key
    }

    private func preciseNoteID(at point: CGPoint) -> String? {
        noteTapTargets
            .filter { id, target in
                id != "seed" && rotatedRoundedRectContains(point: point, target: target)
            }
            .max { lhs, rhs in
                layerPriority(for: lhs.key) < layerPriority(for: rhs.key)
            }?
            .key
    }

    private func roundedRectContains(point: CGPoint, in rect: CGRect, cornerRadius: CGFloat = 30) -> Bool {
        guard !rect.isNull, !rect.isEmpty else { return false }
        return UIBezierPath(
            roundedRect: rect,
            cornerRadius: min(cornerRadius, min(rect.width, rect.height) * 0.5)
        ).contains(point)
    }

    private func rotatedRoundedRectContains(point: CGPoint, target: NoteTapTarget, cornerRadius: CGFloat = 30) -> Bool {
        let radians = -target.rotationDegrees * .pi / 180
        let translatedX = point.x - target.center.x
        let translatedY = point.y - target.center.y
        let unrotatedPoint = CGPoint(
            x: translatedX * cos(radians) - translatedY * sin(radians) + target.center.x,
            y: translatedX * sin(radians) + translatedY * cos(radians) + target.center.y
        )
        let rect = CGRect(
            x: target.center.x - target.size.width * 0.5,
            y: target.center.y - target.size.height * 0.5,
            width: target.size.width,
            height: target.size.height
        )
        return roundedRectContains(point: unrotatedPoint, in: rect, cornerRadius: cornerRadius)
    }

    private func layerPriority(for noteID: String) -> Double {
        if elevatedTransitionNoteID == noteID {
            return 15_000
        }
        if isVisuallyDragging(noteID) {
            return 10_000
        }
        let baseY = noteFrames[noteID]?.midY ?? 0
        let currentY = baseY + (activeDragNoteID == noteID ? effectiveDragOffset.height : 0)
        return Double(currentY)
    }

    @ViewBuilder
    private func noteCard(_ note: APINote, animationDate: Date, requiresDragHoldBeforeDragging: Bool) -> some View {
        let isAddMorphTarget = state.addMorphTargetNoteID == note.id
        let isDragged = activeDragNoteID == note.id
        let baseOpacity = isAddMorphTarget ? 0.001 : 1.0

        let placeholderFace = NoteCard(
            note: note,
            rotation: rotation(for: note.id),
            isReordering: isVisuallyDragging(note.id),
            isInReorderMode: isReorderMode,
            phaseSeed: phaseSeed(for: note.id),
            jiggleProgress: jiggleProgress,
            transitionNamespace: transitionNamespace,
            isExpanded: state.expandedNoteID == note.id,
            isOutlineReady: !suppressedNoteOutlineIDs.contains(note.id),
            isContentReady: !suppressedNoteContentIDs.contains(note.id),
            isTransitionSource: state.expandedNoteID == note.id,
            animationDate: animationDate,
            isSurfaceTransitionEnabled: true
        )
        .overlay {
            if isAddMorphTarget {
                MorphingAddedNoteTarget(note: note, rotation: rotation(for: note.id), transitionNamespace: newThoughtNamespace)
            }
        }

        let placeholderCard = placeholderFace
            .opacity(noteVisibilityOpacity(noteID: note.id, isDragged: isDragged, baseOpacity: baseOpacity))
            .animation(.easeOut(duration: 0.18), value: deletingNoteID)
            .background(
                GeometryReader { proxy in
                    let contentFrame = proxy.frame(in: .named("home-content"))
                    Color.clear.preference(
                        key: NoteFramePreferenceKey.self,
                        value: [note.id: contentFrame]
                    )
                    .preference(
                        key: NoteHitFramePreferenceKey.self,
                        value: [note.id: proxy.frame(in: .global)]
                    )
                    .preference(
                        key: NoteTapTargetPreferenceKey.self,
                        value: [
                            note.id: NoteTapTarget(
                                center: contentFrame.center,
                                size: proxy.size,
                                rotationDegrees: CGFloat(rotation(for: note.id))
                            )
                        ]
                    )
                }
            )

        let card = placeholderCard
            .zIndex(layerPriority(for: note.id))

        if !isReorderMode {
            card.highPriorityGesture(enterReorderGesture(noteID: note.id))
        } else if requiresDragHoldBeforeDragging {
            card
        } else {
            card.simultaneousGesture(dragGesture(noteID: note.id))
        }
    }

    private func synchronizeOrderingIfNeeded() {
        let ids = displayNotes.map(\.id)
        if orderedNoteIDs.isEmpty {
            orderedNoteIDs = ids
        } else {
            let existing = Set(orderedNoteIDs)
            let missing = ids.filter { !existing.contains($0) }
            orderedNoteIDs = deduplicated(orderedNoteIDs.filter(ids.contains) + missing)
        }

        let visible = Set(ids)
        affinityGroups = affinityGroups.compactMap { group in
            let remaining = group.noteIDs.filter { visible.contains($0) }
            return remaining.count >= 2 ? AffinityGroup(noteIDs: remaining) : nil
        }
        let notesByID = Dictionary(uniqueKeysWithValues: displayNotes.map { ($0.id, $0) })
        if columnLayout.isEmpty {
            let layout = buildColumnLayoutFromModel(notesByID: notesByID)
            syncLayoutState(from: layout)
        } else {
            let layout = reconciledColumnLayout(columnLayout, notesByID: notesByID)
            syncLayoutState(from: layout)
        }
    }

    private func resolvedColumnLayout(notesByID: [String: APINote], columnWidth: CGFloat = fallbackHomeColumnWidth()) -> ColumnLayout {
        if columnLayout.isEmpty {
            return buildColumnLayoutFromModel(notesByID: notesByID, columnWidth: columnWidth)
        }
        return reconciledColumnLayout(columnLayout, notesByID: notesByID, columnWidth: columnWidth)
    }

    private func buildLayoutItems(notesByID: [String: APINote], order: [String]? = nil, groups: [AffinityGroup]? = nil) -> [ColumnLayoutItem] {
        var items: [ColumnLayoutItem] = []
        var consumed = Set<String>()
        let sourceOrder = order ?? orderedNoteIDs
        let sourceGroups = groups ?? affinityGroups

        for id in sourceOrder {
            guard let note = notesByID[id], !consumed.contains(id) else { continue }

            if let group = sourceGroups.first(where: { $0.contains(id) }) {
                let groupNoteIDs = group.noteIDs.filter { notesByID[$0] != nil }
                guard groupNoteIDs.count >= 2 else { continue }
                items.append(.group(groupNoteIDs))
                consumed.formUnion(groupNoteIDs)
                continue
            }

            items.append(.note(note.id))
            consumed.insert(id)
        }

        return items
    }

    private func buildColumnLayoutFromModel(notesByID: [String: APINote], order: [String]? = nil, groups: [AffinityGroup]? = nil, columnWidth: CGFloat = fallbackHomeColumnWidth()) -> ColumnLayout {
        var layout = ColumnLayout()
        let items = buildLayoutItems(notesByID: notesByID, order: order, groups: groups)

        for item in items {
            if estimatedColumnHeight(layout.left, side: .left, notesByID: notesByID, columnWidth: columnWidth, previewPlaceholder: nil) <= estimatedColumnHeight(layout.right, side: .right, notesByID: notesByID, columnWidth: columnWidth, previewPlaceholder: nil) {
                layout.left.append(item)
            } else {
                layout.right.append(item)
            }
        }

        return layout
    }

    private func reconciledColumnLayout(_ layout: ColumnLayout, notesByID: [String: APINote], columnWidth: CGFloat = fallbackHomeColumnWidth()) -> ColumnLayout {
        var reconciled = ColumnLayout(
            left: reconcileColumn(layout.left, notesByID: notesByID),
            right: reconcileColumn(layout.right, notesByID: notesByID)
        )
        let usedIDs = Set(reconciled.left.flatMap(\.noteIDs) + reconciled.right.flatMap(\.noteIDs))
        let missingItems = buildLayoutItems(notesByID: notesByID).filter { item in
            !item.noteIDs.contains(where: usedIDs.contains)
        }

        for item in missingItems {
            if estimatedColumnHeight(reconciled.left, side: .left, notesByID: notesByID, columnWidth: columnWidth, previewPlaceholder: nil) <= estimatedColumnHeight(reconciled.right, side: .right, notesByID: notesByID, columnWidth: columnWidth, previewPlaceholder: nil) {
                reconciled.left.append(item)
            } else {
                reconciled.right.append(item)
            }
        }

        return reconciled
    }

    private func reconcileColumn(_ items: [ColumnLayoutItem], notesByID: [String: APINote]) -> [ColumnLayoutItem] {
        items.compactMap { item in
            let visibleIDs = item.noteIDs.filter { notesByID[$0] != nil }
            switch visibleIDs.count {
            case 0:
                return nil
            case 1:
                return .note(visibleIDs[0])
            default:
                return .group(visibleIDs)
            }
        }
    }

    private func estimatedColumnHeight(_ items: [ColumnLayoutItem], side: ColumnSide, notesByID: [String: APINote], columnWidth: CGFloat = fallbackHomeColumnWidth(), previewPlaceholder: GroupPreviewPlaceholder? = nil) -> CGFloat {
        let placeholder = previewPlaceholder ?? groupPreviewPlaceholder
        var total: CGFloat = 0

        for (index, item) in items.enumerated() {
            let itemPlaceholder = placeholder?.side == side && placeholder?.index == index ? placeholder : nil
            if let itemPlaceholder, itemPlaceholder.memberIndex == nil {
                if total > 0 { total += 16 }
                total += itemPlaceholder.height
            }

            if total > 0 { total += 16 }
            total += estimatedHeight(for: item, notesByID: notesByID, columnWidth: columnWidth, previewPlaceholder: itemPlaceholder)
        }

        if let placeholder, placeholder.memberIndex == nil, placeholder.side == side, placeholder.index >= items.count {
            if total > 0 { total += 16 }
            total += placeholder.height
        }

        return total
    }

    private func estimatedHeight(for item: ColumnLayoutItem, notesByID: [String: APINote], columnWidth: CGFloat = fallbackHomeColumnWidth(), previewPlaceholder: GroupPreviewPlaceholder? = nil) -> CGFloat {
        if let measured = measuredItemHeights[item.id], measured > 0 {
            return measured
        }
        let notes = item.noteIDs.compactMap { notesByID[$0] }
        let placeholderNote = previewPlaceholder.flatMap { $0.memberIndex != nil ? notesByID[$0.noteID] : nil }
        if notes.count <= 1,
           let note = notes.first,
           placeholderNote == nil {
            return estimatedHomeNoteCardHeight(for: note, columnWidth: columnWidth)
        }
        return estimatedStackedClusterHeight(
            for: notes,
            columnWidth: columnWidth,
            previewPlaceholderNote: placeholderNote,
            previewPlaceholderIndex: previewPlaceholder?.memberIndex
        )
    }

    private func syncLayoutState(from layout: ColumnLayout) {
        columnLayout = layout
        affinityGroups = layout.groups
        orderedNoteIDs = layout.flattenedOrder
    }

    private func beginDragging(_ noteID: String, touchPoint: CGPoint? = nil) {
        if activeDragNoteID == nil {
            activeDragNoteID = noteID
            isDroppingDraggedNote = false
            if dragStartFrame == nil {
                dragStartFrame = noteFrames[noteID]
            }
            dragScaleAnchor = resolvedDragScaleAnchor(for: noteID, touchPoint: touchPoint)
            if dragBaseColumnLayout.isEmpty {
                dragBaseColumnLayout = columnLayout
            }
            if dragBaseOrder.isEmpty {
                dragBaseOrder = orderedNoteIDs
            }
            if dragBaseAffinityGroups.isEmpty {
                dragBaseAffinityGroups = affinityGroups
            }
        }
    }

    private func clearDragArming() {
        activeDragNoteID = nil
        isDroppingDraggedNote = false
        dragTranslation = .zero
        dragScaleAnchor = .center
        dragTouchPointGlobal = nil
        hoverCandidate = nil
        activePreviewIntent = nil
        resetDeletePreviewState()
        groupPreviewPlaceholder = nil
        dragStartFrame = nil
        dragBaseOrder = []
        dragBaseAffinityGroups = []
        dragBaseColumnLayout = ColumnLayout()
    }

    private func cancelDragging(exitReorderMode: Bool = true) {
        activeDragNoteID = nil
        isDroppingDraggedNote = false
        dragTranslation = .zero
        dragScaleAnchor = .center
        dragTouchPointGlobal = nil
        hoverCandidate = nil
        activePreviewIntent = nil
        resetDeletePreviewState()
        groupPreviewPlaceholder = nil
        dragStartFrame = nil
        dragBaseOrder = []
        dragBaseAffinityGroups = []
        dragBaseColumnLayout = ColumnLayout()
        guard exitReorderMode, isReorderMode else { return }
        withAnimation(.easeOut(duration: 0.16)) {
            jiggleProgress = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            if jiggleProgress == 0 {
                isReorderMode = false
            }
        }
    }

    private func keepReorderModeAfterDrop() {
        activeDragNoteID = nil
        isDroppingDraggedNote = false
        dragTranslation = .zero
        dragScaleAnchor = .center
        dragTouchPointGlobal = nil
        hoverCandidate = nil
        activePreviewIntent = nil
        resetDeletePreviewState()
        groupPreviewPlaceholder = nil
        dragStartFrame = nil
        dragBaseOrder = []
        dragBaseAffinityGroups = []
        dragBaseColumnLayout = ColumnLayout()
        if jiggleProgress < 1 {
            withAnimation(.easeOut(duration: 0.16)) {
                jiggleProgress = 1
            }
        }
    }

    private func settleGroupedDropWithWholeGroupMotion() {
        activeDragNoteID = nil
        isDroppingDraggedNote = false
        dragTranslation = .zero
        dragScaleAnchor = .center
        dragTouchPointGlobal = nil
        hoverCandidate = nil
        dragStartFrame = nil

        DispatchQueue.main.async {
            withAnimation(reorderSpring) {
                activePreviewIntent = nil
                resetDeletePreviewState()
                groupPreviewPlaceholder = nil
                dragBaseOrder = []
                dragBaseAffinityGroups = []
                dragBaseColumnLayout = ColumnLayout()
                if jiggleProgress < 1 {
                    jiggleProgress = 1
                }
            }
        }
    }

    private func endDragging(noteID: String, translation: CGSize) {
        guard (dragStartFrame ?? noteFrames[noteID]) != nil else {
            keepReorderModeAfterDrop()
            return
        }

        if activePreviewIntent == nil {
            withAnimation(reorderSpring) {
                restoreDragBaseline()
                keepReorderModeAfterDrop()
            }
            Task {
                await onPersistManualOrder(orderedNoteIDs)
            }
            return
        }

        if case .delete? = activePreviewIntent {
            let shouldCommitDelete = shouldCommitDeleteOnRelease
            withAnimation(reorderSpring) {
                restoreDragBaseline()
                keepReorderModeAfterDrop()
            }
            if shouldCommitDelete {
                presentDeleteConfirmation(for: noteID)
            }
            return
        }

        Task {
            await onPersistManualOrder(orderedNoteIDs)
        }

        if case .group(_, _) = activePreviewIntent {
            settleGroupedDropWithWholeGroupMotion()
            return
        }

        if let startFrame = dragStartFrame,
           let currentFrame = noteFrames[noteID] {
            isDroppingDraggedNote = true
            let settleTranslation = CGSize(
                width: currentFrame.minX - startFrame.minX,
                height: currentFrame.minY - startFrame.minY
            )
            withAnimation(dropSettleSpring) {
                dragTranslation = settleTranslation
            }
        }

        let droppingNoteID = noteID
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            guard activeDragNoteID == droppingNoteID else { return }
            keepReorderModeAfterDrop()
        }
    }

    private func updateHoverIntent(for noteID: String, translation: CGSize) {
        guard let startFrame = dragStartFrame ?? noteFrames[noteID] else { return }
        let finalFrame = startFrame.offsetBy(dx: translation.width, dy: translation.height)

        guard let resolution = hoverResolution(for: noteID, finalFrame: finalFrame) else {
            hoverCandidate = nil
            if activePreviewIntent != nil {
                withAnimation(reorderSpring) {
                    restoreDragBaseline()
                }
                activePreviewIntent = nil
            }
            resetDeletePreviewState()
            return
        }

        if case .delete = resolution.intent {
            deletePreviewProgress = resolution.deletePreviewProgress
            isDeleteCommitReady = resolution.isDeleteCommitReady
        } else {
            resetDeletePreviewState()
        }

        let now = Date()
        let nextCandidate: HoverCandidate
        if let current = hoverCandidate,
           current.intent == resolution.intent,
           distance(current.anchorPoint, resolution.anchorPoint) <= reorderHoverJitterTolerance {
            nextCandidate = HoverCandidate(
                intent: current.intent,
                since: current.since,
                anchorPoint: resolution.anchorPoint
            )
        } else {
            nextCandidate = HoverCandidate(
                intent: resolution.intent,
                since: now,
                anchorPoint: resolution.anchorPoint
            )
        }

        if let activePreviewIntent, activePreviewIntent != nextCandidate.intent {
            withAnimation(reorderSpring) {
                restoreDragBaseline()
            }
            self.activePreviewIntent = nil
        }

        hoverCandidate = nextCandidate
        maybeActivatePreview(for: noteID, candidate: nextCandidate, finalFrame: finalFrame)
    }

    private func overlappingTarget(for noteID: String, finalFrame: CGRect) -> String? {
        bestOverlapTarget(for: noteID, finalFrame: finalFrame)?.id
    }

    private func bestOverlapTarget(for noteID: String, finalFrame: CGRect) -> (id: String, ratio: CGFloat)? {
        var bestMatch: (id: String, ratio: CGFloat)?

        for (otherID, otherFrame) in noteFrames where otherID != noteID {
            let overlapValue = overlapActivationRatio(between: finalFrame, and: otherFrame)
            guard overlapValue > groupingOverlapThreshold else { continue }

            if let bestMatch, bestMatch.ratio >= overlapValue {
                continue
            }

            bestMatch = (otherID, overlapValue)
        }

        return bestMatch
    }

    private func reorder(noteID: String, finalFrame: CGRect) {
        var newOrder = orderedNoteIDs.filter { $0 != noteID }
        let targetPoints = noteFrames
            .filter { $0.key != noteID }
            .map { (id: $0.key, center: CGPoint(x: $0.value.midX, y: $0.value.midY)) }

        guard let nearest = targetPoints.min(by: {
            distance($0.center, finalFrame.center) < distance($1.center, finalFrame.center)
        }), let targetIndex = newOrder.firstIndex(of: nearest.id) else {
            newOrder.append(noteID)
            orderedNoteIDs = newOrder
            return
        }

        let insertIndex = finalFrame.midY < nearest.center.y ? targetIndex : targetIndex + 1
        newOrder.insert(noteID, at: min(insertIndex, newOrder.count))
        orderedNoteIDs = newOrder
    }

    private func affinityGroup(containing noteID: String) -> AffinityGroup? {
        affinityGroups.first { $0.contains(noteID) }
    }

    private func affinityGroup(startingWith noteID: String) -> AffinityGroup? {
        affinityGroups.first { $0.anchorID == noteID }
    }

    private func removeAffinityGroups(containingAnyOf noteIDs: Set<String>) {
        affinityGroups.removeAll { !noteIDs.isDisjoint(with: $0.noteIDSet) }
    }

    private func removeNoteFromAffinityGroups(_ noteID: String) {
        affinityGroups = affinityGroups.compactMap { group in
            guard group.contains(noteID) else { return group }
            let remaining = group.noteIDs.filter { $0 != noteID }
            return remaining.count >= 2 ? AffinityGroup(noteIDs: remaining) : nil
        }
    }

    private func groupedNoteIDs(adding noteID: String, below targetID: String, in existingIDs: [String]) -> [String] {
        var ids = existingIDs
        ids.removeAll { $0 == noteID }

        if let targetIndex = ids.firstIndex(of: targetID) {
            ids.insert(noteID, at: min(targetIndex + 1, ids.count))
        } else {
            ids.append(targetID)
            ids.append(noteID)
        }

        return deduplicated(ids)
    }

    private func items(in side: ColumnSide, from layout: ColumnLayout) -> [ColumnLayoutItem] {
        switch side {
        case .left:
            return layout.left
        case .right:
            return layout.right
        }
    }

    private func item(at location: ColumnLocation, in layout: ColumnLayout) -> ColumnLayoutItem? {
        let columnItems = items(in: location.side, from: layout)
        guard columnItems.indices.contains(location.index) else { return nil }
        return columnItems[location.index]
    }

    private func set(item: ColumnLayoutItem, at location: ColumnLocation, in layout: inout ColumnLayout) {
        switch location.side {
        case .left:
            guard layout.left.indices.contains(location.index) else { return }
            layout.left[location.index] = item
        case .right:
            guard layout.right.indices.contains(location.index) else { return }
            layout.right[location.index] = item
        }
    }

    private func insert(item: ColumnLayoutItem, at location: ColumnLocation, in layout: inout ColumnLayout) {
        switch location.side {
        case .left:
            layout.left.insert(item, at: min(location.index, layout.left.count))
        case .right:
            layout.right.insert(item, at: min(location.index, layout.right.count))
        }
    }

    private func removing(noteID: String, from layout: ColumnLayout) -> (layout: ColumnLayout, origin: ColumnLocation?) {
        var updated = layout

        for (index, item) in layout.left.enumerated() where item.noteIDs.contains(noteID) {
            let remaining = item.noteIDs.filter { $0 != noteID }
            if remaining.isEmpty {
                updated.left.remove(at: index)
            } else if remaining.count == 1 {
                updated.left[index] = .note(remaining[0])
            } else {
                updated.left[index] = .group(remaining)
            }
            return (updated, ColumnLocation(side: .left, index: index))
        }

        for (index, item) in layout.right.enumerated() where item.noteIDs.contains(noteID) {
            let remaining = item.noteIDs.filter { $0 != noteID }
            if remaining.isEmpty {
                updated.right.remove(at: index)
            } else if remaining.count == 1 {
                updated.right[index] = .note(remaining[0])
            } else {
                updated.right[index] = .group(remaining)
            }
            return (updated, ColumnLocation(side: .right, index: index))
        }

        return (updated, nil)
    }

    private func location(of noteID: String, in layout: ColumnLayout) -> ColumnLocation? {
        for (index, item) in layout.left.enumerated() where item.noteIDs.contains(noteID) {
            return ColumnLocation(side: .left, index: index)
        }
        for (index, item) in layout.right.enumerated() where item.noteIDs.contains(noteID) {
            return ColumnLocation(side: .right, index: index)
        }
        return nil
    }

    private func reorderDestination(for finalFrame: CGRect, in layout: ColumnLayout) -> ColumnLocation? {
        let targetSide: ColumnSide = finalFrame.midX <= columnSplitX(for: layout) ? .left : .right
        let columnItems = items(in: targetSide, from: layout)
        guard !columnItems.isEmpty else { return ColumnLocation(side: targetSide, index: 0) }

        let itemFrames = columnItems.compactMap { item -> CGRect? in
            itemFrame(for: item)
        }
        guard itemFrames.count == columnItems.count else { return nil }

        if let first = itemFrames.first, finalFrame.midY <= first.midY {
            return ColumnLocation(side: targetSide, index: 0)
        }

        if let last = itemFrames.last, finalFrame.midY >= last.midY {
            return ColumnLocation(side: targetSide, index: columnItems.count)
        }

        for index in 1..<itemFrames.count {
            let upper = itemFrames[index - 1]
            let lower = itemFrames[index]
            if finalFrame.midY > upper.midY, finalFrame.midY < lower.midY {
                return ColumnLocation(side: targetSide, index: index)
            }
        }

        return nil
    }

    private func itemFrame(for item: ColumnLayoutItem) -> CGRect? {
        let frames = item.noteIDs.compactMap { noteFrames[$0] }
        guard var union = frames.first else { return nil }
        for frame in frames.dropFirst() {
            union = union.union(frame)
        }
        return union
    }

    private func columnSplitX(for layout: ColumnLayout) -> CGFloat {
        let leftFrames = layout.left.compactMap { itemFrame(for: $0) }
        let rightFrames = layout.right.compactMap { itemFrame(for: $0) }

        if let leftX = leftFrames.map(\.midX).average,
           let rightX = rightFrames.map(\.midX).average {
            return (leftX + rightX) * 0.5
        }

        let allFrames = leftFrames + rightFrames
        guard let minX = allFrames.map(\.midX).min(),
              let maxX = allFrames.map(\.midX).max() else {
            return 0
        }
        return (minX + maxX) * 0.5
    }

    private func hoverResolution(for noteID: String, finalFrame: CGRect) -> HoverResolution? {
        let baseLayout = dragBaseColumnLayout.isEmpty ? columnLayout : dragBaseColumnLayout

        let baseOrder = dragBaseOrder.isEmpty ? orderedNoteIDs : dragBaseOrder

        if let trashResolution = trashHoverResolution(for: noteID, finalFrame: finalFrame) {
            return trashResolution
        }

        if let baseGroup = dragBaseAffinityGroups.first(where: { $0.contains(noteID) }) {
            let startFrame = dragStartFrame ?? noteFrames[noteID] ?? finalFrame
            let travelDistance = distance(startFrame.center, finalFrame.center)
            guard travelDistance >= ungroupMinimumTravelDistance else { return nil }

            let otherMembers = Set(baseGroup.noteIDs).subtracting([noteID])
            let stillTooClose = otherMembers.contains { memberID in
                guard let memberFrame = noteFrames[memberID] else { return false }
                return overlapActivationRatio(between: finalFrame, and: memberFrame) >= ungroupingOverlapThreshold
            }
            if stillTooClose { return nil }

            if let target = bestOverlapTarget(for: noteID, finalFrame: finalFrame) {
                let targetID = target.id
                if !otherMembers.contains(targetID),
                   let groupedPreview = groupedLayout(for: noteID, targetID: targetID, baseLayout: baseLayout) {
                    let anchor = noteFrames[targetID]?.center ?? finalFrame.center
                    return HoverResolution(
                        intent: .group(layout: groupedPreview.layout, placeholder: groupedPreview.placeholder),
                        anchorPoint: anchor
                    )
                }
            }

            if let ungroupedLayout = reorderedLayoutForGroupedNote(noteID: noteID, finalFrame: finalFrame, baseLayout: baseLayout) {
                return HoverResolution(intent: .reorder(layout: ungroupedLayout), anchorPoint: finalFrame.center)
            }
            let reordered = reorderedIDs(noteID: noteID, finalFrame: finalFrame, using: baseOrder)
            let fallbackLayout = buildColumnLayoutFromModel(
                notesByID: Dictionary(uniqueKeysWithValues: displayNotes.map { ($0.id, $0) }),
                order: reordered,
                groups: dragBaseAffinityGroups.compactMap { group in
                    let remaining = group.noteIDs.filter { $0 != noteID }
                    return remaining.count >= 2 ? AffinityGroup(noteIDs: remaining) : nil
                }
            )
            return HoverResolution(intent: .reorder(layout: fallbackLayout), anchorPoint: finalFrame.center)
        }

        if let target = bestOverlapTarget(for: noteID, finalFrame: finalFrame) {
            let targetID = target.id
            if let groupedPreview = groupedLayout(for: noteID, targetID: targetID, baseLayout: baseLayout) {
                let anchor = noteFrames[targetID]?.center ?? finalFrame.center
                return HoverResolution(intent: .group(layout: groupedPreview.layout, placeholder: groupedPreview.placeholder), anchorPoint: anchor)
            }
        }

        if let reorderIntent = reorderIntentForUngroupedNote(noteID: noteID, finalFrame: finalFrame, baseLayout: baseLayout) {
            return HoverResolution(intent: reorderIntent, anchorPoint: finalFrame.center)
        }

        return nil
    }

    private func maybeActivatePreview(for noteID: String, candidate: HoverCandidate, finalFrame: CGRect) {
        guard Date().timeIntervalSince(candidate.since) >= previewActivationDelay(for: candidate.intent) else { return }
        guard activePreviewIntent != candidate.intent else { return }

        withAnimation(reorderSpring) {
            applyPreview(candidate.intent, dragging: noteID)
        }
        activePreviewIntent = candidate.intent
    }

    private func applyPreview(_ intent: HoverIntent, dragging noteID: String) {
        restoreDragBaseline()

        switch intent {
        case .group(let layout, let placeholder):
            syncLayoutState(from: layout)
            groupPreviewPlaceholder = placeholder
        case .reorder(let layout):
            syncLayoutState(from: layout)
            groupPreviewPlaceholder = nil
        case .delete:
            groupPreviewPlaceholder = nil
        }
    }

    private func previewActivationDelay(for intent: HoverIntent) -> TimeInterval {
        switch intent {
        case .delete:
            return 0
        case .group, .reorder:
            return reorderHoverDwellDuration
        }
    }

    private func trashHoverResolution(for noteID: String, finalFrame: CGRect) -> HoverResolution? {
        guard isReorderMode,
              !trashTargetFrame.isNull,
              let pointer = dragTouchPointGlobal ?? noteHitFrames[noteID]?.center else {
            return nil
        }

        let commitFrame = trashTargetFrame.insetBy(dx: -10, dy: -20)
        let previewFrame = commitFrame.insetBy(dx: -14, dy: -12)
        guard previewFrame.contains(pointer) else { return nil }

        let previewBandDistance: CGFloat = 18
        let distanceToCommit = distance(from: pointer, to: commitFrame)
        let progress = max(0, min(1, 1 - (distanceToCommit / previewBandDistance)))
        let isCommitReady = progress >= 0.999

        return HoverResolution(
            intent: .delete,
            anchorPoint: trashTargetFrame.center,
            deletePreviewProgress: progress,
            isDeleteCommitReady: isCommitReady
        )
    }

    private func resetDeletePreviewState() {
        deletePreviewProgress = 0
        isDeleteCommitReady = false
    }

    private func resolvedDragScaleAnchor(for noteID: String, touchPoint: CGPoint?) -> UnitPoint {
        guard let touchPoint,
              let frame = noteHitFrames[noteID],
              frame.width > 0,
              frame.height > 0 else {
            return .center
        }

        let normalizedX = min(max((touchPoint.x - frame.minX) / frame.width, 0), 1)
        let normalizedY = min(max((touchPoint.y - frame.minY) / frame.height, 0), 1)
        return UnitPoint(x: normalizedX, y: normalizedY)
    }

    private func presentDeleteConfirmation(for noteID: String) {
        pendingDeleteNoteID = noteID
        isDeleteConfirmationBusy = false
        withAnimation(.spring(response: 0.26, dampingFraction: 0.86)) {
            isDeleteConfirmationPresented = true
        }
    }

    private func dismissDeleteConfirmation() {
        guard !isDeleteConfirmationBusy else { return }
        withAnimation(.easeOut(duration: 0.16)) {
            isDeleteConfirmationPresented = false
        }
        pendingDeleteNoteID = nil
    }

    private func confirmDelete() {
        guard let noteID = pendingDeleteNoteID, !isDeleteConfirmationBusy else { return }
        isDeleteConfirmationBusy = true
        deletingNoteSnapshot = state.notes.first(where: { $0.id == noteID })
        let fadeDuration: Double = 0.18

        withAnimation(.easeOut(duration: fadeDuration)) {
            deletingNoteID = noteID
            isDeleteConfirmationPresented = false
        }
        pendingDeleteNoteID = nil

        Task {
            try? await Task.sleep(nanoseconds: UInt64(fadeDuration * 1_000_000_000))
            let deleted = await onDeleteNote(noteID)
            await MainActor.run {
                isDeleteConfirmationBusy = false
                if !deleted {
                    withAnimation(.easeOut(duration: 0.16)) {
                        deletingNoteID = nil
                        deletingNoteSnapshot = nil
                    }
                }
            }
        }
    }

    private func deleteConfirmationOverlay(containerSize: CGSize, safeAreaInsets: EdgeInsets) -> some View {
        let cardWidth = min(containerSize.width - 36, 296)
        let anchorX = trashTargetFrame.isNull
            ? containerSize.width - 18 - (cardWidth * 0.5)
            : min(
                max(trashTargetFrame.maxX - (cardWidth * 0.5), 18 + (cardWidth * 0.5)),
                containerSize.width - 18 - (cardWidth * 0.5)
            )
        let anchorY = trashTargetFrame.isNull
            ? safeAreaInsets.top + 78
            : max(trashTargetFrame.maxY + 42, safeAreaInsets.top + 78)

        return ZStack {
            Color.black.opacity(0.08)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    dismissDeleteConfirmation()
                }

            VStack(alignment: .leading, spacing: 16) {
                Text("throw this thought into the trash can?")
                    .font(AppFont.body(18))
                    .foregroundStyle(.black.opacity(0.88))

                HStack {
                    Button("cancel") {
                        dismissDeleteConfirmation()
                    }
                    .font(AppFont.meta(11))
                    .tracking(1.2)
                    .foregroundStyle(.black.opacity(0.56))
                    .buttonStyle(.plain)

                    Spacer(minLength: 0)

                    Button(action: confirmDelete) {
                        Text(isDeleteConfirmationBusy ? "trashing..." : "trash it")
                            .font(AppFont.meta(11))
                            .tracking(1.2)
                            .foregroundStyle(Color(red: 0.74, green: 0.17, blue: 0.14))
                    }
                    .buttonStyle(.plain)
                    .disabled(isDeleteConfirmationBusy)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .frame(width: cardWidth, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(noteSurfaceColor)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(noteBorderColor.opacity(0.94), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.08), radius: 18, x: 0, y: 10)
            .position(x: anchorX, y: anchorY)
            .transition(.scale(scale: 0.84, anchor: .topTrailing).combined(with: .opacity))
        }
        .transition(.opacity)
    }

    private func reorderIntentForUngroupedNote(noteID: String, finalFrame: CGRect, baseLayout: ColumnLayout) -> HoverIntent? {
        let startFrame = dragStartFrame ?? noteFrames[noteID] ?? finalFrame
        let travelDistance = distance(startFrame.center, finalFrame.center)

        guard travelDistance >= reorderMinimumTravelDistance else {
            return nil
        }

        guard let reorderedLayout = reorderedLayoutForUngroupedNote(noteID: noteID, finalFrame: finalFrame, baseLayout: baseLayout),
              reorderedLayout != baseLayout else {
            return nil
        }

        return .reorder(layout: reorderedLayout)
    }

    private func groupedLayout(for noteID: String, targetID: String, baseLayout: ColumnLayout) -> (layout: ColumnLayout, placeholder: GroupPreviewPlaceholder?)? {
        let removal = removing(noteID: noteID, from: baseLayout)
        guard let targetLocation = location(of: targetID, in: removal.layout) else { return nil }
        var layout = removal.layout
        let columnItems = items(in: targetLocation.side, from: layout)
        guard columnItems.indices.contains(targetLocation.index) else { return nil }
        let targetItem = columnItems[targetLocation.index]
        let updatedGroupIDs = groupedNoteIDs(adding: noteID, below: targetID, in: targetItem.noteIDs)
        set(item: .group(updatedGroupIDs), at: targetLocation, in: &layout)
        let placeholder = downwardGroupingPlaceholder(for: noteID, targetID: targetID, origin: removal.origin, baseLayout: baseLayout)
        return (layout, placeholder)
    }

    private func downwardGroupingPlaceholder(for noteID: String, targetID: String, origin: ColumnLocation?, baseLayout: ColumnLayout) -> GroupPreviewPlaceholder? {
        guard let origin,
              let note = displayNotes.first(where: { $0.id == noteID }),
              let startFrame = dragStartFrame ?? noteFrames[noteID],
              let targetFrame = noteFrames[targetID],
              targetFrame.midY > startFrame.midY else {
            return nil
        }

        let placeholderHeight = measuredItemHeights[noteID] ?? estimatedHomeNoteCardHeight(for: note)
        let memberIndex = item(at: origin, in: baseLayout)?.noteIDs.firstIndex(of: noteID)
        return GroupPreviewPlaceholder(
            side: origin.side,
            index: origin.index,
            height: placeholderHeight,
            noteID: noteID,
            memberIndex: memberIndex
        )
    }

    private func reorderedLayoutForUngroupedNote(noteID: String, finalFrame: CGRect, baseLayout: ColumnLayout) -> ColumnLayout? {
        let removal = removing(noteID: noteID, from: baseLayout)
        guard let destination = reorderDestination(for: finalFrame, in: removal.layout) else { return nil }
        var layout = removal.layout
        insert(item: .note(noteID), at: destination, in: &layout)
        return layout
    }

    private func reorderedLayoutForGroupedNote(noteID: String, finalFrame: CGRect, baseLayout: ColumnLayout) -> ColumnLayout? {
        let removal = removing(noteID: noteID, from: baseLayout)
        var layout = removal.layout

        if let destination = reorderDestination(for: finalFrame, in: layout) {
            insert(item: .note(noteID), at: destination, in: &layout)
            return layout
        }

        guard let origin = removal.origin else { return nil }
        let fallbackIndex = min(origin.index + 1, items(in: origin.side, from: layout).count)
        insert(item: .note(noteID), at: ColumnLocation(side: origin.side, index: fallbackIndex), in: &layout)
        return layout
    }

    private func insertionSlotYPositions(for orderWithoutDragged: [String]) -> [CGFloat] {
        guard !orderWithoutDragged.isEmpty else { return [] }

        var slots: [CGFloat] = []
        if let firstFrame = noteFrames[orderWithoutDragged[0]] {
            slots.append(firstFrame.minY)
        }

        for index in 0..<(orderWithoutDragged.count - 1) {
            guard let lhs = noteFrames[orderWithoutDragged[index]],
                  let rhs = noteFrames[orderWithoutDragged[index + 1]] else { continue }
            slots.append((lhs.maxY + rhs.minY) * 0.5)
        }

        if let lastFrame = noteFrames[orderWithoutDragged[orderWithoutDragged.count - 1]] {
            slots.append(lastFrame.maxY)
        }

        return slots
    }

    private func restoreDragBaseline() {
        groupPreviewPlaceholder = nil
        if !dragBaseColumnLayout.isEmpty {
            syncLayoutState(from: dragBaseColumnLayout)
            return
        }
        orderedNoteIDs = dragBaseOrder.isEmpty ? orderedNoteIDs : dragBaseOrder
        affinityGroups = dragBaseAffinityGroups
    }

    private func reorderedIDs(noteID: String, finalFrame: CGRect, using order: [String]) -> [String] {
        var newOrder = order.filter { $0 != noteID }
        let targetPoints = noteFrames
            .filter { $0.key != noteID }
            .map { (id: $0.key, center: CGPoint(x: $0.value.midX, y: $0.value.midY)) }

        guard let nearest = targetPoints.min(by: {
            distance($0.center, finalFrame.center) < distance($1.center, finalFrame.center)
        }), let targetIndex = newOrder.firstIndex(of: nearest.id) else {
            newOrder.append(noteID)
            return newOrder
        }

        let insertIndex = finalFrame.midY < nearest.center.y ? targetIndex : targetIndex + 1
        newOrder.insert(noteID, at: min(insertIndex, newOrder.count))
        return newOrder
    }

    private func distance(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }

    private func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let clampedX = min(max(point.x, rect.minX), rect.maxX)
        let clampedY = min(max(point.y, rect.minY), rect.maxY)
        return distance(point, CGPoint(x: clampedX, y: clampedY))
    }

    private func enterReorderMode() {
        guard !isReorderMode else { return }
        triggerReorderEntryHaptic()
        if !homeHeaderFrame.isNull {
            frozenTrashTargetTopInset = homeHeaderFrame.minY
        }
        isReorderMode = true
        withAnimation(.easeOut(duration: 0.22)) {
            jiggleProgress = 1
        }
    }

    private func enterReorderGesture(noteID: String) -> some Gesture {
        LongPressGesture(minimumDuration: 0.65)
            .onEnded { _ in
                enterReorderMode()
            }
    }

    private func triggerReorderEntryHaptic() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred(intensity: 0.7)
    }

    private func triggerReorderExitHaptic() {
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
    }

    private func dragGesture(noteID: String) -> some Gesture {
        DragGesture(
            minimumDistance: isReorderMode ? 0 : 10_000,
            coordinateSpace: .named("home-scroll")
        )
            .onChanged { value in
                guard isReorderMode else { return }
                beginDragging(noteID)
                guard activeDragNoteID == noteID else { return }
                dragTranslation = value.translation
                updateHoverIntent(for: noteID, translation: value.translation)
            }
            .onEnded { value in
                guard isReorderMode, activeDragNoteID == noteID else { return }
                endDragging(noteID: noteID, translation: value.translation)
            }
    }

    private func pressThenDragGesture(noteID: String) -> some Gesture {
        LongPressGesture(minimumDuration: reorderScrollableDragHoldDuration)
            .sequenced(before: DragGesture(coordinateSpace: .named("home-scroll")))
            .onChanged { value in
                guard isReorderMode else { return }

                switch value {
                case .first(true):
                    beginDragging(noteID)
                case .second(true, let drag?):
                    beginDragging(noteID)
                    guard activeDragNoteID == noteID else { return }
                    dragTranslation = drag.translation
                    updateHoverIntent(for: noteID, translation: drag.translation)
                default:
                    break
                }
            }
            .onEnded { value in
                guard isReorderMode else { return }

                switch value {
                case .second(true, let drag?):
                    guard activeDragNoteID == noteID else { return }
                    endDragging(noteID: noteID, translation: drag.translation)
                default:
                    clearDragArming()
                }
            }
    }

    private func phaseSeed(for id: String) -> Double {
        let scalarSum = id.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return Double(scalarSum % 13) / 13.0
    }

    private func rubberBandOffset(for translation: CGFloat) -> CGFloat {
        let direction: CGFloat = translation >= 0 ? 1 : -1
        let magnitude = pow(abs(translation), 0.82) * 0.78
        return direction * magnitude
    }

//    private func reorderInstruction(bottomInset: CGFloat) -> some View {
//        ReorderMarqueeView(
//            message: "drag to reorder · overlap another card to create an affinity group · swipe up to exit ·"
//        )
//        .frame(height: 46)
//        .frame(maxWidth: .infinity)
//        .padding(.horizontal, 18)
//        .padding(.bottom, max(bottomInset, 10))
//        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
//        .gesture(
//            DragGesture(minimumDistance: 6)
//                .onEnded { value in
//                    if value.translation.height < -18 {
//                        cancelDragging()
//                    }
//                }
//        )
//        .transition(.move(edge: .bottom).combined(with: .opacity))
//    }
}

extension HomeScreen: Equatable {
    static func == (lhs: HomeScreen, rhs: HomeScreen) -> Bool {
        lhs.state == rhs.state
    }
}

//private struct ReorderMarqueeView: View {
//    let message: String
//    @State private var segmentWidth: CGFloat = 1
//
//    var body: some View {
//        GeometryReader { geometry in
//            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
//                let distance = CGFloat(timeline.date.timeIntervalSinceReferenceDate) * 42
//                let wrapWidth = max(segmentWidth + 24, 1)
//                let xOffset = -(distance.truncatingRemainder(dividingBy: wrapWidth))
//
//                HStack(spacing: 24) {
//                    marqueeSegment
//                        .background(
//                            GeometryReader { proxy in
//                                Color.clear.preference(key: MarqueeWidthPreferenceKey.self, value: proxy.size.width)
//                            }
//                        )
//                    marqueeSegment
//                    marqueeSegment
//                }
//                .offset(x: xOffset)
//                .frame(width: geometry.size.width, alignment: .leading)
//            }
//            .clipped()
//            .onPreferenceChange(MarqueeWidthPreferenceKey.self) { width in
//                if width > 0 {
//                    segmentWidth = width
//                }
//            }
//        }
//    }
//
//    private var marqueeSegment: some View {
//        Text(message)
//            .font(AppFont.meta(12))
//            .tracking(1.4)
//            .textCase(.uppercase)
//            .foregroundStyle(.black.opacity(0.72))
//            .fixedSize()
//    }
//}

//private struct MarqueeWidthPreferenceKey: PreferenceKey {
//    static var defaultValue: CGFloat = 0
//
//    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
//        value = max(value, nextValue())
//    }
//}

private struct HomeBackgroundView: View {
    var body: some View {
        ZStack {
            Image("HomeBackground")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color(red: 0.98, green: 0.98, blue: 0.96).opacity(0.06),
                    Color(red: 0.96, green: 0.97, blue: 0.94).opacity(0.24),
                    Color(red: 0.95, green: 0.95, blue: 0.93).opacity(0.34)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }
}

private struct NewNoteScreen: View {
    @ObservedObject var viewModel: ContentViewModel
    let transitionNamespace: Namespace.ID
    @FocusState private var isEditorFocused: Bool
    @State private var showContent: Bool = false
    @State private var isClosing: Bool = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Rectangle()
                    .fill(Color.white.opacity(0.001))
                    .ignoresSafeArea()
                    .onTapGesture {
                        closeNewNote()
                    }

                VStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .fill(noteSurfaceColor)
                            .matchedGeometryEffect(id: "new-thought-surface", in: transitionNamespace)
                            .shadow(color: noteShadowColor.opacity(0.72), radius: 18, x: 0, y: 12)

                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .stroke(noteBorderColor, lineWidth: 1)
                            .matchedGeometryEffect(id: "new-thought-stroke", in: transitionNamespace)

                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 6]))
                            .foregroundStyle(noteBorderColor.opacity(0.95))
                            .matchedGeometryEffect(id: "new-thought-dashed", in: transitionNamespace)
                            .opacity(showContent || isClosing ? 0 : 1)

                        VStack(alignment: .leading, spacing: 0) {
                            if showContent {
                                newNoteContent
                            }
                        }
                        .opacity(showContent ? 1 : 0)
                    }
                    .frame(width: max(geometry.size.width - 36, 0), height: 248, alignment: .topLeading)
                    .padding(.top, geometry.safeAreaInsets.top)

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .ignoresSafeArea(.keyboard)
        .task {
            try? await Task.sleep(nanoseconds: UInt64(noteMorphDuration * 1_000_000_000))
            withAnimation(.easeOut(duration: 0.22)) {
                showContent = true
            }
            try? await Task.sleep(nanoseconds: 120_000_000)
            isEditorFocused = true
        }
    }

    private func closeNewNote() {
        guard !isClosing else { return }
        isClosing = true
        isEditorFocused = false

        withAnimation(.easeOut(duration: 0.14)) {
            showContent = false
        }

        Task {
            try? await Task.sleep(nanoseconds: 110_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(noteTransitionAnimation) {
                    viewModel.discardDraft()
                }
            }
        }
    }

    private var newNoteContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                if viewModel.draftText.isEmpty {
                    Text("start a thought")
                        .font(AppFont.meta(11))
                        .tracking(1.2)
                        .foregroundStyle(.black.opacity(0.34))
                        .padding(.top, 5)
                }

                TextField("", text: $viewModel.draftText, axis: .vertical)
                    .focused($isEditorFocused)
                    .textFieldStyle(.plain)
                    .font(AppFont.body(21))
                    .foregroundStyle(.black)
                    .lineLimit(1...8)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .frame(maxWidth: .infinity, minHeight: 172, alignment: .topLeading)

            HStack {
                Button("cancel") {
                    closeNewNote()
                }
                .font(AppFont.meta(11))
                .tracking(1.2)
                .foregroundStyle(.black.opacity(0.58))
                .buttonStyle(.plain)

                Spacer()

                Button {
                    isEditorFocused = false
                    Task {
                        await viewModel.autosaveDraftIfNeeded()
                        let newID = viewModel.draftNoteID
                        withAnimation(noteTransitionAnimation) {
                            viewModel.addMorphTargetNoteID = newID
                            viewModel.screen = .home
                        }
                        try? await Task.sleep(nanoseconds: UInt64(noteMorphDuration * 1_000_000_000))
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            viewModel.addMorphTargetNoteID = nil
                        }
                    }
                } label: {
                    Text("add")
                        .font(AppFont.meta(11))
                        .tracking(1.2)
                        .foregroundStyle(noteAccentColor)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.trimmedDraftText.isEmpty || viewModel.isDraftSaving)
            }
            .padding(.horizontal, 24)
            .padding(.top, 36)
            .padding(.bottom, 24)
        }
    }
}

private struct NoteFullPageScreen: View {
    @ObservedObject var viewModel: ContentViewModel
    let note: APINote
    let transitionNamespace: Namespace.ID
    @State private var followUpDraft = ""
    @FocusState private var isFollowUpFocused: Bool
    @State private var currentThread: APIConversationThread?
    @State private var isEnriching = false
    @State private var isSendingFollowUp = false
    @State private var showChrome = false
    @State private var showPrimaryContent = false
    @State private var showGrowthContent = false
    @State private var showFootnoteContent = false
    @State private var isClosing = false
    @State private var dragOffset: CGFloat = 0
    @State private var detailContentOffsetY: CGFloat = 0
    @State private var detailTopContentOffsetY: CGFloat = 0
    @State private var detailAnchorPositions: [String: CGFloat] = [:]
    @State private var detailAnchorBaselines: [String: CGFloat] = [:]
    @State private var homeIndicatorHeight: CGFloat = 18

    var body: some View {
        GeometryReader { geometry in
            let topInset = geometry.safeAreaInsets.top

            ZStack(alignment: .topTrailing) {
                detailSurface(topInset: topInset)

                Button {
                    closeDetail()
                } label: {
                    Text("home")
                        .font(AppFont.meta(11))
                        .tracking(1.2)
                        .foregroundStyle(noteAccentColor)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .glassCapsuleButtonChrome()
                }
                .padding(.top, 8)
                .padding(.trailing, 18)
                .opacity(showChrome ? 1 : 0)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .coordinateSpace(name: "detail-surface")
            .offset(y: dragOffset)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard !isClosing else { return }
                        let dy = value.translation.height
                        let dx = value.translation.width
                        guard dy > 18, dy > abs(dx), isDetailAtTop || dragOffset > 0 else { return }
                        dragOffset = dy * 0.55
                    }
                    .onEnded { value in
                        guard !isClosing else { return }
                        let dy = value.translation.height
                        let dx = value.translation.width
                        let predicted = value.predictedEndTranslation.height
                        let wasEligible = isDetailAtTop || dragOffset > 0
                        guard dy > 18, dy > abs(dx), wasEligible else {
                            if dragOffset > 0 {
                                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                                    dragOffset = 0
                                }
                            }
                            return
                        }
                        if dy > 120 || predicted > 220 {
                            closeDetail()
                        } else {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                                dragOffset = 0
                            }
                        }
                    }
            )
            .onAppear {
                detailContentOffsetY = 0
                detailTopContentOffsetY = 0
                detailAnchorPositions = [:]
                detailAnchorBaselines = [:]
                followUpDraft = ""
                startOpenSequence()
            }
            .onChange(of: note.id) { _, _ in
                detailContentOffsetY = 0
                detailTopContentOffsetY = 0
                detailAnchorPositions = [:]
                detailAnchorBaselines = [:]
                dragOffset = 0
                followUpDraft = ""
                startOpenSequence()
            }
            .task(id: note.id) {
                currentThread = await viewModel.fetchConversationThread(noteID: note.id)
            }
            .background(
                GeometryReader { bg in
                    Color.clear.preference(key: HomeIndicatorHeightKey.self, value: max(bg.safeAreaInsets.bottom, 18))
                }
                .ignoresSafeArea(.keyboard)
            )
            .onPreferenceChange(HomeIndicatorHeightKey.self) { value in
                homeIndicatorHeight = value
            }
        }
    }

    private var isDetailAtTop: Bool {
        detailContentOffsetY <= detailTopContentOffsetY + detailDismissTopThreshold
    }

    private var surfaceCornerRadius: CGFloat {
        if dragOffset > 0 {
            let progress = min(max((dragOffset - detailDismissCornerRadiusStart) / detailDismissCornerRadiusTravel, 0), 1)
            return 47 * progress
        }
        return showPrimaryContent ? 0 : 30
    }


    private func detailSurface(
        topInset: CGFloat
    ) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: surfaceCornerRadius, style: .continuous)
                .fill(noteSurfaceColor)
                .matchedGeometryEffect(id: "note-surface-\(note.id)", in: transitionNamespace)
                .shadow(color: noteShadowColor, radius: 24, x: 0, y: 12)
                .ignoresSafeArea()

            RoundedRectangle(cornerRadius: surfaceCornerRadius, style: .continuous)
                .stroke(noteBorderColor.opacity(0.72), lineWidth: 1)
                .matchedGeometryEffect(id: "note-stroke-\(note.id)", in: transitionNamespace)
                .ignoresSafeArea()

            if showPrimaryContent {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        metaStrip
                            .detailDebugAnchor(id: "meta-strip")
                            .padding(.top, 22)

                        Text(note.displayHeadline)
                            .font(AppFont.heading(26))
                            .lineSpacing(4)
                            .foregroundStyle(.black)
                            .detailDebugAnchor(id: "thought-body")
                            .detailDebugAnchor(id: detailPrimaryScrollAnchorID)
                            .padding(.top, 22)

                        divider
                            .padding(.top, 30)

                        if shouldShowCenteredCreepingSection {
                            centeredCreepingSection
                                .padding(.top, 28)
                        }

                        if hasAIGrowthParagraphs {
                            aiGrowthSection
                                .padding(.top, 26)

                            if shouldShowInlineContinueThoughtCTA {
                                inlineContinueThoughtCTA
                                    .padding(.top, 28)
                            }
                        }

                        if !note.sources.isEmpty {
                            footnotesSection
                                .padding(.top, 28)
                        }

                        if !note.prompts.isEmpty {
                            openAnglesSection
                                .padding(.top, 28)
                        }

                        if let latestReply = note.latestChatReply, !latestReply.isEmpty {
                            latestReplySection(latestReply)
                                .padding(.top, 28)
                        }

                        if let pendingFollowUp = pendingFollowUpText {
                            pendingFollowUpSection(pendingFollowUp)
                                .padding(.top, 28)
                        }

                        if shouldShowRequestResponseOnlyCTA && isEnriching {
                            centeredExploringSection
                                .padding(.top, 28)
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 24)
                }
                .scrollDisabled(dragOffset > 0)
                .onPreferenceChange(DetailAnchorPreferenceKey.self) { anchors in
                    detailAnchorPositions = anchors
                    for (id, value) in anchors where detailAnchorBaselines[id] == nil {
                        detailAnchorBaselines[id] = value
                    }
                    detailTopContentOffsetY = 0
                    if let current = anchors[detailPrimaryScrollAnchorID],
                       let baseline = detailAnchorBaselines[detailPrimaryScrollAnchorID] {
                        detailContentOffsetY = max(baseline - current, 0)
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    bottomBar(bottomInset: homeIndicatorHeight)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var metaStrip: some View {
        HStack(spacing: 16) {
            Color.clear
                .frame(width: 0, height: noteCardMetaLineHeight())
                .overlay(alignment: .leading) {
                    Text(noteTimestamp)
                        .font(AppFont.meta(10))
                        .tracking(1.6)
                        .foregroundStyle(.black.opacity(0.5))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
        }
        .opacity(showPrimaryContent ? 1 : 0)
    }

    private var aiGrowthSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(Array(growthParagraphs.enumerated()), id: \.offset) { _, paragraph in
                Text(paragraph)
                    .font(AppFont.body(19))
                    .lineSpacing(4)
                    .foregroundStyle(.black.opacity(0.82))
            }
        }
        .opacity(showGrowthContent ? 1 : 0)
        .offset(y: showGrowthContent ? 0 : 12)
    }

    private var inlineContinueThoughtCTA: some View {
        Group {
            if isEnriching {
                centeredExploringSection
            } else {
                HStack {
                    Spacer()

                    Button {
                        Task { await requestResponse() }
                    } label: {
                        Text("continue creeping")
                            .font(AppFont.meta(11))
                            .tracking(1.2)
                            .foregroundStyle(noteAccentColor)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .glassCapsuleButtonChrome()
                    }

                    Spacer()
                }
            }
        }
        .opacity(showGrowthContent ? 1 : 0)
        .offset(y: showGrowthContent ? 0 : 12)
    }

    private var openAnglesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("open angles")

            ForEach(Array(note.prompts.enumerated()), id: \.offset) { _, prompt in
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(noteAccentColor.opacity(0.78))
                        .frame(width: 5, height: 5)
                        .padding(.top, 9)

                    Text(prompt)
                        .font(AppFont.body(17))
                        .lineSpacing(3)
                        .foregroundStyle(.black.opacity(0.82))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        askAboutPrompt(prompt)
                    } label: {
                        Text("ask")
                            .font(AppFont.meta(11))
                            .tracking(1.2)
                            .foregroundStyle(noteAccentColor)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .glassCapsuleButtonChrome()
                    }
                    .padding(.top, -2)
                }
            }
        }
        .opacity(showGrowthContent ? 1 : 0)
        .offset(y: showGrowthContent ? 0 : 12)
    }

    private var footnotesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionLabel("footnotes")
                .padding(.horizontal, 28)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(note.sources) { source in
                        Link(destination: URL(string: source.url) ?? URL(string: "https://example.com")!) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(sourceHost(source.url))
                                    .font(AppFont.meta(11))
                                    .tracking(1.2)
                                    .textCase(.uppercase)
                                    .foregroundStyle(.black.opacity(0.46))

                                Text(source.title)
                                    .font(AppFont.heading(18, weight: .semibold))
                                    .foregroundStyle(.black)

                                Text(source.snippet)
                                    .font(AppFont.body(15))
                                    .lineSpacing(2)
                                    .foregroundStyle(.black.opacity(0.72))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .fill(Color.white.opacity(0.94))
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .stroke(noteBorderColor, lineWidth: 1)
                            }
                            .shadow(color: .black.opacity(0.035), radius: 10, x: 0, y: 6)
                        }
                        .buttonStyle(.plain)
                        .containerRelativeFrame(.horizontal, count: 3, span: 2, spacing: 14)
                    }
                }
                .padding(.horizontal, 28)
                .scrollTargetLayout()
            }
        }
        .padding(.horizontal, -28)
        .opacity(showFootnoteContent ? 1 : 0)
        .offset(y: showFootnoteContent ? 0 : 12)
    }

    private func latestReplySection(_ reply: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("latest reply")

            VStack(alignment: .leading, spacing: 20) {
                ForEach(Array(paragraphs(from: reply).enumerated()), id: \.offset) { _, paragraph in
                    Text(paragraph)
                        .font(AppFont.body(18))
                        .lineSpacing(3)
                        .foregroundStyle(.black.opacity(0.82))
                }
            }
        }
        .opacity(showGrowthContent ? 1 : 0)
        .offset(y: showGrowthContent ? 0 : 12)
    }

    private func pendingFollowUpSection(_ followUp: String) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            divider

            VStack(alignment: .leading, spacing: 20) {
                ForEach(Array(paragraphs(from: followUp).enumerated()), id: \.offset) { _, paragraph in
                    Text(paragraph)
                        .font(AppFont.body(19))
                        .lineSpacing(4)
                        .foregroundStyle(noteAccentColor.opacity(0.78))
                }
            }
        }
        .opacity(showGrowthContent ? 1 : 0)
        .offset(y: showGrowthContent ? 0 : 12)
    }

    private func bottomBar(bottomInset: CGFloat) -> some View {
        VStack(spacing: 12) {
            if shouldShowRequestResponseOnlyCTA {
                Group {
                    if !isEnriching {
                        VStack(spacing: 10) {
                            Button {
                                Task { await requestResponse() }
                            } label: {
                                Text("grow this idea")
                                    .font(AppFont.meta(11))
                                    .tracking(1.2)
                                    .foregroundStyle(noteAccentColor)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .glassCapsuleButtonChrome()
                            }

                            if note.status == "failed" {
                                Text("AI couldn’t respond last time. Try again.")
                                    .font(AppFont.meta(10))
                                    .tracking(1.0)
                                    .foregroundStyle(.black.opacity(0.46))
                                    .multilineTextAlignment(.center)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            } else {
                HStack(alignment: .center, spacing: 12) {
                    ZStack(alignment: .leading) {
                        if followUpDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("Ask about this")
                                .font(AppFont.meta(11))
                                .tracking(1.2)
                                .foregroundStyle(.black.opacity(0.34))
                        }

                        TextField("", text: $followUpDraft, axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(AppFont.meta(11))
                            .tracking(1.2)
                            .foregroundStyle(.black)
                            .focused($isFollowUpFocused)
                            .lineLimit(1...4)
                    }

                    if !followUpDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button("send") {
                            Task { await sendFollowUp() }
                        }
                        .font(AppFont.meta(11))
                        .tracking(1.2)
                        .foregroundStyle(noteAccentColor)
                        .buttonStyle(.plain)
                        .disabled(
                            isEnriching ||
                            isSendingFollowUp
                        )
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(Color(red: 0.985, green: 0.985, blue: 0.98))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(noteBorderColor.opacity(0.92), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.035), radius: 10, x: 0, y: 6)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, bottomInset)
        .coordinateSpace(name: "detail-bottom-bar")
        .background(
            LinearGradient(
                colors: [
                    noteSurfaceColor.opacity(0),
                    noteSurfaceColor.opacity(0.88),
                    noteSurfaceColor.opacity(0.98)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .opacity(showChrome ? 1 : 0)
        .offset(y: showChrome ? 0 : 10)
    }

    private var shouldShowDeferredGrowthCTA: Bool {
        note.enrichments.isEmpty &&
        note.latestChatReply == nil &&
        ["queued", "retrying", "running"].contains(note.status)
    }

    private var isAwaitingAssistantReply: Bool {
        guard let currentThread else { return false }
        return currentThread.messages.last?.role == MessageRole.user.rawValue
    }

    private var shouldShowRequestResponseOnlyCTA: Bool {
        shouldShowDeferredGrowthCTA || isAwaitingAssistantReply
    }

    private var pendingFollowUpText: String? {
        guard let currentThread,
              let lastMessage = currentThread.messages.last,
              lastMessage.role == MessageRole.user.rawValue else {
            return nil
        }
        return lastMessage.text
    }

    private var shouldShowInlineContinueThoughtCTA: Bool {
        hasAIGrowthParagraphs && !isAwaitingAssistantReply
    }

    private var growthParagraphs: [String] {
        let expansion = note.enrichments.first?.expansion.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return paragraphs(from: expansion)
    }

    private var hasAIGrowthParagraphs: Bool {
        !growthParagraphs.isEmpty
    }

    private var shouldShowCenteredCreepingSection: Bool {
        guard !hasAIGrowthParagraphs else { return false }
        guard pendingFollowUpText == nil else { return false }
        guard (note.latestChatReply?.isEmpty ?? true) else { return false }
        guard note.prompts.isEmpty else { return false }
        guard note.sources.isEmpty else { return false }
        guard ["queued", "running", "retrying"].contains(note.status) else { return false }
        return Date().timeIntervalSince(note.createdAt) < 24 * 60 * 60
    }

    private var centeredExploringSection: some View {
        HStack {
            Spacer()
            ExploringLoadingLabel()
            Spacer()
        }
    }

    private var centeredCreepingSection: some View {
        HStack {
            Spacer()
            AnimatedLoadingLabel(
                baseText: "creeping",
                color: noteAccentColor,
                trailingText: nil
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            Spacer()
        }
    }

    private func requestResponse() async {
        guard !isEnriching else { return }
        isEnriching = true
        defer { isEnriching = false }

        guard await viewModel.requestResponse(for: note.id) else { return }
        currentThread = await viewModel.fetchConversationThread(noteID: note.id)
    }

    private func sendFollowUp() async {
        guard !isSendingFollowUp else { return }
        let message = followUpDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }

        isSendingFollowUp = true
        defer { isSendingFollowUp = false }

        guard await viewModel.sendFollowUp(noteID: note.id, message: message) else { return }
        followUpDraft = ""
        currentThread = await viewModel.fetchConversationThread(noteID: note.id)
    }

    private func askAboutPrompt(_ prompt: String) {
        followUpDraft = prompt
        isFollowUpFocused = true
    }

    private func paragraphs(from text: String) -> [String] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return [] }

        var result: [String] = []
        var current: [String] = []

        for line in normalized.components(separatedBy: .newlines) {
            if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if !current.isEmpty {
                    result.append(current.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines))
                    current.removeAll()
                }
            } else {
                current.append(line)
            }
        }

        if !current.isEmpty {
            result.append(current.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return result.filter { !$0.isEmpty }
    }

    private var noteTimestamp: String {
        noteDetailTimestampLabel(for: note.updatedAt)
    }

    private var divider: some View {
        LinearGradient(
            colors: [
                .clear,
                noteBorderColor,
                .clear
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(height: 1)
        .opacity(showPrimaryContent ? 1 : 0)
    }

    private func startOpenSequence() {
        isClosing = false
        showChrome = false
        showPrimaryContent = false
        showGrowthContent = false
        showFootnoteContent = false

        Task {
            try? await Task.sleep(nanoseconds: UInt64(noteMorphDuration * 1_000_000_000))
            guard !isClosing else { return }

            withAnimation(.easeOut(duration: 0.18)) {
                showChrome = true
                showPrimaryContent = true
            }

            try? await Task.sleep(nanoseconds: 320_000_000)
            guard !isClosing else { return }
            withAnimation(.easeOut(duration: 0.5)) {
                showGrowthContent = true
            }

            try? await Task.sleep(nanoseconds: 360_000_000)
            guard !isClosing else { return }
            withAnimation(.easeOut(duration: 0.5)) {
                showFootnoteContent = true
            }
        }
    }

    private func closeDetail() {
        guard !isClosing else { return }
        isClosing = true

        let fromDrag = dragOffset > 10

        withAnimation(.easeOut(duration: 0.16)) {
            showChrome = false
        }

        if fromDrag {
            showPrimaryContent = false
            showGrowthContent = false
            showFootnoteContent = false
            withAnimation(noteTransitionAnimation) {
                dragOffset = 0
                viewModel.returnHome()
            }
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            guard isClosing else { return }
            withAnimation(.easeOut(duration: 0.12)) {
                showPrimaryContent = false
                showGrowthContent = false
                showFootnoteContent = false
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) {
            guard isClosing else { return }
            withAnimation(noteTransitionAnimation) {
                viewModel.returnHome()
            }
        }
    }

    private func sectionLabel(_ title: String, useAccent: Bool = false) -> some View {
        Text(title)
            .font(AppFont.meta(11))
            .tracking(1.8)
            .textCase(.uppercase)
            .foregroundStyle(useAccent ? noteAccentColor : .black.opacity(0.5))
    }


    private func sourceHost(_ urlString: String) -> String {
        guard let url = URL(string: urlString), let host = url.host else {
            return "citation"
        }
        return host.replacingOccurrences(of: "www.", with: "").lowercased()
    }
}

private struct ExploringLoadingLabel: View {
    var body: some View {
        AnimatedLoadingLabel(
            baseText: "exploring",
            color: noteAccentColor,
            trailingText: "check back later"
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

private struct AnimatedLoadingLabel: View {
    let baseText: String
    let color: Color
    let trailingText: String?
    @State private var dotCount = 1

    var body: some View {
        Text(
            baseText
            + String(repeating: ".", count: dotCount)
            + (trailingText.map { " " + $0 } ?? "")
        )
            .font(AppFont.meta(11))
            .tracking(1.2)
            .foregroundStyle(color)
            .lineLimit(1)
            .allowsTightening(true)
            .minimumScaleFactor(0.82)
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    dotCount = dotCount % 3 + 1
                }
            }
    }
}

private struct AssistantSheet: View {
    @ObservedObject var viewModel: ContentViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var assistantDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("AI Assistant")
                    .font(AppFont.heading(22, weight: .semibold))
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .foregroundStyle(.black)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let note = viewModel.currentNote {
                        Text("Current thought")
                            .font(AppFont.heading(18, weight: .semibold))
                        Text(note.text)
                            .font(AppFont.body(18))
                    } else {
                        Text("Start from a thought, question, or fragment.")
                            .font(AppFont.body(18))
                    }

                    TextField("Ask about this idea...", text: $assistantDraft, axis: .vertical)
                        .textFieldStyle(.roundedBorder)

                    Button("Save as thought") {
                        Task {
                            let text = assistantDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard await viewModel.createNoteFromAssistant(text: text) else { return }
                            assistantDraft = ""
                            dismiss()
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(assistantDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .padding(20)
        .presentationBackground(Color(red: 0.96, green: 0.96, blue: 0.96))
    }
}

private struct NoteCard: View {
    let note: APINote
    let rotation: Double
    let isReordering: Bool
    let isInReorderMode: Bool
    let phaseSeed: Double
    let jiggleProgress: CGFloat
    let transitionNamespace: Namespace.ID
    let isExpanded: Bool
    let isOutlineReady: Bool
    let isContentReady: Bool
    let isTransitionSource: Bool
    let animationDate: Date
    let isSurfaceTransitionEnabled: Bool

    init(
        note: APINote,
        rotation: Double,
        isReordering: Bool,
        isInReorderMode: Bool,
        phaseSeed: Double,
        jiggleProgress: CGFloat,
        transitionNamespace: Namespace.ID,
        isExpanded: Bool,
        isOutlineReady: Bool,
        isContentReady: Bool,
        isTransitionSource: Bool,
        animationDate: Date,
        isSurfaceTransitionEnabled: Bool = true
    ) {
        self.note = note
        self.rotation = rotation
        self.isReordering = isReordering
        self.isInReorderMode = isInReorderMode
        self.phaseSeed = phaseSeed
        self.jiggleProgress = jiggleProgress
        self.transitionNamespace = transitionNamespace
        self.isExpanded = isExpanded
        self.isOutlineReady = isOutlineReady
        self.isContentReady = isContentReady
        self.isTransitionSource = isTransitionSource
        self.animationDate = animationDate
        self.isSurfaceTransitionEnabled = isSurfaceTransitionEnabled
    }

    var body: some View {
        let jiggle = jiggleState(at: animationDate)
        let edgePhase = livingEdgePhase(at: animationDate)
        let edgeAmplitude = livingEdgeAmplitude
        let cometProgress = runningStrokeProgress(at: animationDate)

        VStack(alignment: .leading, spacing: 10) {
            summaryText

            HStack(alignment: .center, spacing: 12) {
                Color.clear
                    .frame(width: 0, height: noteCardMetaLineHeight())
                    .overlay(alignment: .leading) {
                        Text(noteTimestamp)
                            .font(AppFont.meta(10))
                            .tracking(1.2)
                            .foregroundStyle(.black.opacity(0.5))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }

                Spacer()

                if let statusText = statusText {
                    Text(statusText)
                        .font(AppFont.meta(11))
                        .tracking(1.2)
                        .textCase(.uppercase)
                        .foregroundStyle(hasAIResponse ? noteAccentColor : .black.opacity(0.62))
                        .lineLimit(1)
                        .allowsTightening(true)
                        .minimumScaleFactor(0.82)
                }
            }
        }
        .opacity(isContentReady ? 1 : 0)
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .applyNoteSurfaceTransition(
            id: "note-content-\(note.id)",
            namespace: transitionNamespace,
            isEnabled: isSurfaceTransitionEnabled
        )
        .background {
            ZStack {
                if !isExpanded {
                    LivingCellCardShape(phase: edgePhase, amplitude: edgeAmplitude)
                        .fill(noteSurfaceColor)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .applyNoteSurfaceTransition(
                            id: "note-surface-\(note.id)",
                            namespace: transitionNamespace,
                            isEnabled: isSurfaceTransitionEnabled
                        )

                    LivingCellCardShape(phase: edgePhase, amplitude: edgeAmplitude)
                        .stroke(
                            .clear,
                            lineWidth: isReordering ? 1.3 : 1
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .applyNoteSurfaceTransition(
                            id: "note-stroke-\(note.id)",
                            namespace: transitionNamespace,
                            isEnabled: isSurfaceTransitionEnabled
                        )
                } else {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .fill(Color.white.opacity(0.001))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay {
            if !isExpanded {
                ZStack {
                    BilayerCardOutline(
                        phase: edgePhase,
                        amplitude: edgeAmplitude,
                        innerColor: noteAccentColor,
                        innerOpacity: hasAIResponse ? 0.17 : 0.09
                    )
                    .opacity(isOutlineReady ? 1 : 0)
                    .animation(.easeOut(duration: 0.18), value: isOutlineReady)

                    ZStack {
                        LivingCellCardShape(phase: edgePhase, amplitude: edgeAmplitude)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        hasAIResponse ? noteAccentColor.opacity(0.055) : .clear,
                                        hasAIResponse ? noteAccentColor.opacity(0.016) : .clear,
                                        .clear
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )

                        if isActivelyGrowing {
                            RunningStrokeIndicator(
                                phase: edgePhase,
                                amplitude: edgeAmplitude,
                                progress: cometProgress,
                                color: noteAccentColor
                            )
                        }
                    }
                    .opacity(isContentReady ? 1 : 0)
                    .animation(.easeOut(duration: 0.18), value: isContentReady)
                }
                .padding(1.5)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if let statusDot = statusDot {
                Circle()
                    .fill(noteAccentColor)
                    .frame(
                        width: statusDotDiameter(for: statusDot),
                        height: statusDotDiameter(for: statusDot)
                    )
                    .padding(.trailing, 18)
                    .padding(.bottom, 18)
                    .opacity(1)
            }
        }
        .contentShape(LivingCellCardShape(phase: edgePhase, amplitude: edgeAmplitude))
        .rotationEffect(.degrees(rotation + jiggle.rotation))
        .offset(x: jiggle.offset.width, y: jiggle.offset.height)
        .scaleEffect(isReordering ? 1.02 : 1.0)
        .compositingGroup()
        .shadow(
            color: Color.black.opacity(isReordering ? 0.167 : 0.153),
            radius: isReordering ? 10 : 8.33,
            x: 0,
            y: isReordering ? 6 : 5
        )
        .shadow(
            color: noteAccentColor.opacity(hasAIResponse ? 0.07 : 0.047),
            radius: isReordering ? 6 : 5,
            x: 0,
            y: isReordering ? 3 : 2.33
        )
        .opacity(isExpanded ? 0.001 : 1)
        .animation(.easeInOut(duration: 0.18), value: isReordering)
    }

    private var statusText: String? {
        guard statusDot == nil else { return nil }

        if isActivelyGrowing {
            return nil
        }
        if hasUnreadAIResponse {
            return nil
        }
        if note.hasChangesSinceLastVisit {
            return note.changesSinceLastViewedCount == 1 ? "updated" : "\(note.changesSinceLastViewedCount) new"
        }
        if note.status == "enriched" {
            return nil
        }
        if note.status == "failed" {
            return "AI unavailable"
        }
        return note.status
    }

    private var statusDot: StatusDot? {
        if hasUnreadAIResponse {
            return .unread
        }
        return nil
    }

    private var summaryText: some View {
        Text(cardBodyText)
            .font(AppFont.body(18))
            .foregroundStyle(Color(red: 0.17, green: 0.17, blue: 0.17))
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .lineSpacing(2)
            .lineLimit(5)
    }

    private var hasAIResponse: Bool {
        !note.enrichments.isEmpty || !note.sources.isEmpty || !note.prompts.isEmpty || note.latestChatReply != nil
    }

    private var isActivelyGrowing: Bool {
        ["queued", "retrying", "running"].contains(note.status)
    }

    private var cardBodyText: String {
        note.displayHeadline
    }

    private var noteTimestamp: String {
        noteCardTimestampLabel(for: note.updatedAt)
    }

    private func jiggleState(at date: Date) -> (rotation: Double, offset: CGSize) {
        guard isInReorderMode, !isReordering, jiggleProgress > 0.001 else {
            return (0, .zero)
        }

        let t = date.timeIntervalSinceReferenceDate
        let omega = 2 * Double.pi * 6.8
        let phase = phaseSeed * 2 * Double.pi
        let swing = sin(t * omega + phase)
        let cross = cos(t * (omega * 0.92) + phase * 1.3)
        let direction = rotation >= 0 ? 1.0 : -1.0
        let amount = Double(jiggleProgress)

        let rotation = 0.45 * swing * direction * amount
        let offsetX = 0.85 * cross * amount
        let offsetY = 0.6 * swing * amount
        return (rotation, CGSize(width: offsetX, height: offsetY))
    }

    private func runningStrokeProgress(at date: Date) -> CGFloat {
        let cycleDuration = 21.6
        let progress = (date.timeIntervalSinceReferenceDate / cycleDuration).truncatingRemainder(dividingBy: 1)
        return CGFloat(progress >= 0 ? progress : progress + 1)
    }

    private func livingEdgePhase(at date: Date) -> Double {
        let speed = isActivelyGrowing ? 0.7 : 0.28
        return date.timeIntervalSinceReferenceDate * speed + phaseSeed * .pi * 2
    }

    private var livingEdgeAmplitude: CGFloat {
        if isActivelyGrowing {
            return 1.15
        }
        if hasAIResponse {
            return 0.82
        }
        return 0.52
    }

    private var hasUnreadAIResponse: Bool {
        note.timeline.contains { event in
            guard event.isNewSinceLastView else { return false }
            return event.type == TimelineEventKind.noteEnriched.rawValue || event.type == TimelineEventKind.chatUpdated.rawValue
        }
    }

    private func statusDotDiameter(for statusDot: StatusDot) -> CGFloat {
        switch statusDot {
        case .grown, .unread:
            return 8
        }
    }

    private enum StatusDot {
        case grown
        case unread
    }
}

private struct LivingCellCardShape: InsettableShape {
    let phase: Double
    let amplitude: CGFloat
    var cornerRadius: CGFloat = 30
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let insetRect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let w = insetRect.width
        let h = insetRect.height
        let r = min(max(cornerRadius - insetAmount, 14), min(w, h) * 0.28)
        let maxCorner = min(w, h) * 0.42

        func wave(_ speed: Double, _ offset: Double = 0) -> CGFloat {
            CGFloat(sin(phase * speed + offset)) * amplitude
        }

        func clampedCorner(_ value: CGFloat) -> CGFloat {
            min(max(14, value), maxCorner)
        }

        let dTL = clampedCorner(r + wave(1.1))
        let dTR = clampedCorner(r + wave(0.9, 1.3))
        let dBR = clampedCorner(r + wave(1.15, 2.5))
        let dBL = clampedCorner(r + wave(1.05, 3.7))

        let mT = wave(0.8, 0.4) * 0.55
        let mR = wave(0.95, 1.9) * 0.55
        let mB = wave(0.85, 3.1) * 0.55
        let mL = wave(1.0, 4.6) * 0.55

        var path = Path()
        path.move(to: CGPoint(x: insetRect.minX + dTL, y: insetRect.minY - mT * 0.3))
        path.addLine(to: CGPoint(x: insetRect.midX, y: insetRect.minY - mT))
        path.addLine(to: CGPoint(x: insetRect.maxX - dTR, y: insetRect.minY - mT * 0.3))
        path.addQuadCurve(
            to: CGPoint(x: insetRect.maxX + mR * 0.3, y: insetRect.minY + dTR),
            control: CGPoint(x: insetRect.maxX + mR * 0.3, y: insetRect.minY)
        )
        path.addLine(to: CGPoint(x: insetRect.maxX + mR, y: insetRect.midY))
        path.addLine(to: CGPoint(x: insetRect.maxX + mR * 0.3, y: insetRect.maxY - dBR))
        path.addQuadCurve(
            to: CGPoint(x: insetRect.maxX - dBR, y: insetRect.maxY + mB * 0.3),
            control: CGPoint(x: insetRect.maxX + mR * 0.3, y: insetRect.maxY + mB * 0.3)
        )
        path.addLine(to: CGPoint(x: insetRect.midX, y: insetRect.maxY + mB))
        path.addLine(to: CGPoint(x: insetRect.minX + dBL, y: insetRect.maxY + mB * 0.3))
        path.addQuadCurve(
            to: CGPoint(x: insetRect.minX - mL * 0.3, y: insetRect.maxY - dBL),
            control: CGPoint(x: insetRect.minX - mL * 0.3, y: insetRect.maxY + mB * 0.3)
        )
        path.addLine(to: CGPoint(x: insetRect.minX - mL, y: insetRect.midY))
        path.addLine(to: CGPoint(x: insetRect.minX - mL * 0.3, y: insetRect.minY + dTL))
        path.addQuadCurve(
            to: CGPoint(x: insetRect.minX + dTL, y: insetRect.minY - mT * 0.3),
            control: CGPoint(x: insetRect.minX - mL * 0.3, y: insetRect.minY - mT * 0.3)
        )
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> some InsettableShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}

private struct BilayerCardOutline: View {
    let phase: Double
    let amplitude: CGFloat
    let innerColor: Color
    let innerOpacity: Double
    var inset: CGFloat = 3.5

    var body: some View {
        LivingCellCardShape(phase: phase, amplitude: amplitude)
            .inset(by: inset)
            .stroke(innerColor.opacity(innerOpacity), lineWidth: 0.7)
    }
}

private struct RunningStrokeIndicator: View {
    let phase: Double
    let amplitude: CGFloat
    let progress: CGFloat
    let color: Color
    var inset: CGFloat = 3.5

    var body: some View {
        ZStack {
            ClosedLivingStrokeSegment(
                phase: phase,
                amplitude: amplitude,
                inset: inset,
                start: progress - 0.10,
                end: progress,
                color: color.opacity(0.035),
                lineWidth: 0.72,
                blurRadius: 0.55
            )

            ClosedLivingStrokeSegment(
                phase: phase,
                amplitude: amplitude,
                inset: inset,
                start: progress - 0.045,
                end: progress,
                color: color.opacity(0.075),
                lineWidth: 0.88
            )

            ClosedLivingStrokeSegment(
                phase: phase,
                amplitude: amplitude,
                inset: inset,
                start: progress - 0.018,
                end: progress,
                color: color.opacity(0.14),
                lineWidth: 1.02
            )

            ClosedLivingStrokeSegment(
                phase: phase,
                amplitude: amplitude,
                inset: inset,
                start: progress - 0.0022,
                end: progress,
                color: color.opacity(0.26),
                lineWidth: 1.55
            )
        }
    }
}

private struct ClosedLivingStrokeSegment: View {
    let phase: Double
    let amplitude: CGFloat
    let inset: CGFloat
    let start: CGFloat
    let end: CGFloat
    let color: Color
    let lineWidth: CGFloat
    var blurRadius: CGFloat = 0

    var body: some View {
        let normalizedStart = normalized(start)
        let normalizedEnd = normalized(end)

        return Group {
            if normalizedStart <= normalizedEnd {
                segment(from: normalizedStart, to: normalizedEnd)
            } else {
                segment(from: normalizedStart, to: 1)
                segment(from: 0, to: normalizedEnd)
            }
        }
    }

    private func segment(from: CGFloat, to: CGFloat) -> some View {
        LivingCellCardShape(phase: phase, amplitude: amplitude)
            .inset(by: inset)
            .trim(from: from, to: to)
            .stroke(
                color,
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
            )
            .blur(radius: blurRadius)
    }

    private func normalized(_ value: CGFloat) -> CGFloat {
        let wrapped = value.truncatingRemainder(dividingBy: 1)
        return wrapped >= 0 ? wrapped : wrapped + 1
    }
}

private struct EmptyNoteCard: View {
    let transitionNamespace: Namespace.ID
    let isExpanded: Bool
    let isAddMorphActive: Bool
    let isVisible: Bool
    let isDecorationReady: Bool
    let isContentReady: Bool
    let onTap: () -> Void
    @State private var showStaticFadeCard = false
    @State private var staticFadeOpacity = 0.0

    var body: some View {
        Button(action: onTap) {
            ZStack {
                if !isExpanded {
                    if showStaticFadeCard {
                        emptyCardChrome(isMatched: false)
                            .opacity(staticFadeOpacity)
                    } else if !isAddMorphActive {
                        emptyCardChrome(isMatched: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 156, maxHeight: 156, alignment: .topLeading)
            .contentShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isAddMorphActive || showStaticFadeCard)
        .allowsHitTesting(isVisible && !isAddMorphActive && !showStaticFadeCard)
        .opacity(isVisible ? 1 : 0)
        .scaleEffect(isVisible ? 1 : 0.96)
        .animation(.easeInOut(duration: 0.22), value: isVisible)
        .onChange(of: isAddMorphActive) { wasActive, isActive in
            if isActive {
                showStaticFadeCard = false
                staticFadeOpacity = 0
            } else if wasActive {
                showStaticFadeCard = true
                staticFadeOpacity = 0

                withAnimation(.easeOut(duration: 0.28)) {
                    staticFadeOpacity = 1
                }

                Task {
                    try? await Task.sleep(nanoseconds: 320_000_000)
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        showStaticFadeCard = false
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func emptyCardChrome(isMatched: Bool) -> some View {
        ZStack {
            if isMatched {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(noteSurfaceColor)
                    .matchedGeometryEffect(id: "new-thought-surface", in: transitionNamespace)
            } else {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(noteSurfaceColor)
            }

            if isMatched {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(.clear, lineWidth: 1)
                    .matchedGeometryEffect(id: "new-thought-stroke", in: transitionNamespace)
            } else {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(.clear, lineWidth: 1)
            }

            if isMatched {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 6]))
                    .foregroundStyle(noteBorderColor.opacity(0.95))
                    .matchedGeometryEffect(id: "new-thought-dashed", in: transitionNamespace)
                    .opacity(isDecorationReady ? 1 : 0)
            } else {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 6]))
                    .foregroundStyle(noteBorderColor.opacity(0.95))
                    .opacity(isDecorationReady ? 1 : 0)
            }

            if isContentReady {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.black.opacity(0.52))

                        Spacer()
                    }

                    Spacer(minLength: 0)

                    Text("Start a thought...")
                        .font(AppFont.body(20))
                        .foregroundStyle(Color(red: 0.17, green: 0.17, blue: 0.17))
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 18)
            }
        }
        .compositingGroup()
        .shadow(color: Color.black.opacity(0.153), radius: 8.33, x: 0, y: 5)
        .shadow(color: noteAccentColor.opacity(0.047), radius: 5, x: 0, y: 2.33)
    }
}

private struct MorphingAddedNoteTarget: View {
    let note: APINote
    let rotation: Double
    let transitionNamespace: Namespace.ID

    var body: some View {
        RoundedRectangle(cornerRadius: 30, style: .continuous)
            .fill(noteSurfaceColor)
            .matchedGeometryEffect(id: "new-thought-surface", in: transitionNamespace)
            .overlay {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(.clear, lineWidth: 1)
                    .matchedGeometryEffect(id: "new-thought-stroke", in: transitionNamespace)
            }
            .overlay {
                BilayerCardOutline(
                    phase: 0.82,
                    amplitude: 0.54,
                    innerColor: noteAccentColor,
                    innerOpacity: 0.09
                )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 6]))
                    .foregroundStyle(noteBorderColor.opacity(0.95))
                    .matchedGeometryEffect(id: "new-thought-dashed", in: transitionNamespace)
                    .opacity(0.001)
            }
            .rotationEffect(.degrees(rotation))
            .compositingGroup()
            .shadow(color: Color.black.opacity(0.153), radius: 8.33, x: 0, y: 5)
            .shadow(color: noteAccentColor.opacity(0.047), radius: 5, x: 0, y: 2.33)
            .allowsHitTesting(false)
    }
}

private struct RelatedNoteCluster: View {
    let notes: [APINote]
    let columnWidth: CGFloat
    let rotations: [Double]
    let activeDragNoteID: String?
    let isDroppingDraggedNote: Bool
    let isInReorderMode: Bool
    let requiresDragHoldBeforeDragging: Bool
    let dragTranslation: CGSize
    let phaseSeed: (String) -> Double
    let jiggleProgress: CGFloat
    let transitionNamespace: Namespace.ID
    let expandedNoteID: String?
    let suppressedNoteOutlineIDs: Set<String>
    let suppressedNoteContentIDs: Set<String>
    let deletingNoteID: String?
    let previewPlaceholderNote: APINote?
    let previewPlaceholderIndex: Int?
    let animationDate: Date
    let onSelect: (String) -> Void
    let onEnterReorderMode: () -> Void
    let onDragChanged: (String, CGSize) -> Void
    let onDragEnded: (String, CGSize) -> Void

    var body: some View {
        let stackSlots = stackedClusterSlots(
            notes: notes,
            columnWidth: columnWidth,
            previewPlaceholderNote: previewPlaceholderNote,
            previewPlaceholderIndex: previewPlaceholderIndex
        )
        let visibleSlots = stackSlots.filter { !$0.isPlaceholder }

        ZStack(alignment: .topLeading) {
            ForEach(visibleSlots, id: \.id) { slot in
                if let index = slot.originalIndex {
                    clusterCard(note: slot.note, index: index)
                        .offset(
                            x: clusterHorizontalOffset(for: index),
                            y: slot.topOffset
                        )
                        .zIndex(activeDragNoteID == slot.note.id ? Double(notes.count + 1) : Double(index))
                }
            }
        }
        .padding(
            .bottom,
            stackedClusterBottomPadding(
                for: notes,
                columnWidth: columnWidth,
                previewPlaceholderNote: previewPlaceholderNote,
                previewPlaceholderIndex: previewPlaceholderIndex
            )
        )
    }

    private func clusterCard(note: APINote, index: Int) -> some View {
        let isDragged = activeDragNoteID == note.id

        let placeholderCard = NoteCard(
            note: note,
            rotation: rotations.indices.contains(index) ? rotations[index] : 0,
            isReordering: activeDragNoteID == note.id,
            isInReorderMode: isInReorderMode,
            phaseSeed: phaseSeed(note.id),
            jiggleProgress: jiggleProgress,
            transitionNamespace: transitionNamespace,
            isExpanded: expandedNoteID == note.id,
            isOutlineReady: !suppressedNoteOutlineIDs.contains(note.id),
            isContentReady: !suppressedNoteContentIDs.contains(note.id),
            isTransitionSource: expandedNoteID == note.id,
            animationDate: animationDate,
            isSurfaceTransitionEnabled: true
        )
            .opacity(clusterCardOpacity(noteID: note.id, isDragged: isDragged))
            .animation(.easeOut(duration: 0.18), value: deletingNoteID)
            .background(
                GeometryReader { proxy in
                    let contentFrame = proxy.frame(in: .named("home-content"))
                    Color.clear.preference(
                        key: NoteFramePreferenceKey.self,
                        value: [note.id: contentFrame]
                    )
                    .preference(
                        key: NoteHitFramePreferenceKey.self,
                        value: [note.id: proxy.frame(in: .global)]
                    )
                    .preference(
                        key: NoteTapTargetPreferenceKey.self,
                        value: [
                            note.id: NoteTapTarget(
                                center: contentFrame.center,
                                size: proxy.size,
                                rotationDegrees: CGFloat(rotations.indices.contains(index) ? rotations[index] : 0)
                            )
                        ]
                    )
                }
            )

        let cardBody = placeholderCard

        if !isInReorderMode {
            return AnyView(
                cardBody.highPriorityGesture(enterReorderGesture(noteID: note.id))
            )
        }
        return AnyView(cardBody)
    }

    private func clusterCardOpacity(noteID: String, isDragged: Bool) -> Double {
        if isDragged {
            return 0.001
        }
        if deletingNoteID == noteID {
            return 0.001
        }
        return 1
    }

    private func activeClusterDragGesture(noteID: String) -> AnyGesture<Void> {
        if requiresDragHoldBeforeDragging && isInReorderMode {
            return AnyGesture(pressThenDragGesture(noteID: noteID).map { _ in () })
        }

        return AnyGesture(clusterDragGesture(noteID: noteID).map { _ in () })
    }

    private func clusterHorizontalOffset(for index: Int) -> CGFloat {
        let direction: CGFloat = index.isMultiple(of: 2) ? -1 : 1
        return direction * clusterAlternatingOffset
    }

    private func enterReorderGesture(noteID: String) -> some Gesture {
        LongPressGesture(minimumDuration: 0.65)
            .onEnded { _ in
                onEnterReorderMode()
            }
    }

    private func clusterDragGesture(noteID: String) -> some Gesture {
        DragGesture(
            minimumDistance: isInReorderMode ? 0 : 10_000,
            coordinateSpace: .named("home-scroll")
        )
            .onChanged { value in
                onDragChanged(noteID, value.translation)
            }
            .onEnded { value in
                if value.translation == .zero {
                    onDragEnded(noteID, .zero)
                } else {
                    onDragEnded(noteID, value.translation)
                }
            }
    }

    private func pressThenDragGesture(noteID: String) -> some Gesture {
        LongPressGesture(minimumDuration: reorderScrollableDragHoldDuration)
            .sequenced(before: DragGesture(coordinateSpace: .named("home-scroll")))
            .onChanged { value in
                guard isInReorderMode else { return }

                switch value {
                case .first(true):
                    onDragChanged(noteID, .zero)
                case .second(true, let drag?):
                    onDragChanged(noteID, drag.translation)
                default:
                    break
                }
            }
            .onEnded { value in
                guard isInReorderMode else { return }

                switch value {
                case .second(true, let drag?):
                    onDragEnded(noteID, drag.translation)
                default:
                    onDragEnded(noteID, .zero)
                }
            }
    }
}

private struct HoldToDragCaptureView: UIViewRepresentable {
    let isEnabled: Bool
    let minimumHoldDuration: TimeInterval
    let onBegan: () -> Void
    let onChanged: (CGSize) -> Void
    let onEnded: (CGSize) -> Void
    let onCancelled: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> CaptureView {
        let view = CaptureView()
        view.backgroundColor = .clear

        let recognizer = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        recognizer.minimumPressDuration = minimumHoldDuration
        recognizer.allowableMovement = 12
        recognizer.cancelsTouchesInView = true
        recognizer.delegate = context.coordinator
        view.addGestureRecognizer(recognizer)
        context.coordinator.recognizer = recognizer
        return view
    }

    func updateUIView(_ uiView: CaptureView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.recognizer?.minimumPressDuration = minimumHoldDuration
        context.coordinator.recognizer?.isEnabled = isEnabled
        uiView.isUserInteractionEnabled = isEnabled
    }

    final class CaptureView: UIView {}

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: HoldToDragCaptureView
        weak var recognizer: UILongPressGestureRecognizer?
        private var startPoint: CGPoint?

        init(_ parent: HoldToDragCaptureView) {
            self.parent = parent
        }

        @objc
        func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
            guard let view = recognizer.view else { return }
            let coordinateView = view.window ?? view.superview ?? view
            let point = recognizer.location(in: coordinateView)

            switch recognizer.state {
            case .began:
                startPoint = point
                parent.onBegan()
                parent.onChanged(.zero)
            case .changed:
                guard let startPoint else { return }
                parent.onChanged(
                    CGSize(
                        width: point.x - startPoint.x,
                        height: point.y - startPoint.y
                    )
                )
            case .ended:
                guard let startPoint else {
                    parent.onCancelled()
                    return
                }
                parent.onEnded(
                    CGSize(
                        width: point.x - startPoint.x,
                        height: point.y - startPoint.y
                    )
                )
                self.startPoint = nil
            case .cancelled, .failed:
                startPoint = nil
                parent.onCancelled()
            default:
                break
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }
    }
}

private struct GlobalDragCaptureView: UIViewRepresentable {
    let isEnabled: Bool
    let minimumHoldDuration: TimeInterval
    let onBegan: (CGPoint) -> Void
    let onChanged: (CGPoint, CGSize) -> Void
    let onEnded: (CGPoint, CGSize) -> Void
    let onCancelled: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> CaptureView {
        let view = CaptureView()
        view.backgroundColor = .clear

        let recognizer = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        recognizer.minimumPressDuration = minimumHoldDuration
        recognizer.allowableMovement = 12
        recognizer.cancelsTouchesInView = true
        recognizer.delegate = context.coordinator
        view.addGestureRecognizer(recognizer)
        context.coordinator.recognizer = recognizer
        return view
    }

    func updateUIView(_ uiView: CaptureView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.recognizer?.minimumPressDuration = minimumHoldDuration
        context.coordinator.recognizer?.isEnabled = isEnabled
        uiView.isUserInteractionEnabled = isEnabled
    }

    final class CaptureView: UIView {}

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: GlobalDragCaptureView
        weak var recognizer: UILongPressGestureRecognizer?
        private var startPoint: CGPoint?

        init(_ parent: GlobalDragCaptureView) {
            self.parent = parent
        }

        @objc
        func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
            guard let view = recognizer.view else { return }
            let coordinateView = view.window ?? view.superview ?? view
            let point = recognizer.location(in: coordinateView)

            switch recognizer.state {
            case .began:
                startPoint = point
                parent.onBegan(point)
                parent.onChanged(point, .zero)
            case .changed:
                guard let startPoint else { return }
                parent.onChanged(
                    point,
                    CGSize(
                        width: point.x - startPoint.x,
                        height: point.y - startPoint.y
                    )
                )
            case .ended:
                guard let startPoint else {
                    parent.onCancelled()
                    return
                }
                parent.onEnded(
                    point,
                    CGSize(
                        width: point.x - startPoint.x,
                        height: point.y - startPoint.y
                    )
                )
                self.startPoint = nil
            case .cancelled, .failed:
                startPoint = nil
                parent.onCancelled()
            default:
                break
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }
    }
}

private struct ScrollOffsetObserverView: UIViewRepresentable {
    let onChange: (CGFloat) -> Void

    func makeUIView(context: Context) -> ObserverView {
        let view = ObserverView()
        view.backgroundColor = .clear
        view.onChange = onChange
        return view
    }

    func updateUIView(_ uiView: ObserverView, context: Context) {
        uiView.onChange = onChange
        uiView.attachIfNeeded()
    }

    final class ObserverView: UIView {
        var onChange: ((CGFloat) -> Void)?
        private weak var observedScrollView: UIScrollView?
        private var observation: NSKeyValueObservation?

        override func didMoveToSuperview() {
            super.didMoveToSuperview()
            attachIfNeeded()
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            attachIfNeeded()
        }

        func attachIfNeeded() {
            guard let scrollView = enclosingScrollView(), scrollView !== observedScrollView else { return }

            observation?.invalidate()
            observedScrollView = scrollView
            observation = scrollView.observe(\.contentOffset, options: [.initial, .new]) { [weak self] scrollView, _ in
                DispatchQueue.main.async {
                    self?.onChange?(scrollView.contentOffset.y)
                }
            }
        }

        private func enclosingScrollView() -> UIScrollView? {
            var view = superview
            while let current = view {
                if let scrollView = current as? UIScrollView {
                    return scrollView
                }
                view = current.superview
            }
            return nil
        }

        deinit {
            observation?.invalidate()
        }
    }
}

private struct HoverCandidate {
    let intent: HoverIntent
    let since: Date
    let anchorPoint: CGPoint
}

private enum HoverIntent: Equatable {
    case group(layout: ColumnLayout, placeholder: GroupPreviewPlaceholder?)
    case reorder(layout: ColumnLayout)
    case delete
}

private struct HoverResolution {
    let intent: HoverIntent
    let anchorPoint: CGPoint
    var deletePreviewProgress: CGFloat = 0
    var isDeleteCommitReady: Bool = false
}

private enum ColumnSide: Equatable {
    case left
    case right
}

private struct ColumnLocation: Equatable {
    let side: ColumnSide
    let index: Int
}

private struct GroupPreviewPlaceholder: Equatable {
    let side: ColumnSide
    let index: Int
    let height: CGFloat
    let noteID: String
    let memberIndex: Int?
}

private struct NoteTapTarget: Equatable {
    let center: CGPoint
    let size: CGSize
    let rotationDegrees: CGFloat
}

private enum ColumnLayoutItem: Equatable, Identifiable {
    case note(String)
    case group([String])

    var id: String {
        switch self {
        case .note(let id):
            return id
        case .group(let ids):
            return "group-" + ids.joined(separator: "-")
        }
    }

    var noteIDs: [String] {
        switch self {
        case .note(let id):
            return [id]
        case .group(let ids):
            return ids
        }
    }
}

private struct ColumnLayout: Equatable {
    var left: [ColumnLayoutItem] = []
    var right: [ColumnLayoutItem] = []

    var isEmpty: Bool {
        left.isEmpty && right.isEmpty
    }

    var groups: [AffinityGroup] {
        (left + right).compactMap { item in
            item.noteIDs.count >= 2 ? AffinityGroup(noteIDs: item.noteIDs) : nil
        }
    }

    var flattenedOrder: [String] {
        var result: [String] = []
        let count = max(left.count, right.count)

        for index in 0..<count {
            if index < left.count {
                result.append(contentsOf: left[index].noteIDs)
            }
            if index < right.count {
                result.append(contentsOf: right[index].noteIDs)
            }
        }

        return deduplicated(result)
    }
}

private struct PositionedColumnItem: Identifiable, Equatable {
    let item: ColumnLayoutItem
    let indexSeed: Int
    let origin: CGPoint
    let height: CGFloat
    let previewPlaceholder: GroupPreviewPlaceholder?

    var id: String {
        item.id
    }
}

private struct AffinityGroup: Equatable {
    let noteIDs: [String]

    var anchorID: String? {
        noteIDs.first
    }

    var noteIDSet: Set<String> {
        Set(noteIDs)
    }

    func contains(_ noteID: String) -> Bool {
        noteIDs.contains(noteID)
    }
}

private enum HomeItem: Identifiable {
    case note(APINote)
    case group([APINote])
    case seed

    var id: String {
        switch self {
        case .note(let note):
            return note.id
        case .group(let notes):
            return "group-\(notes.map(\.id).joined(separator: "-"))"
        case .seed:
            return "seed"
        }
    }

    var kind: Kind {
        switch self {
        case .note(let note):
            return .note(note)
        case .group(let notes):
            return .group(notes)
        case .seed:
            return .seed
        }
    }

    var estimatedHeight: CGFloat {
        switch self {
        case .note(let note):
            return estimatedHomeNoteCardHeight(for: note)
        case .group(let notes):
            return estimatedStackedClusterHeight(for: notes)
        case .seed:
            return 156
        }
    }

    enum Kind {
        case note(APINote)
        case group([APINote])
        case seed
    }
}

private struct NoteFramePreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct NoteHitFramePreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct NoteTapTargetPreferenceKey: PreferenceKey {
    static var defaultValue: [String: NoteTapTarget] = [:]

    static func reduce(value: inout [String: NoteTapTarget], nextValue: () -> [String: NoteTapTarget]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct HomeItemHeightPreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]

    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct HomeHeaderFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .null

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if !next.isNull {
            value = next
        }
    }
}

private struct TrashTargetFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .null

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if !next.isNull {
            value = next
        }
    }
}

private struct DetailAnchorPreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]

    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct HomeContentHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct HomeIndicatorHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 18

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}

private extension Array where Element == CGFloat {
    var average: CGFloat? {
        guard !isEmpty else { return nil }
        return reduce(CGFloat.zero, +) / CGFloat(count)
    }
}

private extension View {
    func detailDebugAnchor(id: String) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: DetailAnchorPreferenceKey.self,
                    value: [id: proxy.frame(in: .named("detail-surface")).minY]
                )
            }
        )
    }

    @ViewBuilder
    func applyNoteSurfaceTransition(id: String, namespace: Namespace.ID, isEnabled: Bool, isSource: Bool = true) -> some View {
        if isEnabled && !debugDisableNoteSurfaceTransition {
            matchedGeometryEffect(id: id, in: namespace, isSource: isSource)
        } else {
            self
        }
    }
}

private func deduplicated(_ ids: [String]) -> [String] {
    var seen = Set<String>()
    return ids.filter { seen.insert($0).inserted }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(viewModel: .previewModel(), shouldBootstrap: false)
    }
}
