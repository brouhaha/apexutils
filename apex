#!/usr/bin/env python3
# Program to list directory or extract files from an image of an
# APEX disk

# Copyright 2014, 2016 Eric Smith <spacewar@gmail.com>
# All rights reserved.

#    This program is free software: you can redistribute it and/or
#    modify it under the terms of version 3 of the GNU General Public
#    License as published by the Free Software Foundation.

#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
#    General Public License for more details.

#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see
#    <http://www.gnu.org/licenses/>.


import argparse
import datetime
import fnmatch
import io
from collections import namedtuple
import os
import sys
import time
from zipfile import ZipFile, ZipInfo

def hexdump(b):
    for i in range(0, len(b), 16):
        print("%02x:" % i, end = '')
        for j in range(0, 16):
            if i + j < len(b):
                print("%02x" % b[i+j], end = '')
        print()


class Apex:
    
    DirEntry = namedtuple('DirEntry', ['status',
                                       'filename',
                                       'first_block',
                                       'size_blocks',
                                       'date'])

    def __init__(self, image,
                 update = False,
                 backup_dir = False,
                 include_tentative = False,
                 include_replaced = False):
        if isinstance(image, str):
            if update:
                self.imagef = open(image, 'r+b')
            else:
                self.imagef = open(image, 'rb')
        image = self.imagef.read()
        self.dirty = False

        self.block_size = 256

        # for now, only handles 16-sector Apple Disk II images:
        self.block_count = 560
        self.blocks_per_track = 16
        self.files_per_dir = 48

        if len(image) != self.block_size * self.block_count:
            raise Exception('wrong file size')

        # DOS 3.3 uses 2:1 interleave in descending order
        self.dos33_to_phys = [0x00, 0x0d, 0x0b, 0x09,
                              0x07, 0x05, 0x03, 0x01,
                              0x0e, 0x0c, 0x0a, 0x08,
                              0x06, 0x04, 0x02, 0x0f]
        self.phys_to_dos33 = self.invert_table(self.dos33_to_phys)
        
        # Apple ProDOS and Apple Pascal uses 2:1 interleave in ascending order
        self.prodos_to_phys = [0x00, 0x02, 0x04, 0x06,
                               0x08, 0x0a, 0x0c, 0x0e,
                               0x01, 0x03, 0x05, 0x07,
                               0x09, 0x0b, 0x0d, 0x0f]
        self.phys_to_prodos = self.invert_table(self.prodos_to_phys)

        # CP/M uses 3:1 interleave in ascending order
        self.cpm_to_phys = [0x00, 0x03, 0x06, 0x09,
                            0x0c, 0x0f, 0x02, 0x05,
                            0x08, 0x0b, 0x0e, 0x01,
                            0x04, 0x07, 0x0a, 0x0d]
        self.phys_to_cpm = self.invert_table(self.cpm_to_phys)

        self.prodos_to_dos33 = self.compose_table(self.prodos_to_phys,
                                                  self.phys_to_dos33)

        self.blocks = [image[self.block_to_offset(b):self.block_to_offset(b)+self.block_size] for b in range(self.block_count)]

        self.parse_directory(backup_dir = backup_dir,
                             include_tentative = include_tentative,
                             include_replaced  = include_replaced)


    def flush(self):
        if not self.dirty:
            return

        image = bytearray(self.block_size * self.block_count)
        for block_num in range(self.block_count):
            offset = self.block_to_offset(block_num)
            image[offset:offset+self.block_size] = self.blocks[block_num]

        self.imagef.seek(0)
        self.imagef.write(image)

        self.dirty = False


    def close(self):
        self.flush()
        self.imagef.close()


    @staticmethod
    def invert_table(table):
        inverse_table = [ None ] * len(table)
        for i in range(len(table)):
            if (table[i] < 0) or (table[i] >= len(table)):
                raise Exception('Table element(s) out of range')
            if inverse_table[table[i]] is not None:
                raise Exception('Table elements not unique')
            inverse_table[table[i]] = i
        return inverse_table

    @staticmethod
    def compose_table(table1, table2):
        if len(table1) != len(table2):
            raise Exception('Tables not same length')
        return [table2[table1[i]] for i in range(len(table1))]

    def block_to_offset(self, b):
        return ((b//self.blocks_per_track) * self.blocks_per_track +
                self.prodos_to_dos33[b % self.blocks_per_track]) * self.block_size

    @staticmethod
    def decode_date(v):
        day = v % 32
        month = (v//32) % 16
        year = 1976 + v//512
        try:
            return datetime.datetime(year, month, day, 12, 0, 0)
        except ValueError:
            print('warning: bad date %d: year %d, month %d, day %d' % (v, year, month, day))
            return None

    @staticmethod
    def munge_filename(f):
        f = f.lower()
        f = f.replace(' ', '')
        return f


    # Apex disk blocks
    # 0-8  boot
    # 9-12 primary directory
    # 13-16  backup directory
    # 17-    file storage
    # 17-25  resident code (RESCOD.SYS)
    # max 48 files in directory
    # dir:
    #   $000-$20f     0- 527:  11-byte filename entries
    #   $210-$23f   528- 575:  status - 0=null, 1=valid, 254=replace, 255=tentative
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
    def parse_directory(self,
                        pattern = None,
                        backup_dir = False,
                        include_tentative = False,
                        include_replaced = False):
        if backup_dir:
            raw_dir = self.blocks[13] + self.blocks[14] + self.blocks[15] + self.blocks[16]
        else:
            raw_dir = self.blocks[9] + self.blocks[10] + self.blocks[11] + self.blocks[12]

        self.dir = []
        for i in range(self.files_per_dir):
            status = raw_dir[528+i]
            name = ''.join(chr(c) for c in raw_dir[i*11: i*11+8]) + '.' + ''.join(chr(c) for c in raw_dir[i*11+8: i*11+11])
            if status == 0:
                continue
            if status not in [1, 254, 255]:
                print('file %s has unexpected status %d', (name, status))
                continue
            if status == 254 and not include_replaced:
                continue
            if status == 255 and not include_tentative:
                continue
            first_block = raw_dir[576+2*i] + 256 * raw_dir[576+2*i+1]
            last_block = raw_dir[672+2*i] + 256 * raw_dir[672+2*i+1]
            fdate = raw_dir[920+2*i] + 256 * raw_dir[920+2*i+1]
            self.dir.append(self.DirEntry(status, name, first_block, last_block - first_block + 1, self.decode_date(fdate)))


    @staticmethod
    def match_filename(filename, patterns):
        if patterns is None or len(patterns) == 0:
            return True
        for pattern in patterns:
            if fnmatch.fnmatch(filename, pattern):
                return True
        return False
        
    def list_directory(self, f, patterns = None, sorted = False):
        if sorted:
            dir = sorted(self.dir, key=lambda d: d.filename)
        else:
            dir = self.dir

        print('filename     s start  size  date     ', file = f)
        print('------------ - ----- ----- ----------', file = f)
        for entry in dir:
            filename = self.munge_filename(entry.filename)
            if not self.match_filename(filename, patterns):
                continue
            print('%11s %c %5d %5d %s' % (entry.filename,
                                          { 1: ' ', 254: 'r', 255: 't' }[entry.status],
                                          entry.first_block,
                                          entry.size_blocks,
                                          entry.date), file = f)
        return True

    bin_extensions = ('.bin', '.i2l', '.obj', '.sav', '.sys')
    # .pdq .dat ?

    def extract_files(self, patterns = None, destdir = None, destzip = None, verbose = False, text_only = False, text_conv = False):
        if destzip is not None:
            destzip = ZipFile(destzip, mode='w')
        if destdir is not None:
            if not os.path.isdir(destdir):
                os.mkdir(destdir)
        for entry in self.dir:
            filename = self.munge_filename(entry.filename)

            if not self.match_filename(filename, patterns):
                continue

            textFile = not filename.endswith(self.bin_extensions)
            if text_only and not textFile:
                continue

            if entry.status == 254:
                filename += '.replaced'
            elif entry.status == 255:
                filename += '.tentative'

            if verbose:
                print('extracting %s' % filename)

            data = bytearray()
            for b in range(entry.first_block, entry.first_block + entry.size_blocks):
                data += self.blocks[b]
            if textFile and text_conv:
                cz = data.find(0x1a)
                if (cz >= 0):
                    data = data[:cz]
            if destzip is not None:
                if entry.date is None:
                    destzip.writestr(filename, data)
                else:
                    info = ZipInfo(filename, date_time = (entry.date.year,
                                                          entry.date.month,
                                                          entry.date.day,
                                                          entry.date.hour,
                                                          entry.date.minute,
                                                          entry.date.second))
                    destzip.writestr(info, data)
            else:
                if args.destdir is not None:
                    path = os.path.join(destdir, filename)
                else:
                    path = filename
                with open(path, 'wb') as f:
                    f.write(data)
                if entry.date is not None:
                    timestamp = time.mktime(entry.date.timetuple())
                    os.utime(path, (timestamp, timestamp))
        if destzip is not None:
            destzip.close()
        return True

    def insert_file(self, hostf, fn):
        for entry in self.dir:
            filename = self.munge_filename(entry.filename)
            if self.match_filename(filename, [fn]):
                break
        else:
            print('Apex file not found', file = sys.stderr)
            return False
        data = hostf.read()
        # pad to block boundary
        if len(data) % self.block_size != 0:
            data += bytearray(self.block_size - (len(data) % self.block_size))
        if len(data) > (entry.size_blocks * self.block_size):
            print('host file longer than Apex file', file = sys.stderr)
            return False
        for rel_block_num in range(0, len(data) // self.block_size):
            offset = rel_block_num * self.block_size
            self.blocks[entry.first_block + rel_block_num] = data[offset:offset + self.block_size]
        self.dirty = True


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description = 'List directory or extract files from an Apex disk image')

    parser.add_argument('-v', '--verbose',
                        action = 'store_true',
                        help = 'increased verbosity')

    parser.add_argument('--tentative',
                        action = 'store_true',
                        help = 'include tentative files')

    parser.add_argument('--replaced',
                        action = 'store_true',
                        help = 'include replaced files')

    subparsers = parser.add_subparsers(dest = 'command',
                                       help = 'sub-command help')

    ls_commands = ['ls', 'dir', 'v', 'l']

    parser_ls = subparsers.add_parser(ls_commands[0],
                                      aliases = ls_commands[1:],
                                      help = 'list directory')

    extract_commands = ['extract', 'e', 'x']

    parser_extract = subparsers.add_parser(extract_commands[0],
                                           aliases = extract_commands[1:],
                                           help = 'extract files')
    parser_extract.add_argument('-t', '--textconv',
                                action = 'store_true',
                                help = 'truncate text files to EOF char')
    dest_group = parser_extract.add_mutually_exclusive_group(required = True)
    dest_group.add_argument('-d', '--destdir',
                            type = str,
                            help = 'destination directory')
    dest_group.add_argument('-z', '--destzip',
                            type = argparse.FileType('wb'),
                            help = 'destination ZIP file')

    insert_commands = ['insert']

    parser_insert = subparsers.add_parser(insert_commands[0],
                                          aliases = insert_commands[1:],
                                          help = 'insert file')
    parser_insert.add_argument('hostf',
                               type = argparse.FileType('rb'),
                               help = 'host file to insert')
    parser_insert.add_argument('apexfn',
                               type = str,
                               help = 'destination Apex filename')

    '''
    image_type_group = parser.add_mutually_exclusive_group()
    image_type_group.add_argument('--logical',
                                  action = 'store_const',
                                  dest = 'image_sector_order',
                                  const = 'logical',
                                  help = 'logical sector order')
    image_type_group.add_argument('--do',
                                  action = 'store_const',
                                  dest = 'image_sector_order',
                                  const = 'dos',
                                  help = 'Apple DOS sector order (typical of .do files)')
    image_type_group.add_argument('--po',
                                  action = 'store_const',
                                  dest = 'image_sector_order',
                                  const = 'prodos',
                                  help = 'Apple ProDOS sector order (typical of .po files)')
    ''' 

    parser.add_argument('--pattern',
                        type = str,
                        help = 'filename pattern to match')

    parser.add_argument('image',
                        type = str,
                        help = 'Apex image filename')
    
    # Unfortunately, putting the 'patterns' arg after the 'image' arg
    # makes parsing fail.
    #parser.add_argument('patterns',
    #                    type = str,
    #                    nargs = '*',
    #                    help = 'filename patterns')


    args = parser.parse_args()

    apex = Apex(args.image,
                include_tentative = args.tentative,
                include_replaced  = args.replaced,
                update = args.command in insert_commands)
    
    if args.pattern is None:
        patterns = []
    else:
        patterns = [args.pattern]

    if args.command in ls_commands:
        result = apex.list_directory(f = sys.stdout,
                                     patterns = patterns)
    elif args.command in extract_commands:
        result = apex.extract_files(patterns = patterns,
                                    destdir = args.destdir,
                                    destzip = args.destzip,
                                    verbose = args.verbose,
                                    text_conv = args.textconv)
    elif args.command in insert_commands:
        result = apex.insert_file(hostf = args.hostf,
                                  fn = args.apexfn)
    else:
        print('Internal error', file = sys.stderr)
        result = False

    apex.close()
    if result:
        sys.exit(0)
    else:
        sys.exit(1)
