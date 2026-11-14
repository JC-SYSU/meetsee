import Foundation
@main struct SettingsUpdateTests {
 static func main() {
  let old=Settings()
  func check(_ next:Settings,scan:Bool,query:Bool,listener:Bool=false) {
   let update=SettingsUpdate(from:old,to:next)
   precondition(update.needsScan == scan && update.queryChanged == query && update.listenerChanged == listener)
  }
  check(old,scan:false,query:false)
  var s=old;s.fontName="MiSans";s.highlightStyle="pearl";s.scanMotion="wave";s.glassTintStrength=0.8;s.visibleRows=8;s.windowWidth="wide"
  check(s,scan:false,query:false)
  s=old;s.hotKey=1;check(s,scan:false,query:false);precondition(SettingsUpdate(from:old,to:s).shortcutChanged)
  s=old;s.kinds=[.application];check(s,scan:false,query:true)
  s=old;s.matchPath=true;s.limit=50;check(s,scan:false,query:true)
  s=old;s.customExtensions="mp3";check(s,scan:false,query:true)
  s=old;s.showHidden=true;check(s,scan:true,query:true)
  s=old;s.roots=["/Applications"];check(s,scan:true,query:true)
  s=old;s.blacklistEnabled=true;s.blockedKeywords=["private"];check(s,scan:true,query:true)
  s=old;s.autoRefresh=false;check(s,scan:false,query:false,listener:true)
  precondition(SettingsUpdate(from:s,to:old).needsScan)
  s=old;s.blacklistEnabled=false;s.blockedKeywords=["inactive"]
  check(s,scan:false,query:false)
  print("PASS: presentation/no-op saves do not scan; query changes only rematch; scope changes and listener enable calibrate; disable only stops listener")
 }
}
