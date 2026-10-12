# Source and evidence SHA-256 manifest

Immutable production source commit: 691eae48d67789bf798e270cb9cca7790d728d26 (parent 40723492b97983c0c7bc6d441a1bcbace823ffe8). Hashes cover every changed production/test file and every review evidence artifact except this manifest itself. Git hashes are SHA-256 of normalized Git blob bytes; Windows checkout hashes are shown for CRLF-pinned PowerShell files.

## Production and regression source

| Path | Git-content SHA-256 | Windows checkout SHA-256 | Purpose |
|---|---|---|---|
| .github/workflows/f2-acl-source-only.yml | af65c996a3f616b8848989dab678fccdd95f2a20881bdecf2e5af4b3efc88699 | — | Windows PowerShell 5.1 regression/parse/whitespace CI |
| scripts/f2-acl/F2AclIcacls.Runtime.psm1 | d1f4697e6fcb04d8707442e7c0579dc1bd0934c0565d48c5527080af462663e4 | — | F2 G1 source/release implementation or regression |
| scripts/f2-acl/F2_ICACLS_SOURCE_PINS.json | 7e05d48ef25e7cff19d84db151395921b5d89b52b1e2f45b94a84a4778a615ce | — | F2 G1 source/release implementation or regression |
| scripts/f2-acl/Invoke-F2IcaclsProtectedCoordinator.ps1 | 9b8816c941eebaa87aafd597e6bc326d380c7fbb34321ef97ab0c04a4c1ac515 | — | F2 G1 source/release implementation or regression |
| scripts/f2-acl/Invoke-F2ProtectedReleaseUpdate.ps1 | 47953d6124c021b0b0332a37ab0183ea1b544cfb375a78c9a38081f7ca92e4fd | 49afef854aaee2b4501325063ade14e496072aaf74745e1203c2029ce9287744 | Corrected protected release updater |
| scripts/f2-acl/Start-F2ProtectedReleaseUpdate.ps1 | d5141345c4131673206b9679464a4e1e4ebf872fb42213015f32052e474b0f17 | dc342139f4168e624d8554017a560c4c9243767847aaa411bdc6fb349693dfd3 | F2 G1 source/release implementation or regression |
| scripts/f2-acl/Test-F2AclEntrypointArguments.ps1 | c8e9a126d6124fe3067a7ee228eaa897d56b4c66853124aee10f72aca038690d | cb2dca12f721eeff25dfa65978d668a7dbe438aeb5cdc31c74adb682e5484ce0 | F2 G1 source/release implementation or regression |
| scripts/f2-acl/Test-F2AclIcacls.Runtime.ps1 | cb22431c813d6c1a09c8ca04e270c9b1f316e365990e32d9c751cd00d9f3e152 | f4da5c189f226e4b397cc91656ff117f1aab29f7695dc0abfd8f1d5403b4aed5 | F2 G1 source/release implementation or regression |
| scripts/f2-acl/Test-F2AclProtectedReleaseNativeHelper.ps1 | 5e899f1d2a763955e5db49b092570ea0fa2f9e7956722b7c039b326d4fbb507e | d250a1b3ad40f6f78be75dc135857f022ae3eef3b4202aa7988b8ea8d2b894f1 | Exact production C# compile and TEMP-only native test |
| scripts/f2-acl/Test-F2AclProtectedReleaseUpdater.ps1 | e19bed3430cc09a6f9bae49781b944b8eabc89ecd82ab63a4c98d9d3e8bcad45 | a2d93eff1d2e4024db7478cf6f951fb0491d815aed10d6549febd776c6d8a1f2 | F2 G1 source/release implementation or regression |

The candidate v3 manifest pins seven release files; all hashes and the source-pin manifest SHA are unchanged from the prior reviewed candidate:

