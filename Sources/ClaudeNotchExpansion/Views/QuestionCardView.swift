import SwiftUI

struct QuestionCardView: View {
    let question: PendingQuestion
    @EnvironmentObject var appState: AppState

    @State private var selectedLabels: [Int: Set<String>] = [:]
    @State private var customTexts: [Int: String] = [:]

    private var session: ClaudeSession? {
        appState.sessions.first { $0.id == question.sessionId }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.claudeTeal)
                        .frame(width: 6, height: 6)
                    Text("\(appState.sessions.filter { !$0.isTerminated }.count)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.claudeTeal)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.claudeTeal.opacity(0.12)))

                Image(systemName: "questionmark.bubble")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.claudeTeal)
                Text("Claude is asking")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                if let session {
                    Text(session.displayName)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.4))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider().overlay(Color.white.opacity(0.1))

            // Questions
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 10) {
                    ForEach(Array(question.questions.enumerated()), id: \.offset) { idx, item in
                        QuestionItemView(
                            item: item,
                            selected: selectedLabels[idx] ?? [],
                            customText: Binding(
                                get: { customTexts[idx] ?? "" },
                                set: { customTexts[idx] = $0 }
                            ),
                            onSelect: { label in handleSelect(idx: idx, item: item, label: label) },
                            onClearSelection: { selectedLabels[idx] = [] },
                            onCustomTextSubmit: { handleCustomTextSubmit(idx: idx, item: item) }
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .frame(maxHeight: 300)

            Divider().overlay(Color.white.opacity(0.1))

            // Submit / Send row
            HStack(spacing: 8) {
                Spacer()
                Button("Submit") { submitAll() }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 14)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.claudeTeal))
                    .buttonStyle(.plain)
                    .disabled(!allAnswered)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: 10,
                bottomLeadingRadius: 18,
                bottomTrailingRadius: 18,
                topTrailingRadius: 10,
                style: .continuous
            )
            .fill(Color.notchBG)
        )
        .padding(.horizontal, 4)
    }

    // MARK: - Logic

    private var allAnswered: Bool {
        question.questions.indices.allSatisfy { idx in
            let hasOption = !(selectedLabels[idx] ?? []).isEmpty
            let hasCustom = !(customTexts[idx] ?? "").trimmingCharacters(in: .whitespaces).isEmpty
            return hasOption || hasCustom
        }
    }

    private func handleSelect(idx: Int, item: QuestionItem, label: String) {
        if item.multiSelect {
            var set = selectedLabels[idx] ?? []
            if set.contains(label) { set.remove(label) } else { set.insert(label) }
            selectedLabels[idx] = set
        } else {
            // Clicking an option clears any typed custom text (mutually exclusive for single-select)
            customTexts[idx] = ""
            selectedLabels[idx] = [label]

            // Auto-submit only if there are no multi-select questions AND all others answered
            guard !hasMultiSelect else { return }
            let allOthersDone = question.questions.indices.allSatisfy { i in
                guard i != idx else { return true }
                let hasOption = !(selectedLabels[i] ?? []).isEmpty
                let hasCustom = !(customTexts[i] ?? "").trimmingCharacters(in: .whitespaces).isEmpty
                return hasOption || hasCustom
            }
            if allOthersDone { submitAll(overrideIdx: idx, overrideLabel: label) }
        }
    }

    private func handleCustomTextSubmit(idx: Int, item: QuestionItem) {
        let text = (customTexts[idx] ?? "").trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        // Typing custom text deselects option buttons for single-select
        if !item.multiSelect { selectedLabels[idx] = [] }

        guard !hasMultiSelect, !item.multiSelect else { return }
        // Single-select only question: auto-submit when all answered
        let allOthersDone = question.questions.indices.allSatisfy { i in
            guard i != idx else { return true }
            let hasOption = !(selectedLabels[i] ?? []).isEmpty
            let hasCustom = !(customTexts[i] ?? "").trimmingCharacters(in: .whitespaces).isEmpty
            return hasOption || hasCustom
        }
        if allOthersDone { submitAll() }
    }

    private var hasMultiSelect: Bool {
        question.questions.contains { $0.multiSelect }
    }

    private func submitAll(overrideIdx: Int? = nil, overrideLabel: String? = nil) {
        var answers: [String: String] = [:]
        for (idx, item) in question.questions.enumerated() {
            var parts: [String] = []
            var set = selectedLabels[idx] ?? []
            if let oi = overrideIdx, oi == idx, let ol = overrideLabel { set = [ol] }
            parts.append(contentsOf: set.sorted())
            let custom = (customTexts[idx] ?? "").trimmingCharacters(in: .whitespaces)
            if !custom.isEmpty { parts.append(custom) }
            if !parts.isEmpty {
                answers[item.question] = parts.joined(separator: ", ")
            }
        }
        let q = question
        Task { await PermissionServer.shared.submitAnswer(requestId: q.id, answers: answers) }
        appState.removeQuestion(id: question.id)
        if let sid = appState.sessions.first(where: { $0.id == question.sessionId })?.id {
            appState.updateSessionState(id: sid, state: .active)
        }
    }
}

