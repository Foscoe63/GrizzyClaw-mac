import XCTest
@testable import GrizzyClawUI

@MainActor
final class LowContextSafeToolSelectionTests: XCTestCase {
    func testNotesPrefersSearchOverReadNote() throws {
        let defs = """
        {
          "data": {
            "tools": [
              { "name": "notes_read_note", "inputSchema": { "required": ["references"] } },
              { "name": "notes_open_note", "inputSchema": { "required": [] } },
              { "name": "notes_search_notes", "inputSchema": { "required": [] } }
            ]
          }
        }
        """
        let picked = ChatSessionModel.__testing_pickSafeToolName(
            domain: "notes",
            userText: "Do I have any notes?",
            getToolDefinitionsResult: defs
        )
        XCTAssertEqual(picked, "notes_search_notes")
    }

    func testRemindersPrefersSearchOverUpdateReminder() throws {
        let defs = """
        {
          "data": {
            "tools": [
              { "name": "reminders_update_reminder", "inputSchema": { "required": ["reminder"] } },
              { "name": "reminders_delete_reminder", "inputSchema": { "required": ["reminder"] } },
              { "name": "reminders_search_reminders", "inputSchema": { "required": [] } },
              { "name": "reminders_list_lists", "inputSchema": { "required": [] } }
            ]
          }
        }
        """
        let picked = ChatSessionModel.__testing_pickSafeToolName(
            domain: "reminders",
            userText: "Do I have any reminders for today?",
            getToolDefinitionsResult: defs
        )
        XCTAssertEqual(picked, "reminders_search_reminders")
    }

    func testMailPrefersSearchOverGetMessages() throws {
        let defs = """
        {
          "data": {
            "tools": [
              { "name": "mail_get_messages", "inputSchema": { "required": ["references"] } },
              { "name": "mail_open_message", "inputSchema": { "required": [] } },
              { "name": "mail_search_messages", "inputSchema": { "required": [] } }
            ]
          }
        }
        """
        let picked = ChatSessionModel.__testing_pickSafeToolName(
            domain: "mail",
            userText: "Check my inbox for unread email",
            getToolDefinitionsResult: defs
        )
        XCTAssertEqual(picked, "mail_search_messages")
    }
}

