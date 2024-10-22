
.PHONY: all clean

all: crc

crc: crc.asm
	nasm -g -f elf64 -w+all -w+error -o crc.o crc.asm
	ld --fatal-warnings -o crc crc.o

clean: 
	rm -f *.o crc