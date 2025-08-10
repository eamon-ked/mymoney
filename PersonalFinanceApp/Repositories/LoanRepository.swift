import Foundation
import Combine

@MainActor
class LoanRepository: ObservableObject {
    private let localDB = LocalDatabaseManager.shared
    private let syncManager = SyncManager.shared
    
    @Published var loans: [PrivateLoan] = []
    @Published var isLoading = false
    @Published var error: String?
    
    init() {
        loadLoans()
    }
    
    func loadLoans() {
        isLoading = true
        error = nil
        do {
            loans = try localDB.fetchPrivateLoans()
            isLoading = false
        } catch {
            self.error = error.localizedDescription
            isLoading = false
        }
    }
    
    func addLoan(_ loan: PrivateLoan) {
        do {
            try localDB.insert(loan)
            loadLoans()
            syncManager.triggerSync()
        } catch { self.error = error.localizedDescription }
    }
    
    func updateLoan(_ loan: PrivateLoan) {
        do {
            loan.updatedAt = Date()
            loan.syncStatus = "pending"
            try localDB.save()
            loadLoans()
            syncManager.triggerSync()
        } catch { self.error = error.localizedDescription }
    }
    
    func deleteLoan(_ loan: PrivateLoan) {
        do {
            try localDB.delete(loan)
            loadLoans()
            syncManager.triggerSync()
        } catch { self.error = error.localizedDescription }
    }
}


