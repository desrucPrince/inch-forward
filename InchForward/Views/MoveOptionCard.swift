import SwiftUI
import SwiftData

struct MoveOptionCard: View {
    @Bindable var move: Move
    let estimatedTime: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Text(move.title)
                    .font(.headline)
                    .foregroundColor(.primary)
                if let desc = move.M_description, !desc.isEmpty {
                    Text(desc)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                HStack {
                    Text("Category: \(move.category.rawValue.capitalized)")
                        .font(.caption2)
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "timer")
                        Text(estimatedTime)
                    }
                    .font(.caption2)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(UIColor.systemBackground))
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Goal.self, Move.self, configurations: config)
    
    let goal = Goal(title: "Learn SwiftUI", G_description: "Master SwiftUI development")
    let move = Move(title: "Build a sample app", M_description: "Create a simple todo app with animations and complex layouts", estimatedDuration: 1800, category: .learning, isDefaultMove: true, goal: goal)
    
    container.mainContext.insert(goal)
    container.mainContext.insert(move)
    
    return MoveOptionCard(
        move: move,
        estimatedTime: "30 min",
        action: {}
    )
    .modelContainer(container)
    .padding()
} 
