import Foundation
@main struct SearchPerformanceTests {
 static func main() {
  let entries=(0..<1500).map { i in Entry(path:"/fixture/\(i % 2 == 0 ? "中文" : "logic")/file\(i).\(i % 3 == 0 ? "mp3" : "txt")",directory:false,modified:Double(i % 19)) }
  for legacy in [false,true] { for path in [false,true] { for modified in [false,true] { for limit in [1,5,20,50,2000] {
   var s=Settings();s.roots=["/fixture"];s.matchPath=path;s.sortModified=modified;s.limit=limit
   if legacy { s.legacyKinds=[.text,.other] }
   for query in ["file","file1","中文 file","logic","mp3","", "nothing"] {
    let old=referenceSearch(entries,query:query,settings:s);let new=search(entries,query:query,settings:s)
    precondition(old.total == new.total && old.entries.map{$0.path} == new.entries.map{$0.path},"Ranking/filter mismatch")
   }
  } } } }
  var polls=0
  _=search(entries,query:"file",settings:Settings(),cancelled:{polls += 1;return polls >= 3})
  precondition(polls == 3)
  print("PASS: bounded top-N matches full sorting across limits, legacy/current categories, path/name matching and both sort modes; cancellation stops traversal")
 }
}
