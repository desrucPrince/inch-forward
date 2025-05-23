import SwiftUI

struct DayCompleteView: View {
    let message: String
    var onContinue: (() -> Void)? = nil
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "party.popper.fill")
                .font(.system(size: 70))
                .foregroundColor(.green)
            Text("Amazing Progress!")
                .font(.title)
                .fontWeight(.bold)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            
            if let onContinue = onContinue {
                Button(action: onContinue) {
                    HStack {
                        Image(systemName: "arrow.forward.circle.fill")
                        Text("Continue with Another Move")
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .foregroundStyle(.primary)
                    .font(.headline)
                    .cornerRadius(10)
                }
                .padding(.top)
            }
        }
        .padding()
    }
}

#Preview {
    DayCompleteView(message: "Great job completing 'Write 500 words'!")
} 