import Contacts
import ContactsUI
import CoreLocation
import GnoshbotData
import Intents
import MapKit
import SwiftUI
import UserNotifications

struct MapGeocoder: AddressGeocoding {
    func geocode(_ draft: AddressDraft) async throws -> (latitude: Double, longitude: Double) {
        let geocoder = CLGeocoder()
        let marks = try await geocoder.geocodeAddressString(draft.geocodeQuery)
        guard let location = marks.first?.location else {
            throw AddressSaveError.geocodeFailed
        }
        return (location.coordinate.latitude, location.coordinate.longitude)
    }

    func reverse(coordinate: CLLocationCoordinate2D) async throws -> AddressDraft {
        let geocoder = CLGeocoder()
        let marks = try await geocoder.reverseGeocodeLocation(
            CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        )
        guard let mark = marks.first else { throw AddressSaveError.geocodeFailed }
        return AddressDraft(
            label: "",
            line1: [mark.subThoroughfare, mark.thoroughfare]
                .compactMap { $0 }
                .joined(separator: " "),
            line2: nil,
            city: mark.locality ?? "",
            region: mark.administrativeArea ?? "",
            postalCode: mark.postalCode ?? "",
            country: mark.isoCountryCode ?? mark.country ?? "US",
            isDefault: false
        )
    }
}

@MainActor
final class AddressPipeline {
    var settings: ControlPlaneSettings
    var http: any HTTPPerforming
    var geocoder: any AddressGeocoding
    var hydrator: CacheHydrator

    init(
        settings: ControlPlaneSettings,
        http: any HTTPPerforming = URLSession.shared,
        geocoder: any AddressGeocoding = MapGeocoder()
    ) {
        self.settings = settings
        self.http = http
        self.geocoder = geocoder
        self.hydrator = CacheHydrator(settings: settings, http: http)
    }

    func save(
        draft: AddressDraft,
        replacing id: UUID?,
        store: GnoshbotStore
    ) async throws -> EnsureResponse {
        let coords = try await geocoder.geocode(draft)
        _ = try store.saveAddress(
            draft: draft,
            latitude: coords.latitude,
            longitude: coords.longitude,
            replacing: id
        )
        if settings.isDemo {
            try await PrototypeCatalog.hydrate(into: store)
            return EnsureResponse(status: .ready, restaurants: try store.restaurantSnapshots().count)
        }
        let client = RegionEnsureClient(
            settings: settings,
            http: http,
            opaqueUser: DeviceIdentity.opaqueUser(defaults: DeviceIdentity.appGroupDefaults())
        )
        let ensured = try await client.ensureSavedAddress(
            latitude: coords.latitude,
            longitude: coords.longitude
        )
        store.lastEnsureCopy = ensured.mappingCopy
        let geohash5 = RegionBBox.fiveMilesAround(
            latitude: coords.latitude,
            longitude: coords.longitude
        ).geohash5
        if ensured.status == .ready {
            try await hydrator.hydrate(geohash5: geohash5, into: store)
        }
        return ensured
    }
}

struct HomeView: View {
    @Query(sort: \DeliveryLocation.label) private var addresses: [DeliveryLocation]
    @Query(sort: \ActiveOrderCache.timestamp, order: .reverse) private var orders: [ActiveOrderCache]
    @State private var showEditor = false
    @State private var editorDraft = AddressDraft.brooklynHome
    @State private var editingId: UUID?
    @State private var errorText: String?
    @State private var mappingCopy: String?
    @State private var showOnboarding = false

    private var settings: ControlPlaneSettings { ControlPlaneSettings.fromAppBundle() }
    private var pipeline: AddressPipeline { AddressPipeline(settings: settings) }

