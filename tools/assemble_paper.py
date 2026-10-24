#!/usr/bin/env python3
"""Rebuild docs/论文主要思路.md from the four drafts in docs/修订稿草稿/.

Edit the drafts, then run `python3 tools/assemble_paper.py`. The title block and figures 0a/0b at the top of the
assembled document (everything before "## 摘要") are kept; then come the abstract (end of draft 2), sections 1-5
(draft 1), sections 6-7 (draft 2), section 8 with references and appendix A (draft 3) and appendix B (draft 4).
"""
import os

DOCS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "docs")
DRAFTS = os.path.join(DOCS, "修订稿草稿")
OUT = os.path.join(DOCS, "论文主要思路.md")


def read(name):
    with open(os.path.join(DRAFTS, name), encoding="utf-8") as f:
        return f.read().strip()


def strip_rule(text):
    text = text.rstrip()
    while text.endswith("---"):
        text = text[:-3].rstrip()
    return text


p1, p2, p3, p4 = (read(n) for n in ["1_第1-5节.md", "2_第6-7节与摘要.md", "3_第8节_参考文献_附录A.md", "4_附录B_修改对照.md"])
i = p2.index("## 摘要")
sec67, abstract = strip_rule(p2[:i]), p2[i:].strip()
with open(OUT, encoding="utf-8") as f:
    cur = f.read()
header = strip_rule(cur[:cur.index("## 摘要")])
doc = "\n\n---\n\n".join([header, abstract, strip_rule(p1), sec67, strip_rule(p3), p4]) + "\n"
with open(OUT, "w", encoding="utf-8") as f:
    f.write(doc)
print(f"wrote {OUT} ({len(doc)} characters)")
