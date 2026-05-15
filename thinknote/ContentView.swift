//
//  ContentView.swift
//  thinknote
//
//  Created by 严汀 on 4/5/26.
//

import SwiftUI

private let noteTransitionAnimation = Animation.timingCurve(0.2, 0.9, 0.1, 1.0, duration: 0.55)
private let noteMorphDuration: Double = 0.55
private let detailDismissTopThreshold: CGFloat = 0.5
private let detailDismissCornerRadiusStart: CGFloat = 42
private let detailDismissCornerRadiusTravel: CGFloat = 96
private let detailPrimaryScrollAnchorID = "thought-label"
private let detailBottomBarVisualClearance: CGFloat = 50
private let noteAccentColor = Color(red: 0.53, green: 0.66, blue: 0.61)
private let noteBorderColor = Color(red: 0.88, green: 0.88, blue: 0.86)
private let noteShadowColor = Color.black.opacity(0.08)
private let debugDisableNoteSurfaceTransition = false
private let debugLogNoteTapFlow = false
let isRunningInPreviews = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"

func debugNoteLog(_ items: Any...) {
#if DEBUG
    guard debugLogNoteTapFlow else { return }
    print("[ThinknoteDebug]", items.map { String(describing: $0) }.joined(separator: " "))
#endif
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
            Color(red: 0.95, green: 0.95, blue: 0.95)
                .ignoresSafeArea()

            HomeScreen(
                viewModel: viewModel,
                transitionNamespace: noteTransitionNamespace,
                expandedNoteID: activeDetailNote?.id,
                newThoughtNamespace: newThoughtNamespace
            )
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

            if let message = viewModel.errorMessage {
                VStack {
                    Spacer()

                    Text(message)
                        .font(AppFont.meta(13))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.92), in: Capsule())
                        .overlay {
                            Capsule()
                                .stroke(Color.black.opacity(0.1), lineWidth: 1)
                        }
                        .padding(.bottom, 20)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(3)
            }
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

