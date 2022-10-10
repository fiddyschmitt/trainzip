# trainzip
A seekable compression format.

This script splits a file into pieces, compresses each piece, then combines them back into one file. This means that you get the benefit of compression, plus the ability to seek through the archive without needing to extract first.

The script uses ZStandard for compression, but other compressors will be added in future.

# Usage

## Compress a file
`cat bigfile.dat | ./trainzip.sh > bigfile.trainzip`

## Decompress
`cat bigfile.trainzip | ./trainzip.sh --decompress > bigfile_restored.dat`

