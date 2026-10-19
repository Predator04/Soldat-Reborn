extends RefCounted
## Level title / author filter (#288) — the game-side copy of the master
## server's filter.go (keep the two word lists and rules in step). Words are
## matched after leetspeak / accent normalisation ("Sh1t", "f.u.c.k",
## "FUUUCK"); a STRONG word also matches inside a longer word ("bullshit"), a
## TOKEN word only as a whole word (+ -s / -es / -ed / -er), because those
## hide inside innocent ones ("cockpit", "grape", "title", "spicy").
## The server masks what it finds; the editor's Publish asks for another
## title instead (mask(title) != title).

const STRONG := [
	"fuck", "shit", "cunt", "nigger", "nigga", "faggot", "whore", "slut",
	"bitch", "porn", "hitler", "pussy", "asshole", "motherf", "dickhead",
]
const TOKENS := [
	"ass", "fag", "cum", "tit", "tits", "cock", "dick", "rape", "rapist",
	"retard", "spic", "chink", "kike", "wank", "twat", "nazi", "sex", "jizz",
	"kkk", "hoe", "penis", "vagina", "dildo", "anal", "bastard", "boob",
	"boobs", "cocks", "dicks",
]
const LEET := {
	"0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t", "8": "b",
	"9": "g", "@": "a", "$": "s", "!": "i", "|": "i", "+": "t", "€": "e",
	"¡": "i", "à": "a", "á": "a", "â": "a", "ä": "a", "å": "a", "è": "e",
	"é": "e", "ê": "e", "ë": "e", "ì": "i", "í": "i", "î": "i", "ï": "i",
	"ò": "o", "ó": "o", "ô": "o", "ö": "o", "ù": "u", "ú": "u", "û": "u",
	"ü": "u", "ñ": "n", "ç": "c", "ß": "s",
}
const SUFFIXES := ["", "s", "es", "ed", "er"]


static func norm(s: String) -> String:
	var out := ""
	for ch in s.to_lower():
		var c: String = LEET.get(ch, ch)
		if c >= "a" and c <= "z":
			out += c
	return out


# Letter runs of a word: "boob" -> [["b",1],["o",2],["b",1]].
static func _runs(w: String) -> Array:
	var out: Array = []
	for ch in w:
		if not out.is_empty() and out[-1][0] == ch:
			out[-1][1] += 1
		else:
			out.append([ch, 1])
	return out


# Match w at n[i:], every letter allowed to repeat; end index or -1.
static func _stretch_at(n: String, i: int, runs: Array) -> int:
	for r in runs:
		var c := 0
		while i < n.length() and n[i] == r[0]:
			c += 1
			i += 1
		if c < int(r[1]):
			return -1
	return i


static func word_is_bad(n: String) -> bool:
	if n == "":
		return false
	for w in STRONG:
		var rs := _runs(w)
		for i in n.length():
			if n[i] == w[0] and _stretch_at(n, i, rs) >= 0:
				return true
	for w in TOKENS:
		for suf in SUFFIXES:
			if _stretch_at(n, 0, _runs(w + suf)) == n.length():
				return true
	return false


static func _is_token_char(ch: String) -> bool:
	if LEET.has(ch):
		return true
	var u := ch.unicode_at(0)
	# Letters / digits: anything with a case, plus ASCII digits and CJK etc.
	return (ch.to_lower() != ch.to_upper()) or (u >= 48 and u <= 57) or u > 0x2E7F


## Offensive words in `s` replaced by asterisks (same rules as the server).
static func mask(s: String) -> String:
	var spans: Array = []   # [start, end) character offsets
	var i := 0
	while i < s.length():
		if not _is_token_char(s[i]):
			i += 1
			continue
		var j := i
		while j < s.length() and _is_token_char(s[j]):
			j += 1
		spans.append([i, j])
		i = j
	var bad: Array = []
	for sp in spans:
		bad.append(word_is_bad(norm(s.substr(sp[0], sp[1] - sp[0]))))
	# Spelled out: "f u c k" / "s.h.i.t" — runs of one-letter words joined.
	var k := 0
	while k < spans.size():
		if spans[k][1] - spans[k][0] != 1:
			k += 1
			continue
		var m := k
		var joined := ""
		while m < spans.size() and spans[m][1] - spans[m][0] == 1:
			joined += s[spans[m][0]]
			m += 1
		if m - k >= 3 and word_is_bad(norm(joined)):
			for x in range(k, m):
				bad[x] = true
		k = m
	var out := s
	for x in spans.size():
		if bad[x]:
			var sp: Array = spans[x]
			out = out.substr(0, sp[0]) + "*".repeat(sp[1] - sp[0]) + out.substr(sp[1])
	return out


static func is_clean(s: String) -> bool:
	return mask(s) == s
