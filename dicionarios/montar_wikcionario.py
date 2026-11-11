"""Builds StarDict dictionaries (Portuguese definitions) from the kaikki.org
extraction of the Portuguese Wiktionary.

usage: build_ptwikt.py <raw-wiktextract-data.jsonl.gz> <out dir>
"""
import collections
import gzip
import html
import json
import os
import struct
import sys

# lang_code -> (folder, book name)
BOOKS = {
    "pt": ("wikt-pt-pt", "Português (Wikcionário)"),
    "en": ("wikt-en-pt", "Inglês → Português (Wikcionário)"),
    "es": ("wikt-es-pt", "Espanhol → Português (Wikcionário)"),
    "fr": ("wikt-fr-pt", "Francês → Português (Wikcionário)"),
    "it": ("wikt-it-pt", "Italiano → Português (Wikcionário)"),
    "de": ("wikt-de-pt", "Alemão → Português (Wikcionário)"),
    "la": ("wikt-la-pt", "Latim → Português (Wikcionário)"),
    "ja": ("wikt-ja-pt", "Japonês → Português (Wikcionário)"),
}

GENDER = {"masculine": "m.", "feminine": "f.", "neuter": "n.", "plural": "pl.", "singular": "sg."}


def entry_html(d):
    e = html.escape
    head = f"<b>{e(d.get('pos_title') or d.get('pos') or '')}</b>"
    tags = [GENDER[t] for t in d.get("tags", []) if t in GENDER]
    if tags:
        head += f" <i>{e(' '.join(tags))}</i>"
    ipa = next((s["ipa"] for s in d.get("sounds", []) if s.get("ipa") and "Brazil" in s.get("tags", [])), None) \
        or next((s["ipa"] for s in d.get("sounds", []) if s.get("ipa")), None)
    if ipa:
        head += f" <span>{e(ipa)}</span>"
    items = []
    for s in d.get("senses", []):
        g = "; ".join(x for x in s.get("glosses", []) if x)
        if not g:
            continue
        rt = s.get("raw_tags") or []
        li = (f"<i>({e(', '.join(rt))})</i> " if rt else "") + e(g)
        ex = [x.get("text") for x in s.get("examples", []) if x.get("text")][:1]
        if ex:
            li += f"<br><i>{e(ex[0])}</i>"
        items.append(f"<li>{li}</li>")
    if not items:
        return None
    out = head + "<ol>" + "".join(items) + "</ol>"
    et = [t for t in d.get("etymology_texts", []) if t]
    if et:
        out += f"<p><small>{e(' '.join(et))}</small></p>"
    return out


def stardict_key(w):
    # StarDict orders the index by g_ascii_strcasecmp, then by strcmp.
    b = w.encode("utf-8")
    return (bytes(c + 32 if 65 <= c <= 90 else c for c in b), b)


def write_book(folder, name, entries, lang):
    os.makedirs(folder, exist_ok=True)
    base = os.path.join(folder, os.path.basename(folder))
    words = sorted(entries, key=stardict_key)
    idx = bytearray()
    off = 0
    with open(base + ".dict", "wb") as dic:
        for w in words:
            data = "<hr>".join(entries[w]).encode("utf-8")
            dic.write(data)
            idx += w.encode("utf-8") + b"\0" + struct.pack(">II", off, len(data))
            off += len(data)
    with open(base + ".idx", "wb") as f:
        f.write(idx)
    with open(base + ".ifo", "w", encoding="utf-8") as f:
        f.write("StarDict's dict ifo file\nversion=2.4.2\n"
                f"wordcount={len(words)}\nidxfilesize={len(idx)}\n"
                f"bookname={name}\nsametypesequence=h\n"
                "description=Wikcionário em português (CC BY-SA), via kaikki.org/wiktextract.\n"
                f"lang={lang}-pt\n")
    return len(words)


def main(src, out):
    books = {k: collections.defaultdict(list) for k in BOOKS}
    with gzip.open(src, "rt", encoding="utf-8") as f:
        for line in f:
            try:
                d = json.loads(line)
            except ValueError:
                continue
            lc = d.get("lang_code")
            w = (d.get("word") or "").strip()
            if lc not in books or not w or "\n" in w:
                continue
            h = entry_html(d)
            if h:
                books[lc][w].append(h)
    for lc, (folder, name) in BOOKS.items():
        n = write_book(os.path.join(out, folder), name, books[lc], lc)
        print(f"{name}: {n} verbetes")


if __name__ == "__main__":
    main(*sys.argv[1:3])
