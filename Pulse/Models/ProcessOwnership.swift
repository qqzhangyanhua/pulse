import Foundation

/// `pbi_uid` matches this process. A missing row uid is not our user.
func isOwnUser(rowUid: UInt32?, selfUid: UInt32) -> Bool {
    rowUid == selfUid
}
