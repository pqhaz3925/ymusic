#!/usr/bin/env python3
"""trace-cpu.py <trace> — average %CPU per process from an Activity Monitor trace (skips first 3 s)."""
import subprocess, sys, re, collections
import xml.etree.ElementTree as ET
xml = subprocess.run(["xcrun","xctrace","export","--input",sys.argv[1],"--xpath",
    '/trace-toc/run[@number="1"]/data/table[@schema="sysmon-process"]'],capture_output=True,text=True).stdout
root = ET.fromstring(xml)
ids = {}
def resolve(el):
    if el is None: return None
    if 'ref' in el.attrib: return ids.get(el.attrib['ref'])
    if 'id' in el.attrib: ids[el.attrib['id']] = el
    return el
acc = collections.defaultdict(list)
for row in root.iter('row'):
    t = resolve(row.find('start-time')); p = resolve(row.find('process')); c = resolve(row.find('system-cpu-percent'))
    # register nested ids
    for el in row.iter():
        if 'id' in el.attrib: ids[el.attrib['id']] = el
    if t is None or p is None or c is None: continue
    try: ts = int(t.text)/1e9; cpu = float(c.text)
    except Exception: continue
    name = p.attrib.get('fmt','?').split(' (')[0]
    if ts >= 3: acc[name].append(cpu)
rows = sorted(((sum(v)/len(v), k, len(v)) for k,v in acc.items()), reverse=True)
want = sys.argv[2:] 
for avg,k,n in rows[:14]:
    print(f"{avg:6.1f}%  {k}  (n={n})")