private struct HomeScreen: View {
    @ObservedObject var viewModel: ContentViewModel
    let transitionNamespace: Namespace.ID
    let expandedNoteID: String?
    let newThoughtNamespace: Namespace.ID
    @State private var orderedNoteIDs: [String] = []
    @State private var affinityGroup: AffinityGroup?
    @State private var activeDragNoteID: String?
    @State private var isReorderMode = false
    @State private var dragTranslation: CGSize = .zero
    @State private var noteFrames: [String: CGRect] = [:]
    @State private var affinityCandidate: AffinityCandidate?
    @State private var jiggleProgress: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomTrailing) {
                HomeBackgroundView()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        homeHeader
                            .padding(.bottom, 18)

                        homeLayout(containerWidth: max(geometry.size.width - 36, 0))
                    }
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .topLeading)
                    .padding(.horizontal, 18)
                    .padding(.top, 20)
                    .padding(.bottom, isReorderMode ? 170 : 120)
                }
                .coordinateSpace(name: "home-scroll")
                .onAppear {
                    synchronizeOrderingIfNeeded()
                }
                .onChange(of: viewModel.notes.map(\.id)) { _, _ in
                    synchronizeOrderingIfNeeded()
                }
                .onPreferenceChange(NoteFramePreferenceKey.self) { frames in
                    noteFrames = frames
                }
                .onTapGesture {
                    if isReorderMode {
                        cancelDragging()
                    }
                }

                Button {
                    viewModel.showAssistant = true
                } label: {
                    Text("AI")
                        .font(AppFont.heading(16, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(width: 58, height: 58)
                        .background(Color(red: 0.88, green: 0.88, blue: 0.88), in: Circle())
                        .overlay {
                            Circle()
                                .stroke(Color.black.opacity(0.15), lineWidth: 1)
                        }
                }
                .padding(.trailing, 22)
                .padding(.bottom, isReorderMode ? 148 : 26)

                if isReorderMode {
                    reorderInstruction(bottomInset: geometry.safeAreaInsets.bottom)
                }
            }
        }
        .sheet(isPresented: $viewModel.showAssistant) {
            AssistantSheet(viewModel: viewModel)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var homeHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("garden · \(viewModel.notes.count) thoughts")
                .font(AppFont.meta(11))
                .tracking(1.8)
                .textCase(.uppercase)
                .foregroundStyle(.black.opacity(0.5))

            Spacer(minLength: 0)

            if viewModel.screen != .newNote {
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
    }

    private func homeLayout(containerWidth: CGFloat) -> some View {
        let columns = buildColumns()
        let spacing: CGFloat = 16
        let columnWidth = max((containerWidth - spacing) / 2, 0)

        return HStack(alignment: .top, spacing: spacing) {
            VStack(spacing: 16) {
                ForEach(Array(columns.left.enumerated()), id: \.element.id) { index, item in
                    itemView(item, indexSeed: index * 2)
                }
            }
            .frame(width: columnWidth, alignment: .top)

            VStack(spacing: 16) {
                ForEach(Array(columns.right.enumerated()), id: \.element.id) { index, item in
                    itemView(item, indexSeed: index * 2 + 1)
                }
            }
            .frame(width: columnWidth, alignment: .top)
        }
        .frame(maxWidth: containerWidth, alignment: .topLeading)
    }

    private func rotation(for index: Int) -> Double {
        let values: [Double] = [-1.1, 0.7, -0.6, 0.9, -0.75, 1.0]
        return values[index % values.count]
    }

    private func handleTap(on noteID: String) {
        debugNoteLog("handleTap", noteID, "isReorderMode:", isReorderMode)
        withAnimation(noteTransitionAnimation) {
            viewModel.openNote(noteID: noteID)
        }
    }

    private var displayNotes: [APINote] {
        viewModel.notes
    }

    private var growingSeedCount: Int {
        viewModel.notes.filter { ["queued", "retrying", "running"].contains($0.status) }.count
    }

    @ViewBuilder
    private func itemView(_ item: HomeItem, indexSeed: Int) -> some View {
        switch item.kind {
        case .note(let note):
            noteCard(note, index: indexSeed)
        case .group(let front, let back):
            RelatedNoteCluster(
                front: front,
                back: back,
                frontRotation: rotation(for: indexSeed),
                backRotation: rotation(for: indexSeed + 1),
                activeDragNoteID: activeDragNoteID,
                isInReorderMode: isReorderMode,
                dragTranslation: dragTranslation,
                phaseSeed: phaseSeed,
                jiggleProgress: jiggleProgress,
                transitionNamespace: transitionNamespace,
                expandedNoteID: expandedNoteID
            ) { noteID in
                handleTap(on: noteID)
            } onDragChanged: { noteID, translation in
                guard isReorderMode else { return }
                beginDragging(noteID)
                dragTranslation = translation
                updateAffinityCandidate(for: noteID, translation: translation)
            } onDragEnded: { noteID, translation in
                guard isReorderMode else { return }
                endDragging(noteID: noteID, translation: translation)
            }
        case .seed:
            if !isReorderMode {
                EmptyNoteCard(
                    transitionNamespace: newThoughtNamespace,
                    isExpanded: viewModel.screen == .newNote,
                    isAddMorphActive: viewModel.addMorphTargetNoteID != nil
                ) {
                    withAnimation(noteTransitionAnimation) {
                        viewModel.openNewNote()
                    }
                }
            }
        }
    }

    private func noteCard(_ note: APINote, index: Int) -> some View {
        let isAddMorphTarget = viewModel.addMorphTargetNoteID == note.id

        return NoteCard(
            note: note,
            rotation: rotation(for: index),
            isReordering: activeDragNoteID == note.id,
            isInReorderMode: isReorderMode,
            phaseSeed: phaseSeed(for: note.id),
            jiggleProgress: jiggleProgress,
            transitionNamespace: transitionNamespace,
            isExpanded: expandedNoteID == note.id,
            isTransitionSource: expandedNoteID == note.id
        )
        .opacity(isAddMorphTarget ? 0.001 : 1)
        .overlay {
            if isAddMorphTarget {
                MorphingAddedNoteTarget(note: note, rotation: rotation(for: index), transitionNamespace: newThoughtNamespace)
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .offset(activeDragNoteID == note.id ? dragTranslation : .zero)
        .zIndex(activeDragNoteID == note.id ? 100 : 0)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: NoteFramePreferenceKey.self,
                    value: [note.id: proxy.frame(in: .named("home-scroll"))]
                )
            }
        )
        .onTapGesture {
            debugNoteLog("tap note", note.id, "expanded:", expandedNoteID == note.id)
            if isReorderMode {
                cancelDragging()
            } else {
                handleTap(on: note.id)
            }
        }
        .highPriorityGesture(enterReorderGesture(noteID: note.id))
        .simultaneousGesture(dragGesture(noteID: note.id))
    }

    private func synchronizeOrderingIfNeeded() {
        let ids = displayNotes.map(\.id)
        if orderedNoteIDs.isEmpty {
            orderedNoteIDs = ids
            return
        }

        let existing = Set(orderedNoteIDs)
        let missing = ids.filter { !existing.contains($0) }
        orderedNoteIDs = deduplicated(orderedNoteIDs.filter(ids.contains) + missing)

        if let group = affinityGroup {
            let visible = Set(ids)
            if !visible.contains(group.frontID) || !visible.contains(group.backID) {
                affinityGroup = nil
            }
        }
    }

    private func buildColumns() -> (left: [HomeItem], right: [HomeItem]) {
        var left: [HomeItem] = []
        var right: [HomeItem] = []
        var leftScore: CGFloat = 0
        var rightScore: CGFloat = 0

        let notesByID = Dictionary(uniqueKeysWithValues: displayNotes.map { ($0.id, $0) })
        let items = buildOrderedItems(notesByID: notesByID) + [.seed]

        for item in items {
            let height = item.estimatedHeight
            if leftScore <= rightScore {
                left.append(item)
                leftScore += height + 16
            } else {
                right.append(item)
                rightScore += height + 16
            }
        }

        return (left, right)
    }

    private func buildOrderedItems(notesByID: [String: APINote]) -> [HomeItem] {
        var items: [HomeItem] = []
        var consumed = Set<String>()

        for id in orderedNoteIDs {
            guard let note = notesByID[id], !consumed.contains(id) else { continue }

            if let group = affinityGroup {
                if id == group.frontID,
                   let back = notesByID[group.backID] {
                    items.append(.group(front: note, back: back))
                    consumed.insert(group.frontID)
                    consumed.insert(group.backID)
                    continue
                }

                if id == group.backID {
                    continue
                }
            }

            items.append(.note(note))
            consumed.insert(id)
        }

        return items
    }

    private func beginDragging(_ noteID: String) {
        if activeDragNoteID == nil {
            activeDragNoteID = noteID
            dragTranslation = .zero
            affinityCandidate = nil
        }
    }

    private func cancelDragging() {
        activeDragNoteID = nil
        dragTranslation = .zero
        affinityCandidate = nil
        if isReorderMode {
            withAnimation(.easeOut(duration: 0.16)) {
                jiggleProgress = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                if jiggleProgress == 0 {
                    isReorderMode = false
                }
            }
        }
    }

    private func endDragging(noteID: String, translation: CGSize) {
        guard let startFrame = noteFrames[noteID] else {
            cancelDragging()
            return
        }

        let finalFrame = startFrame.offsetBy(dx: translation.width, dy: translation.height)

        if let targetID = confirmedAffinityTarget(for: noteID, finalFrame: finalFrame) {
            affinityGroup = AffinityGroup(frontID: noteID, backID: targetID)
            orderedNoteIDs.removeAll { $0 == noteID }
            if let targetIndex = orderedNoteIDs.firstIndex(of: targetID) {
                orderedNoteIDs.insert(noteID, at: targetIndex)
            } else {
                orderedNoteIDs.append(noteID)
            }
        } else {
            if let group = affinityGroup, group.contains(noteID) {
                affinityGroup = nil
            }
            reorder(noteID: noteID, finalFrame: finalFrame)
        }

        Task {
            await viewModel.persistManualOrder(orderedNoteIDs)
        }
        cancelDragging()
    }

    private func updateAffinityCandidate(for noteID: String, translation: CGSize) {
        guard let startFrame = noteFrames[noteID] else { return }
        let finalFrame = startFrame.offsetBy(dx: translation.width, dy: translation.height)

        if let targetID = overlappingTarget(for: noteID, finalFrame: finalFrame) {
            if affinityCandidate?.targetID != targetID {
                affinityCandidate = AffinityCandidate(targetID: targetID, since: Date())
            }
        } else {
            affinityCandidate = nil
        }
    }

    private func confirmedAffinityTarget(for noteID: String, finalFrame: CGRect) -> String? {
        guard let targetID = overlappingTarget(for: noteID, finalFrame: finalFrame),
              let candidate = affinityCandidate,
              candidate.targetID == targetID
        else {
            return nil
        }

        return Date().timeIntervalSince(candidate.since) >= 0.5 ? targetID : nil
    }

    private func overlappingTarget(for noteID: String, finalFrame: CGRect) -> String? {
        for (otherID, otherFrame) in noteFrames where otherID != noteID {
            let intersection = finalFrame.intersection(otherFrame)
            guard !intersection.isNull else { continue }
            let overlapArea = intersection.width * intersection.height
            let ownArea = max(finalFrame.width * finalFrame.height, 1)
            if overlapArea / ownArea > 0.35 {
                return otherID
            }
        }
        return nil
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

    private func distance(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }

    private func enterReorderGesture(noteID: String) -> some Gesture {
        LongPressGesture(minimumDuration: 0.65)
            .onEnded { _ in
                if !isReorderMode {
                    isReorderMode = true
                    withAnimation(.easeOut(duration: 0.22)) {
                        jiggleProgress = 1
                    }
                }
            }
    }

    private func dragGesture(noteID: String) -> some Gesture {
        DragGesture(coordinateSpace: .named("home-scroll"))
            .onChanged { value in
                guard isReorderMode else { return }
                if activeDragNoteID == nil {
                    activeDragNoteID = noteID
                }
                guard activeDragNoteID == noteID else { return }
                dragTranslation = value.translation
                updateAffinityCandidate(for: noteID, translation: value.translation)
            }
            .onEnded { value in
                guard isReorderMode, activeDragNoteID == noteID else { return }
                endDragging(noteID: noteID, translation: value.translation)
            }
    }

    private func phaseSeed(for id: String) -> Double {
        let scalarSum = id.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return Double(scalarSum % 13) / 13.0
    }

    private func reorderInstruction(bottomInset: CGFloat) -> some View {
        VStack(spacing: 10) {
            ReorderMarqueeView(
                message: "drag to reorder · overlap another card to create an affinity group · swipe up to exit ·"
            )
                .frame(height: 46)
                .frame(maxWidth: .infinity)

            Capsule()
                .fill(Color.black.opacity(0.22))
                .frame(width: 128, height: 5)
                .gesture(
                    DragGesture(minimumDistance: 6)
                        .onEnded { value in
                            if value.translation.height < -18 {
                                cancelDragging()
                            }
                        }
                )
        }
        .padding(.horizontal, 18)
        .padding(.bottom, max(bottomInset, 10))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

private struct ReorderMarqueeView: View {
    let message: String
    @State private var segmentWidth: CGFloat = 1

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                let distance = CGFloat(timeline.date.timeIntervalSinceReferenceDate) * 42
                let wrapWidth = max(segmentWidth + 24, 1)
                let xOffset = -(distance.truncatingRemainder(dividingBy: wrapWidth))

                HStack(spacing: 24) {
                    marqueeSegment
                        .background(
                            GeometryReader { proxy in
                                Color.clear.preference(key: MarqueeWidthPreferenceKey.self, value: proxy.size.width)
                            }
                        )
                    marqueeSegment
                    marqueeSegment
                }
                .offset(x: xOffset)
                .frame(width: geometry.size.width, alignment: .leading)
            }
            .clipped()
            .onPreferenceChange(MarqueeWidthPreferenceKey.self) { width in
                if width > 0 {
                    segmentWidth = width
                }
            }
        }
    }

    private var marqueeSegment: some View {
        Text(message)
            .font(AppFont.meta(12))
            .tracking(1.4)
            .textCase(.uppercase)
            .foregroundStyle(.black.opacity(0.72))
            .fixedSize()
    }
}

