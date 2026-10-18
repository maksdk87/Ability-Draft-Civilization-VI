#!/usr/bin/env python3
"""Ability Draft (Civ VI) - generator of the per-slot transport files.

The lobby host writes every slot's pick numbers as bits into the game settings:
POCD_S<slot>_<cat>_B<bit> = 1 (cat: L leader, C civilization, D district, B building,
I improvement, U unit). For every such bit the .modinfo has a ConfigurationValueMatches
criterion and a tiny UpdateDatabase action (Data/S/S<ss>_<cat><bit>.sql) that inserts one
row into POCD_SlotBits; Data/POCD_Apply.sql then turns the bits into traits.

This script regenerates only the generated parts and leaves everything hand-written alone:
  * Data/S/*.sql (old files there are removed),
  * in the .modinfo: the C_POCD_S* criteria, the A_POCD_S* actions and the Data/S/ file list,
  * the POCD_Index block in Data/POCD_Schema.sql and Config/POCD_Config.sql,
  * POCD_Cats (bits per menu) and MaxSlots in Config/POCD_Config.sql.

The pick index (number of each leader/civilization/item, 1-based, sorted by type name inside
each menu) is read from Data/POCD_Schema.sql, or rebuilt from a configuration database:
  build_mod.py <mod folder>                          # keep the index, regenerate the rest
  build_mod.py <mod folder> --pool-db DebugConfiguration.sqlite [--domain Players:Expansion2_Players]
Options: --slots 14 (players with a draft), --gamecore Expansion2 (added to every criterion;
'' for none), --check (only report whether anything would change).

Checked 18.10.2026: on the 0.1.1 folder with --gamecore '' it reproduces v27.5 byte for byte;
--pool-db on a configuration database without other mods gives the current index (77 L, 50 C,
16 D, 16 B, 23 I, 58 U). With other mods loaded (BBG Expanded) PlayerItems also holds their
items and non-unique ones (UNIT_GREAT_DIPLOMAT...) - filter before using such a pool.
"""
import argparse, glob, os, re, sqlite3, sys

CATS = ['L', 'C', 'D', 'B', 'I', 'U']
ITEM_PREFIX = {'D': 'DISTRICT_', 'B': 'BUILDING_', 'I': 'IMPROVEMENT_', 'U': 'UNIT_'}
IDX_ROW = re.compile(r"^\('([LCDBIU])', (\d+), '([A-Za-z0-9_]+)'\)[,;]$")
IDX_HEAD = 'INSERT OR REPLACE INTO POCD_Index (Cat, Idx, Entity) VALUES\n'


def read(p):
    with open(p, encoding='utf-8', newline='') as f:
        return f.read()


def write(p, s, check, changes):
    old = read(p) if os.path.exists(p) else None
    if old == s:
        return
    changes.append(p)
    if not check:
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, 'w', encoding='utf-8', newline='') as f:
            f.write(s)


def index_from_sql(path):
    idx = {c: {} for c in CATS}
    s = read(path)
    a = s.index(IDX_HEAD) + len(IDX_HEAD)
    for line in s[a:].split('\n'):
        m = IDX_ROW.match(line)
        if not m:
            raise SystemExit('unexpected line in the POCD_Index block of %s: %r' % (path, line))
        idx[m.group(1)][int(m.group(2))] = m.group(3)
        if line.endswith(';'):
            break
    out = {}
    for c in CATS:
        n = len(idx[c])
        if sorted(idx[c]) != list(range(1, n + 1)):
            raise SystemExit('index %s is not 1..%d' % (c, n))
        out[c] = [idx[c][i] for i in range(1, n + 1)]
    return out


def index_from_db(db, domain):
    g = sqlite3.connect('file:%s?mode=ro' % db, uri=True)
    q = lambda s, *a: [r[0] for r in g.execute(s, a)]
    out = {
        'L': sorted(set(q('SELECT LeaderType FROM Players WHERE Domain = ?', domain))),
        'C': sorted(set(q('SELECT CivilizationType FROM Players WHERE Domain = ?', domain))),
    }
    items = set(q('SELECT Type FROM PlayerItems WHERE Domain = ?', domain))
    for c, pre in ITEM_PREFIX.items():
        out[c] = sorted(t for t in items if t.startswith(pre))
    return out


def index_block(index):
    rows = ["('%s', %d, '%s')" % (c, i + 1, e) for c in CATS for i, e in enumerate(index[c])]
    return IDX_HEAD + ',\n'.join(rows) + ';\n'


def replace_index(s, index, path):
    a = s.index(IDX_HEAD)
    b = s.index(';\n', a) + 2
    return s[:a] + index_block(index) + s[b:]


def gen_slots(bits, slots):
    for s in range(slots):
        for c in CATS:
            for b in range(bits[c]):
                yield s, c, b


def criterion(s, c, b, gamecore):
    x = 'POCD_S%d_%s_B%d' % (s, c, b)
    t = ('\t\t<Criteria id="C_%s">\n'
         '\t\t\t<ConfigurationValueMatches>\n'
         '\t\t\t\t<Group>Game</Group>\n'
         '\t\t\t\t<ConfigurationId>%s</ConfigurationId>\n'
         '\t\t\t\t<Value>1</Value>\n'
         '\t\t\t</ConfigurationValueMatches>\n') % (x, x)
    if gamecore:
        t += '\t\t\t<GameCoreInUse>%s</GameCoreInUse>\n' % gamecore
    return t + '\t\t</Criteria>\n'


