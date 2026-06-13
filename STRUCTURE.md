# Repo + blog structure (planning doc, not published)

Working name: **v100-llm-kit** (rename before publishing if you want something punchier).
Target: `github.com/andrewleech/<name>`, blog post on notes.alelec.net.

## Repo layout

```
v100-llm-kit/
├── README.md                 ← entry point, quick start, links to docs
├── LICENSE                   ← MIT
├── docs/
│   ├── 01-hardware.md        ← what you're buying, MCDM driver setup, photos
│   │                            §dual-V100 NVLink card (PLACEHOLDER — future product)
│   ├── 02-linux-setup.md     ← WSL2 / native Linux build + serve
│   ├── 03-windows-setup.md   ← Windows native build + serve
│   ├── 04-models.md          ← which models, how to pull, sizing
│   ├── 05-claude-code.md     ← point Claude Code at the local server
│   ├── 06-openclaw.md        ← point OpenClaw at the local server
│   └── benchmarks.md         ← measured numbers; §dual-V100 comparison (PLACEHOLDER)
├── scripts/
│   ├── linux/                ← build + serve + download (.sh)
│   ├── windows/              ← build + serve + download (.bat)
│   └── demo/                 ← asciinema recording + gif conversion
├── assets/
│   ├── photos/               ← GPU card photos (YOU to add)
│   ├── casts/                ← .cast recordings
│   └── gifs/                 ← converted gifs
└── releases/                 ← notes on what goes in each GitHub release ZIP
```

## Binary releases (GitHub release assets)

Prebuilt, SM_70 only, so buyers don't need a toolchain. One ZIP per engine per OS:

- `llama.cpp-gemma4-win-sm70.zip`     (upstream, Gemma 4)
- `llama.cpp-gemma4-linux-sm70.zip`
- `ik_llama.cpp-qwen3-win-sm70.zip`   (ik fork, Qwen3 MoE)
- `ik_llama.cpp-qwen3-linux-sm70.zip`

Each ZIP: binaries + the matching serve script + a one-line README pointing back to the repo.

## Blog post

One post telling the story: why V100 in 2026, the MCDM gotcha, two engines for two model
shapes, Windows-vs-WSL2 numbers, Claude Code + OpenClaw running fully local. Embeds the
asciinema casts + a couple of GIFs. Frontmatter tags: [ai, claude, hardware, llm].

Placeholders to fill once available:
- GPU card photos
- dual-V100 NVLink card section + comparative benchmarks
- demo recordings (recording them is part of this task)

## Open items

- [ ] Confirm repo name
- [ ] Record Claude Code demo (what-model + project query)
- [ ] Validate + record OpenClaw
- [ ] Drop in GPU photos
- [ ] dual-V100 NVLink: hardware section + benchmarks (when card exists)
```
