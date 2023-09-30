#!/bin/bash

set -e

NM=/opt/gcc-arm-none-eabi-10.3/bin/arm-none-eabi-nm
OBJDUMP=/opt/gcc-arm-none-eabi-10.3/bin/arm-none-eabi-objdump
ADDR2LINE=/opt/gcc-arm-none-eabi-10.3/bin/arm-none-eabi-addr2line
GDB=/opt/gcc-arm-none-eabi-10.3/bin/arm-none-eabi-gdb

BIOS_PATH="BIOS.elf"
BIOS_SRCS_PATH="/tmp/BIOS_CORTEX_UNIFICATO"
BIOS_OBJDUMP_CACHE="/tmp/objdump_BIOS.txt"

AWK_FUNC_PARSEHEX=$(
	cat <<EOF
	# https://stackoverflow.com/questions/4614775/converting-hex-to-decimal-in-awk-or-sed
	function parsehex(V, OUT)
	{
		H["0"] = 0; H["1"] = 1; H["2"] = 2; H["3"] = 3
		H["4"] = 4; H["5"] = 5; H["6"] = 6; H["7"] = 7
		H["8"] = 8; H["9"] = 9; H["A"] = 10; H["B"] = 11
		H["C"] = 12; H["D"] = 13; H["E"] = 14; H["F"] = 15

		if (V ~ /^0x/) V = substr(V,3);
		for (N = 1; N <= length(V); N++) {
			OUT = (OUT*16) + H[substr(V, N, 1)]
		}
		return(OUT)
	}
EOF
)

# funzione privata
# echo "get_last_trace()"
# echo "   Ritorna il nome del file trace.txt.X con X piu' alto"
get_last_trace() {
	if [ $(find . -type f -name 'trace.txt*' | wc -l) -eq 1 ]; then
		echo "./trace.txt"
		return
	fi
	highest=$(find . -type f -name 'trace.txt.*' | sed 's/.*trace\.txt\.//' | sort -n | tail -n 1)
	echo "./trace.txt.$highest"
}

echo "count_times_address()"
echo "   Ritorna il numero di volte che un indirizzo e' presente in un trace.txt"
count_times_address() {
	address=$(echo "$1" | awk -F '[xX]' '{ print $NF }' | tr 'a-f' 'A-F')
	awk_script=$(
		cat <<EOF
		$AWK_FUNC_PARSEHEX

		BEGIN { address_dec = parsehex(address); total = 0; count = 0 }
		/^0x/ {
			total++;
			if (parsehex(\$1) == address_dec) { count++ }
		}
		END { print "\nIndirizzo trovato", count, "volta/e su", total, "\n" }
EOF
	)
	awk -F ':' -v address="$address" "$awk_script" $(get_last_trace)
}

echo "check_and_create_bios_objdump_cache()"
echo "   Se non e' gia' presente, crea un file con l'output di objdump del bios"
check_and_create_bios_objdump_cache() {
	if [ ! -f "$BIOS_OBJDUMP_CACHE" ]; then
		$OBJDUMP \
			-S \
			--visualize-jumps=color \
			"$BIOS_PATH" \
			>"$BIOS_OBJDUMP_CACHE" 2>/dev/null
	fi
}

echo "setup_bios_sources()"
echo "   Scompatta i sorgenti del bios in $BIOS_SRCS_PATH"
setup_bios_sources() {
	rm -rf "$BIOS_SRCS_PATH"
	mkdir "$BIOS_SRCS_PATH"
	(
		cd "$BIOS_SRCS_PATH"
		cp /home/ivan/Scrivania/DEV/BIOS_CORTEX_UNIFICATO.tar.xz .
		tar -x -f "BIOS_CORTEX_UNIFICATO.tar.xz"
	)
	# prepara i sorgenti per list in gdb
	rm -rf /tmp/Keil510/ARM/PROGETTI/BIOS_CORTEX
	mkdir -p /tmp/Keil510/ARM/PROGETTI/BIOS_CORTEX
	(
		cd /tmp/Keil510/ARM/PROGETTI/BIOS_CORTEX
		cp -r $BIOS_SRCS_PATH/* .
		find . -type f -path './*/*.[cChHsS]' -exec cp \{} . \;
	)
}

echo "clear_bios_objdump_cache()"
echo "   Rimuove il file con l'output di objdump del bios"
clear_bios_objdump_cache() {
	rm "$BIOS_OBJDUMP_CACHE"
}

echo "disassemble_function()"
echo "   Mostra il disassembly di una funzione presente nel bios"
disassemble_function() {
	check_and_create_bios_objdump_cache
	cat "$BIOS_OBJDUMP_CACHE" | less -r -j 10 -p "^[0-9a-f]*\s*<$1>:.*"
}

