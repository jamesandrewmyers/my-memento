import SwiftUI
import MapKit
import CoreData

struct LocationDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var noteIndexViewModel: NoteIndexViewModel
    let location: Location
    let viewContext: NSManagedObjectContext
    let onLocationSelected: (Location) -> Void
    
    @State private var region: MKCoordinateRegion
    @State private var cameraPosition: MapCameraPosition
    @State private var locationManager: LocationManager?
    @State private var formattedAddress = "Loading address..."
    @State private var isLoadingAddress = true
    @State private var notesWithLocation: [IndexPayload] = []
    
    init(location: Location, viewContext: NSManagedObjectContext, onLocationSelected: @escaping (Location) -> Void) {
        self.location = location
        self.viewContext = viewContext
        self.onLocationSelected = onLocationSelected
        
        // Initialize region centered on the location
        let center = CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)
        let span = MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        self._region = State(initialValue: MKCoordinateRegion(center: center, span: span))
        self._cameraPosition = State(initialValue: .region(MKCoordinateRegion(center: center, span: span)))
    }
    
    var body: some View {
        Group {
            if #available(iOS 16.0, *) {
                NavigationStack {
                    contentView
                        .navigationDestination(for: IndexPayload.self) { indexPayload in
                            NoteEditView(indexPayload: indexPayload)
                                .onDisappear {
                                    noteIndexViewModel.refreshIndex(from: viewContext)
                                    loadNotesWithLocation()
                                }
                        }
                }
            } else {
                NavigationView {
                    contentView
                        .navigationDestination(for: IndexPayload.self) { indexPayload in
                            NoteEditView(indexPayload: indexPayload)
                                .onDisappear {
                                    noteIndexViewModel.refreshIndex(from: viewContext)
                                    loadNotesWithLocation()
                                }
                        }
                }
            }
        }
        .onAppear {
            setupLocationManager()
            loadFormattedAddress()
            loadNotesWithLocation()
        }
    }
    
    private var contentView: some View {
        VStack(spacing: 0) {
            // Location Summary Card
            VStack(spacing: 0) {
                // Map View
                if #available(iOS 17.0, *) {
                    Map(position: $cameraPosition) {
                        Marker("", coordinate: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude))
                            .tint(.blue)
                    }
                    .frame(height: 200)
                } else {
                    Map(coordinateRegion: $region, annotationItems: [LocationDetailMapAnnotation(coordinate: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude))]) { annotation in
                        MapPin(coordinate: annotation.coordinate, tint: .blue)
                    }
                    .frame(height: 200)
                }
                
                // Location Info Summary
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "location.fill")
                            .foregroundColor(.blue)
                            .font(.title3)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(location.name ?? "Unnamed Location")
                                .font(.headline)
                                .fontWeight(.semibold)
                            
                            if isLoadingAddress {
                                HStack {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                    Text("Loading address...")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            } else {
                                Text(formattedAddress)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        Text("\(notesWithLocation.count) note\(notesWithLocation.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color(.systemBackground))
            }
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(radius: 2)
            .padding()
            
            // Notes List with full functionality
            NoteListWithFiltersView.readOnly(
                allIndices: notesWithLocation,
                navigationTitle: "Notes with this location",
                showSearch: true,
                showSort: true
            )
        }
        .navigationTitle("Location Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") {
                    dismiss()
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Select") {
                    onLocationSelected(location)
                    dismiss()
                }
            }
        }
    }
    
    private func setupLocationManager() {
        locationManager = LocationManager(context: viewContext, keyManager: KeyManager.shared)
    }
    
    private func loadFormattedAddress() {
        guard let locationManager = locationManager else {
            formattedAddress = String(format: "%.6f, %.6f", location.latitude, location.longitude)
            isLoadingAddress = false
            return
        }
        
        Task {
            do {
                let address = try locationManager.formatAddress(from: location)
                await MainActor.run {
                    self.formattedAddress = address
                    self.isLoadingAddress = false
                }
            } catch {
                await MainActor.run {
                    self.formattedAddress = String(format: "%.6f, %.6f", location.latitude, location.longitude)
                    self.isLoadingAddress = false
                }
            }
        }
    }
    
    private func loadNotesWithLocation() {
        // Find all attachments that reference this location
        let fetchRequest: NSFetchRequest<Attachment> = Attachment.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "location == %@", location)
        
        do {
            let attachments = try viewContext.fetch(fetchRequest)
            let noteIds = Set(attachments.compactMap { $0.note?.id })
            
            // Filter noteIndexViewModel to only include notes with this location
            notesWithLocation = noteIndexViewModel.indexPayloads.filter { indexPayload in
                noteIds.contains(indexPayload.id)
            }.sorted { index1, index2 in
                // Sort by pinned status first, then by creation date
                if index1.pinned != index2.pinned {
                    return index1.pinned && !index2.pinned
                }
                return index1.createdAt > index2.createdAt
            }
        } catch {
            print("Error loading notes with location: \(error)")
            notesWithLocation = []
        }
    }
}

// Helper struct for map annotations
private struct LocationDetailMapAnnotation: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}

#Preview {
    // Create a mock location for preview
    let context = PersistenceController.preview.container.viewContext
    let location = Location(context: context)
    location.id = UUID()
    location.name = "Sample Location"
    location.latitude = 37.7749
    location.longitude = -122.4194
    location.createdAt = Date()
    
    return LocationDetailView(
        location: location,
        viewContext: context,
        onLocationSelected: { _ in }
    )
}