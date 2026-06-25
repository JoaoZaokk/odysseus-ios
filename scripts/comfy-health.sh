#!/usr/bin/env bash
# comfy-health.sh — read-only health check for a ComfyUI server.
# Usage: scripts/comfy-health.sh [http://host:port]   (default: $COMFY_URL or http://127.0.0.1:8188)
# Hits only GET endpoints; never POSTs a workflow. Exits non-zero if /system_stats fails.
set -uo pipefail
C="${1:-${COMFY_URL:-http://127.0.0.1:8188}}"
C="${C%/}"
echo "ComfyUI health check → $C"

code() { curl -s -m 8 -o /dev/null -w "%{http_code}" "$C$1" 2>/dev/null; }

ss=$(code /system_stats)
echo "  GET /system_stats : $ss"
if [ "$ss" != "200" ]; then echo "  ✗ system_stats unreachable"; exit 1; fi

for p in /object_info /queue /history /embeddings; do
  echo "  GET $p : $(code "$p")"
done

# Pretty summary (GPUs + counts) if python3 is available.
if command -v python3 >/dev/null 2>&1; then
  curl -s -m 10 "$C/system_stats" | python3 -c '
import sys,json
d=json.load(sys.stdin); s=d.get("system",{})
print(f"  ComfyUI {s.get(\"comfyui_version\")} on {s.get(\"os\")} | RAM {s.get(\"ram_free\",0)/1e9:.0f}/{s.get(\"ram_total\",0)/1e9:.0f} GB")
for g in d.get("devices",[]):
    print(f"  {g.get(\"name\")}: {g.get(\"vram_free\",0)/1e9:.1f}/{g.get(\"vram_total\",0)/1e9:.1f} GB free")
' 2>/dev/null
fi
echo "✓ done"
