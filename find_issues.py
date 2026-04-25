with open('lib/views/navipg.dart', 'rb') as f:
    raw = f.read()

# Find all occurrences of backtick-r-n
search = b'`r`n'
idx = 0
positions = []
while True:
    pos = raw.find(search, idx)
    if pos == -1:
        break
    positions.append(pos)
    idx = pos + 1

print(f'Found {len(positions)} occurrences of backtick-r-n')
for p in positions:
    print(f'  At byte {p}: ...{raw[max(0,p-30):p+30]}...')
