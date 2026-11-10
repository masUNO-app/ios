import Foundation
import Supabase

/// Runs one PostgREST call and translates what goes wrong into a `DomainError` (`docs/API.md`, Errors).
/// Every live repository goes through this, so screens only ever see `DomainError`.
func liveRequest<Value>(_ body: () async throws -> Value) async throws -> Value {
    do {
        return try await body()
    } catch let error as DomainError {
        throw error
    } catch let error as PostgrestError {
        throw DomainError(postgrest: error)
    } catch is URLError {
        throw DomainError.offline
    } catch is DecodingError {
        throw DomainError.unknown("decoding")
    } catch {
        throw DomainError.unknown(String(describing: error))
    }
}

extension DomainError {
    /// RPCs raise the bare code as `message`. A rejected or expired token comes from PostgREST
    /// itself (`PGRST301`–`PGRST303`), and means the session is gone.
    nonisolated init(postgrest error: PostgrestError) {
        if let code = error.code, ["PGRST301", "PGRST302", "PGRST303"].contains(code) {
            self = .notAuthenticated
        } else if error.message.localizedCaseInsensitiveContains("jwt expired") {
            self = .notAuthenticated
        } else {
            self = DomainError(serverCode: error.message)
        }
    }
}
