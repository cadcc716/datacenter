#!/bin/sh
# Build the manuscript: XeLaTeX, references renumbered in citation order, two more passes for cross-references.
set -e
cd "$(dirname "$0")"
python3 tools/order_refs.py
xelatex -interaction=nonstopmode -halt-on-error manuscript.tex > build.log 2>&1 || { tail -40 build.log; exit 1; }
python3 tools/order_refs.py
xelatex -interaction=nonstopmode -halt-on-error manuscript.tex >> build.log 2>&1 || { tail -40 build.log; exit 1; }
xelatex -interaction=nonstopmode -halt-on-error manuscript.tex >> build.log 2>&1 || { tail -40 build.log; exit 1; }
grep -E "Warning: (Reference|Citation)|undefined" manuscript.log | sort -u | head -20 || true
echo "built manuscript.pdf ($(pdfinfo manuscript.pdf 2>/dev/null | grep Pages))"
