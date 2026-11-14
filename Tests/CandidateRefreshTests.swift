import Foundation
@main struct CandidateRefreshTests {
 static func main() {
  let page = SettingsDestination(name:"显示器",english:"Displays",identifier:"display",parent:"")
  let a = SearchCandidate.setting(page)
  let b = SearchCandidate.setting(SettingsDestination(name:"声音",english:"Sound",identifier:"sound",parent:""))
  precondition(candidateRowsNeedingReload([a,b],[a,b])!.isEmpty)
  precondition(candidateRowsNeedingReload([a,b],[b,a])! == IndexSet([0,1]))
  precondition(candidateRowsNeedingReload([a],[a,b]) == nil)
  let renamed = SearchCandidate.setting(SettingsDestination(name:"显示设置",english:"Displays",identifier:"display",parent:""))
  precondition(candidateRowsNeedingReload([a,b],[renamed,b])! == IndexSet(integer:0))
  precondition(renamed.selectionIdentity == a.selectionIdentity)
  print("PASS: unchanged candidates skip reload; changed/reordered cells refresh; row-count change reloads; stable selection identity")
 }
}
