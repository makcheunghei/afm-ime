#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# Windows 現代速成(ChtQuick SDC/SPD/mschxudp)系統詞庫 → Data/quick.json
#
# 只讀開啟系統來源檔(唯讀),不執行任何 DLL/EXE/原提取器。解析邏輯直接複用已驗證的
# quickime/windows-reference/*/decode_modern_quick.py(decode_spd/decode_sdc/decode_ext),
# 不 import 該 ignored 目錄作 runtime 依賴;純標準庫即可跑。
#
# 運行: python3 -B scripts/build_quick.py [--source DIR] [--cin FILE] [--output FILE]
#
# 編譯規則(固定,不更改;與主代理定稿一致):
#   candidates(默認): 取 Main SDC 中 length==1 的詞條,按 code 分組,raw_score 降序、word_id 作 tie;
#     排除 Unicode Extension A(U+3400..U+4DBF)的 base entries,再附加 ChtQuickExt 中 record_kind ∈ {4,5,6}
#     的記錄(按 record_index 次序),去重。
#   fullCandidates(完整字集): 先保持 candidates 前綴,再附所有 base entries(按 score,補回 ExtA),
#     再附 Ext 所有 record_kind(原次序),最後補舊 CIN 中未出現的 (code, word) pair(按 CIN 行次序),去重。
#   associations(聯想): 對每個 SDC 詞(len>=2)在每個 cut 拆成 prefix→continuation,
#     raw_score 降序、word_id 作 tie,continuation 去重。非舊二元模型。
#   roots: 速成字母根,固定表 a-y + z。
#
# 驗證:寫出前完整驗證(default `aa` 完全等於實機 18 字;你/晶/香/港/好/暑 六組聯想與
# decode-report references 相同),不符即 exit error,不落地。寫出採 temp + os.replace 原子替換。
import argparse
import hashlib
import json
import os
import struct
import sys
import tempfile
from collections import defaultdict
from pathlib import Path

SOURCE_FILES = ("ChtQuick.lex", "ChtQuick.spd", "ChtQuickExt.lex")
DEFAULT_SOURCE = ("quickime/native",)  # 先找這個,再找 quickime/windows-reference/*/modern-system
DEFAULT_CIN = "quickime/microsoft-quick.cin"
DEFAULT_OUTPUT = "Data/quick.json"

# 速成字母根(a-y 日月…卜,z=Z)
ROOTS = dict(zip("abcdefghijklmnopqrstuvwxyz",
                 "日月金木水火土竹戈十大中一弓人心手口尸廿山女田難卜Z"))

# 寫出前硬性比對(來源:decode-report.json 的實機驗證)
EXPECTED_DEFAULT_AA = "昌晶暑間暗曙昍暙闍閶閽闇晿暏彞龧𣊫𣊭"
EXPECTED_ASSOC = {
    "你": ["們", "我", "老", "等", "死我活", "推我讓"],
    "晶": ["片", "瑩剔透", "瑩", "體", "亮", "狀體", "粒"],
    "香": ["港", "水", "煙", "蕉", "味", "腸", "菸", "包", "菇"],
    "港": ["務局", "口", "都", "澳", "警", "市", "警所", "幣", "務"],
    "好": ["像", "處", "幾", "奇", "手", "轉", "評", "不容易", "看"],
    "暑": ["假", "期", "氣", "熱", "氣逼人"],
}
EXT_RECORD_KINDS_DEFAULT = (4, 5, 6)


def need(condition, message):
    if not condition:
        raise ValueError(message)


def u32(data, offset):
    need(0 <= offset <= len(data) - 4, "DWORD outside file")
    return struct.unpack_from("<I", data, offset)[0]


# --- 以下 decode_* 與 quickime/windows-reference/2026-10-14/decode_modern_quick.py 一致 ---
def decode_spd(path):
    data = path.read_bytes()
    need(data[:4] == b"SPD " and u32(data, 4) == len(data), "SPD header")
    count = u32(data, 12)
    end = 16 + count * 32
    need(0 < count < 65536 and end <= len(data), "SPD key bounds")
    keys = []
    for i in range(count):
        raw = data[16 + i * 32:48 + i * 32]
        key = raw.decode("utf-16le").rstrip("\0")
        need(key and len(key) <= 16 and "\0" not in key, "SPD key string")
        keys.append(key.lower())
    need(len(set(keys)) == len(keys), "Duplicate SPD keys")
    need(data[end:end + 4] == b"TRIE", "SPD trie boundary")
    return keys


