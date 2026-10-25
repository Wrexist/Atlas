# Prints the render matrix for exercise-anim-render.yml: the generated specs in priority order (priority.txt first,
# then alphabetical), sliced to one batch and dealt round-robin into 20 shards.
# env: BATCH, BATCH_SIZE, SLUGS (comma list overrides the batch)
import json, os

HERE = os.path.dirname(os.path.abspath(__file__))
SHARDS = 20


def ordered():
    have = sorted(f[:-5] for f in os.listdir(os.path.join(HERE, "specs", "gen")) if f.endswith(".json"))
    with open(os.path.join(HERE, "priority.txt")) as f:
        first = [line.strip() for line in f if line.strip() in have]
    return first + [s for s in have if s not in first]


def main():
    slugs = [s.strip() for s in os.environ.get("SLUGS", "").split(",") if s.strip()]
    if not slugs:
        size = int(os.environ.get("BATCH_SIZE", 60))
        start = int(os.environ.get("BATCH", 0)) * size
        slugs = ordered()[start:start + size]
    shards = [{"id": i, "slugs": slugs[i::SHARDS]} for i in range(SHARDS) if slugs[i::SHARDS]]
    print(json.dumps(shards, separators=(",", ":")))


if __name__ == "__main__":
    main()
