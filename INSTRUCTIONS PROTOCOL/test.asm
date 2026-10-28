# Load r16 lane0 = 1, r17 lane0 = 2
LI  r16, 0, 0x0001
LI  r17, 0, 0x0002

# OR r15 = r16 OR r17  (R3)
OR  r15, r16, r17

# Example INT low add: r20 = MAC(r20, r16, r17, r18)
INT_LOW_ADD  r20, r18, r17, r16

# SHRHI r10 = r10 >> 3 (per halfword)
SHRHI r10, r10, 3

LI r20, 1, 0xABCD

NOP