private struct MarqueeWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct HomeBackgroundView: View {
    var body: some View {
        ZStack {
            Image("HomeBackground")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color(red: 0.98, green: 0.98, blue: 0.96).opacity(0.2),
                    Color(red: 0.96, green: 0.97, blue: 0.94).opacity(0.56),
                    Color(red: 0.95, green: 0.95, blue: 0.93).opacity(0.7)
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

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Rectangle()
                    .fill(Color.white.opacity(0.001))
                    .ignoresSafeArea()
                    .onTapGesture {
                        isEditorFocused = false
                        withAnimation(noteTransitionAnimation) {
                            viewModel.discardDraft()
                        }
                    }

                VStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .fill(Color.white.opacity(0.98))
                            .matchedGeometryEffect(id: "new-thought-surface", in: transitionNamespace)
                            .shadow(color: noteShadowColor.opacity(0.72), radius: 18, x: 0, y: 12)

                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .stroke(noteBorderColor, lineWidth: 1)
                            .matchedGeometryEffect(id: "new-thought-stroke", in: transitionNamespace)

                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 6]))
                            .foregroundStyle(noteBorderColor.opacity(0.95))
                            .matchedGeometryEffect(id: "new-thought-dashed", in: transitionNamespace)
                            .opacity(showContent ? 0 : 1)

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

    private var newNoteContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("start a thought", text: $viewModel.draftText, axis: .vertical)
                .focused($isEditorFocused)
                .textFieldStyle(.plain)
                .font(AppFont.body(21))
                .foregroundStyle(.black)
                .lineLimit(1...8)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .frame(maxWidth: .infinity, minHeight: 172, alignment: .topLeading)

            HStack {
                Button("Cancel") {
                    isEditorFocused = false
                    withAnimation(noteTransitionAnimation) {
                        viewModel.discardDraft()
                    }
                }
                .font(AppFont.meta(12))
                .foregroundStyle(.black.opacity(0.58))

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
                    Text("Add")
                        .font(AppFont.body(18))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.92), in: Capsule())
                        .overlay {
                            Capsule()
                                .stroke(noteBorderColor, lineWidth: 1)
                        }
                }
                .disabled(viewModel.trimmedDraftText.isEmpty || viewModel.isDraftSaving)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 18)
        }
    }
}

