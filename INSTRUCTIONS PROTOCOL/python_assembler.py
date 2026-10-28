"""
assembler_v2.py
---------------
Tiny one-pass assembler for the 25-bit SIMD multimedia ISA used in our project.

It reads a human-readable .asm file and emits a .mem file containing one
25-bit binary instruction per line (as ASCII "0"/"1" characters).

Authors:
    - Travis Coffino
    - Pranay Srivastava
"""

import sys
import os


# ============================================================================
#  Encoding helpers for each instruction format
# ============================================================================

def encode_li(rd, lane, imm16):
    """
    Encode an LI (load immediate into lane) instruction.

    LI format (25 bits total, bit 24 is MSB):
        bit 24          = 0  (LI opcode class)
        bits 23..21     = lane index (0..7)
        bits 20..5      = 16-bit immediate value (imm16)
        bits 4..0       = rd (destination register: 0..31)
    """
    instr = 0
    instr |= 0 << 24                     # bit 24 = 0 for LI format
    instr |= (lane & 0x7)   << 21        # bits 23..21: lane (3 bits)
    instr |= (imm16 & 0xFFFF) << 5       # bits 20..5 : 16-bit immediate
    instr |= (rd & 0x1F)                 # bits 4..0  : destination register
    return instr


def encode_r4(longInt, subAdd, highLow, rd, rs1, rs2, rs3):
    """
    Encode an R4 MAC-style instruction.

    Assembly syntax:
        <MODE> rd, rs1, rs2, rs3

    Bit-level encoding used in the hardware:
        bits 24..23 = 10                        (R4 opcode class)
        bits 22..20 = {LONG/INT, SUB/ADD, HIGH/LOW}  (3 control bits)
        bits 19..15 = rs3   (RIGHTMOST register in the asm line)
        bits 14..10 = rs2
        bits 9..5   = rs1
        bits 4..0   = rd    (LEFTMOST register in the asm line)

    So registers are encoded from RIGHT to LEFT:
        rs3 → highest source field
        rs2 → middle source field
        rs1 → lowest source field
        rd  → destination field
    """
    instr = 0

    # Top-level opcode class for R4 MAC instructions: "10"
    instr |= 0b10 << 23

    # Pack the 3 control bits (LONG/INT, SUB/ADD, HIGH/LOW).
    form = ((longInt & 1) << 2) | ((subAdd & 1) << 1) | (highLow & 1)
    instr |= (form & 0x7) << 20

    # Registers are encoded from right to left (rs3, rs2, rs1, rd).
    instr |= (rs3 & 0x1F) << 15      # bits 19..15 = rs3 (rightmost in asm)
    instr |= (rs2 & 0x1F) << 10      # bits 14..10 = rs2
    instr |= (rs1 & 0x1F) << 5       # bits 9..5   = rs1
    instr |= (rd  & 0x1F)            # bits 4..0   = rd  (leftmost in asm)

    return instr


def encode_r3(opcode, rd, rs1, rs2_or_imm5):
    """
    Encode an R3 ALU/vector instruction.

    R3 format (25 bits total):
        bits 24..23 = 11           (R3 opcode class)
        bits 22..19 = 0000         (unused upper opcode bits in this ISA)
        bits 18..15 = opcode[3:0]  (4-bit opcode used by your ALU)
        bits 14..10 = rs2 OR imm5  (for immediates like SHRHI / MLHCU)
        bits 9..5   = rs1
        bits 4..0   = rd
    """
    instr = 0
    instr |= 0b11 << 23                    # bits 24..23: class "11"
    instr |= (opcode & 0xF) << 15          # bits 18..15: 4-bit opcode
    instr |= (rs2_or_imm5 & 0x1F) << 10    # bits 14..10: rs2 or imm5
    instr |= (rs1 & 0x1F) << 5             # bits 9..5  : rs1
    instr |= (rd & 0x1F)                   # bits 4..0  : rd
    return instr


# ============================================================================
#  Parsing helpers (strip comments, parse registers, numbers, etc.)
# ============================================================================

def remove_comments(line: str) -> str:
    """
    Remove comments from a line of assembly.

    Comment starters: '#' and '--'.
    """
    for sep in ("#", "--"):
        if sep in line:
            line = line.split(sep, 1)[0]
    return line.strip()


def clean_token(tok: str) -> str:
    """Remove commas and surrounding whitespace from a token."""
    return tok.replace(",", "").strip()


def parse_int(token: str) -> int:
    """
    Parse a numeric token as an integer.

    Supports:
        - Decimal:  "10"
        - Hex:      "0x10"
        - Binary:   "0b1010"
    """
    token = clean_token(token)
    return int(token, 0)


def parse_reg(token: str) -> int:
    """
    Parse a register name/number into an integer index 0..31.

    Acceptable formats:
        - "16"  -> 16
        - "r16" -> 16
        - "R17" -> 17
    """
    token = clean_token(token)
    token = token.lower()
    if token.startswith("r"):
        token = token[1:]
    return int(token, 0)


# ============================================================================
#  Assembling a single line of assembly text
# ============================================================================

