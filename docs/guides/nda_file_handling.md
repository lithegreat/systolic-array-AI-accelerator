# NDA-Safe File Handling

These rules apply to all contributors and AI agents working with project files,
especially files produced by proprietary EDA/backend flows.

## Storage and sharing

- Keep all generated files exclusively on Eikon machines. Do not copy, sync,
  upload, attach, or otherwise transfer generated outputs elsewhere.
- LRZ GitLab is the only permitted remote repository or sharing destination for
  project files. Do not use GitHub, personal storage, public hosting, or other
  external services.
- Push only human-authored `.tcl` and similar reproducible flow/control files
  to LRZ GitLab. Never push generated outputs.
- GDS submission is local only. Do not commit, push, upload, or attach GDS.

## Never commit or share

Do not commit, push, upload, or attach:

- GDS or extracted parasitics;
- binary files;
- logs, screenshots, or reports;
- any other generated files or outputs.

Keep all output-generation steps reproducible. Document the commands, inputs,
and steps needed to recreate outputs instead of sharing the outputs themselves.
Do not stage restricted outputs, even temporarily.

## Agent checks

Before running a flow that generates files, confirm it is running on an Eikon
machine and its outputs will stay there. Before staging or pushing, inspect the
files being included and exclude generated or disallowed files. If the machine,
file type, or destination is uncertain, do not generate or transfer the files;
ask the user for clarification.
