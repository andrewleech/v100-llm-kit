# 01, Hardware & driver setup

## The card

Tesla V100-SXM2-16GB. Volta architecture, compute capability 7.0, 16 GB HBM2 at ~900 GB/s.
It's a 2017 datacentre part, fp16 only, no bf16, no fp8, no int8 tensor cores. That memory
bandwidth is what drives token generation speed, and it's the reason the card's still worth it.

<!-- PHOTO: V100 SXM2 card, in the machine and/or on the bench -->

The fp16-only nature drives most of the build decisions. A fair bit of newer-GPU quant advice
leans on bf16 or fp8 tricks that just don't exist here, so don't copy recipes across without
checking they're fp16-friendly.

A V100 SXM2 isn't a normal PCIe card, it's the mezzanine form factor, so it needs either an
SXM2 carrier board or a SXM2-to-PCIe adapter to run in a desktop. If you bought a built machine
from me that's already sorted.

## Driver mode: MCDM (Windows + WSL2)

Skip this whole section if you're on **native Linux**, the standard NVIDIA driver just works.

On Windows the V100 is headless (no display outputs), so the datacentre driver defaults it to
**TCC** mode. WSL2's GPU passthrough can't use TCC, you'll get `Failed to initialize NVML`
inside WSL. The fix is **MCDM** mode (Microsoft Compute Driver Model), which is GPU-PV
compatible. WDDM isn't available on this card (no display engine), so MCDM is the only option
that lets WSL2 see the GPU, and it works fine on Volta.

Check the current mode from a Windows terminal:

```powershell
nvidia-smi.exe        # look at the Driver-Model column, you want MCDM
```

If it reads TCC, flip it to MCDM (this is a registry change + reboot, done once). Then from
inside WSL:

```bash
/usr/lib/wsl/lib/nvidia-smi --query-gpu=name,driver_model.current --format=csv,noheader
# Tesla V100-SXM2-16GB, MCDM
```

### WSL2 gotchas worth knowing

- `nvidia-smi` isn't on `PATH` in WSL, use the full `/usr/lib/wsl/lib/nvidia-smi`.
- WSL2 uses `/dev/dxg` for passthrough, not `/dev/nvidia*`. The latter not existing is normal.
- Don't `apt install` a Linux NVIDIA driver inside WSL, it can't talk to `/dev/dxg` anyway,
  the WSL libs in `/usr/lib/wsl/lib` are what's used.
- `dmesg` showing `dxgk: ... Ioctl failed: -22` at boot is a red herring, ignore it.

### WSL2 networking

If you'll reach the server from Windows or the LAN, set mirrored networking mode in
`C:\Users\<you>\.wslconfig`:

```ini
[wsl2]
networkingMode=mirrored
```

Mirror mode gives WSL2 the same IP as Windows, so `localhost` works from both sides without
port forwarding. Restart WSL after changing it (`wsl --shutdown`).

## Dual V100 + NVLink

<!-- PLACEHOLDER: dual-V100 NVLink PCIe card, future product. -->

A PCIe card mounting two V100s with an NVLink bridge is in the works. It opens up
tensor-parallel inference and models/contexts too big for a single 16 GB card. Setup notes and
[benchmarks](benchmarks.md#dual-v100--nvlink) to follow once it's built.

## CPU and RAM

For Gemma 4 (pure GPU) the CPU barely matters. For Qwen3 it does, the MoE expert offload runs
expert FFN compute on the CPU, so memory bandwidth is the bottleneck there. The reference box is
a Ryzen 9 3900X (Zen 2, AVX2, no AVX-512) with DDR4. A newer CPU with AVX-512 and DDR5 would
lift the Qwen3 TG numbers a fair bit. 48 GB of RAM given to the inference process is comfortable.
