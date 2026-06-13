# Benchmarks

All measured on a Tesla V100-SXM2-16GB + Ryzen 9 3900X (Zen 2, 12C/24T, DDR4), MCDM driver
mode. `llama-bench`, q8_0 KV cache, flash attention on. Your CPU and RAM speed will shift the
Qwen3 numbers (it does CPU expert compute); Gemma 4 is pure-GPU so it's mostly CPU-independent.

## Single V100

### Gemma 4 26B-A4B QAT Q4_0 — upstream llama.cpp (commit 02182fc)

`-ngl 99 -fa 1 -ctk q8_0 -ctv q8_0 -t 6 -p 512 -n 128`

| Test | Windows native | WSL2 | CPU-only |
|---|---|---|---|
| pp512 | 1982 t/s | 2048 t/s | 69.7 t/s |
| tg128 | **56.8 t/s** | 47.0 t/s | 13.1 t/s |

### Qwen3.6 35B-A3B IQ4_XS — ik_llama.cpp (commit 022bd00a)

`-ngl 99 --fit 1 --fit-margin 1664 -fa 1 -ctk q8_0 -ctv q8_0 -ub 2048 -t 12 -p 512 -n 128`

| Test | Windows native | WSL2 |
|---|---|---|
| pp512 | 460.9 t/s | 441.3 t/s |
| tg128 | **37.7 t/s** | 26.3 t/s |

## Windows native vs WSL2

PP is within noise. TG is faster on Windows native — ~21% for Gemma 4, ~43% for Qwen3. The
WSL2 GPU-PV layer taxes the memory-bound decode path, and Qwen3 pays more because MoE expert
offload creates frequent GPU↔CPU sync points that each wear the overhead. Gemma 4 is pure-GPU
so it sees less. Run native if you want the speed; WSL2 if you want the Linux tooling.

Both tested in MCDM mode. TCC mode (Windows, no WSL) might claw back a little more on top, but
getting MCDM back afterwards is a registry edit + reboot, so it wasn't worth measuring yet.

## Notes on the knobs

- **Threads:** Gemma 4 wants `-t 6` not `-t 12` — fully GPU-resident, so extra threads only add
  scheduling overhead (~11% better TG at 6). Qwen3 wants `-t 12` because it actually uses the
  cores for expert compute.
- **Batch size:** `-ub 2048` roughly doubles Qwen3 prompt processing vs the 512 default, for a
  ~2 GB compute buffer that's safe at any context. `-ub 4096` gets ~3x PP but evicts too many
  experts at high context. Gemma 4 likes `-ub 1024`.
- **Context size:** bigger `-c` reserves more KV up front. On Qwen3 that pushes more experts to
  CPU and slows every turn, so size it for what you actually use.

## Dual V100 + NVLink

<!-- PLACEHOLDER: dual-V100 NVLink card not built yet. To fill in once the hardware exists. -->

Coming once the dual-card is assembled. Planned comparisons against the single-card numbers
above:

- [ ] Tensor-parallel TG/PP for Qwen3 (`--tensor-split`, NVLink vs PCIe peer copy)
- [ ] Larger models / longer context that won't fit on one 16 GB card
- [ ] Whether NVLink bandwidth actually helps TG, or if it stays memory-bound per-GPU
- [ ] Gemma 4 across two cards (does pure-GPU TP beat single-card, or just add latency)
- [ ] Power draw and thermals under sustained dual-card load