def slot_file(s, c, b):
    return 'Data/S/S%02d_%s%d.sql' % (s, c, b)


def action(s, c, b):
    x = 'POCD_S%d_%s_B%d' % (s, c, b)
    return ('\t\t<UpdateDatabase id="A_%s" criteria="C_%s">\n'
            '\t\t\t<Properties>\n'
            '\t\t\t\t<LoadOrder>900100</LoadOrder>\n'
            '\t\t\t</Properties>\n'
            '\t\t\t<File>%s</File>\n'
            '\t\t</UpdateDatabase>\n') % (x, x, slot_file(s, c, b))


def strip_blocks(s, start_re, end_tag):
    """remove every generated block; return text and the position of the first one (or None)"""
    first = None
    while True:
        m = re.search(start_re, s)
        if not m:
            return s, first
        a = s.rfind('\n', 0, m.start()) + 1
        b = s.index(end_tag, m.end()) + len(end_tag)
        b = s.index('\n', b) + 1
        if first is None or a < first:
            first = a
        s = s[:a] + s[b:]


def build_modinfo(s, bits, slots, gamecore):
    keys = list(gen_slots(bits, slots))
    s, at = strip_blocks(s, r'<Criteria id="C_POCD_S\d+_', '</Criteria>')
    if at is None:
        at = s.index('\t</ActionCriteria>')
    s = s[:at] + ''.join(criterion(*k, gamecore) for k in keys) + s[at:]
    s, at = strip_blocks(s, r'<UpdateDatabase id="A_POCD_S\d+_', '</UpdateDatabase>')
    if at is None:
        m = re.search(r'<UpdateDatabase id="POCD_SCHEMA"', s)
        b = s.index('</UpdateDatabase>', m.end())
        at = s.index('\n', b) + 1
    s = s[:at] + ''.join(action(*k) for k in keys) + s[at:]
    s = re.sub(r'(?m)^\t\t<File>Data/S/[^<]*</File>\n', '', s)
    at = s.index('\t</Files>')
    s = s[:at] + ''.join('\t\t<File>%s</File>\n' % slot_file(*k) for k in keys) + s[at:]
    return s


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('mod')
    ap.add_argument('--slots', type=int, default=14)
    ap.add_argument('--gamecore', default='Expansion2')
    ap.add_argument('--pool-db')
    ap.add_argument('--domain', default='Players:Expansion2_Players')
    ap.add_argument('--check', action='store_true')
    a = ap.parse_args()
    mod = a.mod
    schema = os.path.join(mod, 'Data', 'POCD_Schema.sql')
    config = os.path.join(mod, 'Config', 'POCD_Config.sql')
    infos = glob.glob(os.path.join(mod, '*.modinfo'))
    if len(infos) != 1:
        raise SystemExit('expected one .modinfo in %s' % mod)
    index = index_from_db(a.pool_db, a.domain) if a.pool_db else index_from_sql(schema)
    bits = {c: max(1, len(index[c]).bit_length()) for c in CATS}
    changes = []

    write(schema, replace_index(read(schema), index, schema), a.check, changes)
    cs = replace_index(read(config), index, config)
    cs = re.sub(r"(INSERT OR REPLACE INTO POCD_Cats \(Cat, Bits\) VALUES\n)[^\n]*\n",
                lambda m: m.group(1) + ','.join("('%s', %d)" % (c, bits[c]) for c in CATS) + ';\n', cs)
    cs = re.sub(r"(VALUES \('MaxSlots', )\d+(\);)", lambda m: '%s%d%s' % (m.group(1), a.slots, m.group(2)), cs)
    write(config, cs, a.check, changes)

    keep = set()
    for s, c, b in gen_slots(bits, a.slots):
        p = os.path.join(mod, *slot_file(s, c, b).split('/'))
        keep.add(os.path.normpath(p))
        write(p, '-- POCD_S%d_%s_B%d\nINSERT OR IGNORE INTO POCD_SlotBits (Slot, Cat, Bit) VALUES (%d, \'%s\', %d);\n'
              % (s, c, b, s, c, b), a.check, changes)
    for p in glob.glob(os.path.join(mod, 'Data', 'S', '*')):
        if os.path.normpath(p) not in keep:
            changes.append('remove ' + p)
            if not a.check:
                os.remove(p)

    write(infos[0], build_modinfo(read(infos[0]), bits, a.slots, a.gamecore), a.check, changes)

    print('pool:', ' '.join('%s %d (%d bits)' % (c, len(index[c]), bits[c]) for c in CATS))
    print('slots %d, actions %d, gamecore %r' % (a.slots, sum(bits.values()) * a.slots, a.gamecore))
    print(('would change' if a.check else 'changed'), len(changes), 'file(s)')
    for p in changes[:20]:
        print('  ' + p)
    return 0


if __name__ == '__main__':
    sys.exit(main())
