import hashlib, json, subprocess
from pathlib import Path
repo = Path(r"C:\r97-d3-20261029")
commits = [
("D3.1","7d058899abc1663ff7d4175b5a508532367cd5da"),
("D3.2","709215e338b079457550265887393c247a6f15e8"),
("D3.3","b112384384eee4290d6da6e50abf2f96f4a5c33a"),
("D3.3_DIAG","69ce753f7b34e8815b44063de33fd6470a0b4f61"),
("D3.3_RETAIN","363bfd85134f708406b05eaff8450c98928bab3f"),
("D3.4","406697793ac57fafe1da5ea64359815ff2d2bed7"),
("D3.5","ca48ecdd6c1608118e9f9c6bbac7e2129f5c669a"),
]
paths = [
"game/tests/prototypes/p3_1_r9_2_candidate_impl.gd",
"game/tests/prototypes/p3_1_r9_6r1_candidate_probe.gd",
"game/tests/prototypes/p3_1_r9_6r1_face_interface_patch.gd",
"game/tests/prototypes/p3_1_r9_2_e2e_inputs.jsonl",
]
rows=[]
for label, commit in commits:
    row={"label":label,"commit":commit}
    row["parent"]=subprocess.check_output(["git","rev-parse",f"{commit}^"],cwd=repo,text=True).strip()
    row["tree"]=subprocess.check_output(["git","rev-parse",f"{commit}^{{tree}}"],cwd=repo,text=True).strip()
    row["files"]={}
    for p in paths:
        blob=subprocess.check_output(["git","rev-parse",f"{commit}:{p}"],cwd=repo,text=True).strip()
        data=subprocess.check_output(["git","cat-file","blob",blob],cwd=repo)
        row["files"][p]={"blob":blob,"physical_sha256":hashlib.sha256(data).hexdigest(),"bytes":len(data)}
    rows.append(row)
print(json.dumps(rows,indent=2))
