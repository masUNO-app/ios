import Testing
@testable import masUNO

struct CommunicationNotificationTests {
    @Test func messageBodyOmitsTheSenderAlreadyInTheHeader() {
        let payload = NotificationPayload(kind: "chat_message", body: "Hi", count: 1)
        #expect(payload.communicationBody(fallback: "Ari P.: Hi") == "Hi")
    }

    @Test func mergedMessagesFromOlderServersOmitRepeatedNames() {
        let payload = NotificationPayload(kind: "chat_message", body: "Ari P. and Sam L. · 3 new messages", count: 3)
        #expect(payload.communicationBody(fallback: "") == "3 new messages")
        let spanish = NotificationPayload(kind: "chat_message", body: "Ari P. · 2 mensajes nuevos", count: 2)
        #expect(spanish.communicationBody(fallback: "") == "2 mensajes nuevos")
    }

    @Test func messageTextIsPreservedEvenWhenItContainsNamesOrSeparators() {
        let payload = NotificationPayload(kind: "chat_message", body: "Ari P.: Hi · Court 2", count: 1)
        #expect(payload.communicationBody(fallback: "") == "Ari P.: Hi · Court 2")
    }
}
