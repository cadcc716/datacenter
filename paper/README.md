# Typeset manuscript (Applied Energy layout)

`manuscript.pdf` is the English manuscript, typeset in the article layout of *Applied Energy* (Elsevier) after the
benchmark paper Zhang et al., Appl Energy 2026;425:128499: highlights, article info and keywords, abstract
(background → gap → method → case results → conclusion), boxed nomenclature, introduction with three themed
literature reviews, research gaps and numbered contributions, model sections with numbered propositions, case
analysis, sensitivity analysis, discussion, numbered conclusions, CRediT/declaration/acknowledgements, appendices,
data availability and references numbered in order of citation.

All 26 experiments are in the paper. Table 7 maps each experiment to its subsection, figures and tables, and Table C.1
lists the script and the result files behind it.

| Section | Content | Experiments |
|---|---|---|
| 1 Introduction | Background, data center DR, IES, recovery and coordination; gaps; four contributions | — |
| 2 System architecture | AIDC-IES (Fig. 1), recovery channel, lag-bounded backlog (Lemma 1), IES model, Jiangsu settlement | — |
| 3 Model and theory | Objective, indicators, strategies (Table 3), Proposition 1, Theorem 1, Proposition 2 | — |
| 4 Method | Framework (Fig. 2), DRO commitment (Proposition 3), capability region (Proposition 4), MPC, ADMM (Proposition 5), Algorithm 1, timing | 14 |
| 5.1 Case settings | Data, parameters, experiment map (Table 7) | — |
| 5.2 Mechanism and performance | Mechanism, case day, 52 days, sources of benefit | 1, 2, 4, 7, 11 |
| 5.3 Capacity, price, coordination | Reliable capacity, substitution, shadow prices, capability region, distributed coordination | 5, 12, 13, 25, 26 |
| 5.4 Day-ahead commitment | Pairing, risk-averse commitments, scenario generation and drift | 6, 15, 23 |
| 5.5 Sensitivity | Commitment/gap/margin, rebound and payment, realism and policy, tariffs and climates | 3, 8, 9, 10, 16, 17, 18 |
| 5.6 Validation and extensions | Job-level validation, overheads and capping, offshore wind, waste-heat recovery | 19, 20, 21, 22, 24 |
| Appendices A–C | Parameters with sources, proofs and numerical checks, supplementary results, reproducibility | 11 (Fig. B.1), 4 and 3 (Figs. C.1–C.2) |

## Build

Requires XeLaTeX (TeX Live 2023 with `extsizes`, `unicode-math`, `titlesec`, `caption`, `booktabs`, `makecell`,
`dblfloatfix`) and the fonts Charis SIL and STIX Two Math:

```bash
paper/build.sh          # -> paper/manuscript.pdf
```

The figures are the vector PDFs in `matlab/figures_en/`, drawn by `python3 tools/plot_results.py --en` and
`python3 tools/draw_diagrams.py --en` in the journal style of `tools/journal_style.py` (serif type, framed panels,
validated colour palette). Reference entries live in `references.tex`; `tools/order_refs.py` numbers them in the
order of first citation.

## Before submission

- Author names, affiliations, e-mail, CRediT roles and funding are placeholders in `manuscript.tex` and
  `sections/backmatter.tex`.
- The data-availability statement promises the code and data upon publication; add the repository link.
- Check the bibliographic details of the policy documents, company announcements and preprints against the
  publisher or official pages (see the note in `references.tex`).
