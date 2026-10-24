#!/usr/bin/env python3
"""Builds Pinguo/Resources/dictionary.sqlite from CC-CEDICT and the complete HSK vocabulary list.

Usage: scripts/build_dictionary.py [--cedict cedict_ts.u8] [--hsk complete.min.json]
Missing inputs are downloaded into a temporary directory.
"""
import argparse
import io
import json
import re
import sqlite3
import tempfile
import urllib.request
import zipfile
from pathlib import Path

CEDICT_URL = "https://www.mdbg.net/chinese/export/cedict/cedict_1_0_ts_utf-8_mdbg.zip"
HSK_URL = "https://raw.githubusercontent.com/drkameleon/complete-hsk-vocabulary/main/complete.min.json"
OUTPUT = Path(__file__).resolve().parent.parent / "Pinguo" / "Resources" / "dictionary.sqlite"

CEDICT_LINE = re.compile(r"^(\S+) (\S+) \[([^\]]*)\] /(.*)/$")
TONE_MARKS = {
    "a": "āáǎà", "e": "ēéěè", "i": "īíǐì", "o": "ōóǒò", "u": "ūúǔù", "ü": "ǖǘǚǜ",
}
# CEDICT lists readings in no particular order; these are the readings learners meet most often.
PREFERRED_READINGS = {
    "了": "le5", "得": "de5", "着": "zhe5", "行": "xing2", "长": "chang2", "地": "de5", "的": "de5",
    "还": "hai2", "都": "dou1", "和": "he2", "为": "wei4", "只": "zhi3", "种": "zhong3", "重": "zhong4",
    "便": "bian4", "觉": "jue2", "好": "hao3", "少": "shao3", "发": "fa1", "干": "gan4", "要": "yao4",
    "看": "kan4", "当": "dang1", "教": "jiao1", "处": "chu4", "没": "mei2", "中": "zhong1", "会": "hui4",
    "说": "shuo1", "乐": "le4", "数": "shu4", "调": "diao4", "差": "cha4", "相": "xiang1", "应": "ying1",
    "将": "jiang1", "空": "kong1", "分": "fen1", "量": "liang4", "更": "geng4", "过": "guo4", "给": "gei3",
    "哪": "na3", "那": "na4", "什": "shen2", "么": "me5", "啊": "a5", "呢": "ne5", "吧": "ba5", "吗": "ma5",
    "似": "si4", "藏": "cang2", "朝": "chao2", "传": "chuan2", "弹": "tan2", "降": "jiang4", "露": "lu4",
    "难": "nan2", "片": "pian4", "曲": "qu3", "强": "qiang2", "散": "san4", "省": "sheng3", "盛": "sheng4",
    "似乎": "si4 hu1", "同": "tong2", "系": "xi4", "兴": "xing4", "血": "xue4", "一": "yi1", "与": "yu3",
    "载": "zai4", "转": "zhuan3", "作": "zuo4", "参": "can1", "大": "da4", "倒": "dao4", "累": "lei4",
    "哦": "o4", "仇": "chou2", "冲": "chong1", "担": "dan1", "缝": "feng2", "供": "gong1", "划": "hua2",
    "几": "ji3", "假": "jia3", "间": "jian1", "结": "jie2", "卡": "ka3", "看见": "kan4 jian4", "模": "mo2",
    "宁": "ning2", "铺": "pu1", "撒": "sa3", "上": "shang4", "术": "shu4", "吐": "tu3", "为了": "wei4 le5",
    "为什么": "wei4 shen2 me5", "咽": "yan4", "要是": "yao4 shi5", "钻": "zuan1", "得到": "de2 dao4",
}
POS_NAMES = {
    "n": "Noun", "v": "Verb", "a": "Adjective", "d": "Adverb", "m": "Numeral", "q": "Measure word",
    "r": "Pronoun", "p": "Preposition", "c": "Conjunction", "u": "Particle", "e": "Interjection",
    "o": "Onomatopoeia", "y": "Particle", "f": "Locative", "s": "Place word", "t": "Time word",
    "nr": "Name", "ns": "Place name", "nz": "Proper noun", "vn": "Verb", "an": "Adjective",
    "i": "Idiom", "l": "Phrase", "j": "Abbreviation", "b": "Attributive", "z": "Descriptive",
}


def syllable_with_tone_mark(syllable: str) -> str:
    syllable = syllable.replace("u:", "ü").replace("v", "ü").replace("U:", "Ü")
    if not syllable or not syllable[-1].isdigit():
        return syllable
    tone = int(syllable[-1])
    base = syllable[:-1]
    if tone not in (1, 2, 3, 4):
        return base
    lower = base.lower()
    if "a" in lower:
        target = lower.index("a")
    elif "e" in lower:
        target = lower.index("e")
    elif "ou" in lower:
        target = lower.index("o")
    else:
        vowel_positions = [i for i, ch in enumerate(lower) if ch in TONE_MARKS]
        if not vowel_positions:
            return base
        target = vowel_positions[-1]
    vowel = lower[target]
    marked = TONE_MARKS[vowel][tone - 1]
    if base[target].isupper():
        marked = marked.upper()
    return base[:target] + marked + base[target + 1:]


