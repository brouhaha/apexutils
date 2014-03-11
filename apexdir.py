#!/usr/bin/python2

import sys

def hexdump(b):
    for i in range(0, len(b), 16):
        print "%02x:" % i,
        for j in range(0, 16):
            if i + j < len(b):
                print "%02x" % b[i+j],
        print

def invert_table(table):
    inverse_table = [ None ] * len(table)
    for i in range(len(table)):
        if (table[i] < 0) or (table[i] >= len(table)):
            raise Exception('Table element(s) out of range')
        if inverse_table[table[i]] is not None:
            raise Exception('Table elements not unique')
        inverse_table[table[i]] = i
    return inverse_table

def compose_table(table1, table2):
    if len(table1) != len(table2):
        raise Exception('Tables not same length')
    return [table2[table1[i]] for i in range(len(table1))]

# interleave tables

# DOS 3.3 uses 2:1 interleave in descending order
dos33_to_phys  = [ 0x00, 0x0d, 0x0b, 0x09, 0x07, 0x05, 0x03, 0x01,
                   0x0e, 0x0c, 0x0a, 0x08, 0x06, 0x04, 0x02, 0x0f ]

phys_to_dos33  = invert_table(dos33_to_phys)

# Apple Pascal uses 2:1 interleave in ascending order
pascal_to_phys = [ 0x00, 0x02, 0x04, 0x06, 0x08, 0x0a, 0x0c, 0x0e,
                   0x01, 0x03, 0x05, 0x07, 0x09, 0x0b, 0x0d, 0x0f ]

phys_to_pascal = invert_table(pascal_to_phys)

# CP/M uses 3:1 interleave in ascending order
cpm_to_phys    = [ 0x00, 0x03, 0x06, 0x09, 0x0c, 0x0f, 0x02, 0x05,
                   0x08, 0x0b, 0x0e, 0x01, 0x04, 0x07, 0x0a, 0x0d ]

phys_to_cpm = invert_table(cpm_to_phys)




if len(sys.argv) != 2:
    print >>sys.stderr, 'Usage: %s image.dsk' % sys.argv[0]
    sys.exit(1)

with open(sys.argv[1], 'rb') as f:
    image = f.read()

block_size = 256
block_count = 560
blocks_per_track = 16
files_per_dir = 48

if len(image) != block_size * block_count:
    print >>sys.stderr, 'wrong file size'
    sys.exit(2)

# Apex uses same interleave as Pascal
pascal_to_dos33 = compose_table(pascal_to_phys, phys_to_dos33)

def block_to_offset(b):
    return ((b//blocks_per_track) * blocks_per_track +
            pascal_to_dos33[b % blocks_per_track]) * block_size

blocks_str = [image[block_to_offset(b):block_to_offset(b)+block_size] for b in range(block_count)]
blocks = [[ord(image[block_to_offset(b) + i]) for i in range(block_size)] for b in range(block_count)]

raw_dir = blocks[9] + blocks[10] + blocks[11] + blocks[12]

def decode_date(v):
    day = v % 32
    month = (v//32) % 16
    year = 1976 + v//512
    return '%04d.%02d.%02d' % (year, month, day)

def munge_filename(f):
    f = f.lower()
    f = f.replace(' ', '')
    return f

dir = []
for i in range(files_per_dir):
    status = raw_dir[528+i]
    if status == 0:
       continue
    name = ''.join(chr(c) for c in raw_dir[i*11: i*11+8]) + '.' + ''.join(chr(c) for c in raw_dir[i*11+8: i*11+11])
    first_block = raw_dir[576+2*i] + 256 * raw_dir[576+2*i+1]
    last_block = raw_dir[672+2*i] + 256 * raw_dir[672+2*i+1]
    fdate = raw_dir[920+2*i] + 256 * raw_dir[920+2*i+1]
    dir.append((name, first_block, last_block - first_block + 1, decode_date(fdate)))

if False:
    dir = sorted(dir, key=lambda d: d[1])

print 'filename     start  size  date     '
print '------------ ----- ----- ----------'
for (name, first_block, size, date) in dir:
    print '%11s %5d %5d %s' % (name, first_block, size, date)

extract = True

bin_extensions = ('.bin', '.i2l', '.obj', '.sav', '.sys')
# .pdq .dat ?

if extract:
    for (name, first_block, size, date) in dir:
        name = munge_filename(name)
        print name

        textFile = not name.endswith(bin_extensions)
    
        with open(name, 'wb') as f:
            for b in range(first_block, first_block + size):
                bs = blocks_str[b]
                if textFile:
                    cz = bs.find(chr(0x1a))
                    if (cz >= 0):
                        f.write(bs[0:cz])
                        break
                f.write(bs)



# Apex disk blocks
# 0-8  boot
# 9-12 primary directory
# 13-16  backup directory
# 17-    file storage
# 17-25  resident code (RESCOD.SYS)
# max 48 files in directory
# dir:
#   $000-$20f     0- 527:  11-byte filename entries
#   $210-$23f   528- 575:  status - 0=null, <128 closed, >127 tentative
#   $240-$29f   576- 671:  first block #
#   $2a0-$2ff   672- 767:  last block #
#   $300-$349   768- 841:
#   $34a        842:      prdev
#   $34b-$34c   843- 844:  pmaxb
#   $34d-$357   845- 855:  prname
#   $358-$393   856- 915:  title
#   $394-$395   916- 917:  volume
#   $396-$397   918- 919:  dirdat
#   $398-$3f7   920-1015:  fdate
#   $3f8-$3ff  1016-1023:  flags
