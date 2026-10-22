# GF180 public PDK source inventory

Last reviewed: 2026-10-22

This is a source-level compatibility audit for the
[GF180 backend](../../asic/gf180/README.md), not an implementation or signoff
report. Public upstream directory metadata and text files were inspected at
immutable revisions over read-only network requests. This audit did not
initialize PDK sources or generate compiled libraries, netlists, extraction data
or layout.
The supplied upstream README describes a documentation build, not RTL-to-GDS.

## Source identity

The parent PDK is pinned at
[`de3240d7529a6970437ac3344820aaae7839f215`](https://github.com/google/gf180mcu-pdk/tree/de3240d7529a6970437ac3344820aaae7839f215).
Its Git tree, not the nested repositories' current branch heads, defines:

| Component | Path relative to PDK | Pinned nested revision |
| --- | --- | --- |
| 7-track standard cells | `libraries/gf180mcu_fd_sc_mcu7t5v0/latest` | `43beb45e4d323a76239de436db2df6732e9a689b` |
| 9-track standard cells | `libraries/gf180mcu_fd_sc_mcu9t5v0/latest` | `3781fd2951da6e3dc4600e52d997398a9463caeb` |
| Primitives / physical verification | `libraries/gf180mcu_fd_pr/latest` | `9f992d5a9186d1f7820c58f039c484ad35b2edea` |
| I/O | `libraries/gf180mcu_fd_io/latest` | `2aeec51ea2824b6cc0b396acfc39f4535f40b23a` |
| Building-block SRAM | `libraries/gf180mcu_fd_bd_sram/latest` | `6a03b4584ffd90905f8a3bdc0327da173d3c8f69` |
| SRAM macro IP | `macros/gf180mcu_fd_ip_sram/latest` | `9c411928870ce15226228fa52ddb6ecc0ea4ffbe` |
| PDK build dependency | `third_party/open-source-pdks` | `6658edd208f5b566be504f016477a7cb04a78cb8` |

The macro-IP revision matches the existing standalone `vendor/sram` gitlink;
the current SRAM build/simulation scripts still use that standalone checkout.
I/O, building-block SRAM and the build dependency were identified by gitlink;
their contents were not audited in this pass.

## Verified available sources

| Source | Verified observation | Backend implication |
| --- | --- | --- |
| Standard-cell Liberty | Both libraries contain 15 corner headers/templates: five PVT points each for nominal 1.8 V, 3.3 V and 5 V families; actual cell groups are separate corner fragments under `cells/`. | Actual 1.8 V timing sources exist, but compiling a corner header alone would create an empty library. |
| Technology LEF | Each standard-cell library has 12 technology LEFs covering multiple metal-count/top-metal options. | Routing geometry/site source exists; it is not automatically an FC technology file. |
| Cell physical/logical views | The inspected 7-track `cells/buf` directory includes per-drive LEF, GDS, CDL and functional/behavioral Verilog. | Source data can support library preparation; a complete cell-by-cell view-consistency check is still needed. |
| Physical-only cell families | The 7-track tree includes `antenna`, `endcap`, `fill`, `fillcap` and `filltie`. | Use actual library cells when designing finishing/PG adapters; no insertion strategy is qualified yet. |
| SRAM | The PDK pins the same macro-IP source already used by the project. | Reuse the existing controller and library helpers, not an independently updated macro. |
| KLayout verification | Primitive sources include DRC, LVS, antenna and density deck entry points and runner scripts. | Public rule sources are available; execution, coverage and completion/pass parsing remain unverified. |

Evidence:

- [7-track Liberty directory](https://github.com/google/globalfoundries-pdk-libs-gf180mcu_fd_sc_mcu7t5v0/tree/43beb45e4d323a76239de436db2df6732e9a689b/liberty)
  and [9-track Liberty directory](https://github.com/google/globalfoundries-pdk-libs-gf180mcu_fd_sc_mcu9t5v0/tree/3781fd2951da6e3dc4600e52d997398a9463caeb/liberty).
- [7-track technology directory](https://github.com/google/globalfoundries-pdk-libs-gf180mcu_fd_sc_mcu7t5v0/tree/43beb45e4d323a76239de436db2df6732e9a689b/tech)
  and [9-track technology directory](https://github.com/google/globalfoundries-pdk-libs-gf180mcu_fd_sc_mcu9t5v0/tree/3781fd2951da6e3dc4600e52d997398a9463caeb/tech).
- [Representative cell views](https://github.com/google/globalfoundries-pdk-libs-gf180mcu_fd_sc_mcu7t5v0/tree/43beb45e4d323a76239de436db2df6732e9a689b/cells/buf).
- [Public DRC directory](https://github.com/google/globalfoundries-pdk-libs-gf180mcu_fd_pr/tree/9f992d5a9186d1f7820c58f039c484ad35b2edea/rules/klayout/drc)
  and [LVS directory](https://github.com/google/globalfoundries-pdk-libs-gf180mcu_fd_pr/tree/9f992d5a9186d1f7820c58f039c484ad35b2edea/rules/klayout/lvs).

## Voltage compatibility: a source-level match exists

Both TT standard-cell Liberty headers explicitly state `nom_voltage : 1.8`,
`nom_temperature : 25`, `nom_process : 1`, `time_unit : 1ns`,
`voltage_unit : 1V` and `capacitive_load_unit(1, pf)`.
The five 7-track 1.8 V-family headers were checked individually:

| Corner suffix | Voltage (V) | Temperature (C) | Process number |
| --- | --- | --- | --- |
| `tt_025C_1v80` | 1.80 | 25 | 1 |
| `ss_125C_1v62` | 1.62 | 125 | 1 |
| `ss_n40C_1v62` | 1.62 | -40 | 1 |
| `ff_125C_1v98` | 1.98 | 125 | 1 |
| `ff_n40C_1v98` | 1.98 | -40 | 1 |

These match the five existing SRAM characterization points in the
[library helper](../../asic/gf180/scripts/libraries/sram.tcl).
The [7-track TT header](https://github.com/google/globalfoundries-pdk-libs-gf180mcu_fd_sc_mcu7t5v0/blob/43beb45e4d323a76239de436db2df6732e9a689b/liberty/gf180mcu_fd_sc_mcu7t5v0__tt_025C_1v80.lib)
and [9-track TT header](https://github.com/google/globalfoundries-pdk-libs-gf180mcu_fd_sc_mcu9t5v0/blob/3781fd2951da6e3dc4600e52d997398a9463caeb/liberty/gf180mcu_fd_sc_mcu9t5v0__tt_025C_1v80.lib)
also map `VDD`/`VNW` to the corner supply and `VSS`/`VPW` to zero.
That does not prove body/well connectivity: the representative cell LEF
exposes VDD/VSS, so the physical tie strategy must be verified separately.

There is no demonstrated need to change the SRAM to 3.3 V just to obtain
matching standard-cell timing sources. This does **not** establish 50 MHz
logic timing, SRAM timing closure, operating limits/reliability, power integrity,
or compatibility with the surrounding SoC's voltage domain.

## Experimental candidate, not an approved fabrication target

For the next library-preparation experiment, use **7-track, nominal 1.8 V,
five routing metals, 9K top metal** as a candidate:

- It has the five matching SRAM/standard-cell PVT points above.
- The inspected `gf180mcu_5LM_1TM_9K_7t_tech.lef` declares site
  `GF018hv5v_mcu_sc7`, 0.56 x 3.92 um, `DATABASE MICRONS 2000` and
  `MANUFACTURINGGRID 0.0050`.
- Its actual routing layers are **Metal1 through Metal5**, not six layers
  inferred by adding the numbers in the filename. Metal1/3/5 are horizontal;
  Metal2/4 are vertical.
- The corresponding 9-track source has site `GF018hv5v_green_sc9`,
  0.56 x 5.04 um, with the same stated precision/grid.
- The primitive DRC runner documents option **C** as five metals, 9K top metal,
  MIM option B. This is a candidate alignment, not a validation of the runset.

This candidate is not wired into the approved site configuration. Cell-area
closure, SRAM placement, MIM/process options, SoC compatibility and course
acceptance are still open. The 7-track row is shorter, but that alone does not
prove better final area or timing. Do not set `interface_approved=1` on this basis.

**Extraction warning:** both inspected technology LEFs explicitly say:
“This Techfile contains not correct Parasitic Information” and instruct use of
appropriate parasitic files. Do not derive qualified STA/RC corners from their
placeholder capacitance/resistance values. The source LEF's 2000 DBU/um also
does not prove the precision of an as-yet-unbuilt standard-cell NDM.

## Conversion and genuinely unresolved integration work

| Input/work | Status after this audit | Next action |
| --- | --- | --- |
| Standard-cell timing DBs | Five-corner assembly/compilation/independent readback scripts and offline tests implemented; licensed execution not performed. | Run the [standard-cell library workflow](../../asic/gf180/README.md#standard-cell-db-preparation-experimental) on Eikon, then qualify its actual LC results. |
| Standard-cell NDM and FC technology | Technology LEFs/cell views available; no usable FC technology/NDM package verified in inspected paths. | Locate an approved package or prepare and validate one with licensed tools; do not pass LEF as `tech_file`. |
| SRAM NDM | Macro sources available; FC-compatible physical library remains unfinished. | Build against the same selected technology/precision as standard cells, then compare timing panes. |
| RC extraction and layer mapping | No qualified FC extraction corner/map established by this audit. | Inspect additional upstream/tool collateral or obtain the approved stack-specific extraction setup. “Not verified” is not proof the entire public PDK lacks it. |
| PG, body ties and finishing | Real cell families identified; no qualified adapters. | Implement against the chosen geometry/cells and verify all supplies, legality, density and antenna repair. |
| DRC/LVS/antenna/density | Public KLayout sources exist; no execution or full-rule qualification. | Validate stack switches, model/deck dependencies, coverage, completion and report parsing before connecting the signoff adapter. |
| Independent STA | Timing sources exist; extracted multi-corner checks are not implemented/verified. | Prepare matching SDC/PVT/RC setup and fail on unconstrained paths and electrical violations. |

## Read-only local inspection

[inspect_pdk.tcl](../../asic/gf180/scripts/inspect_pdk.tcl) uses Tcl and Git only,
does not fetch dependencies, invoke EDA tools, write files or require licenses.
It inspects an already-initialized checkout at the parent-pinned revision.
An absent, changed or incomplete required checkout is an explicit error,
not an empty successful inventory.

Initialize on Eikon as documented in the [flow guide](../../asic/gf180/README.md).
For this audit, initialize these nested paths at the PDK-pinned revisions:

```bash
git -C asic/gf180/vendor/pdk submodule update --init --checkout -- \
    libraries/gf180mcu_fd_sc_mcu7t5v0/latest \
    libraries/gf180mcu_fd_sc_mcu9t5v0/latest \
    libraries/gf180mcu_fd_pr/latest \
    macros/gf180mcu_fd_ip_sram/latest
tclsh asic/gf180/scripts/inspect_pdk.tcl
```

The checker verifies clean checkout identities, the five 1.8 V-family
standard-cell and SRAM metadata points, nonempty cell-view inventories,
technology LEF grid/site/layer metadata and named public deck sources.
Its success marker means **source inspection only**, not full cell-view
equivalence, correct extraction, deck completeness or physical signoff.
It intentionally requires both standard-cell libraries for this comparative
inventory; a final implementation need not use both.

On a machine without initialized collateral, source-only unit tests remain useful:

```bash
tclsh asic/gf180/tests/pdk.test.tcl
```

The unit tests use synthetic text/source-metadata fixtures, not generated
netlists, reports, compiled libraries or GDS. Live in-memory checks also verified
the Liberty parser against both pinned TT libraries and the technology parser
against both five-metal/9K LEFs, including exact sites, directions, grid and
precision. The full offline inventory cannot pass here until the required
nested sources are initialized.

Follow the [NDA-safe handling policy](../guides/nda_file_handling.md):
all generated implementation/library/signoff outputs remain on Eikon.
