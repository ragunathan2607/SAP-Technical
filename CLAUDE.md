# Instructions for Claude

## Pushing code

When the user says "push" (git push, push the code, ...):

* Push to the branch **`SAP-Technical`** of `ragunathan2607/SAP-Technical`. It is the main working branch;
  do not create other branches and do not push to `main`.
* Put each new development into a **new folder** named after its main object (program, class, app ID), e.g.
  `SAP-Technical/Z_MY_REPORT/`, with the source files and a `README.md` (purpose, installation, test).
* Choose the area folder by topic:
  * `SAP-MOC/` – EHS Management of Change / Issue & Activity Management (`/IAM/`, `/MOC/`, `ZMOC*`)
  * `SAP-Technical/` – general / cross-module ABAP developments
  * `SAP-UI5/` – SAPUI5 / Fiori apps
* Add the new folder to the index table of the area `README.md` and of the root `README.md`.
* ABAP sources: `.abap` extension, SAP object name as file name.
