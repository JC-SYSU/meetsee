//! Read-only acceptance tool. Not packaged or called by the application.
use lokii_core::{
    cache,
    indexer::IndexStore,
    search::{self, SearchMode},
};
use serde_json::{json, Value};
use std::io::{self, BufRead, Write};
fn main() {
    let path = std::env::args()
        .nth(1)
        .expect("private cache path required");
    let (index, _) = cache::load_compact(std::path::Path::new(&path)).expect("read private cache");
    let store = IndexStore::new();
    store.replace_compact(index);
    store.warm_query_index();
    for line in io::stdin().lock().lines() {
        let req: Value = serde_json::from_str(&line.unwrap()).unwrap();
        if let Some(path) = req["inspect"].as_str() {
            let present = store
                .read()
                .iter()
                .any(|(_, entry)| entry.path_equals(path));
            println!("{}", json!({"present": present}));
            io::stdout().flush().unwrap();
            continue;
        }
        if let Some(roots) = req["roots"].as_array() {
            let index = store.read();
            let counts: Vec<_> = roots.iter().map(|root| {
                let root = root.as_str().unwrap();
                let prefix = format!("{}/", root.trim_end_matches('/'));
                json!({"root": root, "count": index.iter().filter(|(_, entry)| entry.path_equals(root) || entry.path_starts_with(&prefix)).count()})
            }).collect();
            println!("{}", json!({"total": index.len(), "roots": counts}));
            io::stdout().flush().unwrap();
            continue;
        }
        let (results, error) = search::dispatch(
            &store,
            req["q"].as_str().unwrap(),
            if req["mode"] == "regex" {
                SearchMode::Regex
            } else {
                SearchMode::Substring
            },
            req["limit"].as_u64().unwrap_or(5000).min(5000) as usize,
        );
        println!(
            "{}",
            json!({"results":results.into_iter().map(|r|r.entry).collect::<Vec<_>>(),"error":error})
        );
        io::stdout().flush().unwrap();
    }
}