// MARK: - Single question item

private struct QuestionItemView: View {
    let item: QuestionItem
    let selected: Set<String>
    @Binding var customText: String
    let onSelect: (String) -> Void
    let onClearSelection: () -> Void
    let onCustomTextSubmit: () -> Void

    @FocusState private var textFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let header = item.header, !header.isEmpty {
                Text(header.uppercased())
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.claudeTeal.opacity(0.8))
                    .tracking(0.5)
            }
            Text(item.question)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            if !item.options.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(item.options, id: \.label) { opt in
                        OptionButton(
                            label: opt.label,
                            description: opt.description,
                            isSelected: selected.contains(opt.label),
                            isMultiSelect: item.multiSelect
                        ) { onSelect(opt.label) }
                    }
                }
            }

            // Custom text input — shown always as "Other" fallback
            HStack(spacing: 6) {
                Image(systemName: "pencil")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(textFocused || !customText.isEmpty
                                     ? Color.claudeTeal : Color.white.opacity(0.3))
                TextField("Custom answer...", text: $customText)
                    .font(.system(size: 11))
                    .foregroundStyle(.white)
                    .textFieldStyle(.plain)
                    .focused($textFocused)
                    .onSubmit { onCustomTextSubmit() }
                    .onChange(of: customText) { _ in
                        // Typing clears option selection for single-select
                        if !item.multiSelect, !customText.isEmpty {
                            onClearSelection()
                        }
                    }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.white.opacity(textFocused ? 0.07 : 0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .strokeBorder(
                                textFocused ? Color.claudeTeal.opacity(0.5) : Color.white.opacity(0.08),
                                lineWidth: 1
                            )
                    )
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Option button

private struct OptionButton: View {
    let label: String
    let description: String?
    let isSelected: Bool
    let isMultiSelect: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if isMultiSelect {
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .font(.system(size: 10))
                        .foregroundStyle(isSelected ? Color.claudeTeal : Color.white.opacity(0.4))
                }
                Text(label)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .white : Color.white.opacity(0.75))
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 9)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isSelected ? Color.claudeTeal.opacity(0.25) : Color.white.opacity(0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .strokeBorder(isSelected ? Color.claudeTeal.opacity(0.6) : Color.clear, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .help(description ?? "")
    }
}

// MARK: - Simple flow layout for option buttons

private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 300
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxW: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { y += rowH + spacing; x = 0; rowH = 0 }
            rowH = max(rowH, size.height)
            x += size.width + spacing
            maxW = max(maxW, x)
        }
        return CGSize(width: maxW, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { y += rowH + spacing; x = bounds.minX; rowH = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            rowH = max(rowH, size.height)
            x += size.width + spacing
        }
    }
}
