# R9.4 Source and Evidence Identities

| Candidate | R9.3 baseline | Tested R9.4 source | Direct parent | Current draft PR HEAD | Implementation SHA-256 | Probe SHA-256 |
|---|---|---|---|---|---|---|
| A | ce6d14d5c3d465ac5477e54354f2d1219171f6f0 | f0c93415dd56886a1c05ff2e6a1340e420f22c59 | d5903242e41642a2633e18dc181c4389188c65b2 | b41dc7207fae3911ecd7b082850535b7e965db5b | 970fe99f192ea2a3fea3e682072ed3562e6f57c843561dd4440e46381a384d8a | a954024ff7494bdedf089b345c58cff8bf6202c99307dbb1a6a0597fee6f9baf |
| C | 5def207d7b1cff8d7f70476f1221c7b9c5771e27 | af4d6027d9d57c9f2b8023aa27b31d2dd2dcedf2 | 5def207d7b1cff8d7f70476f1221c7b9c5771e27 | 2cbe572a1fd1e5ebf871e9b43b515ef2522f38c5 | 7072f39b2c48dcb38048e2ee3d1687baa9377bcc99ca8250c2c0f84cff17d24 | bffa4ebb299ecfadc412ca23a19d3cecaba6d2f9b8d00a32e37322e965174d8c |
| D | 51744eebf17646ca52612936146adeb0f9db001b | 6ea04229b5ff06090f346c8749c1f5a53994227c | 51744eebf17646ca52612936146adeb0f9db001b | 464087947da00a45090a289ade4917882ce0ada5 | a33b464ea569f54fb39b72d2198fa971796c0cb5370a64a9696362cd0313f2a6 | 09d80b8d99c10778ca33028811270e03547b6214021c0d7d86cc7e169b5826fb |

Tested-source commits precede documentation-only evidence commits in the candidate PRs. Physical source hashes and Git blob IDs are recorded in each candidate report. Candidate branches change only isolated prototype implementation/probe files plus evidence/report files.

Manifest SHA-256: 1610c535f98a11e26ca1890c0d99addf4316fbcaa7ec9cdb7dfaa71cf5bb3972
Godot: 4.7.2.stable.official.ed1daf0bf
Godot executable SHA-256: c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643
Comparison base: bench/p3-1-r9-3-comparison at d114b17be4174057aa1d42aa32892d21fac45959. PR #185 and candidate PRs #182–#184 remain unchanged.
