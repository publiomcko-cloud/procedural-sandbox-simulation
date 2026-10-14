# F2 G1 source-pin v2 migration candidate

Status: SOURCE_ONLY / NO RELEASE AUTHORIZATION

Parent: `6520528971bf9d2f7028c89319b660a13c538b55`

## Distinct trust roles

* Retained baseline: immutable v1 capture and evidence provenance. The old collector digest `bea7cc93710c83d48a8ef9e54af306401694f17f611e696caa856938ca71a19b` and protocol-module digest `42ba4dd5e31d1db64198bb1cee16d519f087a40364dfb4d2696b4a5bd844d728` remain unchanged, and original v1 manifests are retained byte-for-byte.
* Active source: exact reviewed raw-mask correction, protocol-module Windows digest `cbeb608ccc4395f7944cca4fb84a7095219930de7a9bd4643fe4b0240dfd3cce`. The separately pinned corroboration module uses Git-representation SHA-256 `12232e77b8b88638b6ef20e3d8bfd652a891277c715e40ec75c554074de60f1e` (the module currently uses LF, with no explicit eol rewrite for *.psm1).
* v2 contract: explicit `-PinContractVersion 2` in `Test-F2IcaclsSourcePins`. Legacy v1 remains its default. Fail-closed checks require the original legacy manifest digest and both baseline source hashes, while active code uses independent hashes.
* Source-only tests: protocol and corroboration suites exercise the v2 current/historical split, an explicit legacy mismatch, a forged baseline pin, and a mismatched v2 manifest digest. Existing synthetic v1 fixtures remain supported.

## Not activated

The collector launcher, installed v2/v3 packages, updater, runtime, candidate v3 JSON, and historical evidence are NOT changed. The source-only v2 contract is not an approved release manifest and cannot be used to activate the installed runtime. A future, separately authorized release design must version the runtime package schema and updater contracts (currently hard-pinned to seven v3 files and v1 source pins), bind exact future commit/package hashes without circularity, and obtain separate Windows validation and independent source-security acceptance before any CI or elevated operation.

No UAC, ACL mutation, protected-source access, VM/G: operation, CI, deployment, or merge is authorized by this commit.
