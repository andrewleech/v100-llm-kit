# Release assets

Each GitHub release ships prebuilt, **SM_70 (V100) only** binaries so buyers don't need a
toolchain. One ZIP per engine per OS.

| Asset | Engine | Model | OS |
|---|---|---|---|
| `llama.cpp-gemma4-win-sm70.zip` | upstream llama.cpp | Gemma 4 | Windows native |
| `llama.cpp-gemma4-linux-sm70.zip` | upstream llama.cpp | Gemma 4 | Linux / WSL2 |
| `ik_llama.cpp-qwen3-win-sm70.zip` | ik_llama.cpp | Qwen3 | Windows native |
| `ik_llama.cpp-qwen3-linux-sm70.zip` | ik_llama.cpp | Qwen3 | Linux / WSL2 |

## ZIP contents

```
<engine>-<model>-<os>-sm70/
├── bin/                    ← llama-server, llama-bench, llama-cli (+ DLLs/libs)
├── serve-<model>.{sh,bat}  ← the matching serve script
├── download-models.{sh,bat}
├── qwen3-template-patched.jinja   ← Qwen ZIPs only
└── README.txt              ← one-liner pointing back to the repo
```

## Build provenance (record per release)

- upstream llama.cpp commit: `02182fc` (Gemma 4 build tested here)
- ik_llama.cpp commit: `022bd00a` (Qwen3 build tested here)
- CUDA: 12.8 (Windows), 12.6 (Linux) — both 12.x for SM_70
- Build flags: `-DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=70 -DGGML_CUDA_FORCE_MMQ=ON`

## TODO for packaging

- [ ] Script to assemble each ZIP from a built tree (collect bin/ + DLLs + serve script)
- [ ] Confirm which CUDA runtime DLLs must ship in the Windows ZIPs vs rely on the installer
- [ ] Checksums in the release notes
