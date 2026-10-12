# Review artifact manifest

Source correction: `e5a66a7558c027e54b1510e7197d6e3a331cff19`  
Source parent: `bd14a1908085065f08d3c62e4dd17fa3203a53ff`  
Branch: `fix/f2-g1-ps51-entrypoint-release`

All SHA-256 values below are full raw file digests over the checked-out bytes. The production source commit is the release identity. The review-only docs commit that will contain this manifest does not change production package bytes.

## Changed production source and test files

| File | Purpose | SHA-256 |
|---|---|---|
| `.github/workflows/f2-acl-source-only.yml` | Windows PS 5.1 source-only suite and parser CI | `ebfc37f9e9973d7eaaba6859d5ec0505cd305ac13896a40cc79cf5498ad863f5` |
| `scripts/f2-acl/F2_ICACLS_SOURCE_PINS.json` | Current launcher/coordinator pins; historical collector-base identity retained | `0caa7a421a190f11351abadb2f78e3569f1287a1b38f09d62932a0caa8c3b5bb` |
| `scripts/f2-acl/Invoke-F2IcaclsCapture.ps1` | Fixed standard-token launcher argument handling | `0b9214c3d6f6e96081b9d86aa8d62087c82527443f2c4b3e7ee09a1ca3dae818` |
| `scripts/f2-acl/Invoke-F2IcaclsProtectedCoordinator.ps1` | Fixed protected coordinator argument handling | `e965823752518edfcac7ed50bd49bf489f6d924fa404e41138266857ea41b624` |
| `scripts/f2-acl/Test-F2AclEntrypointArguments.ps1` | Inert real-PS5.1 synthetic entrypoint invocation regression | `79c5622f1cb2283abc0892a57e94cec3fe1778d7abe3e1ba404f9e78fa1eb477` |
| `scripts/f2-acl/Test-F2AclIcacls.Runtime.ps1` | Static production entrypoint contract checks; runtime tests remain synthetic | `0801c2c5163c8e4d3c05c998d91ebd74b7fcca931399ac5b05f9d7e581b27b1f` |

## Seven-file release package

The unchanged package members, source pins, external v2 manifest contract, baseline identities and full digests are listed in `README.md` and `approved-release-v2-candidate.json`.

## Review and validation evidence

| File | Purpose | SHA-256 |
|---|---|---|
| `README.md` | Defect, source lineage, test report, old/new release comparison, upgrade threat model and owner gates | `5723f62f8f2d45e70aa7e2dc1781fa223635afb5a40311f499c35e019c3d2bb2` |
| `approved-release-v2-candidate.json` | Candidate external v2 release manifest for source commit e5a66a; not installed/trusted | `8ef5920f3c3c3c789b0c9af7314843437dbb57741ad29f78d57beabb43050d96` |
| `validation-ps51.log.txt` | Complete Windows PowerShell 5.1 regression suite output and diff-check result | `041ba6d15d7763b435242f78bf62c1c441eddb26991e768276a13d14d30611c9` |
| `parser-ps51.log.txt` | Independent parser sweep executed by Windows PowerShell 5.1 | `d9d670daf60446a34bd3e35eec457ba584e7a2923cf2e927dcf2444a6fda9d48` |
| `candidate-manifest-validation-ps51.log.txt` | Actual production disk-loader and seven-file source validator output | `8ba0c29239db3b376ed8453dad28bc9fa7b7525a5628fea16c88d060b45aae8a` |
| `legacy-create-only-installer-synthetic.log.txt` | Failed historical installer fixture retained transparently; no protected paths written | `5fde9004220b1bd90c7a2b5fa845844516f7f0524dc8bb1cb0446639ef104444` |
| `Test-CandidateReleaseManifest.ps1` | Reproducible candidate manifest verification through actual module functions | `2fc6759733f9d48a91ff70675207acdf458908ef9702b2b3002be600b2337c3b` |
| `Test-TrackedPowerShellParse.ps1` | Reproducible PS 5.1 parser sweep for tracked F2 PowerShell files | `61522bc13eb67c7b9fe8ea6e37b2a50f61b65ac1201eb6f4005b1d383ecda503` |

Exact local commands, process exit codes, assertion counts and limitations are in the logs and `README.md`. GitHub Windows CI is linked from the published draft pull request after the workflow completes. This manifest intentionally does not hash itself.
