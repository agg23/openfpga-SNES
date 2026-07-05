# Builds one or more bitstream variants and installs the bit-reversed .rev
# files into pkg/pocket/Cores/agg23.SNES/.
#
# Usage: build.sh <variant>... | all
#   variants: ntsc pal ntsc_spc none none_pal

usage() {
  echo "Usage: build.sh <variant>... | all" >&2
  echo "  variants: ntsc pal ntsc_spc none none_pal" >&2
  exit 1
}

rev_name() {
  case "$1" in
    ntsc | none) echo "snes_main.rev" ;;
    pal | none_pal) echo "snes_pal.rev" ;;
    ntsc_spc) echo "snes_spc.rev" ;;
    *) return 1 ;;
  esac
}

[[ $# -ge 1 ]] || usage

if [[ ! -f generate.tcl || ! -d projects ]]; then
  echo "Run from the repository root (generate.tcl not found)" >&2
  exit 1
fi

variants=("$@")
if [[ "$1" == "all" ]]; then
  variants=(ntsc pal ntsc_spc)
fi

for v in "${variants[@]}"; do
  rev_name "$v" > /dev/null || usage
done

for v in "${variants[@]}"; do
  out="$(rev_name "$v")"
  echo "=== Building variant '$v' -> pkg/pocket/Cores/agg23.SNES/$out ==="
  quartus_sh -t generate.tcl "$v"

  # The Pocket expects the RBF with the bits of each byte reversed
  python3 - projects/output_files/snes_pocket.rbf "pkg/pocket/Cores/agg23.SNES/$out" <<'EOF'
import sys
src, dst = sys.argv[1], sys.argv[2]
table = bytes(int(f"{i:08b}"[::-1], 2) for i in range(256))
with open(src, "rb") as f:
    data = f.read()
with open(dst, "wb") as f:
    f.write(data.translate(table))
print(f"Wrote {dst} ({len(data)} bytes)")
EOF
done
