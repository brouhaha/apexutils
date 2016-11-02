# apexutils - Utility to list directory or extract files from Apex disk images

Copyright 2014, 2016 Eric Smith <spacewar@gmail.com>

apexutils development is hosted at the
[apexutils Github repository](https://github.com/brouhaha/apexutils/).

## Introduction

The Apex operating system was developed by members of the
[6502 Group](http://www.6502group.org/),
originally for use on the 6502. Apex was written in
[XPL0](http://www.xpl0.org/),
a portable block structured language, and was later ported to 68000 systems.

This package currently provides a single utility, 'apex', which
can list the directory of an Apple II Apex disk image file, or
extract files from such an image.

The image should be a "DOS order" image.

apexutils is written in
[Python](http://www.python.org/),
and Python 3.4 or newer is required.


## Usage:

* To list the directory of the image xpl0.dsk:

  `apex ls xpl0.dsk`

* To list only the '.sav' files:

  `apex ls --pattern '*.sav' xpl0.dsk`

* To extract all of the files from the image xpl0.dsk to the current
directory:

  `apex extract xpl0.dsk`

* To extract all of the '.sav' files into the directory 'save_files':

  `apex extract --pattern '*.sav' --destdir save_files xpl0.dsk`

* To extract all of the '.sys' files into a new ZIP file 'sys_files.zip':

  `apex extract --pattern '*.sys' --destzip sys_files.zip xpl0.dsk`


## License information:

This program is free software: you can redistribute it and/or modify
it under the terms of version 3 of the GNU General Public License
as published by the Free Software Foundation.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