def pinyin_with_tone_marks(numbered: str) -> str:
    syllables = [syllable_with_tone_mark(s) for s in numbered.split()]
    joined = ""
    for syllable in syllables:
        if joined and syllable[:1].lower() in "aeoāáǎàēéěèōóǒò" and joined[-1].isalpha():
            joined += "'"
        joined += syllable
    return joined


def tones_of(numbered: str) -> str:
    tones = []
    for syllable in numbered.split():
        tones.append(syllable[-1] if syllable[-1:].isdigit() and syllable[-1] in "12345" else "0")
    return "".join(tones)


def is_proper_noun_entry(pinyin: str, definitions: list[str]) -> bool:
    return pinyin[:1].isupper() or all(d.startswith("surname ") for d in definitions)


def is_variant_entry(definitions: list[str]) -> bool:
    return all(re.match(r"^(old )?variant of|^see also|^see ", d) for d in definitions)


def load_inputs(args):
    workdir = Path(tempfile.mkdtemp())
    if args.cedict:
        cedict_text = Path(args.cedict).read_text(encoding="utf-8")
    else:
        archive = urllib.request.urlopen(CEDICT_URL).read()
        with zipfile.ZipFile(io.BytesIO(archive)) as zf:
            cedict_text = zf.read("cedict_ts.u8").decode("utf-8")
    if args.hsk:
        hsk = json.loads(Path(args.hsk).read_text(encoding="utf-8"))
    else:
        hsk = json.loads(urllib.request.urlopen(HSK_URL).read())
    del workdir
    return cedict_text, hsk


def hsk_index(hsk_entries):
    index = {}
    for entry in hsk_entries:
        levels = entry.get("l", [])
        old = sorted(int(l[1:]) for l in levels if l.startswith("o"))
        new = sorted(int(l[1:]) for l in levels if l.startswith("n"))
        level = old[0] if old else (new[0] if new else None)
        readings = [f["i"]["n"].replace(" ", " ").lower() for f in entry.get("f", [])]
        index[entry["s"]] = {
            "level": level,
            "frequency": entry.get("q"),
            "pos": [POS_NAMES[p] for p in entry.get("p", []) if p in POS_NAMES],
            "readings": readings,
        }
    return index


def choose_primary(simplified, candidates, hsk_info):
    preferred = PREFERRED_READINGS.get(simplified)
    def rank(candidate):
        pinyin, definitions = candidate["pinyin"], candidate["definitions"]
        matches_hsk = hsk_info is not None and pinyin.lower().replace("u:", "u:") in hsk_info["readings"]
        return (
            0 if preferred and candidate["pinyin"].lower() == preferred else 1,
            0 if matches_hsk else 1,
            1 if is_proper_noun_entry(pinyin, definitions) else 0,
            1 if is_variant_entry(definitions) else 0,
            candidate["order"],
        )
    return sorted(candidates, key=rank)[0]


def build(cedict_text, hsk):
    hsk_by_word = hsk_index(hsk)
    by_simplified = {}
    for order, line in enumerate(cedict_text.splitlines()):
        if line.startswith("#"):
            continue
        match = CEDICT_LINE.match(line)
        if not match:
            continue
        traditional, simplified, pinyin, definitions = match.groups()
        by_simplified.setdefault(simplified, []).append({
            "traditional": traditional,
            "pinyin": pinyin,
            "definitions": [d for d in definitions.split("/") if d],
            "order": order,
        })

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    if OUTPUT.exists():
        OUTPUT.unlink()
    db = sqlite3.connect(OUTPUT)
    db.executescript("""
        CREATE TABLE headword (
            simplified TEXT PRIMARY KEY,
            traditional TEXT NOT NULL,
            pinyin TEXT NOT NULL,
            tones TEXT NOT NULL,
            definitions TEXT NOT NULL,
            other_readings TEXT NOT NULL,
            part_of_speech TEXT,
            hsk_level INTEGER,
            frequency_rank INTEGER
        ) WITHOUT ROWID;
    """)
    rows = []
    for simplified, candidates in by_simplified.items():
        info = hsk_by_word.get(simplified)
        primary = choose_primary(simplified, candidates, info)
        others = [
            {"pinyin": pinyin_with_tone_marks(c["pinyin"]), "definitions": c["definitions"]}
            for c in candidates if c is not primary
        ]
        rows.append((
            simplified,
            primary["traditional"],
            pinyin_with_tone_marks(primary["pinyin"]),
            tones_of(primary["pinyin"]),
            json.dumps(primary["definitions"], ensure_ascii=False),
            json.dumps(others, ensure_ascii=False),
            ", ".join(info["pos"]) if info and info["pos"] else None,
            info["level"] if info else None,
            info["frequency"] if info else None,
        ))
    db.executemany("INSERT INTO headword VALUES (?,?,?,?,?,?,?,?,?)", rows)
    db.commit()
    db.execute("VACUUM")
    db.close()
    print(f"Wrote {len(rows)} headwords to {OUTPUT} ({OUTPUT.stat().st_size / 1_000_000:.1f} MB)")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--cedict")
    parser.add_argument("--hsk")
    args = parser.parse_args()
    build(*load_inputs(args))


if __name__ == "__main__":
    main()
