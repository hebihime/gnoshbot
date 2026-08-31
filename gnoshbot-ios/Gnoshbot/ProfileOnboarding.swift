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
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                ForEach(slugs, id: \.self) { slug in
                    SelectChip(title: slug, isOn: selected.wrappedValue.contains(slug)) {
                        toggle(slug, in: selected)
                    }
                }
            }
        }
    }

    private func toggle(_ slug: String, in selected: Binding<[String]>) {
        withAnimation(.snappy(duration: 0.15)) {
            if selected.wrappedValue.contains(slug) {
                selected.wrappedValue.removeAll { $0 == slug }
            } else {
                selected.wrappedValue.append(slug)
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
        withAnimation(.snappy(duration: 0.15)) {
            if !profile.neverIngredients.contains(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) {
                profile.neverIngredients.append(value)
            }
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
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
            ForEach(slugs, id: \.self) { slug in
                SelectChip(title: slug, isOn: selected.contains(slug)) {
                    withAnimation(.snappy(duration: 0.15)) {
                        if selected.contains(slug) {
                            selected.removeAll { $0 == slug }
                        } else {
                            selected.append(slug)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct SelectChip: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                }
                Text(title)
                    .font(.caption.weight(isOn ? .semibold : .regular))
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, 8)
            .background(isOn ? Color.accentColor : Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            .foregroundStyle(isOn ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "On" : "Off")
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
