
import SwiftUI
import SwiftData

struct CreateGoalView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) var dismiss
    @Environment(GoalViewModel.self) var viewModel

    @State private var title: String = ""
    @State private var description: String = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Goal Title", text: $title)
                TextField("Description (Optional)", text: $description, axis: .vertical)

                Button("Create Goal") {
                    guard !title.isEmpty else { return }
                    
                    // Create the new goal
                    let newGoal = Goal(title: title, G_description: description.isEmpty ? nil : description)
                    modelContext.insert(newGoal)
                    
                    // Save changes
                    try? modelContext.save()
                    
                    // Process the new goal with AI for SMART formatting and initial moves
                    Task {
                        await viewModel.processNewGoalWithAI(newGoal)
                    }
                    
                    dismiss()
                }
                .disabled(title.isEmpty)
            }
            .navigationTitle("New Goal")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Goal.self, configurations: config)
    let modelContext = container.mainContext
    let viewModel = GoalViewModel(modelContext: modelContext)
    
    return CreateGoalView()
        .modelContainer(container)
        .environment(viewModel)
}
