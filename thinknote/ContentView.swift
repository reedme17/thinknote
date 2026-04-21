//
//  ContentView.swift
//  thinknote
//
//  Created by 严汀 on 4/5/26.
//

import SwiftUI

private let noteTransitionAnimation = Animation.spring(response: 0.56, dampingFraction: 0.88, blendDuration: 0.12)
private let noteAccentColor = Color(red: 0.53, green: 0.66, blue: 0.61)
private let noteBorderColor = Color(red: 0.88, green: 0.88, blue: 0.86)
private let noteShadowColor = Color.black.opacity(0.08)

private enum AppFont {
    static func heading(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        switch weight {
        case .semibold, .bold:
            return .custom("AlegreyaSans-Medium", size: size)
        default:
            return .custom("AlegreyaSans-Regular", size: size)
        }
    }

    static func body(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        switch weight {
        case .medium, .semibold, .bold:
            return .custom("DavidLibre-Medium", size: size)
        default:
            return .custom("DavidLibre-Regular", size: size)
        }
    }

    static func meta(_ size: CGFloat) -> Font {
        .custom("AlegreyaSans-Regular", size: size)
    }
}

struct ContentView: View {
    @StateObject private var viewModel = ContentViewModel()
    @Namespace private var noteTransitionNamespace

    var body: some View {
        ZStack {
            Color(red: 0.95, green: 0.95, blue: 0.95)
                .ignoresSafeArea()

            if viewModel.screen != .newNote {
                HomeScreen(
                    viewModel: viewModel,
                    transitionNamespace: noteTransitionNamespace,
                    expandedNoteID: activeDetailNote?.id
                )
                .opacity(activeDetailNote == nil ? 1 : 0.35)
                .allowsHitTesting(activeDetailNote == nil)
                .zIndex(0)
            }

            if viewModel.screen == .newNote {
                NewNoteScreen(viewModel: viewModel)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
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
            await viewModel.bootstrap()
        }
    }

    private var activeDetailNote: APINote? {
        guard case .detail(let noteID) = viewModel.screen else { return nil }
        return viewModel.note(for: noteID)
    }
}

private struct HomeScreen: View {
    @ObservedObject var viewModel: ContentViewModel
    let transitionNamespace: Namespace.ID
    let expandedNoteID: String?
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
                    reorderInstruction
                }
            }
        }
        .sheet(isPresented: $viewModel.showAssistant) {
            AssistantSheet(viewModel: viewModel)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
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
        let values: [Double] = [-2.2, 1.4, -1.2, 1.8, -1.5, 2.0]
        return values[index % values.count]
    }

    private func handleTap(on noteID: String) {
        withAnimation(noteTransitionAnimation) {
            viewModel.openNote(noteID: noteID)
        }
    }

    private var displayNotes: [APINote] {
        if viewModel.notes.count >= 4 {
            return Array(viewModel.notes.prefix(4))
        }

        let existingIDs = Set(viewModel.notes.map(\.id))
        let filler = ContentViewModel.demoNotes.filter { !existingIDs.contains($0.id) }
        return Array((viewModel.notes + filler).prefix(4))
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
                EmptyNoteCard {
                    viewModel.openNewNote()
                }
            }
        }
    }

    private func noteCard(_ note: APINote, index: Int) -> some View {
        NoteCard(
            note: note,
            rotation: rotation(for: index),
            isReordering: activeDragNoteID == note.id,
            isInReorderMode: isReorderMode,
            phaseSeed: phaseSeed(for: note.id),
            jiggleProgress: jiggleProgress,
            transitionNamespace: transitionNamespace,
            isExpanded: expandedNoteID == note.id
        )
        .frame(maxWidth: .infinity)
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
        orderedNoteIDs = orderedNoteIDs.filter(ids.contains) + missing

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
        LongPressGesture(minimumDuration: 1.5)
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

    private var reorderInstruction: some View {
        VStack(spacing: 10) {
            Text("Drag to reorder. Overlap another card to create an affinity group.")
                .font(AppFont.meta(13))
                .foregroundStyle(.black.opacity(0.72))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background(Color.white.opacity(0.9), in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                }

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
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .transition(.move(edge: .bottom).combined(with: .opacity))
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
    @FocusState private var isEditorFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar

            TextEditor(text: $viewModel.draftText)
                .focused($isEditorFocused)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .font(AppFont.body(22))
                .foregroundStyle(.black)
                .padding(.horizontal, 18)
                .padding(.top, 18)

            Spacer(minLength: 0)

            HStack(alignment: .center) {
                Menu {
                    Button("Discard draft") {
                        viewModel.discardDraft()
                    }
                } label: {
                    Text("...")
                        .font(AppFont.heading(24, weight: .semibold))
                        .foregroundStyle(.black)
                }

                Spacer()

                Button {
                    Task {
                        await viewModel.requestResponseForDraft()
                    }
                } label: {
                    if viewModel.isDraftResponding {
                        ProgressView()
                            .tint(.black)
                    } else {
                        Text("Request response")
                            .font(AppFont.body(18))
                            .foregroundStyle(.black)
                    }
                }
                .disabled(viewModel.trimmedDraftText.isEmpty || viewModel.isDraftResponding)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
        }
        .task {
            isEditorFocused = true
        }
        .task(id: viewModel.draftText) {
            guard !viewModel.trimmedDraftText.isEmpty else {
                return
            }

            try? await Task.sleep(nanoseconds: 700_000_000)

            if !Task.isCancelled {
                await viewModel.autosaveDraftIfNeeded()
            }
        }
    }

    private var topBar: some View {
        HStack {
            Spacer()

            Button {
                Task {
                    await viewModel.returnHomeFromDraft()
                }
            } label: {
                Text("home")
                    .font(AppFont.heading(16, weight: .semibold))
                    .foregroundStyle(.black)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .overlay(alignment: .bottomTrailing) {
            if viewModel.isDraftSaving {
                Text("auto-saving...")
                    .font(AppFont.meta(13))
                    .foregroundStyle(.black.opacity(0.65))
                    .padding(.trailing, 18)
                    .padding(.top, 60)
            } else if viewModel.didAutosaveDraft {
                Text("saved")
                    .font(AppFont.meta(13))
                    .foregroundStyle(.black.opacity(0.55))
                    .padding(.trailing, 18)
                    .padding(.top, 60)
            }
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

    var body: some View {
        GeometryReader { geometry in
            let topInset = geometry.safeAreaInsets.top
            let bottomInset = max(geometry.safeAreaInsets.bottom, 18)

            ZStack(alignment: .topTrailing) {
                detailSurface(topInset: topInset, bottomInset: bottomInset)

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
                .padding(.top, topInset + 12)
                .padding(.trailing, 18)
                .opacity(showChrome ? 1 : 0)
            }
            .ignoresSafeArea()
            .onAppear {
                startOpenSequence()
            }
        }
    }

    private func detailSurface(topInset: CGFloat, bottomInset: CGFloat) -> some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    metaStrip
                        .padding(.top, topInset + 54)

                    sectionLabel("seed")
                        .padding(.top, 26)

                    Text(note.text)
                        .font(AppFont.body(28))
                        .lineSpacing(4)
                        .foregroundStyle(.black)
                        .padding(.top, 12)

                    divider
                        .padding(.top, 30)

                    aiGrowthSection
                        .padding(.top, 26)

                    if !note.prompts.isEmpty {
                        openAnglesSection
                            .padding(.top, 28)
                    }

                    if !note.sources.isEmpty {
                        footnotesSection
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

                    Color.clear
                        .frame(height: 36)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 28)
            }

            bottomBar(bottomInset: bottomInset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(noteDetailBackground)
        .clipShape(RoundedRectangle(cornerRadius: showPrimaryContent ? 0 : 30, style: .continuous))
        .matchedGeometryEffect(id: "note-surface-\(note.id)", in: transitionNamespace)
    }

    private var metaStrip: some View {
        HStack(spacing: 16) {
            Text(noteTimestamp)
                .font(AppFont.meta(11))
                .tracking(1.6)
                .textCase(.uppercase)
                .foregroundStyle(.black.opacity(0.5))

            Text(aiStatusText)
                .font(AppFont.meta(11))
                .tracking(1.6)
                .textCase(.uppercase)
                .foregroundStyle(noteAccentColor)
        }
        .opacity(showPrimaryContent ? 1 : 0)
    }

    private var aiGrowthSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Circle()
                    .fill(noteAccentColor)
                    .frame(width: 7, height: 7)

                sectionLabel("AI growth", useAccent: true)
            }

            Text(latestInterpretation)
                .font(AppFont.body(21))
                .lineSpacing(4)
                .foregroundStyle(.black)
                .padding(.top, 12)

            if !summaryLine.isEmpty {
                Text(summaryLine)
                    .font(AppFont.body(16))
                    .foregroundStyle(.black.opacity(0.68))
                    .padding(.top, 14)
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
            }
        }
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

    private func bottomBar(bottomInset: CGFloat) -> some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                sectionLabel("continue the thread")

                TextField("Ask a follow-up...", text: $viewModel.followUpDraft, axis: .vertical)
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
            }

            HStack {
                Menu {
                    Button(viewModel.showTimeline ? "Hide evolution" : "Show evolution") {
                        viewModel.toggleTimeline()
                    }

                    Button("Refresh note") {
                        Task {
                            await viewModel.refreshCurrentNote()
                        }
                    }
                } label: {
                    Text("...")
                        .font(AppFont.heading(24, weight: .semibold))
                        .foregroundStyle(.black)
                }

                Spacer()

                Button {
                    Task {
                        if viewModel.followUpDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            await viewModel.requestResponse(for: note.id)
                        } else {
                            await viewModel.sendFollowUp()
                        }
                    }
                } label: {
                    Group {
                        if viewModel.isEnriching || viewModel.isSendingFollowUp {
                            ProgressView()
                                .tint(.black)
                        } else {
                            Text("Request response")
                                .font(AppFont.body(18))
                                .foregroundStyle(.black)
                        }
                    }
                    .frame(minWidth: 152)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.92), in: Capsule())
                    .overlay {
                        Capsule()
                            .stroke(noteBorderColor, lineWidth: 1)
                    }
                }
                .disabled(viewModel.isEnriching || viewModel.isSendingFollowUp)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, bottomInset)
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

    private var latestInterpretation: String {
        note.enrichments.first?.expansion ?? "Request response to grow this thought."
    }

    private var summaryLine: String {
        if let event = note.timeline.first {
            return event.summary.lowercased()
        }
        return note.status
    }

    private var aiStatusText: String {
        if !note.enrichments.isEmpty {
            return "grown \(note.enrichments.count)x"
        }
        if note.latestChatReply != nil {
            return "conversation active"
        }
        return "captured"
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

    private var noteDetailBackground: some View {
        RoundedRectangle(cornerRadius: showPrimaryContent ? 0 : 30, style: .continuous)
            .fill(Color.white)
            .overlay {
                RoundedRectangle(cornerRadius: showPrimaryContent ? 0 : 30, style: .continuous)
                    .stroke(noteBorderColor.opacity(0.72), lineWidth: 1)
            }
            .shadow(color: noteShadowColor, radius: 24, x: 0, y: 12)
    }

    private func startOpenSequence() {
        isClosing = false
        showChrome = false
        showPrimaryContent = false
        showGrowthContent = false
        showFootnoteContent = false

        withAnimation(.easeOut(duration: 0.18).delay(0.24)) {
            showChrome = true
        }

        withAnimation(.easeOut(duration: 0.18).delay(0.24)) {
            showPrimaryContent = true
        }

        withAnimation(.easeOut(duration: 0.6).delay(0.56)) {
            showGrowthContent = true
        }

        withAnimation(.easeOut(duration: 0.6).delay(1.0)) {
            showFootnoteContent = true
        }
    }

    private func closeDetail() {
        guard !isClosing else { return }
        isClosing = true

        withAnimation(.easeOut(duration: 0.16)) {
            showChrome = false
        }

        withAnimation(.easeOut(duration: 0.2)) {
            showPrimaryContent = false
            showGrowthContent = false
            showFootnoteContent = false
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

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
            let jiggle = jiggleState(at: timeline.date)

            VStack(alignment: .leading, spacing: 14) {
                summaryText

                HStack(alignment: .center, spacing: 12) {
                    Text(noteTimestamp)
                        .font(AppFont.meta(11))
                        .tracking(1.2)
                        .textCase(.uppercase)
                        .foregroundStyle(.black.opacity(0.5))

                    Spacer()

                    Text(cardStatus)
                        .font(AppFont.meta(11))
                        .tracking(1.2)
                        .textCase(.uppercase)
                        .foregroundStyle(hasAIResponse ? noteAccentColor : .black.opacity(0.62))
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(Color.white.opacity(0.96))
                    .overlay {
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .stroke(
                                isReordering || hasAIResponse ? noteAccentColor.opacity(isReordering ? 0.55 : 0.34) : noteBorderColor,
                                lineWidth: isReordering ? 1.3 : 1
                            )
                    }
            )
            .matchedGeometryEffect(id: "note-surface-\(note.id)", in: transitionNamespace)
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
            .rotationEffect(.degrees(rotation + jiggle.rotation))
            .offset(x: jiggle.offset.width, y: jiggle.offset.height)
            .scaleEffect(isReordering ? 1.02 : 1.0)
            .opacity(isExpanded ? 0.001 : 1)
            .shadow(
                color: noteShadowColor.opacity(isReordering ? 1 : 0.72),
                radius: isReordering ? 18 : 14,
                x: 0,
                y: isReordering ? 12 : 8
            )
            .animation(.easeInOut(duration: 0.18), value: isReordering)
        }
    }

    private var cardStatus: String {
        if hasAIResponse {
            return "growing"
        }
        return note.status
    }

    private var summaryText: some View {
        Text(note.text)
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
}

private struct EmptyNoteCard: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Circle()
                        .stroke(noteBorderColor.opacity(0.9), lineWidth: 1)
                        .frame(width: 28, height: 28)
                        .overlay {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.black.opacity(0.52))
                        }

                    Spacer()
                }

                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Start a thought...")
                        .font(AppFont.body(20))
                        .foregroundStyle(.black.opacity(0.88))

                    Text("tap to capture")
                        .font(AppFont.meta(12))
                        .tracking(1.1)
                        .textCase(.uppercase)
                        .foregroundStyle(.black.opacity(0.46))
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, minHeight: 156, maxHeight: 156, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(Color.white.opacity(0.96))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(noteBorderColor.opacity(0.35), lineWidth: 1)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 6]))
                    .foregroundStyle(noteBorderColor.opacity(0.95))
            }
            .shadow(color: noteShadowColor.opacity(0.58), radius: 12, x: 0, y: 8)
        }
        .buttonStyle(.plain)
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
                isExpanded: expandedNoteID == back.id
            )
                .padding(.top, 56)
                .padding(.leading, 8)
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
                isExpanded: expandedNoteID == front.id
            )
                .padding(.trailing, 8)
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

private extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
