#!/usr/bin/env python3
"""Record accepted clarification answers into spec.md.
Usage: record-answers.py SPEC  N1 'answer1'  N2 'answer2' ...
For each Qn: ledger Status -> Answered, marker [NEEDS CLARIFICATION: Qn — ...] -> **[Qn: answer]**,
append '- Q: <question> → A: <answer>' under ## Clarifications, bump counter."""
import re, sys, pathlib
spec = pathlib.Path(sys.argv[1]); s = spec.read_text()
pairs = list(zip(sys.argv[2::2], sys.argv[3::2]))
for n, a in pairs:
    n = int(n)
    m = re.search(rf'^\| {n} \| ([^|]+) \| ([^|]+) \| Open \|$', s, re.M)
    if not m: print(f"Q{n}: ledger row not found or already answered", file=sys.stderr); sys.exit(1)
    q = m.group(2).strip()
    s = s[:m.start()] + f"| {n} | {m.group(1).strip()} | {q} | Answered |" + s[m.end():]
    s, k = re.subn(rf'\[NEEDS CLARIFICATION: Q{n} — [^\]]*\]', f'**[Q{n}: {a}]**', s)
    if k == 0: print(f"Q{n}: warning, no marker replaced", file=sys.stderr)
    s = s.replace("- (пока нет принятых ответов)\n", "")
    # append under today's session (last line of Clarifications block before next '## ')
    idx = s.index("## Open Questions Ledger")
    s = s[:idx].rstrip("\n") + f"\n- Q{n}: {q} → A: {a}\n\n" + s[idx:]
cnt = len(re.findall(r'^- Q\d+: .* → A: ', s, re.M))
s = re.sub(r'\*\*Questions accepted so far\*\*: \d+ / 100', f'**Questions accepted so far**: {cnt} / 100', s)
spec.write_text(s); print(f"accepted so far: {cnt} / 100")
