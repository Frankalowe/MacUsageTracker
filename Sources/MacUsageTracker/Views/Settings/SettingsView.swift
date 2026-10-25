import SwiftUI

@MainActor
final class SettingsUIState: ObservableObject {
    // UI state helper
}

public struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var dataManager: DataManager
    
    var onClose: (() -> Void)?
    
    @StateObject private var uiState = SettingsUIState()
    @StateObject private var localLLM = LocalLLMService.shared
    
    public init(onClose: (() -> Void)? = nil) {
        self.onClose = onClose
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Preferences")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    dataManager.save()
                    if let onClose = onClose {
                        onClose()
                    } else {
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            Form {
                Section("Startup & Tracking") {
                    Toggle("Launch automatically when Mac starts up / logs in", isOn: Binding(
                        get: { dataManager.settings.launchAtLogin },
                        set: { newValue in
                            dataManager.settings.launchAtLogin = newValue
                            LaunchAtLoginManager.setEnabled(newValue)
                            dataManager.save()
                        }
                    ))
                    
                    Picker("Minimum Session Threshold:", selection: $dataManager.settings.minimumSessionSeconds) {
                        Text("30 seconds").tag(30)
                        Text("1 minute (Recommended)").tag(60)
                        Text("2 minutes").tag(120)
                        Text("5 minutes").tag(300)
                    }
                    .help("Periods shorter than this (e.g. accidental lid open) will not be saved to history.")
                }
                
                Section("Smart Reminders & Motivators") {
                    Toggle("Stretch & Hydrate alert every 90 minutes", isOn: $dataManager.settings.enableHydrateReminder)
                    Toggle("Motivational quote alert every 60 minutes", isOn: $dataManager.settings.enableMotivationalQuotes)
                    
                    if dataManager.settings.enableMotivationalQuotes {
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle("Source quotes from local LLM (Ollama)", isOn: $dataManager.settings.useLocalLLMForQuotes)
                            
                            if dataManager.settings.useLocalLLMForQuotes {
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(localLLM.isOllamaAvailable ? Color.green : Color.orange)
                                        .frame(width: 8, height: 8)
                                    Text(localLLM.isOllamaAvailable ? "Ollama Online (\(localLLM.availableModels.count) models available)" : "Ollama Offline (Falls back to curated quotes)")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                    
                                    Spacer()
                                    
                                    Button("Refresh") {
                                        Task {
                                            await localLLM.refreshModels(endpoint: dataManager.settings.localLLMEndpoint)
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                                
                                if !localLLM.availableModels.isEmpty {
                                    Picker("Model:", selection: $dataManager.settings.localLLMModel) {
                                        Text("Auto (Fastest available)").tag("auto")
                                        ForEach(localLLM.availableModels, id: \.self) { model in
                                            Text(model).tag(model)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                }
                                
                                Button(action: {
                                    Task {
                                        if let quote = await localLLM.generateMotivationalQuote(
                                            preferredModel: dataManager.settings.localLLMModel,
                                            endpoint: dataManager.settings.localLLMEndpoint
                                        ) {
                                            NotificationService.shared.sendNotification(
                                                title: "⚡ Local LLM Quote",
                                                subtitle: "Generated by \(dataManager.settings.localLLMModel == "auto" ? "Ollama" : dataManager.settings.localLLMModel)",
                                                body: "\"\(quote.quote)\" — \(quote.author)"
                                            )
                                        }
                                    }
                                }) {
                                    HStack(spacing: 4) {
                                        if localLLM.isGenerating {
                                            ProgressView()
                                                .controlSize(.small)
                                        } else {
                                            Image(systemName: "sparkles")
                                        }
                                        Text(localLLM.isGenerating ? "Generating..." : "Test Local LLM Quote ↗")
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .disabled(localLLM.isGenerating || !localLLM.isOllamaAvailable)
                                
                                if let testQuote = localLLM.lastGeneratedQuote {
                                    Text("\"\(testQuote.quote)\" — \(testQuote.author)")
                                        .font(.system(size: 10, weight: .medium, design: .serif))
                                        .foregroundColor(.secondary)
                                        .padding(6)
                                        .background(Color.gray.opacity(0.1))
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                            }
                        }
                        .padding(.leading, 18)
                        .padding(.vertical, 4)
                    }
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Toggle("End-of-day reminder after 10 hours screen time", isOn: $dataManager.settings.enableTenHourReminder)
                        Text("Sent only if 10 hours is reached today; otherwise no alert is sent.")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                
                Section("35-Day Storage Policy (Monthly Analysis)") {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Retention Policy:")
                                .font(.system(size: 11, weight: .medium))
                            Text("35 Days (Full Month Analysis)")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Text("Stored Sessions:")
                                .font(.system(size: 11, weight: .medium))
                            Text("\(dataManager.sessionsInRetentionPeriod().count) periods in last 35 days")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        
                        HStack(spacing: 10) {
                            Button("View Monthly History ↗") {
                                TimerHistoryWindowController.shared.showWindow()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                        .padding(.top, 4)
                    }
                    .padding(.vertical, 4)
                }
                
                Section("Website Tracking (Brave, Chrome, Safari, Edge, Arc)") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Websites are tracked natively via macOS Automation. For 100% precision without permission prompts, you can also use the companion extension:")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 8) {
                            Button("macOS Automation Settings ↗") {
                                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            
                            Button("Show Browser Extension Folder ↗") {
                                let extPath = "/Users/franklowe/Documents/antigravity/brave-oppenheimer/BrowserExtension"
                                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: extPath)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 500, height: 580)
    }
}
