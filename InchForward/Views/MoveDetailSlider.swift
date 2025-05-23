import SwiftUI

// MARK: - Move Detail Level
enum MoveDetailLevel: CaseIterable {
    case vague
    case concise
    case detailed
    case granular
    case stepByStep
    
    var title: String {
        switch self {
        case .vague: return "Vague"
        case .concise: return "Concise"
        case .detailed: return "Detailed"
        case .granular: return "Granular"
        case .stepByStep: return "Step-by-Step"
        }
    }
    
    var description: String {
        switch self {
        case .vague: return "High-level, less overwhelming"
        case .concise: return "Brief and focused"
        case .detailed: return "Default detail level"
        case .granular: return "More specific steps"
        case .stepByStep: return "Micro-steps, easy to complete"
        }
    }
    
    var timeMultiplier: Double {
        switch self {
        case .vague: return 0.5
        case .concise: return 0.75
        case .detailed: return 1.0
        case .granular: return 1.5
        case .stepByStep: return 2.5
        }
    }
}

// MARK: - Custom Slider Component
struct MoveDetailSlider: View {
    @Binding var selectedLevel: MoveDetailLevel
    @Binding var isAdjusting: Bool
    let onLevelChange: (MoveDetailLevel) -> Void
    
    @State private var sliderValue: Double = 2.0 // Default to .detailed (index 2)
    
    private let levels = MoveDetailLevel.allCases
    
    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(.blue)
                Text("MOVE DETAIL LEVEL")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(selectedLevel.title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.blue)
            }
            
            // Custom Slider
            VStack(spacing: 8) {
                // Slider Track
                ZStack {
                    // Background track
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 8)
                    
                    // Active track (left of thumb)
                    HStack {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(LinearGradient(
                                colors: [.orange, .blue, .green],
                                startPoint: .leading,
                                endPoint: .trailing
                            ))
                            .frame(width: CGFloat(sliderValue / Double(levels.count - 1)) * (UIScreen.main.bounds.width - 80), height: 8)
                        Spacer()
                    }
                    
                    // Thumb
                    HStack {
                        Spacer()
                            .frame(width: CGFloat(sliderValue / Double(levels.count - 1)) * (UIScreen.main.bounds.width - 80))
                        
                        Circle()
                            .fill(.white)
                            .stroke(selectedLevel == .detailed ? .blue : .gray, lineWidth: 2)
                            .frame(width: 20, height: 20)
                            .shadow(radius: 2)
                        
                        Spacer()
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            isAdjusting = true
                            let newValue = max(0, min(Double(levels.count - 1), 
                                value.location.x / (UIScreen.main.bounds.width - 80) * Double(levels.count - 1)))
                            sliderValue = newValue
                            
                            let newLevel = levels[Int(round(newValue))]
                            if newLevel != selectedLevel {
                                selectedLevel = newLevel
                                onLevelChange(newLevel)
                            }
                        }
                        .onEnded { _ in
                            isAdjusting = false
                            // Snap to nearest level
                            sliderValue = Double(selectedLevel.index)
                        }
                )
                
                // Level indicators
                HStack {
                    ForEach(Array(levels.enumerated()), id: \.offset) { index, level in
                        VStack(spacing: 2) {
                            Circle()
                                .fill(selectedLevel == level ? .blue : .gray.opacity(0.3))
                                .frame(width: 6, height: 6)
                            
                            if index == 0 || index == levels.count - 1 {
                                Text(level.title)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        if index < levels.count - 1 {
                            Spacer()
                        }
                    }
                }
            }
            .padding(.horizontal)
            
            // Description
            Text(selectedLevel.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            // Estimated time adjustment
            if selectedLevel != .detailed {
                HStack {
                    Image(systemName: "clock")
                        .foregroundStyle(.orange)
                        .font(.caption)
                    
                    Text("Time estimate: \(selectedLevel.timeMultiplier, specifier: "%.1f")x")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    
                    Spacer()
                }
                .padding(.horizontal)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(16)
        .onAppear {
            sliderValue = Double(selectedLevel.index)
        }
    }
}

// MARK: - Extension for Index
extension MoveDetailLevel {
    var index: Int {
        return MoveDetailLevel.allCases.firstIndex(of: self) ?? 2
    }
}

// MARK: - Preview
#Preview {
    @Previewable @State var selectedLevel = MoveDetailLevel.detailed
    @Previewable @State var isAdjusting = false
    
    return VStack {
        MoveDetailSlider(
            selectedLevel: $selectedLevel,
            isAdjusting: $isAdjusting
        ) { newLevel in
            print("Level changed to: \(newLevel.title)")
        }
        
        Spacer()
    }
    .padding()
} 