def decode_sdc(path, keys):
    data = path.read_bytes()
    need(data[:4] == b"SDC " and u32(data, 4) == len(data), "SDC header")
    max_length = u32(data, 28)
    need(0 < max_length <= 32, "SDC word length")
    ends = struct.unpack_from("<%dI" % max_length, data, 48)
    need(all(a <= b for a, b in zip((0,) + ends[:-1], ends)), "SDC length boundaries")
    count = ends[-1]
    need(count > 0 and 48 + 4 * max_length <= len(data), "SDC word count")
    index_start = 48 + 4 * max_length
    word_start = index_start + count * 4
    need(word_start <= len(data), "SDC index bounds")
    order = struct.unpack_from("<%dI" % count, data, index_start)
    need(set(order) == set(range(count)), "SDC index must be a permutation")
    spans = []
    previous = 0
    cursor = word_start
    for length, end in enumerate(ends, 1):
        spans.append((previous, end, length, cursor))
        cursor += (end - previous) * length * 2
        previous = end
    code_start = cursor
    score_start = code_start + cursor - word_start
    trie_start = score_start + count * 4
    need(trie_start <= len(data) and data[trie_start:trie_start + 4] == b"TRIE", "SDC sections/trie boundary")
    rows = []
    for lo, hi, length, start in spans:
        for word_id in range(lo, hi):
            offset = start + (word_id - lo) * length * 2
            word = data[offset:offset + length * 2].decode("utf-16le", errors="strict")
            need("\0" not in word, "SDC null inside word")
            code_offset = code_start + offset - word_start
            code_ids = struct.unpack_from("<%dH" % length, data, code_offset)
            need(all(1 <= c <= len(keys) for c in code_ids), "SDC key outside SPD")
            rows.append(dict(word_id=word_id, word=word, length=length,
                             codes=[keys[c - 1] for c in code_ids],
                             raw_score=u32(data, score_start + word_id * 4)))
    return rows, dict(words=count, max_length=max_length, keys=len(keys))


def decode_ext(path):
    data = path.read_bytes()
    need(data[:8] == b"mschxudp", "Ext signature")
    table, records, end, count = struct.unpack_from("<4I", data, 12)
    need(end == len(data) and table >= 32 and table + count * 4 == records, "Ext header bounds")
    offsets = struct.unpack_from("<%dI" % count, data, table)
    need(offsets[0] == 0 and all(a < b for a, b in zip(offsets, offsets[1:])), "Ext record offsets")
    rows = []
    for i, relative in enumerate(offsets):
        start = records + relative
        finish = records + offsets[i + 1] if i + 1 < count else end
        need(records <= start < finish <= len(data) and finish - start >= 12, "Ext record bounds")
        record = data[start:finish]
        marker, key_offset, word_offset, kind = struct.unpack_from("<4H", record)
        need(marker == 8 and key_offset == 8 and key_offset < word_offset < len(record), "Ext record layout")
        key_bytes, word_bytes = record[key_offset:word_offset], record[word_offset:]
        need(len(key_bytes) % 2 == 0 and len(word_bytes) % 2 == 0, "Ext UTF16 alignment")
        need(key_bytes[-2:] == b"\0\0" and word_bytes[-2:] == b"\0\0", "Ext terminators")
        code = key_bytes[:-2].decode("utf-16le", errors="strict")
        word = word_bytes[:-2].decode("utf-16le", errors="strict")
        need(code and word and "\0" not in code + word, "Ext strings")
        rows.append(dict(record_index=i, code=code.lower(), word=word, record_kind=kind))
    return rows


# --- 來源 / CIN 讀取 ---
def has_source_files(directory):
    return all((directory / name).is_file() for name in SOURCE_FILES)


def locate_source(repo_root):
    native = repo_root / DEFAULT_SOURCE[0]
    if has_source_files(native):
        return native
    reference = repo_root / "quickime" / "windows-reference"
    found = sorted(p for p in reference.glob("*/modern-system") if has_source_files(p)) if reference.is_dir() else []
    return found[-1] if found else None


def decode_cin(path):
    """回傳 (code→[word...] 按 CIN 行次序且 pair 去重, 總 pair 數)。

    chardef 區以 ``line.partition(' ')`` 分開 code 與後方 text——word 本身字元原樣保留
    (例如 ``za`` 嘅 U+3000 全形空格;用 split() 會將佢當空白丢掉)。chardef 區內只跳過
    ``#``/``%`` 開頭嘅 comment/指令行;code 或 word 為空則不收。
    """
    by_code = defaultdict(list)
    seen = set()
    inside = False
    with path.open(encoding="utf-8") as handle:
        for line in handle:
            text = line.rstrip("\r\n")
            if text == "%chardef begin":
                inside = True
                continue
            if text == "%chardef end":
                break
            if not inside or not text or text[0] in "#%":
                continue
            code, separator, word = text.partition(" ")
            if not separator or not code or not word:
                continue
            pair = (code, word)
            if pair in seen:
                continue
            seen.add(pair)
            by_code[code].append(word)
    return by_code, len(seen)