| Candidate package file | SHA-256 |
|---|---|
| scripts/f2-acl/F2AclCapture.Protocol.psm1 | 42ba4dd5e31d1db64198bb1cee16d519f087a40364dfb4d2696b4a5bd844d728 |
| scripts/f2-acl/F2AclIcacls.Corroboration.psm1 | a52ed86218a0ba0c0801ee6e84a4a5e47c73eda43db78f818b0b12670ad5110b |
| scripts/f2-acl/F2AclIcacls.Runtime.psm1 | d1f4697e6fcb04d8707442e7c0579dc1bd0934c0565d48c5527080af462663e4 |
| scripts/f2-acl/Invoke-F2IcaclsCapture.ps1 | 0b9214c3d6f6e96081b9d86aa8d62087c82527443f2c4b3e7ee09a1ca3dae818 |
| scripts/f2-acl/Invoke-F2IcaclsProtectedCoordinator.ps1 | 9b8816c941eebaa87aafd597e6bc326d380c7fbb34321ef97ab0c04a4c1ac515 |
| scripts/f2-acl/F2_ICACLS_SOURCE_PINS.json | 7e05d48ef25e7cff19d84db151395921b5d89b52b1e2f45b94a84a4778a615ce |
| scripts/f2-acl/Invoke-F2AclReadOnlyCapture.ps1 | bea7cc93710c83d48a8ef9e54af306401694f17f611e696caa856938ca71a19b |

External candidate manifest SHA-256: be98e9101f9171bb1bba59bfa063fc424132e19579b16d75816cec3b345974e2

## Review package and evidence

