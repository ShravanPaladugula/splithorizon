include drafts;
import os;
with entry {
    print("CACHE_DIR", CACHE_DIR);
    print("exists", os.path.exists(CACHE_DIR + "/launch.json"));
    print("cwd", os.getcwd());
    c = load_fixture_cache("launch");
    print("keys", list(c.keys()) if c else []);
    if c {
        print("title", c.get("world", {}).get("title", "?"));
    }
}
