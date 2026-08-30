# A transport seam under APIClient

Supersedes nothing in [ADR 0001](0001-no-shared-abstractions-over-the-api-surface.md). It answers
the reopening that ADR predicted, on the argument that ADR named.

ADR 0001 closed the door on protocols **over** the API surface — six candidates, all refuted,
always for the same reason: the app declares zero protocols, `APIClient` is a concrete
`final class`, and every proposed seam would have had exactly one adapter. Its last section
then said, in as many words:

> **no test can reach a view model's load path.** … If that gap is ever worth closing, a protocol
> at that one seam has a real second adapter — the test double — which is exactly the condition
> the six rejected candidates could not meet. Reopen this ADR then, on that argument.

A round-3 review (2026-08-30, 18 agents, every candidate put through adversarial refutation)
produced twelve candidates. Ten were refuted. This was one of the two that survived, and it is
the one that meets the condition above.

## What was measured

Established twice, by an explorer and then independently by a verifier who built their own
harness rather than trusting the proposal:

- The bundle held **152 tests in 11 files**, every one of them pure decoding, parsing or
  table-checking. (ADR 0001 says 128; it was already stale by 24.)
- Of the **36** `final class … : ObservableObject` in `Odysseus/`, tests constructed **zero**.
- **21** view models declare `func load() async`. None was reachable.
- `APIClient` has exactly **one** production construction site: `AppState.swift:34`.
- It builds exactly **two** `URLSession`s, both inside its own `init`, both stored `let`.
- Reaching those two sessions from a test through the type instead of under it would have taken
  **13 protocols and ~94 member signatures** — a shallow mirror of a concrete class, which is
  precisely what ADR 0001 refused.
- **5** call sites bypass `send()` and hold a session directly (`login`, `logout`, `stop`,
  `ChatStreamClient.bytes(for:)`, `ResearchAPI`). Any seam placed *above* `send` misses all five.
  `login` is the method whose non-2xx-is-a-success design ADR 0001 explicitly protects.

Two facts were established empirically, not by reasoning:

- A `URLProtocol` in `configuration.protocolClasses` intercepts **both** `session.data(for:)`
  **and** `session.bytes(for:)`. The SSE reader is reachable, not only the request/response path.
- `URLProtocol.registerClass(_:)` is **not** an alternative. It returns `true` and does not
  reach a session built from `URLSessionConfiguration.default`, which is what both of these are;
  the request resolved real DNS and failed with `NSURLErrorDomain -1003`.

## The decision

`APIClient.init` takes one defaulted parameter:

```swift
init(config: ServerConfig, protocolClasses: [AnyClass]? = nil)
```

`nil` is Foundation's own protocol chain — the production path, and the only thing the app itself
ever asks for. `AppState.swift:34` is untouched. No protocol is declared; `grep -rE "protocol "
Odysseus/` still returns nothing, so ADR 0001's premise remains literally true. **The seam is
under the type, not in front of it**, which is why it does not contradict that ADR.

The second adapter is `OdysseusTests/StubTransport.swift`: a `URLProtocol` subclass with a
path-keyed routing table, recording what the app sent.

## Why this is a deepening and not just a hook

The interface gained is one Foundation-shaped optional. What sits behind it is the whole request
stack: two tuned session configurations, the cookie jar, the 401 → `onUnauthenticated` hop, the
2xx guard, the FastAPI 422 `detail`-array flattening, the non-JSON body cap, `decodeList`'s
single-key-wrapper fallback, the cancellation mapping, and the SSE byte stream.

Deletion test: the callers here are the tests, and without the parameter there is no interception
point at all. Complexity does not move — it either concentrates behind this parameter or every
test file carries its own mirror of whatever it wants to fake.

The two `URLSessionConfiguration` blocks, which were the same seven lines twice, are now one
`sessionConfiguration(cookies:protocolClasses:)`; the two sessions differ only in their timeouts.
That is what keeps the new parameter from being written twice.

## What it bought immediately

Thirteen tests that could not have been written the day before: a view model's `load()` asserted
on `memories`, `error` and `loading`; the error retracted by a second successful load; the 401
callback firing and 403 provably *not* firing it; the 422 array flattened into one sentence; the
5 KB non-JSON body capped at 500 characters; both of `decodeList`'s wire shapes; and the body the
app actually writes on `POST /api/memory/add`.

Each was checked by sabotage before being trusted — the 422 separator was changed on purpose and
the test failed with the expected diff.

## What this does not license

It does not reopen the six candidates ADR 0001 refuted. They were refuted on the one-adapter rule,
on the deletion test, and on divergence between call sites — none of which this changes. A protocol
**over** the API surface still has one adapter and still needs an argument this ADR does not supply.
