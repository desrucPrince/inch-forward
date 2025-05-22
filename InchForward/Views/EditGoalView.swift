import SwiftUI
import SwiftData

struct EditGoalView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) var dismiss
    @Query(sort: \Goal.createdAt, order: .forward) private var goals: [Goal]
    @ObservedObject var viewModel: GoalViewModel
    
    @State private var selectedGoal: Goal?
    @State private var showEditSheet = false
    @State private var showAddMoveSheet = false
    
    var body: some View {
        NavigationStack {
            List {
                if goals.isEmpty {
                    ContentUnavailableView {
                        Label("No Goals", systemImage: "flag.fill")
                    } description: {
                        Text("You haven't created any goals yet.")
                    } actions: {
                        Button("Create a Goal") {
                            dismiss()
                        }
                    }
                } else {
                    ForEach(goals) { goal in
                        GoalSectionView(goal: goal, viewModel: viewModel) { selectedGoal in
                            self.selectedGoal = selectedGoal
                            self.showEditSheet = true
                        } addMoveAction: { selectedGoal in
                            self.selectedGoal = selectedGoal
                            self.showAddMoveSheet = true
                        }
                    }
                }
            }
            .navigationTitle("Your Goals")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showEditSheet) {
                if let goal = selectedGoal {
                    EditGoalDetailView(goal: goal, viewModel: viewModel)
                }
            }
            .sheet(isPresented: $showAddMoveSheet) {
                if let goal = selectedGoal {
                    AddMoveView(goal: goal, viewModel: viewModel)
                }
            }
        }
    }
}

struct GoalSectionView: View {
    @Bindable var goal: Goal
    @ObservedObject var viewModel: GoalViewModel
    var editAction: (Goal) -> Void
    var addMoveAction: (Goal) -> Void
    
    @State private var isExpanded = false
    
    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading) {
                        Text(goal.title)
                            .font(.headline)
                        
                        if let description = goal.G_description, !description.isEmpty {
                            Text(description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(isExpanded ? nil : 2)
                        }
                    }
                    
                    Spacer()
                    
                    Button {
                        isExpanded.toggle()
                    } label: {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .foregroundColor(.secondary)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    isExpanded.toggle()
                }
                
                if isExpanded {
                    Divider()
                    
                    // Goal status
                    HStack {
                        Text("Status:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text(goal.isCompleted ? "Completed" : "In Progress")
                            .font(.caption)
                            .foregroundColor(goal.isCompleted ? .green : .blue)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(goal.isCompleted ? Color.green.opacity(0.2) : Color.blue.opacity(0.2))
                            )
                        
                        Spacer()
                        
                        if !goal.isCompleted {
                            Button {
                                goal.isCompleted = true
                                goal.completionDate = Date()
                                try? modelContext.save()
                            } label: {
                                Text("Mark Complete")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    
                    // Moves section
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Moves (\(goal.moves.count))")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            Spacer()
                            
                            Button {
                                addMoveAction(goal)
                            } label: {
                                Label("Add Move", systemImage: "plus")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                        }
                        
                        if goal.moves.isEmpty {
                            Text("No moves created yet")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.vertical, 4)
                        } else {
                            ForEach(goal.moves) { move in
                                MoveRow(move: move)
                            }
                        }
                    }
                    .padding(.top, 4)
                    
                    // Action buttons
                    HStack {
                        Button {
                            editAction(goal)
                        } label: {
                            Label("Edit Goal", systemImage: "pencil")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        
                        Spacer()
                    }
                    .padding(.top, 8)
                }
            }
            .padding(.vertical, 8)
        }
    }
}

struct MoveRow: View {
    @Bindable var move: Move
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(move.title)
                    .font(.callout)
                
