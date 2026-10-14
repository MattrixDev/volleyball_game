#!/usr/bin/env python3
"""Erzeugt die Liga: teams/*.tres mit Trikotfarben und je 14 festen Spielern (PlayerData).

Jeder Spieler ist ein fester Charakter: gleicher Seed -> gleiche Namen, Groessen und Staerken.
Neu erzeugen:  python3 tools/make_teams.py
"""
import os
import random

OUT = os.path.join(os.path.dirname(__file__), "..", "teams")

# Staerke des Teams (Mittel der Stammspieler, 70 = normal) und Stil.
TEAMS = [
    dict(id="nordhafen", name="SV Nordhafen", short="SVN", tier=75, style="ausgeglichen",
         jersey=(0.14, 0.18, 0.31), panel=(0.9, 0.9, 0.88), number=(0.93, 0.93, 0.91), shorts=(0.14, 0.18, 0.31),
         socks=(0.9, 0.9, 0.88), shoes=(0.9, 0.9, 0.88), accent=(0.14, 0.18, 0.31), sole=(0.85, 0.85, 0.84),
         libero=(0.79, 0.64, 0.26), libero_panel=(0.14, 0.18, 0.31), libero_number=(0.14, 0.18, 0.31)),
    dict(id="eichenberg", name="TSV Eichenberg", short="TSV", tier=74, style="blockstark",
         jersey=(0.46, 0.16, 0.2), panel=(0.89, 0.85, 0.77), number=(0.93, 0.9, 0.84), shorts=(0.2, 0.15, 0.17),
         socks=(0.46, 0.16, 0.2), shoes=(0.2, 0.18, 0.19), accent=(0.46, 0.16, 0.2), sole=(0.82, 0.8, 0.76),
         libero=(0.84, 0.84, 0.81), libero_panel=(0.46, 0.16, 0.2), libero_number=(0.46, 0.16, 0.2)),
    dict(id="seewald", name="VC Seewald", short="VCS", tier=72, style="abwehrstark",
         jersey=(0.2, 0.36, 0.33), panel=(0.16, 0.18, 0.19), collar=(0.88, 0.88, 0.85), logo=(0.88, 0.88, 0.85),
         number=(0.93, 0.93, 0.9), shorts=(0.16, 0.18, 0.19), socks=(0.16, 0.18, 0.19), shoes=(0.88, 0.88, 0.85),
         accent=(0.2, 0.36, 0.33), sole=(0.84, 0.84, 0.82),
         libero=(0.85, 0.5, 0.28), libero_panel=(0.16, 0.18, 0.19), libero_number=(0.16, 0.18, 0.19)),
    dict(id="sturmhafen", name="VC Sturmhafen", short="VCS", tier=79, style="aufschlagstark",
         jersey=(0.08, 0.09, 0.1), panel=(0.86, 0.72, 0.2), number=(0.95, 0.82, 0.3), shorts=(0.08, 0.09, 0.1),
         socks=(0.08, 0.09, 0.1), shoes=(0.12, 0.12, 0.13), accent=(0.86, 0.72, 0.2), sole=(0.8, 0.8, 0.78),
         libero=(0.86, 0.72, 0.2), libero_panel=(0.08, 0.09, 0.1), libero_number=(0.08, 0.09, 0.1)),
    dict(id="bernsteinbucht", name="SG Bernsteinbucht", short="SGB", tier=77, style="schnell",
         jersey=(0.86, 0.47, 0.14), panel=(0.98, 0.96, 0.92), number=(0.98, 0.96, 0.92), shorts=(0.98, 0.96, 0.92),
         socks=(0.86, 0.47, 0.14), shoes=(0.95, 0.95, 0.93), accent=(0.86, 0.47, 0.14), sole=(0.85, 0.85, 0.84),
         libero=(0.2, 0.3, 0.45), libero_panel=(0.98, 0.96, 0.92), libero_number=(0.98, 0.96, 0.92)),
    dict(id="graufelden", name="TSV Graufelden", short="TSG", tier=70, style="blockstark",
         jersey=(0.42, 0.45, 0.48), panel=(0.75, 0.15, 0.17), number=(0.97, 0.97, 0.96), shorts=(0.2, 0.22, 0.24),
         socks=(0.42, 0.45, 0.48), shoes=(0.2, 0.22, 0.24), accent=(0.75, 0.15, 0.17), sole=(0.82, 0.82, 0.8),
         libero=(0.75, 0.15, 0.17), libero_panel=(0.2, 0.22, 0.24), libero_number=(0.97, 0.97, 0.96)),
    dict(id="morgental", name="USC Morgental", short="USC", tier=67, style="abwehrstark",
         jersey=(0.36, 0.56, 0.78), panel=(0.97, 0.97, 0.96), number=(0.97, 0.97, 0.96), shorts=(0.97, 0.97, 0.96),
         socks=(0.36, 0.56, 0.78), shoes=(0.97, 0.97, 0.96), accent=(0.36, 0.56, 0.78), sole=(0.86, 0.86, 0.85),
         libero=(0.17, 0.24, 0.37), libero_panel=(0.97, 0.97, 0.96), libero_number=(0.97, 0.97, 0.96)),
    dict(id="ostergrund", name="Blau-Weiß Ostergrund", short="BWO", tier=64, style="jung",
         jersey=(0.17, 0.32, 0.62), panel=(0.97, 0.97, 0.96), number=(0.97, 0.97, 0.96), shorts=(0.17, 0.32, 0.62),
         socks=(0.97, 0.97, 0.96), shoes=(0.97, 0.97, 0.96), accent=(0.17, 0.32, 0.62), sole=(0.86, 0.86, 0.85),
         libero=(0.93, 0.83, 0.25), libero_panel=(0.17, 0.32, 0.62), libero_number=(0.17, 0.32, 0.62)),
]

