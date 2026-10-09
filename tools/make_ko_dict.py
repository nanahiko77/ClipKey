#!/usr/bin/env python3
"""한국어 학습용 어휘 목록(tools/ko_vocab.tsv)으로 추천 단어 사전(Keyboard/ko_dict.txt)을 만든다.

- 동형어 번호(가다01)를 떼고 같은 단어는 하나로 합친다. 순위는 가장 높은 것을 쓴다.
- 동사·형용사는 자주 쓰는 활용형을 미리 만들어 같이 넣는다 (갔어, 가까운, 추워요 ...).
- 출력 한 줄 = 한 단어와 그 활용형들(띄어쓰기로 구분), 자주 쓰는 순서.

실행: python3 tools/make_ko_dict.py
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "tools" / "ko_vocab.tsv"
OUT = ROOT / "Keyboard" / "ko_dict.txt"

JUNG = list("ㅏㅐㅑㅒㅓㅔㅕㅖㅗㅘㅙㅚㅛㅜㅝㅞㅟㅠㅡㅢㅣ")
JONG = [""] + list("ㄱㄲㄳㄴㄵㄶㄷㄹㄺㄻㄼㄽㄾㄿㅀㅁㅂㅄㅅㅆㅇㅈㅊㅋㅌㅍㅎ")


def split(ch):
    v = ord(ch) - 0xAC00
    if not 0 <= v < 11172:
        return None
    return v // 588, JUNG[(v % 588) // 28], JONG[v % 28]


def join(cho, jung, jong=""):
    return chr(0xAC00 + (cho * 21 + JUNG.index(jung)) * 28 + JONG.index(jong))


def set_last(s, jung=None, jong=None):
    """마지막 글자의 모음이나 받침을 바꾼다"""
    c, v, j = split(s[-1])
    return s[:-1] + join(c, jung if jung is not None else v, jong if jong is not None else j)


def last(s):
    return split(s[-1])


BRIGHT = {"ㅏ", "ㅗ", "ㅑ", "ㅘ"}

# 받침 ㅂ인데 규칙 활용하는 말 (입어, 잡아, 좁아 ...)
B_REGULAR = set("입잡씹뽑업접집좁꼽")
# ㄷ 불규칙 (들어, 걸어, 물어, 깨달아)
D_IRREGULAR_LAST = set("듣걷묻싣붇긷")
D_IRREGULAR_STEM = ("깨닫", "일컫")
# ㅅ 불규칙 (나아, 지어, 이어 ...)
S_IRREGULAR_LAST = set("낫짓붓잇긋젓")
# 르로 끝나지만 ㅡ만 빠지는 말 (따라, 치러)
REU_REGULAR = ("따르", "치르")


class Stem:
    def __init__(self, word, pos):
        self.word = word
        self.s = word[:-1]           # 어간
        self.pos = pos               # "v" 동사, "a" 형용사
        c, v, j = last(self.s)
        self.v, self.j = v, j
        s = self.s
        if j == "ㅂ" and s[-1] not in B_REGULAR:
            self.kind = "b"
        elif s[-1] in D_IRREGULAR_LAST or s.endswith(D_IRREGULAR_STEM):
            self.kind = "d"
        elif j == "ㅅ" and s[-1] in S_IRREGULAR_LAST:
            self.kind = "s"
        elif j == "ㅎ" and pos == "a" and not s.endswith("좋"):
            self.kind = "h"
        elif j == "ㄹ":
            self.kind = "l"
        elif j:
            self.kind = "c"          # 규칙 자음 어간
        else:
            self.kind = "vowel"

    # 아/어 붙은 꼴: 가, 먹어, 해, 추워, 들어, 몰라, 나아, 그래
    def a(self):
        s, v, j, k = self.s, self.v, self.j, self.kind
        bright = v in BRIGHT
        if s == "푸르":
            return "푸르러"
        if k == "vowel":
            if s.endswith("하"):
                return s[:-1] + "해"
            if v == "ㅡ":
                prev = split(s[-2]) if len(s) >= 2 else None
                if s.endswith("르") and prev and not prev[2] and not s.endswith(REU_REGULAR):
                    pb = prev[1] in BRIGHT
                    return s[:-2] + join(prev[0], prev[1], "ㄹ") + ("라" if pb else "러")
                pb = prev is not None and prev[1] in BRIGHT
                return set_last(s, jung="ㅏ" if pb else "ㅓ")
            if v in ("ㅏ", "ㅓ", "ㅐ", "ㅔ", "ㅕ", "ㅑ"):
                return s
            if v == "ㅗ":
                return set_last(s, jung="ㅘ")
            if v == "ㅜ":
                return set_last(s, jung="ㅝ")
            if v == "ㅚ":
                return set_last(s, jung="ㅙ")
            if v == "ㅣ":
                return set_last(s, jung="ㅕ")
            return s + "어"
        if k == "b":
            base = set_last(s, jong="")
            if s.endswith(("돕", "곱")):
                return base + "와"
            return base + "워"
        if k == "d":
            return set_last(s, jong="ㄹ") + ("아" if bright else "어")
        if k == "s":
            return set_last(s, jong="") + ("아" if bright else "어")
        if k == "h":
            return set_last(s, jung="ㅒ" if v in ("ㅑ", "ㅕ") else "ㅐ", jong="")
        return s + ("아" if bright else "어")

    # 으가 붙는 자리의 어간: 먹으, 가, 살, 추우, 들으, 나으, 그러
    def eu(self, drop_l=False):
        s, k = self.s, self.kind
        if k == "vowel":
            return s
        if k == "l":
            return set_last(s, jong="") if drop_l else s
        if k == "b":
            return set_last(s, jong="") + "우"
        if k == "d":
            return set_last(s, jong="ㄹ") + "으"
        if k == "s":
            return set_last(s, jong="") + "으"
        if k == "h":
            return set_last(s, jong="")
        return s + "으"

    def with_jong(self, jong):
        """먹은/간/산/추운, 먹을/갈/살"""
        return set_last(self.eu(drop_l=True), jong=jong) if self.kind == "l" and jong != "ㄹ" \
            else set_last(self.eu(), jong=jong)

    def past(self):
        return set_last(self.a(), jong="ㅆ")

    def formal(self):
        if self.kind in ("vowel", "l"):
            return set_last(self.eu(drop_l=True), jong="ㅂ") + "니다"
        return self.s + "습니다"

    def forms(self):
        s, a, p = self.s, self.a(), self.past()
        is_verb = self.pos == "v" or s.endswith(("있", "없"))
        neun = (self.eu(drop_l=True) if self.kind == "l" else s) + "는"
        n = self.with_jong("ㄴ")
        l = self.with_jong("ㄹ")
        out = [self.word, a + "요", s + "고"]
        out += [neun] if is_verb else [n]
        out += [p + "어요", a, p + "다", p + "어",
                self.eu() + "면", a + "서", s + "지", self.formal(), s + "지만"]
        if is_verb:
            if not s.endswith(("있", "없")):
                out += [n]           # 있은, 없은은 거의 쓰지 않는다
            out += [l, self.eu(drop_l=True) + "세요", neun + "데", l + "게", l + "까"]
        else:
            out += [n + "데", l]
            if s.endswith("하"):
                out += [s + "세요"]     # 안녕하세요, 건강하세요, 행복하세요
        out += [self.eu(drop_l=True) + "니까", s + "게", s + "기", a + "도", a + "야", p + "는데"]
        # 말할 때 자주 쓰는 끝 (오타 교정이 바른 말을 고치지 않도록 넣어 둔다)
        short = self.eu(drop_l=True) if self.kind == "l" else s     # 사네, 기네
        out += [s + "잖아", p + "잖아", s + "겠다", s + "겠어", s + "겠어요", short + "네", short + "네요",
                s + "거든", p + "거든", p + "었어", p + "었다", p + "지만"]
        if is_verb:
            out += [self.eu() + "려고", s + "자", neun + "구나", s + "죠"]
        else:
            out += [s + "구나", s + "죠"]
        return out


# 학습용 목록에 없지만 자주 쓰는 말 (단어, 품사, 순위)
EXTRA = [
    ("희한하다", "형", 4000),
    ("어이없다", "형", 3000),
    ("수고하셨습니다", "고", 2000),
    ("고생하셨습니다", "고", 2500),
    ("감사드립니다", "고", 2500),
    ("잘부탁드립니다", "고", 4000),
]
TYPOS = ROOT / "tools" / "ko_typos.tsv"

SPECIAL = {
    "아니다": "아니다 아니에요 아니고 아닌 아니야 아니었어요 아니었다 아니면 아니라 아닙니다 아니지만 아닌데 아니니까 아니어도",
}


def main():
    entries = {}   # 단어 -> [순위, 품사들, 처음 나온 순서]
    order = 0
    for line in SRC.read_text(encoding="utf-8").splitlines()[1:]:
        cols = line.split("\t")
        if len(cols) < 5 or not cols[1]:
            continue
        rank = int(cols[0]) if cols[0].isdigit() else 99999
        word = re.sub(r"\d+$", "", cols[1].strip())
        pos = cols[2].strip()
        # 도쿄(동경) -> 도쿄, 동경
        names = [w for w in re.split(r"[()]", word) if w] if "(" in word else [word]
        for w in names:
            e = entries.setdefault(w, [rank, set(), order])
            e[0] = min(e[0], rank)
            e[1].add(pos)
            order += 1

    for w, pos, rank in EXTRA:
        e = entries.setdefault(w, [rank, set(), order])
        e[0] = min(e[0], rank)
        e[1].add(pos)
        order += 1

    lines = []
    for w, (rank, poss, o) in sorted(entries.items(), key=lambda kv: (kv[1][0], kv[1][2])):
        if w in SPECIAL:
            forms = SPECIAL[w].split()
        elif w.endswith("다") and poss & {"동", "형", "보"} and len(w) >= 2 and split(w[-2]):
            pos = "v" if poss & {"동", "보"} else "a"
            forms = Stem(w, pos).forms()
        else:
            forms = [w]
        seen, uniq = set(), []
        for f in forms:
            if f not in seen:
                seen.add(f)
                uniq.append(f)
        lines.append(" ".join(uniq))

    # 자주 틀리는 말: "!틀린꼴 바른꼴" 줄로 맨 뒤에 붙인다 (바른꼴에는 띄어쓰기가 있을 수 있다)
    typos, seen_typo = [], set()
    for line in TYPOS.read_text(encoding="utf-8").splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        wrong, right = line.split("\t")
        if wrong == right or wrong in seen_typo:
            continue
        seen_typo.add(wrong)
        typos.append(f"!{wrong} {right}")
    lines += typos

    header = "# ClipKey 한국어 추천 사전. tools/make_ko_dict.py로 만든다. 한 줄 = 한 단어와 활용형, 자주 쓰는 순서. !줄은 자주 틀리는 말\n"
    OUT.write_text(header + "\n".join(lines) + "\n", encoding="utf-8")
    total = sum(len(l.split()) for l in lines)
    print(f"{len(lines)} words, {total} forms -> {OUT.relative_to(ROOT)} ({OUT.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    sys.exit(main())