                if let description = move.M_description, !description.isEmpty {
                    Text(description)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            HStack(spacing: 4) {
                Text(move.category.rawValue.capitalized)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Text("•")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Text(move.displayDuration)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct EditGoalDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) var dismiss
    @Bindable var goal: Goal
    @ObservedObject var viewModel: GoalViewModel
    
    @State private var title: String = ""
    @State private var description: String = ""
    
    var body: some View {
        NavigationView {
            Form {
                TextField("Goal Title", text: $title)
                TextField("Description", text: $description, axis: .vertical)
                    .lineLimit(5)
                
                Section("Goal Status") {
                    Toggle("Mark as Completed", isOn: $goal.isCompleted)
                    
                    if goal.isCompleted {
                        DatePicker("Completion Date", selection: Binding(
                            get: { goal.completionDate ?? Date() },
                            set: { goal.completionDate = $0 }
                        ))
                    }
                }
                
                Section {
                    Button("Delete Goal", role: .destructive) {
                        modelContext.delete(goal)
                        try? modelContext.save()
                        dismiss()
                    }
                }
            }
            .navigationTitle("Edit Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        goal.title = title
                        goal.G_description = description.isEmpty ? nil : description
                        try? modelContext.save()
                        dismiss()
                    }
                    .disabled(title.isEmpty)
                }
            }
            .onAppear {
                title = goal.title
                description = goal.G_description ?? ""
            }
        }
    }
}

struct AddMoveView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) var dismiss
    @Bindable var goal: Goal
    @ObservedObject var viewModel: GoalViewModel
    
    @State private var title: String = ""
    @State private var description: String = ""
    @State private var estimatedDuration: Double = 300 // 5 minutes default
    @State private var category: MoveCategory = .planning
    @State private var isDefaultMove: Bool = false
    
    var body: some View {
        NavigationView {
            Form {
                TextField("Move Title", text: $title)
                
                TextField("Description (Optional)", text: $description, axis: .vertical)
                    .lineLimit(3)
                
                Section("Details") {
                    Picker("Category", selection: $category) {
                        ForEach(MoveCategory.allCases, id: \.self) { category in
                            Text(category.rawValue.capitalized)
                                .tag(category)
                        }
                    }
                    
                    VStack(alignment: .leading) {
                        Text("Estimated Duration: \(Int(estimatedDuration / 60)) minutes")
                            .font(.callout)
                        
                        Slider(value: $estimatedDuration, in: 60...3600, step: 60) {
                            Text("Duration")
                        } minimumValueLabel: {
                            Text("1m")
                        } maximumValueLabel: {
                            Text("60m")
                        }
                    }
                    
                    Toggle("Set as Default Move", isOn: $isDefaultMove)
                }
                
                Button("Add Move") {
                    let newMove = Move(
                        title: title,
                        M_description: description.isEmpty ? nil : description,
                        estimatedDuration: estimatedDuration,
                        category: category,
                        isDefaultMove: isDefaultMove,
                        goal: goal
                    )
                    
                    // If this is set as default, unset any existing default
                    if isDefaultMove {
                        for move in goal.moves where move.isDefaultMove {
                            move.isDefaultMove = false
                        }
                    }
                    
                    modelContext.insert(newMove)
                    try? modelContext.save()
                    dismiss()
                }
                .disabled(title.isEmpty)
            }
            .navigationTitle("Add New Move")
            .navigationBarTitleDisplayMode(.inline)
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
    let container = try! ModelContainer(for: Goal.self, Move.self, DailyProgress.self, configurations: config)
    
    // Create sample data
    let goal1 = Goal(title: "Write a Novel", G_description: "Complete the first draft of my fantasy novel")
    let goal2 = Goal(title: "Learn SwiftUI", G_description: "Master SwiftUI development")
    
    let move1 = Move(title: "Outline Chapter 1", M_description: "Create detailed outline", estimatedDuration: 1800, category: .planning, goal: goal1)
    let move2 = Move(title: "Write 500 words", M_description: "Focus on getting words on the page", estimatedDuration: 3600, category: .writing, goal: goal1)
    let move3 = Move(title: "Build sample app", M_description: "Create a simple app with SwiftUI", estimatedDuration: 7200, category: .creating, goal: goal2)
    
    container.mainContext.insert(goal1)
    container.mainContext.insert(goal2)
    container.mainContext.insert(move1)
    container.mainContext.insert(move2)
    container.mainContext.insert(move3)
    
    let viewModel = GoalViewModel(modelContext: container.mainContext)
    
    return EditGoalView(viewModel: viewModel)
        .modelContainer(container)
}
