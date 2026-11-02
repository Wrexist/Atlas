# Prints the render matrix for exercise-anim-render.yml: the generated specs in priority order (priority.txt first,
# then alphabetical), less those already on the exercise-videos branch, sliced to one batch and dealt round-robin
# into 20 shards. Skipping rendered clips keeps batches stable as templates add exercises mid-order.
# env: BATCH, BATCH_SIZE, SLUGS (comma list overrides the batch), DONE (path to the branch's index.txt)
import json, os

HERE = os.path.dirname(os.path.abspath(__file__))
SHARDS = 20


def ordered():
    have = sorted(f[:-5] for f in os.listdir(os.path.join(HERE, "specs", "gen")) if f.endswith(".json"))
    with open(os.path.join(HERE, "priority.txt")) as f:
        first = [line.strip() for line in f if line.strip() in have]
    return first + [s for s in have if s not in first]


def rendered():
    path = os.environ.get("DONE", "")
    if not path or not os.path.exists(path):
        return set()
    with open(path) as f:
        return {line.strip() for line in f if line.strip()}


def main():
    slugs = [s.strip() for s in os.environ.get("SLUGS", "").split(",") if s.strip()]
    if not slugs:
        size = int(os.environ.get("BATCH_SIZE", 60))
        start = int(os.environ.get("BATCH", 0)) * size
        done = rendered()
        slugs = [s for s in ordered() if s not in done][start:start + size]
    shards = [{"id": i, "slugs": slugs[i::SHARDS]} for i in range(SHARDS) if slugs[i::SHARDS]]
    print(json.dumps(shards, separators=(",", ":")))


if __name__ == "__main__":
    main()