def assemble_line(line: str, lineno: int):
    """
    Assemble a single line of assembly source code.

    Returns:
        - None if the line is blank or a pure comment.
        - int 25-bit encoded instruction otherwise.
    """
    line = remove_comments(line)
    if line == "":
        return None

    parts = [clean_token(p) for p in line.split()]
    if not parts:
        return None

    instr_name = parts[0].upper()

    # ------------------------------------------------------------------------
    # LI format
    # ------------------------------------------------------------------------
    if instr_name == "LI":
        # Syntax: LI rd, lane, imm16
        if len(parts) != 4:
            raise ValueError(f"[line {lineno}] LI expects: LI rd, lane, imm16")
        rd    = parse_reg(parts[1])
        lane  = parse_int(parts[2])
        imm16 = parse_int(parts[3])
        return encode_li(rd, lane, imm16)

    # ------------------------------------------------------------------------
    # R4 MAC family format
    # ------------------------------------------------------------------------
    r4_modes = {
        "INT_LOW_ADD"   : (0, 0, 0),
        "INT_HIGH_ADD"  : (0, 0, 1),
        "INT_LOW_SUB"   : (0, 1, 0),
        "INT_HIGH_SUB"  : (0, 1, 1),
        "LONG_LOW_ADD"  : (1, 0, 0),
        "LONG_HIGH_ADD" : (1, 0, 1),
        "LONG_LOW_SUB"  : (1, 1, 0),
        "LONG_HIGH_SUB" : (1, 1, 1),
    }

    if instr_name in r4_modes:
        # Syntax: <MODE> rd, rs1, rs2, rs3
        if len(parts) != 5:
            raise ValueError(
                f"[line {lineno}] {instr_name} expects: "
                f"{instr_name} rd, rs1, rs2, rs3"
            )

        longInt, subAdd, highLow = r4_modes[instr_name]

        rd  = parse_reg(parts[1])
        rs1 = parse_reg(parts[2])
        rs2 = parse_reg(parts[3])
        rs3 = parse_reg(parts[4])

        return encode_r4(longInt, subAdd, highLow, rd, rs1, rs2, rs3)

    # ------------------------------------------------------------------------
    # R3 ALU / vector ops
    # ------------------------------------------------------------------------
    r3_info = {
        "NOP"   : (0b0000, "nop"),
        "SHRHI" : (0b0001, "rd_rs1_imm5"),   # SHRHI rd, rs1, shamt
        "AU"    : (0b0010, "rd_rs1_rs2"),
        "CNT1H" : (0b0011, "rd_rs1"),
        "AHS"   : (0b0100, "rd_rs1_rs2"),
        "OR"    : (0b0101, "rd_rs1_rs2"),
        "BCW"   : (0b0110, "rd_rs1"),
        "MAXWS" : (0b0111, "rd_rs1_rs2"),
        "MINWS" : (0b1000, "rd_rs1_rs2"),
        "MLHU"  : (0b1001, "rd_rs1_rs2"),
        "MLHCU" : (0b1010, "rd_rs1_imm5"),   # MLHCU rd, rs1, imm5
        "AND"   : (0b1011, "rd_rs1_rs2"),
        "CLZW"  : (0b1100, "rd_rs1"),
        "ROTW"  : (0b1101, "rd_rs1_rs2"),
        "SFWU"  : (0b1110, "rd_rs1_rs2"),
        "SFHS"  : (0b1111, "rd_rs1_rs2"),
    }

    if instr_name in r3_info:
        opcode, form = r3_info[instr_name]

        if form == "nop":
            rd = rs1 = rs2_or_imm = 0
            return encode_r3(opcode, rd, rs1, rs2_or_imm)

        elif form == "rd_rs1_imm5":
            if len(parts) != 4:
                raise ValueError(
                    f"[line {lineno}] {instr_name} expects: "
                    f"{instr_name} rd, rs1, imm5"
                )
            rd   = parse_reg(parts[1])
            rs1  = parse_reg(parts[2])
            imm5 = parse_int(parts[3]) & 0x1F
            return encode_r3(opcode, rd, rs1, imm5)

        elif form == "rd_rs1":
            if len(parts) != 3:
                raise ValueError(
                    f"[line {lineno}] {instr_name} expects: "
                    f"{instr_name} rd, rs1"
                )
            rd  = parse_reg(parts[1])
            rs1 = parse_reg(parts[2])
            rs2 = 0
            return encode_r3(opcode, rd, rs1, rs2)

        elif form == "rd_rs1_rs2":
            if len(parts) != 4:
                raise ValueError(
                    f"[line {lineno}] {instr_name} expects: "
                    f"{instr_name} rd, rs1, rs2"
                )
            rd  = parse_reg(parts[1])
            rs1 = parse_reg(parts[2])
            rs2 = parse_reg(parts[3])
            return encode_r3(opcode, rd, rs1, rs2)

    # Unknown mnemonic
    raise ValueError(f"[line {lineno}] Unknown instruction: {instr_name}")


# ============================================================================
#  Main driver: ask for .asm name, write instructions.mem in same folder
# ============================================================================

def main():
    """
    Usage (generic, works on anyone's machine):

        Option 1: Provide input on the command line
            python assembler_v2.py program.asm

        Option 2: Let the script prompt you
            python assembler_v2.py
            Type input .asm file name: program.asm

    In both cases, output is always written to:
        instructions.mem

    located in the SAME FOLDER as the input .asm file.
    """
    # 1) Get input .asm filename (argv[1] if present, otherwise prompt)
    if len(sys.argv) >= 2:
        in_file = sys.argv[1]
    else:
        in_file = input("Type input .asm file name: ").strip()

    # 2) Compute output path: same directory as input file
    asm_dir = os.path.dirname(os.path.abspath(in_file))
    out_file = os.path.join(asm_dir, "instructions.mem")

    binary_instrs = []

    # 3) Read, assemble, collect instructions
    with open(in_file, "r") as f:
        for lineno, line in enumerate(f, 1):
            instr = assemble_line(line, lineno)
            if instr is not None:
                bits = f"{instr:025b}"   # 25-bit binary string
                binary_instrs.append(bits)

    # 4) Write instructions.mem in the same folder
    with open(out_file, "w") as f:
        for bits in binary_instrs:
            f.write(bits + "\n")

    print(f"Wrote {len(binary_instrs)} instructions.")
    print(f"Output in file: {out_file}")


if __name__ == "__main__":
    main()