def is_extension_a(word):
    return any(0x3400 <= ord(ch) <= 0x4DBF for ch in word)


def sha256_of(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


# --- 建表 ---
def build(source_dir, cin_path):
    keys = decode_spd(source_dir / "ChtQuick.spd")
    rows, _ = decode_sdc(source_dir / "ChtQuick.lex", keys)
    ext = decode_ext(source_dir / "ChtQuickExt.lex")

    base_by_code = defaultdict(list)   # code → length==1 base rows(已排序)
    for row in rows:
        if row["length"] == 1:
            base_by_code[row["codes"][0]].append(row)
    for bucket in base_by_code.values():
        bucket.sort(key=lambda r: (-r["raw_score"], r["word_id"]))

    ext_by_code = defaultdict(list)    # code → ext rows(record_index 次序)
    for row in ext:
        ext_by_code[row["code"]].append(row)

    cin_by_code, cin_pairs = ({}, 0)
    if cin_path is not None:
        cin_by_code, cin_pairs = decode_cin(cin_path)

    codes = sorted(set(base_by_code) | set(ext_by_code) | set(cin_by_code))

    candidates = {}
    full_candidates = {}
    for code in codes:
        base = base_by_code.get(code, ())
        extra = ext_by_code.get(code, ())

        seen = set()
        default = []
        for row in base:
            if is_extension_a(row["word"]) or row["word"] in seen:
                continue
            seen.add(row["word"])
            default.append(row["word"])
        for row in extra:
            if row["record_kind"] in EXT_RECORD_KINDS_DEFAULT and row["word"] not in seen:
                seen.add(row["word"])
                default.append(row["word"])
        candidates[code] = default

        seen = set()
        full = []
        for word in default:
            if word not in seen:
                seen.add(word)
                full.append(word)
        for row in base:
            if row["word"] not in seen:
                seen.add(row["word"])
                full.append(row["word"])
        for row in extra:
            if row["word"] not in seen:
                seen.add(row["word"])
                full.append(row["word"])
        for word in cin_by_code.get(code, ()):
            if word not in seen:
                seen.add(word)
                full.append(word)
        full_candidates[code] = full

    associations = build_associations(rows)
    return candidates, full_candidates, associations, cin_pairs, len(ext)


def build_associations(rows):
    completions = defaultdict(list)
    for row in rows:
        word = row["word"]
        if row["length"] < 2:
            continue
        for cut in range(1, len(word)):
            completions[word[:cut]].append(
                (row["raw_score"], row["word_id"], word[cut:]))
    associations = {}
    for prefix in sorted(completions):
        ordered = sorted(completions[prefix], key=lambda item: (-item[0], item[1]))
        seen = set()
        kept = []
        for _score, _word_id, continuation in ordered:
            if continuation not in seen:
                seen.add(continuation)
                kept.append(continuation)
        associations[prefix] = kept
    return associations


# --- 驗證 ---
def validate(candidates, associations):
    actual_aa = candidates["aa"]
    need("".join(actual_aa) == EXPECTED_DEFAULT_AA,
         "default aa 不符:\n  期待 %s\n  實得 %s" % (EXPECTED_DEFAULT_AA, "".join(actual_aa)))
    for prefix, reference in EXPECTED_ASSOC.items():
        actual = associations.get(prefix, [])
        need(actual[:len(reference)] == reference,
             "聯想樣本 %s 不符:\n  期待 %s\n  實得 %s" % (prefix, reference, actual[:len(reference)]))
    need(candidates and associations, "輸出空表")


def main(argv=None):
    repo_root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description="Build Data/quick.json from Windows modern Quick system dictionaries.")
    parser.add_argument("--source", type=Path, default=None,
                        help="包含 %s 的目錄(預設自動搜尋)" % "/".join(SOURCE_FILES))
    parser.add_argument("--cin", type=Path, default=None,
                        help="舊 CIN 補充檔(預設 %s;缺失則不用)" % DEFAULT_CIN)
    parser.add_argument("--output", type=Path, default=None,
                        help="輸出 JSON(預設 %s)" % DEFAULT_OUTPUT)
    args = parser.parse_args(argv)

    source_dir = args.source if args.source is not None else locate_source(repo_root)
    if source_dir is None or not has_source_files(source_dir):
        print("找不到來源目錄(需含 %s);可用 --source 指定。" % ", ".join(SOURCE_FILES), file=sys.stderr)
        return 2
    source_dir = source_dir.resolve()

    cin_arg = args.cin if args.cin is not None else (repo_root / DEFAULT_CIN)
    cin_path = None
    cin_note = None
    if cin_arg is not None and Path(cin_arg).is_file():
        cin_path = Path(cin_arg).resolve()
    else:
        cin_note = "CIN 缺失,未附加 CIN pair"

    output = (args.output if args.output is not None else (repo_root / DEFAULT_OUTPUT))
    output = Path(output).resolve()
    need(output != source_dir, "輸出不可覆蓋來源目錄")
    if cin_path is not None:
        need(output != cin_path, "輸出不可覆蓋 CIN")

    try:
        candidates, full_candidates, associations, cin_pairs, ext_records = build(source_dir, cin_path)
        validate(candidates, associations)
    except ValueError as error:
        print("驗證失敗: %s" % error, file=sys.stderr)
        return 1

    source_files = [dict(name=name, bytes=(source_dir / name).stat().st_size,
                         sha256=sha256_of(source_dir / name)) for name in SOURCE_FILES]
    try:
        dir_label = str(source_dir.relative_to(repo_root))
    except ValueError:
        dir_label = str(source_dir)

    document = {
        "version": 1,
        "candidates": candidates,
        "fullCandidates": full_candidates,
        "associations": associations,
        "roots": ROOTS,
        "metadata": {
            "generator": "scripts/build_quick.py",
            "schema_version": 1,
            "source": {"format": "Windows modern Quick (SDC/SPD/mschxudp)",
                       "directory": dir_label, "files": source_files},
            "cin": ({"path": str(cin_path), "used": True, "sha256": sha256_of(cin_path),
                     "pairs": cin_pairs} if cin_path is not None
                    else {"path": str(cin_arg), "used": False, "note": cin_note}),
            "policy": {
                "default": "Main SDC length==1 per code, raw_score desc / word_id tie; "
                           "base entries in Unicode Extension A (U+3400..U+4DBF) excluded; "
                           "ChtQuickExt record_kind in {4,5,6} appended by record_index; deduped.",
                "full": "Default list first, then all base entries by score, then all Ext records "
                        "(any record_kind) in record order, then CIN pairs absent above in CIN line order; deduped.",
                "associations": "Per SDC word (length>=2) split at each cut into prefix→continuation; "
                                "raw_score desc / word_id tie; continuations deduped; not the old bigram model.",
                "roots": "Quick letter roots, a-y fixed table plus z=Z.",
            },
            "counts": {
                "codes": len(candidates),
                "candidate_entries": sum(len(v) for v in candidates.values()),
                "full_candidate_entries": sum(len(v) for v in full_candidates.values()),
                "extension_records": ext_records,
                "association_prefixes": len(associations),
                "association_entries": sum(len(v) for v in associations.values()),
                "cin_pairs": cin_pairs if cin_path is not None else 0,
            },
            "coverage": {
                "sampled": True,
                "verified_on_device": [
                    "default code 'aa' == %s (18 chars)" % EXPECTED_DEFAULT_AA,
                    "associations for 你/晶/香/港/好/暑 match decode-report references",
                ],
                "note": "Default policy verified on real device for sampled code 'aa' only; "
                        "full-code consistency is NOT asserted.",
            },
        },
    }

    payload = json.dumps(document, ensure_ascii=False, separators=(",", ":")) + "\n"

    output.parent.mkdir(parents=True, exist_ok=True)
    handle, temp_path = tempfile.mkstemp(dir=str(output.parent), prefix=".quick.json.", suffix=".tmp")
    try:
        with os.fdopen(handle, "w", encoding="utf-8") as stream:
            stream.write(payload)
        os.replace(temp_path, output)
    except BaseException:
        if os.path.exists(temp_path):
            os.unlink(temp_path)
        raise

    print(json.dumps({
        "output": str(output),
        "bytes": os.path.getsize(output),
        "codes": len(candidates),
        "candidate_entries": sum(len(v) for v in candidates.values()),
        "full_candidate_entries": sum(len(v) for v in full_candidates.values()),
        "association_prefixes": len(associations),
        "association_entries": sum(len(v) for v in associations.values()),
        "cin_pairs": cin_pairs if cin_path is not None else 0,
    }, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
