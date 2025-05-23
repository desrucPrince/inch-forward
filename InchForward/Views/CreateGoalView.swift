import SwiftUI
import SwiftData

struct CreateGoalView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) var dismiss
    @Environment(GoalViewModel.self) var viewModel
    
    @State private var title: String = ""
    @State private var description: String = ""
    @State private var selectedGoalType: GoalType = .macro
    @State private var isCreating: Bool = false
    @State private var showingSuccessAnimation: Bool = false
    
    // Focus states for better UX
    @FocusState private var titleFieldFocused: Bool
    @FocusState private var descriptionFieldFocused: Bool
    
    enum GoalType: String, CaseIterable {
        case macro = "Macro Goal"
        case meso = "Meso Goal"
        case micro = "Micro Goal"
        
        var subtitle: String {
            switch self {
            case .macro:
                return "Big business objective"
            case .meso:
                return "Important milestone"
            case .micro:
                return "Daily 1% improvement"
            }
        }
        
        var icon: String {
            switch self {
            case .macro:
                return "target"
            case .meso:
                return "flag.fill"
            case .micro:
                return "plus.circle.fill"
            }
        }
        
        var gradient: LinearGradient {
            switch self {
            case .macro:
                return LinearGradient(colors: [Color.blue, Color.purple], startPoint: .topLeading, endPoint: .bottomTrailing)
            case .meso:
                return LinearGradient(colors: [Color.green, Color.blue], startPoint: .topLeading, endPoint: .bottomTrailing)
            case .micro:
                return LinearGradient(colors: [Color.orange, Color.pink], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: [Color(.systemBackground), Color(.secondarySystemBackground)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                // Main content in ScrollView
                ScrollView {
                    VStack(spacing: 20) {
                        // Header section with motivation
                        VStack(spacing: 0) {
                            Image(systemName: "arrow.up.right.circle.fill")
                                .font(.system(size: 50))
                                .foregroundStyle(selectedGoalType.gradient)
                                .symbolEffect(.bounce, value: selectedGoalType)
                            
                            Text("Every big achievement starts with a single step")
                                .font(.headline)
                                .multilineTextAlignment(.center)
                                .foregroundColor(.secondary)
                        }
                        
                        // Goal type selector
                        VStack(alignment: .leading, spacing: 16) {
                            Text("What type of goal is this?")
                                .font(.title3)
                                .fontWeight(.semibold)
                            
                            LazyVGrid(columns: [
                                GridItem(.flexible()),
                                GridItem(.flexible()),
                                GridItem(.flexible())
                            ], spacing: 12) {
                                ForEach(GoalType.allCases, id: \.self) { type in
                                    GoalTypeCard(
                                        type: type,
                                        isSelected: selectedGoalType == type
                                    ) {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            selectedGoalType = type
                                        }
                                    }
                                }
                            }
                        }
                        
                        // Input fields
                        VStack(spacing: 20) {
                            // Title field
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Goal Title")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                TextField("What do you want to achieve?", text: $title)
                                    .textFieldStyle(ModernTextFieldStyle())
                                    .focused($titleFieldFocused)
                                    .submitLabel(.next)
                                    .onSubmit {
                                        descriptionFieldFocused = true
                                    }
                            }
                            
                            // Description field
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Description")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                TextField("Add more details (optional)", text: $description)
                                    .textFieldStyle(ModernTextFieldStyle())
                                    .focused($descriptionFieldFocused)
                            }
                        }
                        
                        // 1% improvement tip
                        if selectedGoalType == .micro {
                            TipCard(
                                icon: "lightbulb.fill",
                                title: "1% Better Today",
                                message: "Make this goal something you can complete in 15-30 minutes. Small, consistent steps create massive results over time.",
                                backgroundColor: Color.orange.opacity(0.1),
                                iconColor: .orange
                            )
                        }
                        
                        // Add bottom padding to prevent content from being hidden behind the button
                        Color.clear
                            .frame(height: 100) // Space for the fixed button
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                }
                
                // Fixed button at bottom - ignores keyboard
                VStack {
                    Spacer()
                    
                    // Create Goal button with clear background overlay
                    VStack(spacing: 0) {
                        // Gradient fade effect above button
                        LinearGradient(
                            colors: [
                                Color(.systemBackground).opacity(0),
                                Color(.systemBackground).opacity(0.8),
                                Color(.systemBackground)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 20)
                        
                        // Button container with clear background
                        VStack {
                            Button(action: createGoal) {
                                HStack {
                                    if isCreating {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                            .scaleEffect(0.8)
                                    } else {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.title3)
                                    }
                                    
                                    Text(isCreating ? "Creating..." : "Create Goal")
                                        .font(.headline)
                                        .fontWeight(.semibold)
                                }
                                .foregroundColor(.primary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(
                                    RoundedRectangle(cornerRadius: 20)
                                        .fill(selectedGoalType.gradient)
                                        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                                )
                                .scaleEffect(title.isEmpty ? 0.95 : 1.0)
                                .opacity(title.isEmpty ? 0.6 : 1.0)
                            }
                            .disabled(title.isEmpty || isCreating)
                            .padding(.horizontal, 20)
                        }
                        .padding(.bottom, 20)
                        .background(Color(.systemBackground))
                    }
                }
                .ignoresSafeArea(.keyboard) // This prevents the button from moving up with keyboard
            }
            .navigationTitle("New Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.secondary)
                }
                
                ToolbarItem(placement: .keyboard) {
                    HStack {
                        Spacer()
                        Button("Done") {
                            hideKeyboard()
                        }
                        .foregroundColor(.blue)
                    }
                }
            }
            .onAppear {
                // Auto-focus on title field when view appears
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    titleFieldFocused = true
                }
            }
        }
    }
    
    private func createGoal() {
        guard !title.isEmpty else { return }
        
        withAnimation(.easeInOut(duration: 0.3)) {
            isCreating = true
        }
        
        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        // Create the new goal
        let newGoal = Goal(title: title, G_description: description.isEmpty ? nil : description)
        modelContext.insert(newGoal)
        
        // Save changes
        do {
            try modelContext.save()
            
            // Process the new goal with AI for SMART formatting and initial moves
            Task {
                await viewModel.processNewGoalWithAI(newGoal)
                
                // Success feedback and dismiss
                await MainActor.run {
                    let successFeedback = UINotificationFeedbackGenerator()
                    successFeedback.notificationOccurred(.success)
                    
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                        showingSuccessAnimation = true
                    }
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        dismiss()
                    }
                }
            }
        } catch {
            // Handle error
            isCreating = false
            // You might want to show an error alert here
        }
    }
    
    private func hideKeyboard() {
        titleFieldFocused = false
        descriptionFieldFocused = false
    }
}

