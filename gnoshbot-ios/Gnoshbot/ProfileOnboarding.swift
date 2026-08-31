import SwiftUI
import GnoshbotData

struct BioShieldView: View {
    @Binding var profile: ProfileEnvelope

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Hard constraints. Gnoshbot will not guess if every nearby item collides.")
                    .font(.footnote)
                section(title: "Allergens", slugs: ProfileEnvelope.allergenSlugs, selected: $profile.allergens)
                section(title: "Frameworks", slugs: ProfileEnvelope.frameworkSlugs, selected: $profile.frameworks)
                TextField("Custom exclusion", text: customBinding)
                    .textInputAutocapitalization(.never)
            }
            .padding()
        }
        .navigationTitle("Bio-Shield")
    }

    private var customBinding: Binding<String> {
        Binding(
            get: { profile.customExclusions.first ?? "" },
            set: { profile.customExclusions = $0.trimmingCharacters(in: .whitespaces).isEmpty ? [] : [$0] }
        )
    }

    private func section(title: String, slugs: [String], selected: Binding<[String]>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], spacing: 8) {
                ForEach(slugs, id: \.self) { slug in
                    let on = selected.wrappedValue.contains(slug)
                    Button {
                        if on {
                            selected.wrappedValue.removeAll { $0 == slug }
                        } else {
                            selected.wrappedValue.append(slug)
                        }
                    } label: {
                        Text(slug)
                            .font(.caption)
                            .frame(minWidth: 44, minHeight: 44)
                            .padding(.horizontal, 8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(on ? Color.accentColor : Color.primary, lineWidth: on ? 4 : 2)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
    }
}

struct FlavorView: View {
    @Binding var profile: ProfileEnvelope
    @State private var neverDraft = ""

    var body: some View {
        Form {
            Section("What you crave") {
                chipCloud(ProfileEnvelope.cuisineChips, selected: $profile.preferredCuisines)
            }
            Section("Meal types") {
                chipCloud(ProfileEnvelope.mealChips, selected: $profile.preferredMealTypes)
            }
            Section("Never order this") {
                chipCloud(["cilantro", "olives", "mayonnaise", "onion"], selected: $profile.neverIngredients)
                TextField("Add ingredient", text: neverBinding)
                    .textInputAutocapitalization(.never)
                    .onSubmit { commitNever() }
            }
            Section("Spice") {
                Picker("Spice", selection: $profile.spice) {
                    Text("Mild").tag("mild")
                    Text("Medium").tag("medium")
                    Text("High").tag("high")
                }
                .pickerStyle(.segmented)
            }
        }
        .navigationTitle("Flavor")
    }

    private var neverBinding: Binding<String> {
        Binding(get: { neverDraft }, set: { neverDraft = $0 })
    }

    private func commitNever() {
        let value = neverDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        if !profile.neverIngredients.contains(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) {
            profile.neverIngredients.append(value)
        }
        neverDraft = ""
    }

    private func chipCloud(_ slugs: [String], selected: Binding<[String]>) -> some View {
        FlexibleChips(slugs: slugs, selected: selected)
    }
}

private struct FlexibleChips: View {
    var slugs: [String]
    @Binding var selected: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(slugs, id: \.self) { slug in
                let on = selected.contains(slug)
                Button(slug) {
                    if on {
                        selected.removeAll { $0 == slug }
                    } else {
                        selected.append(slug)
                    }
                }
                .buttonStyle(.bordered)
                .tint(on ? .accentColor : .secondary)
                .frame(minHeight: 44)
            }
        }
    }
}

struct ProfileOnboardingView: View {
    @State private var profile = PrototypeProfileStore.load()
    var onDone: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Set Bio-Shield and flavor so lunch picks from the prototype neighborhood can follow your constraints. Allergens are filtered on-device before any model sees a menu.")
                        .font(.footnote)
                }
                NavigationLink("Bio-Shield") {
                    BioShieldView(profile: $profile)
                }
                NavigationLink("Flavor Fingerprint") {
                    FlavorView(profile: $profile)
                }
            }
            .navigationTitle("Your profile")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Continue") {
                        GnoshbotStore.shared.persistProfile(profile)
                        PrototypeProfileStore.hasCompletedOnboarding = true
                        onDone()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") {
                        PrototypeProfileStore.hasCompletedOnboarding = true
                        onDone()
                    }
                }
            }
        }
    }
}