private struct NoteFullPageScreen: View {
    @ObservedObject var viewModel: ContentViewModel
    let note: APINote
    let transitionNamespace: Namespace.ID
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
    @State private var detailBottomBarHeight: CGFloat = 128
    @State private var detailBottomBarInputTop: CGFloat = 14

    var body: some View {
        GeometryReader { geometry in
            let topInset = geometry.safeAreaInsets.top
            let bottomInset = max(geometry.safeAreaInsets.bottom, 18)

            ZStack(alignment: .topTrailing) {
                detailSurface(
                    topInset: topInset,
                    bottomInset: bottomInset
                )

                Button {
                    closeDetail()
                } label: {
                    Text("home")
                        .font(AppFont.heading(15, weight: .semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.82), in: Capsule())
                        .overlay {
                            Capsule()
                                .stroke(Color.black.opacity(0.08), lineWidth: 1)
                        }
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
                startOpenSequence()
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

    private var detailScrollBottomPadding: CGFloat {
        max(detailBottomBarHeight - detailBottomBarInputTop + detailBottomBarVisualClearance, 36)
    }

    private func detailSurface(
        topInset: CGFloat,
        bottomInset: CGFloat
    ) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: surfaceCornerRadius, style: .continuous)
                .fill(Color.white)
                .matchedGeometryEffect(id: "note-surface-\(note.id)", in: transitionNamespace)
                .shadow(color: noteShadowColor, radius: 24, x: 0, y: 12)
                .ignoresSafeArea()

            RoundedRectangle(cornerRadius: surfaceCornerRadius, style: .continuous)
                .stroke(noteBorderColor.opacity(0.72), lineWidth: 1)
                .matchedGeometryEffect(id: "note-stroke-\(note.id)", in: transitionNamespace)
                .ignoresSafeArea()

            if showPrimaryContent {
                ZStack(alignment: .bottom) {
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

                            if viewModel.showTimeline {
                                timelineSection
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
                        }
                        .padding(.horizontal, 28)
                        .padding(.bottom, detailScrollBottomPadding)
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

                    bottomBar(bottomInset: bottomInset)
                        .background {
                            GeometryReader { proxy in
                                Color.clear
                                    .preference(key: DetailBottomBarHeightPreferenceKey.self, value: proxy.size.height)
                            }
                        }
                }
                .onPreferenceChange(DetailBottomBarHeightPreferenceKey.self) { height in
                    guard height > 0 else { return }
                    detailBottomBarHeight = height
                }
                .onPreferenceChange(DetailBottomBarInputTopPreferenceKey.self) { top in
                    guard top >= 0 else { return }
                    detailBottomBarInputTop = top
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var metaStrip: some View {
        HStack(spacing: 16) {
            Text(noteTimestamp)
                .font(AppFont.meta(11))
                .tracking(1.6)
                .textCase(.uppercase)
                .foregroundStyle(.black.opacity(0.5))

            if let statusLabel = detailStatusLabel {
                Text(statusLabel)
                    .font(AppFont.meta(11))
                    .tracking(1.6)
                    .textCase(.uppercase)
                    .foregroundStyle(noteAccentColor)
            }

        }
        .opacity(showPrimaryContent ? 1 : 0)
    }

    private var aiGrowthSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(Array(growthParagraphs.enumerated()), id: \.offset) { index, paragraph in
                VStack(alignment: .leading, spacing: 20) {
                    Text(paragraph)
                        .font(AppFont.body(19))
                        .lineSpacing(4)
                        .foregroundStyle(.black)

                    if index < growthParagraphs.count - 1 {
                        divider
                    }
                }
            }
        }
        .opacity(showGrowthContent ? 1 : 0)
        .offset(y: showGrowthContent ? 0 : 12)
    }

    private var inlineContinueThoughtCTA: some View {
        HStack {
            Spacer()

            Button {
                Task { await viewModel.requestResponse(for: note.id) }
            } label: {
                Text("Continue this thought")
                    .font(AppFont.heading(15, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.82), in: Capsule())
                    .overlay {
                        Capsule()
                            .stroke(Color.black.opacity(0.08), lineWidth: 1)
                    }
            }
            .disabled(viewModel.isEnriching)

            Spacer()
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
                        .foregroundStyle(.black.opacity(0.9))
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

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("recent evolution")

            ForEach(note.timeline.prefix(5)) { event in
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.summary)
                        .font(AppFont.body(16))
                        .foregroundStyle(.black.opacity(0.84))

                    Text(event.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(AppFont.meta(12))
                        .foregroundStyle(.black.opacity(0.5))
                }
                .padding(.bottom, 2)
            }
        }
        .opacity(showFootnoteContent ? 1 : 0)
        .offset(y: showFootnoteContent ? 0 : 12)
    }

    private func latestReplySection(_ reply: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("latest reply")

            Text(reply)
                .font(AppFont.body(18))
                .lineSpacing(3)
                .foregroundStyle(.black.opacity(0.82))
        }
        .opacity(showGrowthContent ? 1 : 0)
        .offset(y: showGrowthContent ? 0 : 12)
    }

    private func pendingFollowUpSection(_ followUp: String) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            divider

            Text(followUp)
                .font(AppFont.body(19))
                .lineSpacing(4)
                .foregroundStyle(noteAccentColor.opacity(0.78))
        }
        .opacity(showGrowthContent ? 1 : 0)
        .offset(y: showGrowthContent ? 0 : 12)
    }

    private func bottomBar(bottomInset: CGFloat) -> some View {
        VStack(spacing: 12) {
            if shouldShowRequestResponseOnlyCTA {
                Button {
                    Task { await viewModel.requestResponse(for: note.id) }
                } label: {
                    Text("Request response")
                        .font(AppFont.body(18))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.92), in: Capsule())
                        .overlay {
                            Capsule()
                                .stroke(noteBorderColor, lineWidth: 1)
                        }
                }
                .disabled(viewModel.isEnriching)
                .frame(maxWidth: .infinity)
                .background {
                    GeometryReader { proxy in
                        Color.clear
                            .preference(
                                key: DetailBottomBarInputTopPreferenceKey.self,
                                value: proxy.frame(in: .named("detail-bottom-bar")).minY
                            )
                    }
                }
            } else {
                TextField("Ask about this", text: $viewModel.followUpDraft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(AppFont.body(17))
                    .foregroundStyle(.black)
                    .lineLimit(1...4)
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
                    .background {
                        GeometryReader { proxy in
                            Color.clear
                                .preference(
                                    key: DetailBottomBarInputTopPreferenceKey.self,
                                    value: proxy.frame(in: .named("detail-bottom-bar")).minY
                                )
                        }
                    }

                if !viewModel.followUpDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    HStack {
                        Spacer()

                        Button("Send follow-up") {
                            Task { await viewModel.sendFollowUp() }
                        }
                        .font(AppFont.body(18))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.92), in: Capsule())
                        .overlay {
                            Capsule()
                                .stroke(noteBorderColor, lineWidth: 1)
                        }
                        .disabled(viewModel.isEnriching || viewModel.isSendingFollowUp)
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, bottomInset)
        .coordinateSpace(name: "detail-bottom-bar")
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(0),
                    Color.white.opacity(0.88),
                    Color.white.opacity(0.98)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .opacity(showChrome ? 1 : 0)
        .offset(y: showChrome ? 0 : 10)
    }

    private var primaryDetailActionTitle: String {
        viewModel.followUpDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Request response" : "Send follow-up"
    }

    private var shouldShowDeferredGrowthCTA: Bool {
        note.enrichments.isEmpty &&
        note.latestChatReply == nil &&
        ["queued", "retrying", "running"].contains(note.status)
    }

    private var isAwaitingAssistantReply: Bool {
        guard let currentThread = viewModel.currentThread else { return false }
        return currentThread.messages.last?.role == MessageRole.user.rawValue
    }

    private var shouldShowRequestResponseOnlyCTA: Bool {
        shouldShowDeferredGrowthCTA || isAwaitingAssistantReply
    }

    private var pendingFollowUpText: String? {
        guard let currentThread = viewModel.currentThread,
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
        let paragraphs = expansion
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return paragraphs
    }

    private var hasAIGrowthParagraphs: Bool {
        !growthParagraphs.isEmpty
    }

    private var detailStatusLabel: String? {
        if note.latestChatReply != nil {
            return "in conversation"
        }
        if note.enrichments.isEmpty {
            return "noted"
        }
        return nil
    }

    private var noteTimestamp: String {
        if Calendar.current.isDateInToday(note.updatedAt) {
            return note.updatedAt.formatted(date: .omitted, time: .shortened)
        }
        if Calendar.current.isDateInYesterday(note.updatedAt) {
            return "yesterday"
        }
        return note.updatedAt.formatted(date: .abbreviated, time: .omitted)
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
        return host.replacingOccurrences(of: "www.", with: "")
    }
}

