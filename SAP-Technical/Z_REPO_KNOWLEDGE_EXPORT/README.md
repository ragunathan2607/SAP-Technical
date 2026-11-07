# Z_REPO_KNOWLEDGE_EXPORT – SAP package → Markdown knowledge base (ZIP)

`Z_REPO_KNOWLEDGE_EXPORT` reads everything stored in one or more SAP development packages and writes it as
Markdown documentation packed into ZIP files. The result is a self-contained, searchable knowledge base of the
package. You upload the ZIPs to a Markdown-aware documentation or AI assistant tool as they are; there is nothing
to convert by hand.

The program is read-only: it never changes repository objects and never commits.

---

## 1. Install the program

1. Run transaction **SE38**, create the program `Z_REPO_KNOWLEDGE_EXPORT`, type *Executable program*, and save it in a
   local package (`$TMP`) or in your tools package.
2. Paste the full content of `z_repo_knowledge_export.abap` and activate it.
   No text elements or selection texts are needed; they are set in the code.
3. If activation reports an error, note the line number. Every field outside a table key is read dynamically, so release
   differences normally cannot cause syntax errors. The only static dependency is BOPF
   (`/BOBF/CL_FRW_FACTORY`, `/BOBF/OBM_BO_KEY`), which every S/4HANA system has.

## 2. Run it

| Field | Meaning |
| --- | --- |
| Package(s) | One or more packages, ranges or patterns (`ZMM*`) |
| Object type / name filter | Optional: restrict to e.g. `CLAS`, `BOBF`, `DDLS` or to name patterns |
| Include all sub packages | Recursively adds every sub package (default on) |
| Start at top super package | Walks up from the given package to the top super package and extracts that **whole** tree |
| Source code / signatures / DDIC / … | Content switches – all on by default |
| Customizing table contents + max rows | Exports the table **contents** (configuration values) of tables with delivery class C, G, E, S, W |
| BOPF business objects | Complete BO configuration and the implementing classes |
| Used classes/FMs/BOR outside | Also extract every class, interface, function module, program, transaction and BOR object the package uses (code where-used index, superclasses, interfaces, `TYPE REF TO`, BOPF / workflow / Gateway / BAdI / BSP configuration) |
| Used DDIC outside package | Also extract every data element, structure, table, table type and domain the package uses |
| Incl. standard SAP objects | **On (default):** the two options above include standard SAP objects (`CL_*`, `BAPI_*`, `MARA`, `MATNR` …). **Off:** only `Z*`, `Y*` and your own namespaces |
| Reference depth | `1` (default) = objects used **directly** by the package. `2` = also the objects those objects use, and so on. Each level multiplies the volume |
| Max objects outside package | Safety limit (default 5000). When it is reached, ERRORS.md says so |
| Max rows per repository table | Limit for generic table dumps (BOPF, framework tables, …) |
| Documentation ZIPs / Plugin-layout ZIPs | Output layout, see sections 3 and 4 |
| Skill name | Optional; default `sap-pkg-<package>` (lower case, hyphens) |
| Max lines per .md file | Default **1800**. Claude reads files in windows of about 2000 lines, so each file can be read in one go |
| Max MB per ZIP | Default **20 MB** uncompressed per volume (the ZIP itself is much smaller) |
| Max files per ZIP (skill) | Default **190**. claude.ai rejects skill ZIPs with more than **200 files**, so in skill mode many objects are bundled into one file and a new volume starts before 190 files. Ignored for Claude Code plugin output |
| Download to PC / Application server + Directory | Where the ZIPs are written |
| Test run | Runs everything and reports the files, lines and volumes it would produce, but writes nothing. Use it first on a big package |

**Big packages (hundreds of thousands to crores of lines):** run in background (SE38 → *Program → Execute in
Background*) with **Application server** and a directory such as `/tmp/claude`. Then copy the ZIPs with **CG3Y** (or
AL11 / your file transfer tool). Frontend download does not work in background, and dialog processes have a runtime limit.

At the end, the program lists the packages, number of objects, Markdown lines, written ZIP files, and every error or
limitation.

## 3. What you get

```
sap-pkg-zmm-vol-01.zip           volume 1 (one skill)
sap-pkg-zmm-vol-02.zip           volume 2 (only if more than "Max MB per ZIP" or "Max files per ZIP")
...
sap-pkg-zmm-index.zip            master index (only when there is more than one volume)
```

Inside every **claude.ai skill ZIP** (at most 190 files):