    var body: some View {
        NavigationStack {
            List {
                if settings.isDemo {
                    Section {
                        Text(
                            "Prototype: Siri confirms Home, then On it. Bio-Shield filters the bundled neighborhood before any on-device model re-ranks flavor. This is not a funded Smart Account. Payment is off — no meal is coming."
                        )
                        .font(.footnote)
                    }
                    Section("Profile") {
                        NavigationLink("Bio-Shield") {
                            BioShieldView(profile: Binding(
                                get: { GnoshbotStore.shared.profile },
                                set: { GnoshbotStore.shared.persistProfile($0) }
                            ))
                        }
                        NavigationLink("Flavor Fingerprint") {
                            FlavorView(profile: Binding(
                                get: { GnoshbotStore.shared.profile },
                                set: { GnoshbotStore.shared.persistProfile($0) }
                            ))
                        }
                    }
                }
                if let latest = orders.first {
                    Section("Current order") {
                        Text(latest.deliverySpokenLine)
                        Text(latest.status.rawValue)
                        if settings.isDemo, latest.status == .launching {
                            Text("Prototype: payment not enabled.")
                                .font(.footnote)
                        }
                    }
                }
                Section {
                    if addresses.isEmpty {
                        Text(AddressCopy.emptyState)
                    }
                    ForEach(addresses, id: \.id) { row in
                        Button {
                            editingId = row.id
                            editorDraft = AddressDraft(
                                label: row.label,
                                line1: row.line1,
                                line2: row.line2,
                                city: row.city,
                                region: row.region,
                                postalCode: row.postalCode,
                                country: row.country,
                                isDefault: row.isDefault
                            )
                            showEditor = true
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(row.label)
                                    if row.isDefault {
                                        Text("Default")
                                            .font(.caption)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .overlay(
                                                Capsule().stroke(Color.primary, lineWidth: 1)
                                            )
                                    }
                                }
                                Text("\(row.line1), \(row.city)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            try? GnoshbotStore.shared.deleteAddress(id: addresses[index].id)
                        }
                    }
                    Button("Add address") {
                        editingId = nil
                        editorDraft = AddressDraft(
                            label: "",
                            line1: "",
                            city: "",
                            region: "",
                            postalCode: "",
                            country: "US",
                            isDefault: addresses.isEmpty
                        )
                        showEditor = true
                    }
                } header: {
                    Text("Addresses")
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(AddressCopy.caption)
                        if let mappingCopy {
                            Text(mappingCopy)
                        }
                    }
                }
                if let errorText {
                    Section { Text(errorText).foregroundStyle(.red) }
                }
                Section {
                    Button("Allow Siri") {
                        INPreferences.requestSiriAuthorization { status in
                            siriStatus = String(describing: status)
                        }
                    }
                    if !siriStatus.isEmpty {
                        Text(siriStatus).font(.footnote)
                    }
                }
            }
            .navigationTitle("Gnoshbot")
            .onAppear {
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
                if settings.isDemo {
                    Task { try? await PrototypeCatalog.hydrate(into: GnoshbotStore.shared) }
                    if !PrototypeProfileStore.hasCompletedOnboarding {
                        showOnboarding = true
                    }
                }
            }
            .sheet(isPresented: $showOnboarding) {
                ProfileOnboardingView { showOnboarding = false }
            }
            .sheet(isPresented: $showEditor) {
                AddressEditorView(
                    draft: editorDraft,
                    existingId: editingId,
                    onSave: { draft in
                        Task {
                            do {
                                let ensured = try await pipeline.save(
                                    draft: draft,
                                    replacing: editingId,
                                    store: GnoshbotStore.shared
                                )
                                mappingCopy = ensured.mappingCopy
                                errorText = nil
                                showEditor = false
                            } catch AddressSaveError.geocodeFailed {
                                errorText = "Could not geocode that address. Save refused."
                            } catch AddressSaveError.duplicateLabel {
                                errorText = "That label is already used."
                            } catch {
                                errorText = error.localizedDescription
                            }
                        }
                    },
                    onCancel: { showEditor = false }
                )
            }
        }
    }
}