private struct AssistantSheet: View {
    @ObservedObject var viewModel: ContentViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("AI Assistant")
                    .font(AppFont.heading(22, weight: .semibold))
                Spacer()
                Button("Done") {
                    viewModel.showAssistant = false
                }
                .foregroundStyle(.black)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let note = viewModel.currentNote {
                        Text("Current note")
                            .font(AppFont.heading(18, weight: .semibold))
                        Text(note.text)
                            .font(AppFont.body(18))
                    } else {
                        Text("Start from a thought, question, or fragment.")
                            .font(AppFont.body(18))
                    }

                    TextField("Ask about this idea...", text: $viewModel.assistantDraft, axis: .vertical)
                        .textFieldStyle(.roundedBorder)

                    Button("Save as note") {
                        Task {
                            await viewModel.createNoteFromAssistant()
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.assistantDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
    let isTransitionSource: Bool
    @State private var showCardContent = true

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
            let jiggle = jiggleState(at: timeline.date)
            let pulse = growingDotPulse(at: timeline.date)

            VStack(alignment: .leading, spacing: 14) {
                summaryText

                HStack(alignment: .center, spacing: 12) {
                    Text(noteTimestamp)
                        .font(AppFont.meta(11))
                        .tracking(1.2)
                        .textCase(.uppercase)
                        .foregroundStyle(.black.opacity(0.5))

                    Spacer()

                    if let statusText = statusText {
                        Text(statusText)
                            .font(AppFont.meta(11))
                            .tracking(1.2)
                            .textCase(.uppercase)
                            .foregroundStyle(hasAIResponse ? noteAccentColor : .black.opacity(0.62))
                    }
                }
            }
            .opacity(showCardContent ? 1 : 0)
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background {
                ZStack {
                    if !isExpanded {
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .fill(Color.white.opacity(0.96))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .matchedGeometryEffect(id: "note-surface-\(note.id)", in: transitionNamespace)
                            .shadow(
                                color: noteShadowColor.opacity(isReordering ? 1 : 0.72),
                                radius: isReordering ? 18 : 14,
                                x: 0,
                                y: isReordering ? 12 : 8
                            )

                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .stroke(
                                isReordering || hasAIResponse ? noteAccentColor.opacity(isReordering ? 0.55 : 0.34) : noteBorderColor,
                                lineWidth: isReordering ? 1.3 : 1
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .matchedGeometryEffect(id: "note-stroke-\(note.id)", in: transitionNamespace)
                    } else {
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .fill(Color.white.opacity(0.001))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                hasAIResponse ? noteAccentColor.opacity(0.08) : .clear,
                                .clear,
                                .clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .overlay(alignment: .bottomTrailing) {
                if let statusDot = statusDot {
                    Circle()
                        .fill(noteAccentColor)
                        .frame(
                            width: statusDotDiameter(for: statusDot),
                            height: statusDotDiameter(for: statusDot)
                        )
                        .opacity(statusDot == .growing ? pulse.opacity : 1)
                        .scaleEffect(statusDot == .growing ? pulse.scale : 1)
                        .padding(.trailing, 18)
                        .padding(.bottom, 18)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .rotationEffect(.degrees(rotation + jiggle.rotation))
            .offset(x: jiggle.offset.width, y: jiggle.offset.height)
            .scaleEffect(isReordering ? 1.02 : 1.0)
            .opacity(isExpanded ? 0.001 : 1)
            .animation(.easeInOut(duration: 0.18), value: isReordering)
            .onChange(of: isExpanded) { wasExpanded, nowExpanded in
                if nowExpanded {
                    showCardContent = false
                } else if wasExpanded {
                    Task {
                        try? await Task.sleep(nanoseconds: UInt64(noteMorphDuration * 0.55 * 1_000_000_000))
                        withAnimation(.easeOut(duration: 0.22)) {
                            showCardContent = true
                        }
                    }
                }
            }
        }
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
        if note.status == "captured" {
            return "noted"
        }
        return note.status
    }

    private var statusDot: StatusDot? {
        if isActivelyGrowing {
            return .growing
        }
        if hasUnreadAIResponse {
            return .unread
        }
        if note.status == "enriched" && !note.hasChangesSinceLastVisit {
            return .grown
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
        if Calendar.current.isDateInToday(note.updatedAt) {
            return note.updatedAt.formatted(date: .omitted, time: .shortened)
        }
        if Calendar.current.isDateInYesterday(note.updatedAt) {
            return "yesterday"
        }
        return note.updatedAt.formatted(date: .abbreviated, time: .omitted)
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

    private func growingDotPulse(at date: Date) -> (opacity: Double, scale: CGFloat) {
        let progress = (sin((date.timeIntervalSinceReferenceDate / 3.0) * 2 * .pi) + 1) / 2
        let opacity = 0.28 + (0.62 * progress)
        let scale = 0.86 + (0.22 * progress)
        return (opacity, scale)
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
        case .growing:
            return 16.0 / 3.0
        }
    }

    private enum StatusDot {
        case grown
        case growing
        case unread
    }
}

private struct EmptyNoteCard: View {
    let transitionNamespace: Namespace.ID
    let isExpanded: Bool
    let isAddMorphActive: Bool
    let onTap: () -> Void
    @State private var showContent: Bool = true
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
        .onChange(of: isExpanded) { _, nowExpanded in
            if nowExpanded {
                showContent = false
            } else {
                Task {
                    try? await Task.sleep(nanoseconds: UInt64(noteMorphDuration * 1_000_000_000))
                    withAnimation(.easeOut(duration: 0.22)) {
                        showContent = true
                    }
                }
            }
        }
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
                    .fill(Color.white.opacity(0.96))
                    .matchedGeometryEffect(id: "new-thought-surface", in: transitionNamespace)
                    .shadow(color: noteShadowColor.opacity(0.58), radius: 12, x: 0, y: 8)
            } else {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(Color.white.opacity(0.96))
                    .shadow(color: noteShadowColor.opacity(0.58), radius: 12, x: 0, y: 8)
            }

            if isMatched {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(noteBorderColor.opacity(0.35), lineWidth: 1)
                    .matchedGeometryEffect(id: "new-thought-stroke", in: transitionNamespace)
            } else {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(noteBorderColor.opacity(0.35), lineWidth: 1)
            }

            if isMatched {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 6]))
                    .foregroundStyle(noteBorderColor.opacity(0.95))
                    .matchedGeometryEffect(id: "new-thought-dashed", in: transitionNamespace)
            } else {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 6]))
                    .foregroundStyle(noteBorderColor.opacity(0.95))
            }

