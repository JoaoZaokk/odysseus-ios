# MB_ERRORS_SOLUTIONS — errors → causes → fixes (memory bank)

> Each entry: error · probable cause · solution · related commit · validating test · status.

## Carried-over lessons (pre-V1, still relevant)
- **`POST /api/model-endpoints` → 422 "base_url: Field required"** · cause: sent JSON, endpoint
  uses FastAPI `Form(...)` · fix: send `application/x-www-form-urlencoded` · status: ✅ fixed previously.
- **Integration create → 422 "Integration base URL is required"** · cause: body used `url` ·
  fix: CalDAV/CardDAV use `base_url` · status: ✅ fixed previously.
- **`.ody(size:…)` → "argument 'weight' must precede 'design'"** · fix: order `size, weight, design` · status: ✅ pattern documented in CLAUDE.md.
- **macOS sandbox swallows in-app shape dumps** (no `/tmp`, no `log show`) · fix: render to a
  temp on-screen `Text` + screenshot, or GET `/openapi.json` · status: ✅ technique documented.

## V1 finalization (this effort)
_(entries appended as the Red/Blue Team and build work surfaces issues)_
