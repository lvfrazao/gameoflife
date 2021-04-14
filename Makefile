ASSEMBLER = nasm
ASMFLAGS = -f elf64
DEBUG_FLAGS = -f elf64 -g -F dwarf
LINKER = ld
LINKER_FLAGS = --strip-all
TARGET = game_of_life
BUILD_PATH = ./
INSTALL_PATH = /usr/local/bin/
SOURCE = game_of_life.s


$(TARGET): $(TARGET).o
	$(LINKER) $(BUILD_PATH)$(TARGET).o $(LINKER_FLAGS) -o $(TARGET)

$(TARGET).o: $(SOURCE)
	$(ASSEMBLER) $(BUILD_PATH)$(SOURCE) $(ASMFLAGS) -o $(TARGET).o

.PHONY: debug
debug:
	$(ASSEMBLER) $(BUILD_PATH)$(SOURCE) $(DEBUG_FLAGS) -o $(TARGET).o
	$(LINKER) $(BUILD_PATH)$(TARGET).o -o $(TARGET)

.PHONY: all
all: $(TARGET)

.PHONY: install
install:
	mv $(TARGET) $(INSTALL_PATH)

.PHONY: clean
clean:
	$(RM) $(TARGET)
	$(RM) $(TARGET).o
	$(RM) $(INSTALL_PATH)$(TARGET)