            if showContent {
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
    }
}

private struct MorphingAddedNoteTarget: View {
    let note: APINote
    let rotation: Double
    let transitionNamespace: Namespace.ID

    var body: some View {
        RoundedRectangle(cornerRadius: 30, style: .continuous)
            .fill(Color.white.opacity(0.96))
            .matchedGeometryEffect(id: "new-thought-surface", in: transitionNamespace)
            .overlay {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(noteBorderColor, lineWidth: 1)
                    .matchedGeometryEffect(id: "new-thought-stroke", in: transitionNamespace)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 6]))
                    .foregroundStyle(noteBorderColor.opacity(0.95))
                    .matchedGeometryEffect(id: "new-thought-dashed", in: transitionNamespace)
                    .opacity(0.001)
            }
            .rotationEffect(.degrees(rotation))
            .shadow(color: noteShadowColor.opacity(0.72), radius: 14, x: 0, y: 8)
            .allowsHitTesting(false)
    }
}

private struct RelatedNoteCluster: View {
    let front: APINote
    let back: APINote
    let frontRotation: Double
    let backRotation: Double
    let activeDragNoteID: String?
    let isInReorderMode: Bool
    let dragTranslation: CGSize
    let phaseSeed: (String) -> Double
    let jiggleProgress: CGFloat
    let transitionNamespace: Namespace.ID
    let expandedNoteID: String?
    let onSelect: (String) -> Void
    let onDragChanged: (String, CGSize) -> Void
    let onDragEnded: (String, CGSize) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            NoteCard(
                note: back,
                rotation: backRotation,
                isReordering: activeDragNoteID == back.id,
                isInReorderMode: isInReorderMode,
                phaseSeed: phaseSeed(back.id),
                jiggleProgress: jiggleProgress,
                transitionNamespace: transitionNamespace,
                isExpanded: expandedNoteID == back.id,
                isTransitionSource: expandedNoteID == back.id
            )
                .padding(.top, 56)
                .padding(.leading, 8)
                .contentShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                .offset(activeDragNoteID == back.id ? dragTranslation : .zero)
                .zIndex(activeDragNoteID == back.id ? 100 : 0)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: NoteFramePreferenceKey.self,
                            value: [back.id: proxy.frame(in: .named("home-scroll"))]
                        )
                    }
                )
                .onTapGesture {
                    if isInReorderMode {
                        onDragEnded(back.id, .zero)
                    } else {
                        onSelect(back.id)
                    }
                }
                .highPriorityGesture(enterReorderGesture(noteID: back.id))
                .simultaneousGesture(clusterDragGesture(noteID: back.id))

            NoteCard(
                note: front,
                rotation: frontRotation,
                isReordering: activeDragNoteID == front.id,
                isInReorderMode: isInReorderMode,
                phaseSeed: phaseSeed(front.id),
                jiggleProgress: jiggleProgress,
                transitionNamespace: transitionNamespace,
                isExpanded: expandedNoteID == front.id,
                isTransitionSource: expandedNoteID == front.id
            )
                .padding(.trailing, 8)
                .contentShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                .offset(activeDragNoteID == front.id ? dragTranslation : .zero)
                .zIndex(activeDragNoteID == front.id ? 100 : 1)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: NoteFramePreferenceKey.self,
                            value: [front.id: proxy.frame(in: .named("home-scroll"))]
                        )
                    }
                )
                .onTapGesture {
                    if isInReorderMode {
                        onDragEnded(front.id, .zero)
                    } else {
                        onSelect(front.id)
                    }
                }
                .highPriorityGesture(enterReorderGesture(noteID: front.id))
                .simultaneousGesture(clusterDragGesture(noteID: front.id))
        }
        .padding(.bottom, 8)
    }

    private func enterReorderGesture(noteID: String) -> some Gesture {
        LongPressGesture(minimumDuration: 1.5)
            .onEnded { _ in
                onDragChanged(noteID, .zero)
            }
    }

    private func clusterDragGesture(noteID: String) -> some Gesture {
        DragGesture(coordinateSpace: .named("home-scroll"))
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
}