| Path | Git-content/raw SHA-256 | Purpose |
|---|---|---|
| docs\reviews\f2-g1-protected-release-updater\.gitattributes | ac5c50e1b4b30b27d2a3dcc72a6688fa73e1db467740ca6b619ff6d68d7d6911 | Review/evidence packaging attributes or prior validation evidence |
| docs\reviews\f2-g1-protected-release-updater\DEVELOPER_HANDOFF.md | 4426dfe33b5f3160d9166aee3885eafb6bdc08abcbc473dff02c647fdb182fd7 | Developer handoff |
| docs\reviews\f2-g1-protected-release-updater\F2_G1_PROTECTED_RELEASE_UPDATER_REVIEW.md | ae25e350706eeecacb1a20556faecd913f6a24fc45548d6b312ecf51660b756c | Complete updater/recovery/security review |
| docs\reviews\f2-g1-protected-release-updater\f2-runtime-release-v3.candidate.json | be98e9101f9171bb1bba59bfa063fc424132e19579b16d75816cec3b345974e2 | External candidate manifest; reviewed commit/package root updated |
| docs\reviews\f2-g1-protected-release-updater\evidence\.gitattributes | 5a1fa692c9edb81f75a8d78d062c07ec07445d62537af291e7947d080bf627e2 | Review/evidence packaging attributes or prior validation evidence |
| docs/reviews/f2-g1-protected-release-updater/evidence/.gitattributes | 5a1fa692c9edb81f75a8d78d062c07ec07445d62537af291e7947d080bf627e2 | Review/evidence packaging attributes or prior validation evidence |
| docs/reviews/f2-g1-protected-release-updater/evidence/GIT_DIFF_CHECK.txt | 2bbd4e5423278e6f9371b18867d3f59031064631cf582c85a0c0f37bf980c461 | Whitespace validation result |
| docs/reviews/f2-g1-protected-release-updater/evidence/LOCAL_VALIDATION.txt | 88c57104bfee5ca75b756acd70901a26f11b227241373fdb553d22aeead72afd | Commands and local PS5.1 suite results |
| docs/reviews/f2-g1-protected-release-updater/evidence/NATIVE_COMPILE_REPRO_BEFORE_FIX.txt | 58667d09d1324eb595507fad21d34c898b44da378adfc1d8a8814683e935d273 | Sanitized exact compiler failure evidence before fix |
| docs/reviews/f2-g1-protected-release-updater/evidence/POWERSHELL_PARSER.txt | a64c136e1bd0701caafdd326e791b9ea58b0aeabc5388d996bab48451a3caa60 | Parser results |
| docs/reviews/f2-g1-protected-release-updater/evidence/Test-F2AclCapture.Protocol.stderr.log | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 | Full local Windows PowerShell suite stderr |
| docs/reviews/f2-g1-protected-release-updater/evidence/Test-F2AclCapture.Protocol.stdout.log | 6c1f9bf830939755a19eb077d000364bfca9c5ae0ac21421d60fb216f956450b | Full local Windows PowerShell suite stdout |
| docs/reviews/f2-g1-protected-release-updater/evidence/Test-F2AclEntrypointArguments.stderr.log | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 | Full local Windows PowerShell suite stderr |
| docs/reviews/f2-g1-protected-release-updater/evidence/Test-F2AclEntrypointArguments.stdout.log | 516b847cc7a22a88d764f63f1b5ec63b0c4744fcb0ebcec173fc662bd58d2376 | Full local Windows PowerShell suite stdout |
| docs/reviews/f2-g1-protected-release-updater/evidence/Test-F2AclIcacls.Corroboration.stderr.log | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 | Full local Windows PowerShell suite stderr |
| docs/reviews/f2-g1-protected-release-updater/evidence/Test-F2AclIcacls.Corroboration.stdout.log | c631f9353e41d6ef1b53579de3cd2ded6418d916a2145fdbbc95a60cebc632c7 | Full local Windows PowerShell suite stdout |
| docs/reviews/f2-g1-protected-release-updater/evidence/Test-F2AclIcacls.Runtime.stderr.log | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 | Full local Windows PowerShell suite stderr |
| docs/reviews/f2-g1-protected-release-updater/evidence/Test-F2AclIcacls.Runtime.stdout.log | ed707b9a1d45061005c4d3c15da64c307ae0117efda3d2f00f0e81864d807b18 | Full local Windows PowerShell suite stdout |
| docs/reviews/f2-g1-protected-release-updater/evidence/Test-F2AclProtectedReleaseNativeHelper.stderr.log | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 | Complete native-helper suite stdout/stderr |
| docs/reviews/f2-g1-protected-release-updater/evidence/Test-F2AclProtectedReleaseNativeHelper.stdout.log | a1eafbc35a1722b2ecd039ab91a1e70333fb4687fd658338221939abddbd872b | Complete native-helper suite stdout/stderr |
| docs/reviews/f2-g1-protected-release-updater/evidence/Test-F2AclProtectedReleaseUpdater.stderr.log | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 | Full local Windows PowerShell suite stderr |
| docs/reviews/f2-g1-protected-release-updater/evidence/Test-F2AclProtectedReleaseUpdater.stdout.log | 9c901e950093ad7717e31d8f8a9afac32bde845c2f9e151e4d5d8dae12552202 | Full local Windows PowerShell suite stdout |
| docs/reviews/f2-g1-protected-release-updater/evidence/WINDOWS_CI.txt | 649ca057cd812c1c374466cc541bb9bff39a3dcf5c66a1f6b88410153d4fd81a | Hosted Windows CI run/job/results |
| docs/reviews/f2-g1-protected-release-updater/evidence/WINDOWS_PS51_CORROBORATION.log | c631f9353e41d6ef1b53579de3cd2ded6418d916a2145fdbbc95a60cebc632c7 | Review/evidence packaging attributes or prior validation evidence |
| docs/reviews/f2-g1-protected-release-updater/evidence/WINDOWS_PS51_ENTRYPOINT.log | 516b847cc7a22a88d764f63f1b5ec63b0c4744fcb0ebcec173fc662bd58d2376 | Review/evidence packaging attributes or prior validation evidence |
| docs/reviews/f2-g1-protected-release-updater/evidence/WINDOWS_PS51_PROTOCOL.log | 6c1f9bf830939755a19eb077d000364bfca9c5ae0ac21421d60fb216f956450b | Review/evidence packaging attributes or prior validation evidence |
| docs/reviews/f2-g1-protected-release-updater/evidence/WINDOWS_PS51_RUNTIME.log | ed707b9a1d45061005c4d3c15da64c307ae0117efda3d2f00f0e81864d807b18 | Review/evidence packaging attributes or prior validation evidence |
| docs/reviews/f2-g1-protected-release-updater/evidence/WINDOWS_PS51_UPDATER_RERUN.log | 9c901e950093ad7717e31d8f8a9afac32bde845c2f9e151e4d5d8dae12552202 | Review/evidence packaging attributes or prior validation evidence |
| docs/reviews/f2-g1-protected-release-updater/evidence/WINDOWS_PS51_UPDATER_RERUN.stderr | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 | Review/evidence packaging attributes or prior validation evidence |
| docs/reviews/f2-g1-protected-release-updater/evidence/WINDOWS_PS51_UPDATER.log | 80662c4c4b12e2db1c1da6195d302555cbaccdc71cc5f05d897d7436d9674349 | Review/evidence packaging attributes or prior validation evidence |