# Kader: die ersten sechs sind die Startsechs auf den Positionen 1 bis 6, dann der Libero,
# dann die Bank. Zuspieler und Diagonal stehen sich gegenueber.
SQUAD = ["S", "OH", "MB", "OP", "OH", "MB", "L", "S", "OH", "MB", "OP", "L", "OH", "OH"]

HEIGHT = {"S": (1.85, 1.98), "OH": (1.92, 2.03), "OP": (1.96, 2.09), "MB": (2.01, 2.13), "L": (1.78, 1.91)}
KEYS = ["jump", "power", "serve", "receive", "defense", "setting", "block", "speed"]
PROFILE = {
    "S": dict(jump=-4, power=-10, serve=0, receive=-6, defense=0, setting=12, block=-6, speed=2),
    "OH": dict(jump=2, power=4, serve=2, receive=4, defense=2, setting=-12, block=-2, speed=0),
    "OP": dict(jump=5, power=9, serve=4, receive=-15, defense=-4, setting=-12, block=2, speed=-1),
    "MB": dict(jump=4, power=2, serve=-3, receive=-25, defense=-12, setting=-15, block=10, speed=-2),
    "L": dict(jump=-30, power=-35, serve=-40, receive=12, defense=12, setting=-5, block=-40, speed=6),
}
STYLE = {
    "ausgeglichen": {},
    "blockstark": dict(block=5, jump=2),
    "abwehrstark": dict(receive=5, defense=5),
    "aufschlagstark": dict(serve=6, power=2),
    "schnell": dict(setting=4, speed=4),
    "jung": dict(speed=5, jump=3, receive=-3),
}
TRAITS = {
    "S": ["spielmacher", "flatter"],
    "OH": ["sprungwunder", "kraftpaket", "kanone", "flatter"],
    "OP": ["kraftpaket", "kanone", "sprungwunder", "linkshaender"],
    "MB": ["lange_arme", "sprungwunder", "blockleser"],
    "L": ["katze"],
}
FIRST = ["Jonas", "Felix", "Tobias", "Marten", "Ole", "Niklas", "Henrik", "Lasse", "Jannik", "Finn", "Paul",
         "Mats", "Lukas", "Moritz", "David", "Simon", "Jonathan", "Elias", "Max", "Tim", "Benno", "Carl",
         "Rafael", "Nils", "Malte", "Hannes", "Jakob", "Leon", "Emil", "Anton", "Theo", "Vincent", "Julian",
         "Fabian", "Philipp", "Matteo", "Luca", "Noah", "Milan", "Tomás", "Mikkel", "Arvid", "Kai", "Bastian",
         "Linus", "Erik", "Sören", "Janosch", "Aaron", "Konstantin", "Florian", "Dominik", "Adrian", "Levin",
         "Piet", "Bruno", "Joris", "Mika", "Tjark", "Kilian", "Yannick", "Samuel", "Oskar", "Daniel", "Ivo"]
LAST = ["Brandt", "Ahrens", "Lund", "Voss", "Petersen", "Wendt", "Sander", "Krüger", "Mohr", "Ostermann",
        "Rieck", "Lorenz", "Ebert", "Kern", "Schaaf", "Falk", "Roth", "Bender", "Hartung", "Vogler", "Keller",
        "Zander", "Lenz", "Gerber", "Brinkmann", "Haas", "Jansen", "Kühn", "Lindner", "Marquardt", "Neumeier",
        "Pohl", "Quast", "Reimers", "Schöning", "Thiele", "Ullrich", "Vahl", "Wiegand", "Zeller", "Albers",
        "Behrens", "Claasen", "Dreyer", "Engel", "Friese", "Gerdes", "Hollmann", "Ihlenfeld", "Jessen",
        "Kowalski", "Larsen", "Meinke", "Nowak", "Oltmanns", "Paulsen", "Rademacher", "Steffens", "Tamm",
        "Uhlig", "Vollmer", "Wolters", "Yilmaz", "Ziegler", "Andersen", "Böttcher", "Carstens", "Duran",
        "Eilers", "Feddersen", "Grote", "Hinrichs", "Iversen", "Jürgens", "Kasper", "Lohse", "Martens",
        "Nordmann", "Olsen", "Prange", "Rasmussen", "Seidel", "Timm", "Ulbrich", "Vester", "Westphal",
        "Abel", "Bauer", "Conrad", "Dietz", "Eckert", "Frost", "Gerlach", "Hesse", "Ilić", "Jovanović",
        "Kaminski", "Lange", "Mertens", "Nolte", "Otten", "Peters", "Reuter", "Stein", "Tewes", "Urban",
        "Varga", "Weiß", "Zimmer", "Asmussen", "Brodersen", "Christiansen", "Dahl", "Ehlers", "Fink"]