// MARK: - Supporting Views

struct GoalTypeCard: View {
    let type: CreateGoalView.GoalType
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                ZStack {
                    Circle()
                        .fill(isSelected ? type.gradient : LinearGradient(colors: [Color.gray.opacity(0.2)], startPoint: .top, endPoint: .bottom))
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: type.icon)
                        .font(.title3)
                        .foregroundColor(isSelected ? .white : .secondary)
                }
                
                VStack(spacing: 5) {
                    Text(type.rawValue)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(isSelected ? .primary : .secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    
                    Text(type.subtitle)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .padding(.bottom)
                        .padding(.horizontal, 10)
                }
            }
            .padding(.top, 10)
            .frame(width: 115, height: 115) // Fixed size for all cards
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.ultraThinMaterial)
                } else {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.clear)
                        .stroke(Color(.separator), lineWidth: 2)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct ModernTextFieldStyle: TextFieldStyle {
    let isMultiline: Bool
    @Environment(\.isFocused) private var isFocused
    
    init(isMultiline: Bool = false) {
        self.isMultiline = isMultiline
    }
    
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(minHeight: 44) // Always 44pt height for both fields
            .background(
                RoundedRectangle(cornerRadius: 15)
                    .fill(Color(.tertiarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 15)
                            .stroke(
                                isFocused ? Color.blue.opacity(0.5) : Color(.separator),
                                lineWidth: isFocused ? 2.0 : 1.0
                            )
                    )
            )
            .font(.body)
            .animation(.easeInOut(duration: 0.2), value: isFocused)
    }
}

struct TipCard: View {
    let icon: String
    let title: String
    let message: String
    let backgroundColor: Color
    let iconColor: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(iconColor)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text(message)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(backgroundColor)
        )
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
