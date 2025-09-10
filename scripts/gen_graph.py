#!/usr/bin/env python3
"""
Generate a dependency graph (graph.json) for RaspiBlitz shell scripts.

- Scans *.sh files under home.admin/ plus top-level build_sdcard.sh
- Extracts calls to other scripts via common patterns (bash invocation, source)
- Normalizes referenced absolute paths (/home/admin/...) back to repo-relative
- Emits docs/graph/graph.json with nodes and edges suitable for visualizers

Node schema: { id, label, href, group }
Edge schema: { id, source, target, value }

Usage:
  python3 scripts/gen_graph.py

Output:
  docs/graph/graph.json
"""
import json
import os
import re
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
SRC_DIR = REPO_ROOT / 'home.admin'
TOP_FILES = [REPO_ROOT / 'build_sdcard.sh']
OUT_DIR = REPO_ROOT / 'docs' / 'graph'
OUT_FILE = OUT_DIR / 'graph.json'

# Regex patterns to detect script references
PATTERNS = [
    # absolute paths deployed on device
    re.compile(r"/home/admin/([A-Za-z0-9_./-]+\.sh)"),
    # relative or repo subpaths in code
    re.compile(r"(?:\.|\./|\s|\(|;)([A-Za-z0-9_./-]*config\.scripts/[A-Za-z0-9_./-]+\.sh)"),
    re.compile(r"(?:\.|\./|\s|\(|;)([A-Za-z0-9_./-]+\.sh)"),
    # source statements
    re.compile(r"source\s+<?\(?/?home/admin/([A-Za-z0-9_./-]+\.sh)\)?>?"),
    re.compile(r"source\s+([A-Za-z0-9_./-]+\.sh)")
]

# Index all *.sh files across the repo for robust resolution by suffix match
ALL_SH = [p for p in REPO_ROOT.rglob('*.sh') if p.is_file()]
# Map suffix to full relpath candidates
SUFFIX_INDEX = {}
for p in ALL_SH:
    rel = p.relative_to(REPO_ROOT).as_posix()
    SUFFIX_INDEX.setdefault(rel, set()).add(rel)
    # also index by basename
    SUFFIX_INDEX.setdefault(p.name, set()).add(rel)

# Helper to normalize a referenced path string to repo-relative path
def normalize_ref(ref: str, src_rel_dir: str) -> str | None:
    ref = ref.strip()
    # map /home/admin/... back to home.admin/...
    if ref.startswith('config.scripts/') or ref.startswith('setup.scripts/'):
        candidate = f"home.admin/{ref}"
        if (REPO_ROOT / candidate).exists():
            return candidate
    if ref.startswith('home.admin/'):
        if (REPO_ROOT / ref).exists():
            return ref
    if ref.startswith('/home/admin/'):
        candidate = ref[len('/home/admin/'):]
        if candidate.startswith('config.scripts/') or candidate.startswith('setup.scripts/'):
            candidate = f"home.admin/{candidate}"
        if candidate and (REPO_ROOT / candidate).exists():
            return candidate
    # handle ./relative
    if ref.startswith('./'):
        base = Path(src_rel_dir)
        candidate = (base / ref[2:]).as_posix()
        if (REPO_ROOT / candidate).exists():
            return candidate
    # try direct repo-relative
    if (REPO_ROOT / ref).exists():
        return ref
    # suffix match as last resort
    if ref in SUFFIX_INDEX:
        # prefer exact single match
        candidates = sorted(SUFFIX_INDEX[ref])
        # pick shortest path to reduce false positives
        return min(candidates, key=len)
    # try to find by tail component
    tail = ref.split('/')[-1]
    if tail in SUFFIX_INDEX:
        candidates = [c for c in SUFFIX_INDEX[tail] if c.endswith(tail)]
        if candidates:
            return min(candidates, key=len)
    return None

# Categorize node into groups used by the viewer
def categorize(rel: str) -> str:
    if rel == 'build_sdcard.sh':
        return 'BOOT'
    if rel.startswith('home.admin/_'):
        # finer groups for background/provision handled below
        name = Path(rel).name
        if name.startswith('_bootstrap'): return 'BOOT'
        if name.startswith('_background'): return 'BOOT'
        if name.startswith('_provision'): return 'PROV'
        return 'BOOT'
    if rel.startswith('home.admin/00') or rel.startswith('home.admin/99') or rel.startswith('home.admin/98'):
        return 'SSH'
    if rel.startswith('home.admin/setup.scripts/'):
        return 'SETUP'
    if rel.startswith('home.admin/config.scripts/'):
        if '/bonus.' in rel or rel.endswith('/internet.zerotier.sh') or rel.endswith('/internet.tailscale.sh'):
            return 'BONUS'
        return 'CONF'
    return 'CONF'

# Collect nodes and edges
nodes: dict[str, dict] = {}
edges: dict[tuple[str, str], dict] = {}

# Files to scan
scan_files = TOP_FILES + [p for p in SRC_DIR.rglob('*.sh')]

for path in scan_files:
    rel = path.relative_to(REPO_ROOT).as_posix()
    with open(path, 'r', encoding='utf-8', errors='ignore') as f:
        text = f.read()
    # ensure source node exists
    if rel not in nodes:
        nodes[rel] = {
            'id': rel,
            'label': rel,
            'href': rel,
            'group': categorize(rel)
        }
    # find references
    for pat in PATTERNS:
        for m in pat.finditer(text):
            raw = m.group(1)
            target = normalize_ref(raw, rel.rsplit('/', 1)[0] if '/' in rel else '')
            if not target:
                continue
            if target not in nodes:
                nodes[target] = {
                    'id': target,
                    'label': target,
                    'href': target,
                    'group': categorize(target)
                }
            edge_id = (rel, target)
            if edge_id not in edges:
                edges[edge_id] = {
                    'id': f"{rel}__{target}",
                    'source': rel,
                    'target': target,
                    'value': 0
                }
            # increment weight for each reference occurrence
            edges[edge_id]['value'] += 1

# Ensure output dir
OUT_DIR.mkdir(parents=True, exist_ok=True)

# Write graph.json
payload = {
    'nodes': list(nodes.values()),
    'edges': list(edges.values())
}
with open(OUT_FILE, 'w', encoding='utf-8') as f:
    json.dump(payload, f, indent=2)

print(f"Wrote {OUT_FILE} with {len(nodes)} nodes and {len(edges)} edges")