```
sap-pkg-zmm-vol-01/
├── SKILL.md                     name, description, how to navigate, object types, index files (< 500 lines)
└── reference/
    ├── INDEX.md                 type | object | description | lines | volume | file + start line
    ├── PACKAGES.md              package hierarchy with descriptions and object counts
    ├── ERRORS.md / STATS.md     (single volume or index skill)
    ├── part-0001.md             many objects per file, each starts with "# TYPE NAME",
    ├── part-0002.md             separated by "---"; at most 1800 lines per file
    └── ...                      objects longer than 1800 lines continue in the next part files
```

Inside the **Claude Code plugin ZIPs** (no file limit) every object has its own file:

```
.../skills/sap-pkg-zmm-vol-01/
├── SKILL.md
└── reference/
    ├── INDEX.md, PACKAGES.md, ...
    ├── CLAS/ZCL_ORDER.md        one file per object ...
    ├── CLAS/ZCL_BIG_part-001.md ... split at 1800 lines, code blocks closed and reopened
    ├── FUNC/Z_MY_FM.md          one file per function module
    ├── BOBF/ZMY_BO.md           BOPF business objects
    ├── DDLS/ZI_ORDER.md         CDS
    └── TABL/ZMM_CONFIG.md       DDIC + configuration values
```

Object names containing `/` are stored with `=` (`/ABC/CL_X` → `=ABC=CL_X.md`).

### Contents per object type

| Type | Content |
| --- | --- |
| Package (DEVC) | Attributes, texts, sub packages, every object with its file, use accesses |
| PROG | Attributes, texts, text pool, full source, screens (header, elements, flow logic), GUI texts, variants, used objects |
| CLAS / INTF | Properties, relations, sub classes / implementers, friends, **declaration of every component with SE24 descriptions** (types, attributes, constants with values, events, methods with full signature and exceptions, aliases), redefinitions, text pool, **source of every include** (sections, CCDEF, CCMAC, CCIMP, CCAU, every method), used objects |
| FUGR / FUNC | Group texts, every include, text pool, screens; one file per function module with signature, parameter texts, RFC/update type, source |
| TABL | Header, technical settings, fields with data elements and texts, foreign keys, indexes, search help assignments, maintenance dialog, **table contents for customizing tables** |
| VIEW, ENQU, DTEL, DOMA, TTYP, SHLP, TYPE | Full dictionary definition, fixed values, keys, parameters, type group source |
| DDLS, DCLS, DDLX, BDEF, SRVD … | Source code. The source table is found automatically by probing the repository source tables |
| **BOBF** | Every `/BOBF/` repository row of the BO key (nodes, associations, actions, determinations, validations, queries, alternative keys, status, authorization …), the **runtime configuration** (every getter and public attribute of `/BOBF/IF_FRW_CONFIGURATION`), and the list of **implementing classes / constants interfaces**. Each of those is extracted in full under `reference/CLAS/` (option *BOPF classes outside pkg*) |
| MSAG | Every message in every language, last change, long texts |
| TRAN | Definition, texts, parameters, authorization values, GUI attributes |
| **Web Dynpro (WDYN)** | Component, controllers and views, methods with signatures, context, events, UI elements and navigation (WDY_* tables); the controller / view **method source code** is rendered as ABAP from the readable WDY source tables; the **assistance class** and every class the component uses are extracted with full method source |
| BOR, workflow, Gateway, enhancements, BAdIs, number ranges, auth. objects, … | Every repository table of the framework that has the object key, found via DD03L. BOR program source, enhancement implementation source, workflow HRS1* / SWD* tables; DPC/MPC and other referenced classes are extracted with full method source |
| **BSP / UI5 (WAPA)** | Every O2* row; page / view / controller layout and event handler code; **every text file of the application from the MIME repository** (UI5/Fiori: `Component.js`, `manifest.json`, controllers, views, fragments, i18n, css …) – one document per file. Images/fonts and generated `Component-preload.js` / `-dbg.js` are listed only |
| **Workflow** | Tasks (HRS1*: texts, method binding, container) and templates: **latest** definition version, step list, **Mermaid flow diagram**, workflow classes / BOR objects used by the steps (also outside the package) |
| **Smart Forms / Adobe forms** | The generated function group = every code node, program line, initialization, global definition |
| **CMOD / SMOD** | Customer exit projects and SAP enhancements; the `ZX*` exit includes are exported as programs |
| **Objects outside the package (incl. standard SAP)** | Every class, interface, function module (single module, not its whole group), program, transaction, BOR object, data element, structure, table, table type and domain the package uses – found via the where-used index, class relations, signatures and BOPF / workflow / Gateway / BAdI / BSP configuration – up to the reference depth; each file's header says why it was extracted and at which depth |
| Any object | TADIR data, SE61 documentation, used objects (where-used index) |

## 4. Use it in claude.ai (skills)

Requirements: a plan with skills, and **Code execution and file creation** switched on
(*Settings → Capabilities*).

