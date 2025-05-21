import SwiftUI
import SwiftData

struct GoalAndMoveView: View {
    @Bindable var goal: Goal
    @Bindable var move: Move
    @ObservedObject var viewModel: GoalViewModel
    @Binding var showSwapMoveSheet: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Goal Information
            VStack(alignment: .leading) {
                Text("MACRO GOAL:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(goal.title)
                    .font(.title2)
                    .fontWeight(.bold)
                if let desc = goal.G_description, !desc.isEmpty {
                    Text(desc)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
            }
            .padding(.horizontal)

            Divider()

            // Today's Move Card
            VStack(alignment: .leading) {
                Text("TODAY'S 1% MOVE:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(move.title)
                    .font(.title)
                    .fontWeight(.semibold)
                if let moveDesc = move.M_description, !moveDesc.isEmpty {
                    Text(moveDesc)
                        .font(.body)
                        .foregroundColor(.gray)
                }
                HStack {
                    Image(systemName: "timer")
                    Text(move.displayDuration)
                }
                .font(.subheadline)
                .foregroundColor(.secondary.opacity(0.5))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.ultraThinMaterial)
            .cornerRadius(20)
            .padding(.horizontal)
            

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
                    Button("Later Today (1hr)") { viewModel.postponeMove(for: 3600) }
                    Button("Later Today (3hr)") { viewModel.postponeMove(for: 3600 * 3) }
                    Button("Skip for Today", role: .destructive) { viewModel.markAsSkipped() }
                } label: {
                    Label("Later", systemImage: "ellipsis.circle.fill")
                        .padding(.vertical, 10)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 0, maxWidth: .infinity)
                        .background(.ultraThinMaterial)
                        .foregroundColor(.primary)
                        .font(.headline)
                        .cornerRadius(10)
                }
            }
            .padding(.horizontal)
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
            .foregroundColor(.primary)
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
