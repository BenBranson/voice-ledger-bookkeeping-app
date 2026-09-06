import SwiftUI
import CoreAudio
import DesignSystem

/// Owner directive (2026-09-06): "Voice Ledger should have a settings menu
/// for audio input to pick from macbook mic or Maono 200w usb and pick for
/// audio output such as macbooks speakers or my bluetooth Soundcore q45
/// and Soundcore Space One." Lives directly in `VoiceLedgerApp` (not
/// `VoiceLedgerUI`) because it talks to `AudioDeviceManager`'s real
/// CoreAudio calls itself rather than being handed pre-fetched data by a
/// caller — this page IS the I/O, the same reasoning `ConnectionView`'s
/// OAuth flow lives where it can actually reach the backend.
struct AudioSettingsView: View {
    @State private var inputDevices: [AudioDeviceManager.Device] = []
    @State private var outputDevices: [AudioDeviceManager.Device] = []
    @State private var selectedInputID: AudioDeviceID?
    @State private var selectedOutputID: AudioDeviceID?
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VLSpacing.md) {
                Text("Audio Settings")
                    .font(VLTypography.pageTitle())
                    .foregroundStyle(VLColor.textPrimary)

                if let errorMessage {
                    Text(errorMessage)
                        .font(VLTypography.caption())
                        .foregroundStyle(.red)
                }

                deviceCard(
                    title: "MICROPHONE (INPUT)",
                    disclaimer: "Sets your Mac's system-wide default microphone — the same device every other app will use, not just Voice Ledger. Changing this while listening is safe; Voice Ledger already adapts to a mid-conversation device change.",
                    devices: inputDevices,
                    selectedID: $selectedInputID,
                    onSelect: { device in
                        do {
                            try AudioDeviceManager.setDefaultInput(device)
                            errorMessage = nil
                        } catch {
                            errorMessage = "Couldn't switch microphone: \(error.localizedDescription)"
                        }
                    }
                )

                deviceCard(
                    title: "SPEAKERS / HEADPHONES (OUTPUT)",
                    disclaimer: "Sets your Mac's system-wide default output device — the same scope, and the same reasoning, as the microphone picker above.",
                    devices: outputDevices,
                    selectedID: $selectedOutputID,
                    onSelect: { device in
                        do {
                            try AudioDeviceManager.setDefaultOutput(device)
                            errorMessage = nil
                        } catch {
                            errorMessage = "Couldn't switch output device: \(error.localizedDescription)"
                        }
                    }
                )
            }
            .padding(VLSpacing.pageGutter)
        }
        .background(VLColor.background)
        .onAppear(perform: refresh)
    }

    private func refresh() {
        inputDevices = AudioDeviceManager.inputDevices()
        outputDevices = AudioDeviceManager.outputDevices()
        selectedInputID = AudioDeviceManager.currentDefaultInput()?.id
        selectedOutputID = AudioDeviceManager.currentDefaultOutput()?.id
    }

    private func deviceCard(
        title: String,
        disclaimer: String,
        devices: [AudioDeviceManager.Device],
        selectedID: Binding<AudioDeviceID?>,
        onSelect: @escaping (AudioDeviceManager.Device) -> Void
    ) -> some View {
        VLCard {
            VStack(alignment: .leading, spacing: VLSpacing.sm) {
                Text(title)
                    .font(VLTypography.eyebrow())
                    .tracking(VLTypography.eyebrowTracking)
                    .foregroundStyle(VLColor.textMuted)
                Text(disclaimer)
                    .font(VLTypography.caption())
                    .foregroundStyle(VLColor.textMuted)

                if devices.isEmpty {
                    Text("No devices found.")
                        .font(VLTypography.body())
                        .foregroundStyle(VLColor.textMuted)
                } else {
                    VStack(spacing: VLSpacing.xxs) {
                        ForEach(devices) { device in
                            Button {
                                selectedID.wrappedValue = device.id
                                onSelect(device)
                            } label: {
                                HStack {
                                    Image(systemName: selectedID.wrappedValue == device.id ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selectedID.wrappedValue == device.id ? VLColor.cyan : VLColor.textMuted)
                                    Text(device.name)
                                        .font(VLTypography.body())
                                        .foregroundStyle(VLColor.textPrimary)
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                                .padding(.vertical, VLSpacing.xxs)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Button("Refresh Device List") { refresh() }
                    .buttonStyle(.bordered)
            }
        }
    }
}
