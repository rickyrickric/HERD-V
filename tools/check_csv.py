import csv
from collections import defaultdict, Counter
from math import isnan

path = 'sample.csv'
numeric_cols = ['Age','Weight_kg','Milk_Yield','Fertility_Score','Rumination_Minutes_Per_Day','Ear_Temperature_C','Parasite_Load_Index','Fecal_Egg_Count','Respiration_Rate_BPM','Forage_Quality_Index','Movement_Score','Remaining_Months']

rows = []
with open(path, newline='', encoding='utf-8') as f:
    reader = csv.DictReader(f)
    headers = reader.fieldnames
    for r in reader:
        rows.append(r)

n = len(rows)
print(f'Rows: {n}')
print('Headers:', headers)

# ID duplicates
ids = [r.get('ID','') for r in rows]
dup = [k for k,v in Counter(ids).items() if v>1]
print('Duplicate IDs found:', dup)

# Missing counts per column
missing = defaultdict(int)
for r in rows:
    for h in headers:
        if r.get(h) is None or r.get(h).strip()=='':
            missing[h]+=1

print('\nMissing counts:')
for h in headers:
    print(f'  {h}: {missing[h]}')

# Numeric parsing and stats
parse_issues = defaultdict(list)
stats = {}
for col in numeric_cols:
    vals = []
    for i,r in enumerate(rows, start=1):
        s = r.get(col,'')
        s_stripped = s.strip() if s is not None else ''
        if s_stripped=='':
            # treat as missing
            continue
        try:
            v = float(s_stripped)
            if v!=v: # nan
                parse_issues[col].append((i,s))
            else:
                vals.append(v)
        except Exception as e:
            parse_issues[col].append((i,s))
    if vals:
        stats[col] = {'count': len(vals), 'min': min(vals), 'max': max(vals), 'mean': sum(vals)/len(vals)}
    else:
        stats[col] = {'count': 0}

print('\nNumeric column stats:')
for col,st in stats.items():
    print(f'  {col}: {st}')

print('\nParsing issues (showing up to 10 per column):')
for col,issues in parse_issues.items():
    if issues:
        print(f'  {col}: {len(issues)} issues')
        for i,s in issues[:10]:
            print(f'    row {i}: "{s}"')

# Check categorical columns unique values
cat_cols = [h for h in headers if h not in numeric_cols and h!='ID']
print('\nCategorical unique counts (sample):')
for col in cat_cols:
    vals = [r.get(col,'').strip() for r in rows if r.get(col) is not None and r.get(col).strip()!='']
    c = Counter(vals)
    print(f'  {col}: {len(c)} uniques; top 5: {c.most_common(5)}')

# Quick sanity checks
print('\nSanity checks:')
# Milk yield reasonable range
milk_vals = [float(r['Milk_Yield']) for r in rows if r.get('Milk_Yield') and r.get('Milk_Yield').strip()!='']
if milk_vals:
    print('  Milk_Yield mean {:.2f}, min {:.2f}, max {:.2f}'.format(sum(milk_vals)/len(milk_vals), min(milk_vals), max(milk_vals)))

# Any negative numbers
negatives = []
for col in numeric_cols:
    for i,r in enumerate(rows, start=1):
        s = r.get(col,'').strip() if r.get(col) else ''
        if s=='':
            continue
        try:
            v = float(s)
            if v < 0:
                negatives.append((col,i,v))
        except:
            pass
print('  Negative numeric entries:', negatives[:10])

print('\nDone.')