1. Open **Settings → Capabilities → Skills** and choose **Upload skill**.
2. Upload `sap-pkg-…-vol-01.zip`. If the extract produced several volumes, upload every volume ZIP **and** the
   `…-index.zip`. Each ZIP is a separate skill.
3. Make sure the skills are switched on.
4. Ask normally, for example *"Which determinations does BO ZMY_BO have and what does the implementing class
   do?"* or *"Explain method ZCL_ORDER->CHECK and every caller in package ZMM"*. Claude picks the skill from
   its description, opens the index, reads the matching files, and greps when needed.

Tips
- claude.ai accepts at most **200 files** per skill ZIP - the program keeps every skill ZIP at 190 files or fewer
  (*Max files per ZIP*). Other upload limits (ZIP size, number of skills) can change and depend on your plan. If an
  upload is rejected, run again with a smaller **Max MB per ZIP** / **Max files per ZIP**, or use the object type /
  sub package filter to split the content.
- Prefer one skill per functional area: run the program once per sub package and give each run its own *Skill name*.
- Claude does not load whole files into its context. It reads SKILL.md, then the index, then only the files it
  needs, so large volumes are fine as long as each upload is accepted.

## 5. Use it in Claude Code (plugin) – best for very large packages

Run with **Claude Code plugin ZIPs**. Every ZIP contains the same root folder:

```
sap-pkg-zmm-marketplace/
├── .claude-plugin/marketplace.json
└── plugins/sap-pkg-zmm/
    ├── .claude-plugin/plugin.json
    └── skills/
        ├── sap-pkg-zmm-vol-01/SKILL.md + reference/...
        ├── sap-pkg-zmm-vol-02/...
        └── sap-pkg-zmm-index/...
```

1. Unzip **all** ZIPs into the same folder. They merge into one marketplace with one plugin that contains every
   volume.
2. In Claude Code:
   ```
   /plugin marketplace add /path/to/sap-pkg-zmm-marketplace
   /plugin install sap-pkg-zmm@sap-pkg-zmm-marketplace
   ```
3. Restart Claude Code if it asks you to. The skills appear under the plugin, and Claude uses them automatically
   when you ask about the package.

Alternative without a plugin: copy the skill folders (`sap-pkg-zmm-vol-01/` …) into `~/.claude/skills/` (personal)
or `.claude/skills/` in a project, or upload the skill-format ZIPs to claude.ai.

Claude Code works directly on the file system, so it handles any size, including crores of lines: it searches
across all volumes with grep and opens only what it needs.

## 6. Sizing guide

| Package size | Recommended run |
| --- | --- |
| < 200,000 lines | Dialog, *Download to PC*, skill ZIP – usually 1 volume |
| 200,000 – 2,000,000 lines | Background, application server; a few volumes + index; claude.ai or Claude Code |
| > 2,000,000 lines (crores) | Background, application server, **Claude Code plugin**; or one run per sub package / object type |

A Markdown line is about 40–60 bytes, so 20 MB holds roughly 350,000–500,000 lines per volume.

## 7. Notes and limits

- **Standard SAP objects:** with *Incl. standard SAP objects* every object the package uses is extracted, up to
  *Reference depth*. Depth 1 is usually enough for Claude to understand the package (it sees every standard class,
  BAPI / function module, table and data element the package touches). Depth 2+ grows very fast (a standard class
  uses hundreds of others) - use it only in background with the Claude Code plugin output, and raise *Max objects
  outside package* deliberately. Standard function modules are exported one by one, not as whole function groups.
- **Not exported:** Fiori Launchpad catalogs / tiles / target mappings (client-specific `/UI2/` customizing);
  business data in application tables (only customizing tables); SAP-generated Gateway runtime metadata (the MPC
  `define` method source describes the model completely); objects used only dynamically (`CALL METHOD (lv_name)`,
  dynamic SQL table names) - the where-used index cannot see them.
- Web Dynpro controller / view method **bodies** are read from the component's WDY source tables and rendered as
  ABAP. If a release keeps that code only in the generated controller classes, the method bodies may be
  incomplete; the method list, signatures and all WDY_* metadata are always present, and anything unreadable
  is listed in `ERRORS.md`.
- The workflow diagram is derived from the definition tables (step table with `NODEID`, connection table with
  predecessor / successor fields). If a release stores them differently, the step list and all raw definition rows
  are still exported, but the diagram may be missing.

- The where-used information is only as current as the system's where-used index (run SAPRSEUB / SAPRSEUC if it
  is out of date).
- Table contents are read in the current client only.
- Objects that no reader knows are still listed with their TADIR data and documentation, and they appear in
  `reference/ERRORS.md`. That file lists everything that could not be read, with the reason.
- The extract contains source code and configuration values. Treat the ZIPs like the system they come from, and
  check your company's rules before you upload them anywhere.
