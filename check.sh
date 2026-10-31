#!/usr/bin/env bash
# Workspace self-check for kg-learning. Run in the Codespace terminal:  bash check.sh
# Prints PASS/FAIL per item; paste the whole output to Claude if anything fails.

pass=0; fail=0
ok()   { echo "  PASS  $1"; pass=$((pass+1)); }
bad()  { echo "  FAIL  $1"; [ -n "$2" ] && echo "        → $2"; fail=$((fail+1)); }
FUSEKI=http://localhost:3030

echo "== Tools"
if python3 --version >/dev/null 2>&1; then ok "Python $(python3 --version 2>&1 | cut -d' ' -f2)"; else bad "Python missing" "Rebuild the container"; fi
for pkg in rdflib pyshacl owlready2; do
  v=$(python3 -c "import importlib.metadata as m; print(m.version('$pkg'))" 2>/dev/null)
  if [ -n "$v" ]; then ok "$pkg $v"; else bad "$pkg not installed" "pip install $pkg"; fi
done
jv=$(java -version 2>&1 | grep -m1 -oE 'version "[0-9]+' | grep -oE '[0-9]+$')
if [ -n "$jv" ] && [ "$jv" -ge 21 ]; then ok "Java $jv"; else bad "Java 21+ missing (found: ${jv:-none})" "Fuseki 6 and the reasoner need Java 21"; fi

echo "== Fuseki"
if [ -x ~/fuseki/fuseki-server ]; then ok "Fuseki installed in ~/fuseki"; else bad "Fuseki not installed" "See 'If something doesn't work' on the Notion setup page"; fi
if curl -fsS --max-time 5 "$FUSEKI/\$/ping" >/dev/null 2>&1; then
  ok "Fuseki server running on port 3030"
else
  bad "Fuseki not responding on port 3030" "Start it: mkdir -p .fuseki-db && ~/fuseki/fuseki-server --loc=.fuseki-db --update /kg"
fi

G='<urn:check:selftest>'
if curl -fsS --max-time 10 -X POST "$FUSEKI/kg/update" \
     --data-urlencode "update=INSERT DATA { GRAPH $G { <urn:check:s> <urn:check:p> \"ok\" } }" >/dev/null 2>&1; then
  ok "Dataset 'kg' accepts updates"
  n=$(curl -fsS --max-time 10 -G "$FUSEKI/kg/query" -H 'Accept: text/csv' \
       --data-urlencode "query=SELECT (COUNT(*) AS ?n) WHERE { GRAPH $G { ?s ?p ?o } }" 2>/dev/null | tail -1 | tr -d '\r')
  if [ "$n" = "1" ]; then ok "Dataset 'kg' answers SPARQL queries"; else bad "SPARQL query returned '$n' (expected 1)"; fi
  curl -fsS --max-time 10 -X POST "$FUSEKI/kg/update" --data-urlencode "update=DROP SILENT GRAPH $G" >/dev/null 2>&1
  total=$(curl -fsS --max-time 10 -G "$FUSEKI/kg/query" -H 'Accept: text/csv' \
       --data-urlencode "query=SELECT (COUNT(*) AS ?n) WHERE { { ?s ?p ?o } UNION { GRAPH ?g { ?s ?p ?o } } }" 2>/dev/null | tail -1 | tr -d '\r')
  echo "        (your data: ${total:-?} triples stored)"
else
  bad "Dataset 'kg' not reachable for updates" "Check Fuseki was started with --update and the name /kg"
fi
if [ -d .fuseki-db ]; then ok "Data folder .fuseki-db exists (your data survives restarts)"; else bad "No .fuseki-db folder" "Data is in memory only and will be lost on restart"; fi

echo "== Reasoner"
if [ -f reason.py ]; then
  ok "reason.py present"
  tmp=$(mktemp -d)
  python3 - "$tmp" <<'EOF' >/dev/null 2>&1
import sys
from owlready2 import get_ontology, Thing, ObjectProperty
onto = get_ontology("http://example.org/selftest.owl")
with onto:
    class Disease(Thing): pass
    class treats(ObjectProperty): pass
    class Medicine(Thing): equivalent_to = [Thing & treats.some(Disease)]
    class Aspirin(Thing): is_a = [treats.some(Disease)]
onto.save(file=sys.argv[1] + "/selftest.owl", format="rdfxml")
EOF
  out=$(python3 reason.py "$tmp/selftest.owl" 2>&1)
  if echo "$out" | grep -q "Aspirin  ⊑  Medicine"; then ok "HermiT reasoner works (inferred Aspirin ⊑ Medicine)"
  else bad "Reasoner did not produce the expected inference" "$(echo "$out" | tail -3 | tr '\n' ' ')"; fi
  rm -rf "$tmp"
else
  bad "reason.py not found in this folder" "Add it from the Notion setup page (File 2)"
fi

echo "== Repo hygiene"
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  ok "Git repository: $(git remote get-url origin 2>/dev/null | sed 's#.*github.com[:/]##')"
  if grep -qxF '.fuseki-db/' .gitignore 2>/dev/null; then ok ".fuseki-db/ is git-ignored"; else bad ".fuseki-db/ not in .gitignore" "echo '.fuseki-db/' >> .gitignore"; fi
  if [ -f .devcontainer/devcontainer.json ]; then ok ".devcontainer/devcontainer.json present"; else bad "devcontainer.json missing" "Add it from the Notion setup page (File 1)"; fi
  dirty=$(git status --porcelain | wc -l | tr -d ' ')
  [ "$dirty" = "0" ] && ok "All changes committed" || echo "  NOTE  $dirty uncommitted change(s) — commit + sync before stopping the Codespace"
else
  bad "Not inside the git repo" "cd /workspaces/<your-repo> and run again"
fi

echo
echo "Result: $pass passed, $fail failed"
[ "$fail" = "0" ] && echo "All good — you're ready for Day 1." || echo "Paste this whole output to Claude."
