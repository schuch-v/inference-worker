"""Resolve files from RunPod's Hugging Face model cache."""

import argparse
import os
import sys
from pathlib import Path, PurePosixPath


DEFAULT_CACHE_DIR = Path("/runpod-volume/huggingface-cache/hub")


def get_cache_dir() -> Path:
    """Return the cache root, allowing tests and custom mounts to override it."""

    return Path(os.getenv("RUNPOD_HF_CACHE_DIR", str(DEFAULT_CACHE_DIR)))


def _validate_repo_path(repo_path: str) -> PurePosixPath:
    path = PurePosixPath(repo_path)
    if path.is_absolute() or not path.parts or ".." in path.parts:
        raise ValueError("Repository file path must be relative and stay in the repository")
    return path


def candidate_cache_dirs(model_name: str, cache_dir: Path) -> list[Path]:
    """Return exact and case-insensitive cache directory candidates."""

    cache_name = "models--" + model_name.replace("/", "--")
    candidates = [cache_dir / cache_name]

    if cache_dir.is_dir():
        wanted = cache_name.casefold()
        for child in cache_dir.iterdir():
            if child.is_dir() and child.name.casefold() == wanted:
                if child not in candidates:
                    candidates.append(child)

    return candidates


def find_model_path(
    model_name: str,
    file_in_repo: str = "model.gguf",
    cache_dir: Path | None = None,
) -> Path | None:
    """Find an existing repository file in the newest matching snapshot."""

    repo_path = _validate_repo_path(file_in_repo)
    root = cache_dir or get_cache_dir()

    for model_cache_dir in candidate_cache_dirs(model_name, root):
        snapshots_dir = model_cache_dir / "snapshots"
        if not snapshots_dir.is_dir():
            continue

        snapshots = [path for path in snapshots_dir.iterdir() if path.is_dir()]
        snapshots.sort(key=lambda path: path.stat().st_mtime, reverse=True)

        for snapshot in snapshots:
            candidate = snapshot.joinpath(*repo_path.parts)
            if candidate.is_file():
                return candidate

    return None


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Find a file in the RunPod Hugging Face model cache."
    )
    parser.add_argument("model", help="Hugging Face model ID")
    parser.add_argument("path", help="File path inside the model repository")
    args = parser.parse_args()

    try:
        model_path = find_model_path(args.model, args.path)
    except ValueError as error:
        print(f"Error: {error}", file=sys.stderr)
        return 2

    if model_path is None:
        print(
            "Error: Cached file not found. "
            f"Model='{args.model}', File='{args.path}', Cache dir='{get_cache_dir()}'",
            file=sys.stderr,
        )
        return 1

    print(model_path, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