struct AddressEditorView: View {
    @State var draft: AddressDraft
    var existingId: UUID?
    var onSave: (AddressDraft) -> Void
    var onCancel: () -> Void
    @StateObject private var locator = LocationPin()
    @State private var showContacts = false
    @State private var geocodeError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Label", text: $draft.label)
                    TextField("Street", text: $draft.line1)
                    TextField("Apt / buzzer", text: Binding(
                        get: { draft.line2 ?? "" },
                        set: { draft.line2 = $0.isEmpty ? nil : $0 }
                    ))
                    TextField("City", text: $draft.city)
                    TextField("Region", text: $draft.region)
                    TextField("Postal", text: $draft.postalCode)
                    TextField("Country", text: $draft.country)
                    Toggle("Default", isOn: $draft.isDefault)
                }
                Section {
                    TextField("Map search", text: $locator.searchQuery)
                    Button("Search map") {
                        Task { await locator.search() }
                    }
                    Button("Fill Brooklyn Home example") {
                        draft = .brooklynHome
                        locator.coordinate = CLLocationCoordinate2D(
                            latitude: BrooklynDemoAddress.latitude,
                            longitude: BrooklynDemoAddress.longitude
                        )
                    }
                    Button("Use current location") {
                        locator.request()
                    }
                    Button("Choose from Contacts") {
                        showContacts = true
                    }
                    Map(position: $locator.camera) {
                        if let coordinate = locator.coordinate {
                            Marker(draft.label.isEmpty ? "Pin" : draft.label, coordinate: coordinate)
                        }
                    }
                    .frame(height: 220)
                } footer: {
                    Text(AddressCopy.caption)
                }
                if let geocodeError {
                    Section { Text(geocodeError) }
                }
            }
            .navigationTitle(existingId == nil ? "Add address" : "Edit address")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(draft) }
                }
            }
            .sheet(isPresented: $showContacts) {
                ContactPicker { contact in
                    apply(contact)
                    showContacts = false
                }
            }
            .onChange(of: locator.coordinate?.latitude) { _, _ in
                Task { await applyReverse() }
            }
        }
    }

    private func apply(_ contact: CNContact) {
        let postal = contact.postalAddresses.first?.value
        draft.line1 = postal.map { "\($0.street)" } ?? draft.line1
        draft.city = postal?.city ?? draft.city
        draft.region = postal?.state ?? draft.region
        draft.postalCode = postal?.postalCode ?? draft.postalCode
        draft.country = postal?.isoCountryCode.isEmpty == false ? postal!.isoCountryCode : (postal?.country ?? draft.country)
        if draft.label.isEmpty {
            draft.label = [contact.givenName, contact.familyName].filter { !$0.isEmpty }.joined(separator: " ")
        }
    }

    private func applyReverse() async {
        guard let coordinate = locator.coordinate else { return }
        do {
            var reversed = try await MapGeocoder().reverse(coordinate: coordinate)
            reversed.label = draft.label
            reversed.isDefault = draft.isDefault
            draft = reversed
            geocodeError = nil
        } catch {
            geocodeError = "Could not reverse-geocode that pin."
        }
    }
}

@MainActor
final class LocationPin: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var coordinate: CLLocationCoordinate2D?
    @Published var camera: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: BrooklynDemoAddress.latitude,
                longitude: BrooklynDemoAddress.longitude
            ),
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        )
    )
    @Published var searchQuery = ""
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
    }

    func request() {
        manager.requestWhenInUseAuthorization()
        manager.requestLocation()
    }

    func search() async {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = searchQuery
        guard !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        if let item = try? await MKLocalSearch(request: request).start().mapItems.first,
           let found = item.placemark.location?.coordinate
        {
            coordinate = found
            camera = .region(
                MKCoordinateRegion(
                    center: found,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                )
            )
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        coordinate = location.coordinate
        camera = .region(
            MKCoordinateRegion(
                center: location.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
        )
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}

struct ContactPicker: UIViewControllerRepresentable {
    var onPick: (CNContact) -> Void

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, CNContactPickerDelegate {
        var onPick: (CNContact) -> Void
        init(onPick: @escaping (CNContact) -> Void) { self.onPick = onPick }
        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            onPick(contact)
        }
    }
}
