#!/usr/bin/env python3
"""Generate a deterministic, self-terminating RV32I long stress program."""

from __future__ import annotations

import argparse
import json
import random
from pathlib import Path

MASK32 = 0xFFFFFFFF


def u32(value: int) -> int:
    return value & MASK32


def s32(value: int) -> int:
    value &= MASK32
    return value if value < 0x80000000 else value - 0x100000000


def encode_r(opcode: int, rd: int, funct3: int, rs1: int, rs2: int, funct7: int) -> int:
    return (
        (funct7 << 25)
        | (rs2 << 20)
        | (rs1 << 15)
        | (funct3 << 12)
        | (rd << 7)
        | opcode
    )


def encode_i(opcode: int, rd: int, funct3: int, rs1: int, imm: int) -> int:
    return ((imm & 0xFFF) << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode


def encode_s(opcode: int, funct3: int, rs1: int, rs2: int, imm: int) -> int:
    imm &= 0xFFF
    return (
        ((imm >> 5) << 25)
        | (rs2 << 20)
        | (rs1 << 15)
        | (funct3 << 12)
        | ((imm & 0x1F) << 7)
        | opcode
    )


def encode_b(funct3: int, rs1: int, rs2: int, imm: int) -> int:
    assert imm % 2 == 0 and -4096 <= imm <= 4094
    imm &= 0x1FFF
    return (
        (((imm >> 12) & 1) << 31)
        | (((imm >> 5) & 0x3F) << 25)
        | (rs2 << 20)
        | (rs1 << 15)
        | (funct3 << 12)
        | (((imm >> 1) & 0xF) << 8)
        | (((imm >> 11) & 1) << 7)
        | 0x63
    )


def encode_u(opcode: int, rd: int, imm20: int) -> int:
    return ((imm20 & 0xFFFFF) << 12) | (rd << 7) | opcode


def encode_j(rd: int, imm: int) -> int:
    assert imm % 2 == 0 and -(1 << 20) <= imm < (1 << 20)
    imm &= 0x1FFFFF
    return (
        (((imm >> 20) & 1) << 31)
        | (((imm >> 1) & 0x3FF) << 21)
        | (((imm >> 11) & 1) << 20)
        | (((imm >> 12) & 0xFF) << 12)
        | (rd << 7)
        | 0x6F
    )


class Program:
    def __init__(self) -> None:
        self.words: list[int] = []
        self.gpr = [0] * 32
        self.memory: dict[int, int] = {}
        self.counts: dict[str, int] = {}
        self.expected_retire: list[int] = []
        self.expected_stream: list[int] = []

    @property
    def pc(self) -> int:
        return len(self.words) * 4

    def emit(self, word: int, category: str, retires: bool = True) -> None:
        instruction_pc = self.pc
        self.words.append(word & MASK32)
        self.expected_retire.append(0)
        if retires:
            self.expected_stream.append((instruction_pc << 32) | (word & MASK32))
        self.counts[category] = self.counts.get(category, 0) + 1

    def write_reg(self, rd: int, value: int) -> None:
        if rd != 0:
            self.gpr[rd] = u32(value)
            self.expected_retire[-1] = (1 << 63) | (rd << 32) | u32(value)

    def store(self, address: int, size: int, value: int) -> None:
        for byte_index in range(size):
            self.memory[address + byte_index] = (value >> (8 * byte_index)) & 0xFF

    def load(self, address: int, size: int, signed: bool) -> int:
        value = 0
        for byte_index in range(size):
            value |= self.memory.get(address + byte_index, 0) << (8 * byte_index)
        if signed and (value & (1 << (size * 8 - 1))):
            value -= 1 << (size * 8)
        return u32(value)


def generate(seed: int, blocks: int) -> Program:
    rng = random.Random(seed)
    p = Program()
    usable_regs = list(range(1, 20)) + list(range(21, 30))

    # x20 is the data-memory base; x30 is the final signature and x31 is tohost.
    p.emit(encode_u(0x37, 20, 0x2), "setup")
    p.write_reg(20, 0x2000)
    for rd in usable_regs:
        imm = rng.randint(-1024, 1023)
        p.emit(encode_i(0x13, rd, 0b000, 0, imm), "setup")
        p.write_reg(rd, imm)

    r_ops = [
        ("add", 0b000, 0x00),
        ("sub", 0b000, 0x20),
        ("sll", 0b001, 0x00),
        ("slt", 0b010, 0x00),
        ("sltu", 0b011, 0x00),
        ("xor", 0b100, 0x00),
        ("srl", 0b101, 0x00),
        ("sra", 0b101, 0x20),
        ("or", 0b110, 0x00),
        ("and", 0b111, 0x00),
    ]
    i_ops = ["addi", "slti", "sltiu", "xori", "ori", "andi", "slli", "srli", "srai"]
    previous_rd = 1

    for block in range(blocks):
        for operation_index in range(12):
            rd = rng.choice(usable_regs)
            rs1 = previous_rd if rng.random() < 0.55 else rng.choice(usable_regs)
            rs2 = rng.choice(usable_regs)

            if (block + operation_index) % 2 == 0:
                name, funct3, funct7 = r_ops[(block * 12 + operation_index) % len(r_ops)]
                p.emit(encode_r(0x33, rd, funct3, rs1, rs2, funct7), "alu_r")
                a = p.gpr[rs1]
                b = p.gpr[rs2]
                shamt = b & 0x1F
                result = {
                    "add": u32(a + b),
                    "sub": u32(a - b),
                    "sll": u32(a << shamt),
                    "slt": int(s32(a) < s32(b)),
                    "sltu": int(a < b),
                    "xor": a ^ b,
                    "srl": a >> shamt,
                    "sra": u32(s32(a) >> shamt),
                    "or": a | b,
                    "and": a & b,
                }[name]
            else:
                name = i_ops[(block * 12 + operation_index) % len(i_ops)]
                if name in ("slli", "srli", "srai"):
                    imm = rng.randrange(32)
                    funct3 = 0b001 if name == "slli" else 0b101
                    encoded_imm = imm | (0x400 if name == "srai" else 0)
                else:
                    imm = rng.randint(-2048, 2047)
                    encoded_imm = imm
                    funct3 = {
                        "addi": 0b000,
                        "slti": 0b010,
                        "sltiu": 0b011,
                        "xori": 0b100,
                        "ori": 0b110,
                        "andi": 0b111,
                    }[name]
                p.emit(encode_i(0x13, rd, funct3, rs1, encoded_imm), "alu_i")
                a = p.gpr[rs1]
                if name == "addi":
                    result = u32(a + imm)
                elif name == "slti":
                    result = int(s32(a) < imm)
                elif name == "sltiu":
                    result = int(a < u32(imm))
                elif name == "xori":
                    result = a ^ u32(imm)
                elif name == "ori":
                    result = a | u32(imm)
                elif name == "andi":
                    result = a & u32(imm)
                elif name == "slli":
                    result = u32(a << imm)
                elif name == "srli":
                    result = a >> imm
                else:
                    result = u32(s32(a) >> imm)

            p.write_reg(rd, result)
            previous_rd = rd

        if block % 2 == 0:
            offset = ((block * 12) % 1024) & ~3
            source = rng.choice(usable_regs)
            destination = rng.choice(usable_regs)
            p.emit(encode_s(0x23, 0b010, 20, source, offset), "store")
            p.store(0x2000 + offset, 4, p.gpr[source])
            p.emit(encode_i(0x03, destination, 0b010, 20, offset), "load")
            p.write_reg(destination, p.load(0x2000 + offset, 4, True))
            previous_rd = destination

        if block % 4 == 1:
            offset = (512 + block * 3) % 1024
            source = rng.choice(usable_regs)
            destination = rng.choice(usable_regs)
            p.emit(encode_s(0x23, 0b000, 20, source, offset), "store")
            p.store(0x2000 + offset, 1, p.gpr[source])
            p.emit(encode_i(0x03, destination, 0b100, 20, offset), "load")
            p.write_reg(destination, p.load(0x2000 + offset, 1, False))
            previous_rd = destination

        if block % 4 == 2:
            offset = ((768 + block * 6) % 1024) & ~1
            source = rng.choice(usable_regs)
            destination = rng.choice(usable_regs)
            p.emit(encode_s(0x23, 0b001, 20, source, offset), "store")
            p.store(0x2000 + offset, 2, p.gpr[source])
            p.emit(encode_i(0x03, destination, 0b101, 20, offset), "load")
            p.write_reg(destination, p.load(0x2000 + offset, 2, False))
            previous_rd = destination

        if block % 7 == 0:
            wrong_rd = rng.choice(usable_regs)
            target_rd = rng.choice(usable_regs)
            p.emit(encode_b(0b000, 0, 0, 8), "branch")
            p.emit(
                encode_i(0x13, wrong_rd, 0b000, 0, 0x377),
                "wrong_path",
                retires=False,
            )
            imm = (block % 31) - 15
            p.emit(encode_i(0x13, target_rd, 0b000, target_rd, imm), "branch_target")
            p.write_reg(target_rd, p.gpr[target_rd] + imm)
            previous_rd = target_rd

        if block % 11 == 3:
            rd = rng.choice(usable_regs)
            imm = rng.randint(-64, 63)
            p.emit(encode_b(0b001, 0, 0, 8), "branch")
            p.emit(encode_i(0x13, rd, 0b000, rd, imm), "branch_fallthrough")
            p.write_reg(rd, p.gpr[rd] + imm)
            previous_rd = rd

        if block % 19 == 5:
            wrong_rd = rng.choice(usable_regs)
            p.emit(encode_j(0, 8), "jal")
            p.emit(
                encode_i(0x13, wrong_rd, 0b000, 0, 0x255),
                "wrong_path",
                retires=False,
            )

        if block % 37 == 9:
            jalr_pc = p.pc
            p.emit(encode_u(0x17, 28, 0), "jalr_setup")
            p.write_reg(28, jalr_pc)
            p.emit(encode_i(0x13, 28, 0b000, 28, 16), "jalr_setup")
            p.write_reg(28, p.gpr[28] + 16)
            p.emit(encode_i(0x67, 0, 0b000, 28, 0), "jalr")
            p.emit(
                encode_i(0x13, 27, 0b000, 0, 0x166),
                "wrong_path",
                retires=False,
            )

    p.emit(encode_i(0x13, 30, 0b000, 0, 0), "signature")
    p.write_reg(30, 0)
    for rs in usable_regs + [20]:
        p.emit(encode_r(0x33, 30, 0b100, 30, rs, 0), "signature")
        p.write_reg(30, p.gpr[30] ^ p.gpr[rs])

    p.emit(encode_i(0x13, 31, 0b000, 0, 1), "tohost")
    p.write_reg(31, 1)
    p.emit(encode_j(0, 0), "halt", retires=False)
    return p


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--seed", type=lambda value: int(value, 0), default=0x1892026)
    parser.add_argument("--blocks", type=int, default=700)
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path("tests/stress/generated"),
    )
    args = parser.parse_args()

    program = generate(args.seed, args.blocks)
    args.output_dir.mkdir(parents=True, exist_ok=True)

    (args.output_dir / "rv32i_long_stress.hex").write_text(
        "".join(f"{word:08x}\n" for word in program.words),
        encoding="ascii",
    )
    (args.output_dir / "rv32i_long_stress_expected_gpr.hex").write_text(
        "".join(f"{value:08x}\n" for value in program.gpr),
        encoding="ascii",
    )
    (args.output_dir / "rv32i_long_stress_expected_retire.hex").write_text(
        "".join(f"{value:016x}\n" for value in program.expected_retire),
        encoding="ascii",
    )
    (args.output_dir / "rv32i_long_stress_expected_stream.hex").write_text(
        "".join(f"{value:016x}\n" for value in program.expected_stream),
        encoding="ascii",
    )
    metadata = {
        "seed": args.seed,
        "blocks": args.blocks,
        "static_instruction_count": len(program.words),
        "expected_dynamic_retire_count": len(program.expected_stream),
        "program_bytes": len(program.words) * 4,
        "expected_signature_x30": f"0x{program.gpr[30]:08x}",
        "completion_register": "x31",
        "completion_value": 1,
        "instruction_categories": program.counts,
    }
    (args.output_dir / "rv32i_long_stress.json").write_text(
        json.dumps(metadata, indent=2) + "\n",
        encoding="ascii",
    )
    print(
        f"Generated {len(program.words)} instructions "
        f"(seed=0x{args.seed:x}, signature=0x{program.gpr[30]:08x})"
    )


if __name__ == "__main__":
    main()
