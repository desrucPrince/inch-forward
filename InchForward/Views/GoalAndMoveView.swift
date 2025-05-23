import SwiftUI
import SwiftData

struct GoalAndMoveView: View {
    @Bindable var goal: Goal
    @Bindable var move: Move
    @State var viewModel: GoalViewModel
    @Binding var showSwapMoveSheet: Bool
    
    // Slider state
    @State private var selectedDetailLevel: MoveDetailLevel = .detailed
    @State private var isAdjustingSlider: Bool = false
    @State private var showDetailSlider: Bool = false
    @State private var isAdjustingDetailLevel: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Goal Information
            VStack(alignment: .leading) {
                Text("MACRO GOAL:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(goal.title)
                    .font(.title2)
                    .fontWeight(.bold)
                if let desc = goal.G_description, !desc.isEmpty {
                    Text(desc)
                        .font(.subheadline)
                        .foregroundStyle(.gray)
                }
            }
            .padding(.horizontal)

            Divider()

            // Today's Move Card
            VStack(alignment: .leading) {
                Text("TODAY'S 1% MOVE:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(move.title)
                    .font(.title)
                    .fontWeight(.semibold)
                if let moveDesc = move.M_description, !moveDesc.isEmpty {
                    Text(moveDesc)
                        .font(.body)
                        .foregroundStyle(.gray)
                }
                HStack {
                    Image(systemName: "timer")
                    Text(move.displayDuration)
                    
                    Spacer()
                    
                    // Toggle for detail slider
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showDetailSlider.toggle()
                            // Initialize detail level when showing slider
                            if showDetailSlider {
                                selectedDetailLevel = .detailed
                            }
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "slider.horizontal.3")
                            Text("Adjust")
                        }
                        .font(.caption)
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.blue.opacity(0.1))
                        .cornerRadius(12)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary.opacity(0.5))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.ultraThinMaterial)
            .cornerRadius(20)
            .padding(.horizontal)
            .blur(radius: isAdjustingDetailLevel ? 3 : 0)
            .opacity(isAdjustingDetailLevel ? 0.6 : 1.0)
            .animation(.easeInOut(duration: 0.4), value: isAdjustingDetailLevel)
            
            // Move Detail Slider (conditionally shown)
            if showDetailSlider {
                MoveDetailSlider(
                    selectedLevel: $selectedDetailLevel,
                    isAdjusting: $isAdjustingSlider
                ) { newLevel in
                    isAdjustingDetailLevel = true
                    Task {
                        await viewModel.adjustMoveDetailLevel(move, to: newLevel)
                        await MainActor.run {
                            isAdjustingDetailLevel = false
                        }
                    }
                }
                .padding(.horizontal)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
            
            // Recent Progress Section
            if !viewModel.getRecentCompletedMoves().isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .foregroundStyle(.green)
                        Text("RECENT PROGRESS:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    ForEach(Array(viewModel.getRecentCompletedMoves().enumerated()), id: \.offset) { index, completedMove in
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                            Text(completedMove.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 10)
            }

            // Action Buttons
            HStack(spacing: 15) {
                actionButton(title: "Done", systemImage: "checkmark.circle.fill", color: .green) {
                    viewModel.markMoveAsDone()
                }
                actionButton(title: "Swap", systemImage: "arrow.left.arrow.right.circle.fill", color: .blue) {
                    Task { await viewModel.prepareForSwap() }
                    showSwapMoveSheet = true
                }
                Menu {
                    Section("⚡ Move Options") {
                        Button("Break into smaller steps") {
                            // TODO: Implement break into smaller steps functionality
                            print("Break into smaller steps tapped")
                        }
                    }
                    
                    Section("⏰ Timing") {
                        Button("Snooze 1 hour") { viewModel.postponeMove(for: 3600) }
                        Button("Snooze 3 hours") { viewModel.postponeMove(for: 3600 * 3) }
                        Button("Skip for today", role: .destructive) { viewModel.markAsSkipped() }
                    }
                } label: {
                    Label("Adjust", systemImage: "ellipsis.circle.fill")
                        .padding(.vertical, 10)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 0, maxWidth: .infinity)
                        .background(.ultraThinMaterial)
                        .foregroundStyle(.primary)
                        .font(.headline)
                        .cornerRadius(10)
                }
            }
            .padding(.horizontal)
            .disabled(isAdjustingDetailLevel)
            .opacity(isAdjustingDetailLevel ? 0.5 : 1.0)
            .animation(.easeInOut(duration: 0.3), value: isAdjustingDetailLevel)
            Spacer()
        }
    }
    
    @ViewBuilder
    private func actionButton(title: String, systemImage: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: systemImage)
                Text(title)
            }
            .padding(.vertical, 10)
            .frame(minWidth: 0, maxWidth: .infinity)
            .background(.ultraThinMaterial)
            .foregroundStyle(.primary)
            .font(.headline)
            .cornerRadius(10)
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Goal.self, Move.self, configurations: config)
    
    let goal = Goal(title: "Learn SwiftUI", G_description: "Master SwiftUI development")
    let move = Move(title: "Build a sample app", M_description: "Create a simple todo app", estimatedDuration: 1800, category: .learning, isDefaultMove: true, goal: goal)
    
    container.mainContext.insert(goal)
    container.mainContext.insert(move)
    
    return GoalAndMoveView(
        goal: goal,
        move: move,
        viewModel: GoalViewModel(modelContext: container.mainContext),
        showSwapMoveSheet: .constant(false)
    )
    .modelContainer(container)
}
