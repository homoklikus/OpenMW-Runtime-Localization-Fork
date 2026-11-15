extends RefCounted
## Szyna zdarzeń gry (etap 0). Systemy (skrypty – etap 5, dialogi, AI, dźwięk) słuchają tu zamiast
## wywoływać się nawzajem. Zdarzenia nie niosą węzłów Godota – tylko stabilne identyfikatory.

signal cell_loaded(key: String)
signal cell_unloaded(key: String)
signal activated(sid: String, base: String, actor_kind: String)
signal game_saved(path: String)
signal game_loaded(path: String, warnings: Array)
