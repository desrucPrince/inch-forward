import SwiftUI
import SwiftData

struct CreateGoalView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) var dismiss

    @State private var title: String = ""
    @State private var description: String = ""

    var body: some View {
        NavigationView {
            Form {
                TextField("Goal Title", text: $title)
                TextField("Description (Optional)", text: $description, axis: .vertical)

                Button("Create Goal") {
                    guard !title.isEmpty else { return }
                    let newGoal = Goal(title: title, G_description: description.isEmpty ? nil : description)
                    modelContext.insert(newGoal)
                    dismiss()
                }
                .disabled(title.isEmpty)
            }
            .navigationTitle("New Goal")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Goal.self, configurations: config)
    
    return CreateGoalView()
        .modelContainer(container)
} 