def col(c):
    return "Color(%g, %g, %g, 1)" % c


def clamp(v, lo, hi):
    return max(lo, min(hi, v))


def make_team(t, rng, used_names):
    players = []
    numbers = rng.sample(range(1, 21), len(SQUAD))
    for i, role in enumerate(SQUAD):
        starter = i < 7
        base = t["tier"] + (3 if starter else -4) + rng.gauss(0, 2.5)
        while True:
            fn, ln = rng.choice(FIRST), rng.choice(LAST)
            if (fn, ln) not in used_names and ln not in [p["last"] for p in players]:
                used_names.add((fn, ln))
                break
        lo, hi = HEIGHT[role]
        p = dict(first=fn, last=ln, role=role, number=numbers[i], height=round(rng.uniform(lo, hi), 2))
        for k in KEYS:
            v = base + PROFILE[role][k] + STYLE[t["style"]].get(k, 0) + rng.gauss(0, 4)
            p[k] = int(round(clamp(v, 25, 97)))
        # Groessere Spieler blocken etwas besser, kleinere sind schneller.
        p["block"] = int(clamp(p["block"] + round((p["height"] - 2.0) * 30), 25, 97))
        p["speed"] = int(clamp(p["speed"] - round((p["height"] - 1.95) * 25), 25, 97))
        traits = []
        r = rng.random()
        n = 2 if r < 0.1 else (1 if r < 0.5 else 0)
        pool = list(TRAITS[role])
        rng.shuffle(pool)
        traits = pool[:n]
        lefty = "linkshaender" in traits or (role != "L" and rng.random() < 0.08)
        if lefty and "linkshaender" not in traits:
            traits.append("linkshaender")
        p["traits"] = traits
        p["lefty"] = lefty
        p["skin"] = rng.randrange(5)
        p["hair"] = rng.randrange(6)
        p["id"] = "%s_%02d" % (t["id"], p["number"])
        players.append(p)
    return players


def write_team(t, players):
    lines = ['[gd_resource type="Resource" script_class="TeamStyle" load_steps=%d format=3]' % (len(players) + 3), "",
             '[ext_resource type="Script" path="res://scripts/team_style.gd" id="1"]',
             '[ext_resource type="Script" path="res://scripts/player_data.gd" id="2"]', ""]
    for i, p in enumerate(players):
        lines += ['[sub_resource type="Resource" id="p%d"]' % i, 'script = ExtResource("2")',
                  'id = "%s"' % p["id"], 'first_name = "%s"' % p["first"], 'last_name = "%s"' % p["last"],
                  "number = %d" % p["number"], 'role = "%s"' % p["role"], "height_m = %g" % p["height"]]
        lines += ["%s = %d" % (k, p[k]) for k in KEYS]
        lines += ["traits = PackedStringArray(%s)" % ", ".join('"%s"' % x for x in p["traits"]),
                  "left_handed = %s" % ("true" if p["lefty"] else "false"),
                  "skin = %d" % p["skin"], "hair = %d" % p["hair"], ""]
    lines += ["[resource]", 'script = ExtResource("1")', 'id = "%s"' % t["id"], 'name = "%s"' % t["name"],
              'short_name = "%s"' % t["short"], 'play_style = "%s"' % t["style"]]
    for k in ["jersey", "panel", "collar", "logo", "number", "shorts", "socks", "shoes", "accent", "sole"]:
        c = t.get(k, t["panel"] if k in ("collar", "logo") else None)
        lines.append("%s = %s" % (k, col(c)))
    lines += ["libero_jersey = %s" % col(t["libero"]), "libero_panel = %s" % col(t["libero_panel"]),
              "libero_number = %s" % col(t["libero_number"]),
              'players = Array[ExtResource("2")]([%s])' % ", ".join('SubResource("p%d")' % i for i in range(len(players))), ""]
    with open(os.path.join(OUT, t["id"] + ".tres"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines))


def main():
    rng = random.Random(20261014)
    used = set()
    for t in TEAMS:
        players = make_team(t, rng, used)
        write_team(t, players)
        print("%-22s %2d Spieler" % (t["name"], len(players)))


if __name__ == "__main__":
    main()
