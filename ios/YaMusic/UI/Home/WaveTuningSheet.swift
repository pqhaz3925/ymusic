import SwiftUI

/// "Настроить Мою волну": pick an activity, a character, a mood and a language. Each group is
/// single-choice and optional (tap the chosen one again to clear it).
///
/// The choice is saved as it changes and applied once, when the sheet closes: if My Wave is the
/// current source it restarts with the new filters; otherwise they wait for the next start.
struct WaveTuningSheet: View {
    @Environment(AppSettings.self) private var settings
    @Environment(Player.self) private var player
    @Environment(\.dismiss) private var dismiss

    @State private var tuning = WaveTuning()
    @State private var initial = WaveTuning()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 30) {
                    Text("Настроить Мою волну")
                        .font(.system(size: 28, weight: .heavy))
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)

                    group("по занятию") {
                        HStack(spacing: 8) {
                            ForEach(WaveTuning.Activity.allCases) { a in
                                pill(a.title, selected: tuning.activity == a) {
                                    tuning.activity = tuning.activity == a ? nil : a
                                }
                            }
                        }
                    }

                    group("по характеру") {
                        HStack(spacing: 8) {
                            ForEach(WaveTuning.Character.allCases) { c in
                                tile(c, selected: tuning.character == c) {
                                    tuning.character = tuning.character == c ? nil : c
                                }
                            }
                        }
                    }

                    group("под настроение") {
                        HStack(alignment: .top, spacing: 0) {
                            ForEach(WaveTuning.Mood.allCases) { m in
                                orb(m, selected: tuning.mood == m) {
                                    tuning.mood = tuning.mood == m ? nil : m
                                }
                            }
                        }
                    }

                    group("по языку") {
                        HStack(spacing: 8) {
                            ForEach(WaveTuning.Language.allCases) { l in
                                pill(l.title, selected: tuning.language == l) {
                                    tuning.language = tuning.language == l ? nil : l
                                }
                            }
                        }
                    }

                    Button("Сбросить") { tuning = WaveTuning() }
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(tuning.isDefault ? Color.white.opacity(0.3) : .white)
                        .disabled(tuning.isDefault)
                        .padding(.top, 4)
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 24)
                .animation(.snappy(duration: 0.2), value: tuning)
            }
            .scrollIndicators(.hidden)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) { dismiss() }
                        .accessibilityLabel("Закрыть")
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
        .sensoryFeedback(.selection, trigger: tuning)
        .onAppear {
            tuning = settings.waveTuning
            initial = tuning
        }
        .onChange(of: tuning) { settings.waveTuning = tuning }
        .onDisappear(perform: apply)
    }

    /// One restart for the whole visit, and only if My Wave is what is playing.
    private func apply() {
        guard tuning != initial, WaveTuning.isMyWave(player.waveStationId) else { return }
        player.playWave(tuning.stationId)
    }

    // MARK: Pieces

    private func group(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(spacing: 14) {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white.opacity(0.45))
            GlassEffectContainer(spacing: 8) { content() }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    private func pill(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .foregroundStyle(selected ? .black : .white)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(selected ? .regular.tint(Theme.accent).interactive() : .regular.interactive(), in: .capsule)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func tile(_ c: WaveTuning.Character, selected: Bool, action: @escaping () -> Void) -> some View {
        let look = Self.look(c)
        return Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: look.symbol)
                    .font(.system(size: 42, weight: .bold))
                    .foregroundStyle(LinearGradient(colors: look.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(height: 52)
                Text(c.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity)
            .frame(height: 118)
            .contentShape(.rect(cornerRadius: 22))
        }
        .buttonStyle(.plain)
        .glassEffect(selected ? .regular.tint(look.colors[0].opacity(0.45)).interactive() : .regular.interactive(),
                     in: .rect(cornerRadius: 22))
        .overlay {
            if selected {
                RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.7), lineWidth: 1.5)
            }
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func orb(_ m: WaveTuning.Mood, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Circle()
                    .fill(LinearGradient(colors: Self.colors(m), startPoint: .top, endPoint: .bottom))
                    .frame(width: 58, height: 58)
                    .padding(5)
                    .overlay {
                        if selected { Circle().strokeBorder(.white, lineWidth: 2.5) }
                    }
                    .scaleEffect(selected ? 1.06 : 1)
                Text(m.title)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .foregroundStyle(selected ? .white : .white.opacity(0.8))
            }
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private static func look(_ c: WaveTuning.Character) -> (symbol: String, colors: [Color]) {
        switch c {
        case .favorite: ("heart.fill", [Color(red: 1.0, green: 0.35, blue: 0.35), Color(red: 0.75, green: 0.08, blue: 0.16)])
        case .discover: ("sparkle", [Color(red: 1.0, green: 0.90, blue: 0.40), Color(red: 0.95, green: 0.62, blue: 0.10)])
        case .popular: ("bolt.fill", [Color(red: 0.55, green: 1.0, blue: 0.55), Color(red: 0.10, green: 0.70, blue: 0.35)])
        }
    }

    private static func colors(_ m: WaveTuning.Mood) -> [Color] {
        switch m {
        case .active: [Color(red: 0.93, green: 0.62, blue: 0.20), Color(red: 0.90, green: 0.33, blue: 0.16)]
        case .fun: [Color(red: 0.86, green: 0.92, blue: 0.30), Color(red: 0.36, green: 0.76, blue: 0.30)]
        case .calm: [Color(red: 0.36, green: 0.80, blue: 0.70), Color(red: 0.26, green: 0.55, blue: 0.86)]
        case .sad: [Color(red: 0.22, green: 0.45, blue: 0.90), Color(red: 0.35, green: 0.16, blue: 0.86)]
        }
    }
}
