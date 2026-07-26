include engine;
include fixtures;
import json;
import os;

with entry {
    fid = "interlock";
    text = "";
    company = {};
    if not text {
        fx = get_fixture(fid);
        if fx { text = str(fx["proposal"]); }
    }
    result = run_protocol(text, fid, 3, True, company);
    os.makedirs("out", exist_ok=True);
    with open("out/last_run.json", "w") as f {
        json.dump(result, f, indent=2);
    }
    print("OK");
}
