# No shared abstraction over the API surface

A round-2 architecture audit (2026-08-30) proposed seven deepening candidates over `APIClient`,
the settings store, the model decoders, the SSE readers and the remote-list screens. Six were
put through adversarial verification against the source and **six were refuted**; the seventh
was a deletion, not a deepening. We are deliberately keeping the current shape, and this ADR
exists so the next architecture review does not re-propose the same six.

The reason recurs across all of them: **the app declares zero protocols.**
`grep -rE "^\s*(public|internal|private|fileprivate)? ?protocol " Odysseus/` returns nothing.
`APIClient` is a concrete `final class`, every view model takes it by that concrete type, and
there is no second implementation of anything. So each proposed seam would have exactly one
adapter — a hypothetical seam, indirection bought with no leverage — and in most cases the
interface needed to serve every call site would be wider than the implementation behind it.

## What was rejected, and why

| Candidate | Why it was refuted |
|---|---|
| **The remote-collection screen** (13 sites, not the claimed ~20) | Only the ~10-line load state machine is genuinely shared. Container shape varies four ways, five sites cannot accept a module-supplied container, the collection that gates `loading` differs from the one that gates `empty` at four sites, three empty states are interactive views, and error placement is six distinct policies plus a `notConfigured` third state in Email. An interface serving all 13 needs ~10 closures: a shallow module with a giant parameter list. |
| **A setting declared once** (5 view models, not ~8) | `SettingsBag` already *is* the declaration, in 7 lines. Across the whole tree only two key literals are read twice. The search-provider credential slot defeats a declaration table outright: its key is computed from a value decoded four lines earlier in the same load, and the read is deliberately conditional and non-clobbering. |
| **Session authority** | Premise false in both halves. Session state already has exactly one owner (`AppState`); no feature store holds a slice of it. What they hold is `error: String?`, which is display state. The real gap is the opposite of scattering — see [#23](https://github.com/JoaoZaokk/odysseus-ios/issues/23). |
| **A request as a value** (82 methods) | Deletion test *moves*, does not concentrate. `APIClient.login` is the one method where a non-2xx response is a **success**, by design and by comment; a unified request pipeline breaks it. With one adapter and no protocol, the description-object layer is pure relocation. |
| **Tolerant decoding** (33 decoders, not ~25) | This seam was **already built and already failed to generalize**, inside one file: `ChatSession.decodeID` (`Models.swift:212`) is literally the proposed helper, called once, while two near-identical blocks 130 lines away use neither — because all three have different terminal fallbacks. `CreateSessionResponse`'s `""` fallback is load-bearing (`APIClient.swift:358`) and the proposed helper's UUID fallback would break the guard that reads it. |
| **The SSE reader** (2 sites, count exact) | Two adapters clears the bar by exactly one, and the narrow module — "yields frames, routing left to the caller" — removes 12 lines and is a pass-through. The fat version concentrates only chat-domain error vocabulary that the second caller provably discards: `ResearchRunner` binds the thrown error and never reads it (`ResearchGraph.swift:189-191`), rendering one fixed sentence for every failure. |

The one candidate that survived was **deleting `Features`** — fetched three times per session,
read by nothing ([#22](https://github.com/JoaoZaokk/odysseus-ios/issues/22)).

## What this does not say

This is not "the current shape is good". Verification confirmed one real structural problem
that none of the six proposals correctly named: **no test can reach a view model's load path.**
All 128 tests are pure decoding and parsing; the only production symbol any of them touches
near this area is `APIClient.parseGroupedModels`. Because `APIClient` is concrete and injected
by concrete type, driving `BrainViewModel.load()` requires a live server.

If that gap is ever worth closing, a protocol at that one seam has a real second adapter — the
test double — which is exactly the condition the six rejected candidates could not meet. Reopen
this ADR then, on that argument. Do not reopen it on duplication counts.
