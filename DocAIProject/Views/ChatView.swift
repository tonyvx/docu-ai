import SwiftUI
import SwiftData

struct ChatView: View {
    @Query private var documents: [Document]
    @State private var question = ""
    @State private var messages: [ChatMessage] = []
    @State private var isThinking = false

    private let chatService = RAGChatService()
    private let suggestedPrompts = [
        "Summarize this document",
        "What are the key dates?",
        "Find the most important details"
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if messages.isEmpty {
                    welcomeState
                } else {
                    messageList
                }

                Divider()

                composer
            }
            .navigationTitle("Assistant")
            .background(Color(.systemGroupedBackground))
        }
        .task {
            do {
                _ = try await LocalRAGIndex.shared.indexMissingDocuments(from: documents)
            } catch {
                print("Local RAG backfill will retry when sending a question: \(error.localizedDescription)")
            }
        }
    }

    private var welcomeState: some View {
        VStack(spacing: 18) {
            VStack(spacing: 12) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(.accent)

                Text("Ask your documents anything")
                    .font(.title2.bold())

                Text("Use your library to pull summaries, dates, key facts, and context in seconds.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Try a prompt")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(suggestedPrompts, id: \.self) { prompt in
                            Button(prompt) {
                                question = prompt
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding()
    }

    private var messageList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(messages) { message in
                    HStack {
                        if message.isUser { Spacer() }

                        MessageText(message: message)
                            .padding(14)
                            .frame(maxWidth: 320, alignment: .leading)
                            .background(message.isUser ? Color.accentColor : Color(.secondarySystemBackground))
                            .foregroundStyle(message.isUser ? .white : .primary)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                        if !message.isUser { Spacer() }
                    }
                }
            }
            .padding()
        }
    }

    private var composer: some View {
        VStack(spacing: 10) {
            if isThinking {
                HStack {
                    ProgressView()
                    Text("Thinking…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
            }

            HStack(spacing: 12) {
                TextField("Ask about your documents…", text: $question)
                    .textFieldStyle(.roundedBorder)

                Button {
                    Task { await ask() }
                } label: {
                    Image(systemName: "paperplane.fill")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.borderedProminent)
                .disabled(question.isEmpty || isThinking || documents.isEmpty)
            }
            .padding()
        }
    }

    private func ask() async {
        let prompt = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }

        isThinking = true
        let userMessage = ChatMessage(text: prompt, isUser: true)
        messages.append(userMessage)
        question = ""

        defer {
            isThinking = false
        }

        do {
            let priorConversation = messages.dropLast().map { message in
                let role = message.isUser ? "User" : "Assistant"
                return "\(role): \(message.text)"
            }

            let response = try await chatService.answer(
                question: prompt,
                using: documents,
                priorConversation: priorConversation
            )
            messages.append(ChatMessage(text: response, isUser: false))
        } catch let chatError as ChatModelError {
            if case .contextSizeExceeded = chatError {
                messages = compactConversation(messages)
            }
            messages.append(ChatMessage(text: chatError.userMessage, isUser: false))
        } catch {
            messages.append(ChatMessage(text: "The app could not complete this request. Please try a shorter or more specific question.\n\nDetail: \(error.localizedDescription)", isUser: false))
        }
    }

    private func compactConversation(_ conversation: [ChatMessage]) -> [ChatMessage] {
        guard conversation.count > 8 else { return conversation }

        let head = Array(conversation.prefix(2))
        let tail = Array(conversation.suffix(3))
        let middle = conversation.dropFirst(2).dropLast(3)
        let summaryText = "Earlier conversation summary: \(middle.map(\.text).joined(separator: " ").prefix(700))"

        return head + [ChatMessage(text: String(summaryText), isUser: false)] + tail
    }
}

private struct ChatMessage: Identifiable {
    let id = UUID()
    let text: String
    let isUser: Bool
}

private struct MessageText: View {
    let message: ChatMessage

    var body: some View {
        if message.isUser {
            Text(message.text)
        } else if let markdown = try? AttributedString(markdown: message.text) {
            Text(markdown)
        } else {
            Text(message.text)
        }
    }
}
