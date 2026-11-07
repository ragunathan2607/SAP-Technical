# SAP-Technical

SAP technical solutions and code: ABAP developments and SAPUI5 apps, organized by area.

## Repository structure

| Folder | Content |
| --- | --- |
| [`SAP-MOC/`](SAP-MOC/) | ABAP developments for SAP EHS Management of Change (MOC) and Issue & Activity Management (`/IAM/`) |
| [`SAP-Technical/`](SAP-Technical/) | General / cross-module ABAP developments (reports, utilities, enhancements, reusable classes) |
| [`SAP-UI5/`](SAP-UI5/) | SAPUI5 / Fiori applications |

Each development lives in its own sub-folder named after its main object (for example
`SAP-MOC/ZMOC_ACT_TEMPLATE_UPLOAD/`), with a `README.md` that describes the purpose, installation and test steps.

## Conventions

* One folder per development, named after the main object (program, class or app ID).
* ABAP source files use the `.abap` extension and the SAP object name as file name.
* Test data and sample files sit next to the source in the same folder.
* Work on a feature branch and merge into `main` through a pull request.

## Index

### SAP-MOC

| Development | Type | Description |
| --- | --- | --- |
| [`ZMOC_ACT_TEMPLATE_UPLOAD`](SAP-MOC/ZMOC_ACT_TEMPLATE_UPLOAD/) | Executable report | Excel upload of IAM / MOC activity templates, code groups, long texts and assignments with transport recording |

### SAP-Technical

*No developments yet.*

### SAP-UI5

*No applications yet.*