private struct AffinityCandidate {
    let targetID: String
    let since: Date
}

private struct AffinityGroup: Equatable {
    let frontID: String
    let backID: String

    func contains(_ noteID: String) -> Bool {
        noteID == frontID || noteID == backID
    }
}

private enum HomeItem: Identifiable {
    case note(APINote)
    case group(front: APINote, back: APINote)
    case seed

    var id: String {
        switch self {
        case .note(let note):
            return note.id
        case .group(let front, let back):
            return "group-\(front.id)-\(back.id)"
        case .seed:
            return "seed"
        }
    }

    var kind: Kind {
        switch self {
        case .note(let note):
            return .note(note)
        case .group(let front, let back):
            return .group(front: front, back: back)
        case .seed:
            return .seed
        }
    }

    var estimatedHeight: CGFloat {
        switch self {
        case .note(let note):
            let lines = min(max(ceil(Double(note.text.count) / 18.0), 2), 5)
            return 108 + CGFloat(lines) * 24
        case .group:
            return 360
        case .seed:
            return 156
        }
    }

    enum Kind {
        case note(APINote)
        case group(front: APINote, back: APINote)
        case seed
    }
}

private struct NoteFramePreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct DetailAnchorPreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]

    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct DetailBottomBarHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct DetailBottomBarInputTopPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 14

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
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
