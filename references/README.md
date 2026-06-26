# References

Vendor datasheets and reference material for the V100 hardware, kept here so the
specs survive even if the original download links go away.

| File | Hardware | Notes |
|---|---|---|
| `TNS-2SXM2-4P54-300G-spec-v1.3.pdf` | TNS-2SXM2-4P54 dual-SXM2 NVLink baseboard | 2x SXM2 V100, NVLink NVHS 300GB/s, 4x SlimSAS SFF-8654 PCIe x16 uplink to the host. Vendor spec sheet Ver 1.3 (Chinese). Original filename: `TNS-2SXM2-4P54+300G+规格书+Ver1.3.pdf` |
| `TNS-2SXM2-4P54-datasheet-EN.pdf` | TNS-2SXM2-4P54 dual-SXM2 NVLink baseboard | English datasheet for the same board. Original filename: `TNS-2SXM2-4P54_datasheet_EN.pdf` |

Binary files in this repo (PDFs, images) are stored with Git LFS. See
[`.gitattributes`](../.gitattributes). After cloning, run `git lfs pull` if the
files come down as small pointer text instead of the real content.