echo "disassemble_address()"
echo "   Mostra il disassembly intorno ad un certo indirizzo"
disassemble_address() {
	check_and_create_bios_objdump_cache
	ADDRESS="$(echo "$1" | tr 'A-Z' 'a-z' |
		awk -F '[xX]' '{ print$NF }' | sed 's/^0*//')"
	LINES_AFTER=${2:-25}

	#grep -E -B 5 -A $LINES_AFTER "^\s*[0]*$ADDRESS:" "$BIOS_OBJDUMP_CACHE"
	cat "$BIOS_OBJDUMP_CACHE" | less -r -j 10 -p "^\s*[0]*$ADDRESS:.*"
}

echo "bios_grep()"
echo "   Cerca un termine/regex nei sorgenti del bios"
bios_grep() {
	(
		cd "$BIOS_SRCS_PATH"
		grep -C 2 --text -nr --include '*.[chsCHS]' "$1" .
	)
}

echo "bios_addr2line()"
echo "   Mostra a che linea di codice nei sorgenti del bios corrisponde un indirizzo"
bios_addr2line() {
	$ADDR2LINE -e "$BIOS_PATH" $@ |
		sed 's#C:\\Keil510\\ARM\\PROGETTI\\BIOS_CORTEX/##' |
		sed 's/:\([0-9]*\)/ -> \1/'
}

echo "bios_line2addr()"
echo "   Mostra a che indirizzo corrisponde una linea di codice"
bios_line2addr() {
	output=$("$GDB" BIOS.elf -ex "info line $1:$2" --batch 2>/dev/null)

	echo "$output" | grep "^Line " | sort | uniq
}

echo "histo_around_address()"
echo "   Mostra un istogramma degli indirizzi prima e/o dopo un indirizzo fornito"
histo_around_address() {
	address=$(echo "$1" | awk -F '[xX]' '{ print $NF }' | tr 'a-f' 'A-F')
	around_position="${2:-B}"
	around_count="${3:-1}"

	# count_times_address "$address"

	histo=$(cat $(get_last_trace) |
		grep -"$around_position" $around_count $address |
		sort | uniq -c | sort -nr | grep -Ev '\-\-$' | grep -Ev "$address$")
	echo "$histo" >/tmp/histo_around_address.txt

	output=

	while read -r line; do
		count="$(echo "$line" | awk -F ' ' '{ print $1 }')"
		addr="$(echo "$line" | awk -F ' ' '{ print $2 }')"
		src="$(bios_addr2line "$addr" | sed 's#\\t#\\\\t#')"
		src_file="$(echo "$src" | awk -F '->' '{ print $1 }')"
		src_line="$(echo "$src" | awk -F '->' '{ print $2 }')"

		output="$output$count # $addr # $src_file # $src_line\n"
	done </tmp/histo_around_address.txt

	rm /tmp/histo_around_address.txt

	echo -e "$output" | tabulate --sep "#" --format plain
}

echo "histo_addresses()"
echo "   Mostra l'histogramma di tutte le istruzioni eseguite"
histo_addresses() {
	count=${1:-25}

	histo=$(cat $(get_last_trace) |
		sort | uniq -c | sort -nr | head -n $count)
	echo "$histo" >/tmp/histo_around_address.txt

	output=

	while read -r line; do
		count="$(echo "$line" | awk -F ' ' '{ print $1 }')"
		addr="$(echo "$line" | awk -F ' ' '{ print $2 }')"
		src="$(bios_addr2line "$addr" | sed 's#\\t#\\\\t#')"
		src_file="$(echo "$src" | awk -F '->' '{ print $1 }')"
		src_line="$(echo "$src" | awk -F '->' '{ print $2 }')"

		output="$output$count # $addr # $src_file # $src_line\n"
	done </tmp/histo_around_address.txt

	rm /tmp/histo_around_address.txt

	echo -e "$output" | tabulate --sep "#" --format plain
}

echo "attach_gdb()"
echo "   Apri e connetti gdb all'emulatore"
attach_gdb() {
	"$GDB" "$BIOS_PATH" \
		-ex 'target remote :3333' \
		-ex 'directory /tmp/' \
		-ex 'directory /tmp/Keil510/ARM/PROGETTI/BIOS_CORTEX/' \
		-ex 'display $pc' \
		-ex 'list' \
		-ex 'info stack'
}

echo "bios_nm()"
echo "   Cerca all'interno degli oggetti del bios"
bios_nm() {
	"$NM" -nS "$BIOS_PATH" | grep -i -C 2 "$1"
}

set +e
