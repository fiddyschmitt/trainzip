#!/bin/bash

#https://github.com/fiddyschmitt/trainzip
#version 1.0.0

# check stdin
if [ -t 0 ]; then
	echo "No input. Terminating."
	exit
fi

split_size="10MB"
decompress=0

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -s|--split-size) split_size="$2"; shift ;;
		-d|--decompress) decompress=1 ;;
        *) echo "Unknown parameter passed: $1" >&2; exit 1 ;;
    esac
    shift
done

if [ $decompress -eq 0 ]; then

	#Compress the input

	#Write the Magic Bytes
	printf "%b" '\xc0\xff\xee\x1a\xbb' >&1

	#Write the File Format Version
	file_format_version=1
	echo "0: $(printf '%08x' $file_format_version | tac -rs ..)" | xxd -r >&1

	#Create a temporary file to store the current position
	tmpUncompressedPosition=$(mktemp -p /dev/shm)
	echo "0" > $tmpUncompressedPosition

	cat /dev/stdin | split --bytes $split_size --filter='
		#Store the chunk to RAM
		tmpUncompressed=$(mktemp -p /dev/shm)
		cat > $tmpUncompressed
		uncompressed_chunk_size=$(stat -c%s "$tmpUncompressed")
		
		#Compress the chunk in RAM
		tmpCompressed=$(mktemp -p /dev/shm)
		cat $tmpUncompressed | zstd > $tmpCompressed
		compressed_chunk_size=$(stat -c%s "$tmpCompressed")
		
		#Store the metadata
			#Compression format (length-prefixed string)
			compression_format="zstd"
			echo "0: $(printf '%02x' ${#compression_format}  | tac -rs ..)" | xxd -r >&1
			echo -n $compression_format >&1
			
			#Uncompressed start position
			uncompressed_start_byte=$(cat '$tmpUncompressedPosition')
			echo "0: $(printf '%016x' $uncompressed_start_byte | tac -rs ..)" | xxd -r >&1
			
			#Uncompressed end position
			uncompressed_end_byte=$((uncompressed_start_byte + uncompressed_chunk_size))
			#echo Compressing byte: $uncompressed_start_byte
			echo "0: $(printf '%016x' $uncompressed_end_byte | tac -rs ..)" | xxd -r >&1

			#Compressed length
			echo "0: $(printf '%016x' $compressed_chunk_size | tac -rs ..)" | xxd -r >&1
			
		#Store the compressed chunk
		cat $tmpCompressed >&1

		#Keep a record of what uncompressed byte we are up to	
		echo $uncompressed_end_byte > '$tmpUncompressedPosition'	
		
		#Delete the temp files
		rm $tmpUncompressed
		rm $tmpCompressed
	'

	rm $tmpUncompressedPosition

else
	#Decompressing
	
	#Read the Magic Byte
	expected_magic_bytes="c0ffee1abb"
	magicBytes=$(dd if=/dev/stdin status=none iflag=count_bytes count=5 | xxd -ps)
	#echo "Magic Bytes: $magicBytes" >&2
	
	if [ $magicBytes != $expected_magic_bytes ]; then
		echo "Not a valid trainzip. Input does not contain Magic Bytes: $expected_magic_bytes" >&2
		echo "Terminating." >&2
		exit
	fi
	
	#Read the File Format Version
	file_format_version=$(( $(dd if=/dev/stdin status=none iflag=count_bytes count=4 | xxd -ps | tac -rs ..) ))
	#echo "File Format Version: $file_format_version" >&2
	
	while true
	do

		#Compression format (length-prefixed string)
		compress_format_string_length=$(( $(dd if=/dev/stdin status=none iflag=count_bytes count=1 | xxd -ps) ))
		#echo "Compression Format String Length: $compress_format_string_length" >&2
		
		if [ $compress_format_string_length == 0 ]; then
			break
		fi
		
		compress_format_string=$(dd if=/dev/stdin status=none iflag=count_bytes count=$compress_format_string_length)
		#echo "Compression Format: $compress_format_string" >&2
		
		case $compress_format_string in
			"zstd") decompress_command="zstdcat" ;;
			*) echo "Unknown compression format: $compress_format_string" >&2; echo "Terminating." >&2 exit 1 ;;
		esac
		
		#Uncompressed start position
		uncompressed_start_byte=$(dd if=/dev/stdin status=none iflag=count_bytes count=8 | xxd -ps | xargs echo -n | tac -rs ..)
		uncompressed_start_byte=$((16#${uncompressed_start_byte}))
		#echo "Uncompressed start byte: $uncompressed_start_byte" >&2
		
		#Uncompressed end position
		uncompressed_end_byte=$(dd if=/dev/stdin status=none iflag=count_bytes count=8 | xxd -ps | xargs echo -n | tac -rs ..)
		uncompressed_end_byte=$((16#$uncompressed_end_byte))
		#echo "Uncompressed end byte: $uncompressed_end_byte" >&2
		
		#Compressed length
		compressed_chunk_size=$(dd if=/dev/stdin status=none iflag=count_bytes count=8 | xxd -ps | xargs echo -n | tac -rs ..)
		compressed_chunk_size=$((16#$compressed_chunk_size))
		#compressed_chunk_size=$(($compressed_chunk_size+38))
		#echo "Compressed chunk size: $compressed_chunk_size" >&2
		
		#Decompress the chunk
		dd if=/dev/stdin status=none bs=$compressed_chunk_size count=1 iflag=fullblock | eval $decompress_command
	done
	
fi