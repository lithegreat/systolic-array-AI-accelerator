# NDA-Safe File Handling

Follow these rules for all project work involving generated files, backend
outputs, and sharing. They apply to human contributors and AI agents.

## Storage and sharing

- Keep all generated files exclusively on Eikon machines. Do not copy, upload,
  sync, attach, or otherwise transfer generated outputs elsewhere.
- LRZ GitLab is the only permitted remote repository or sharing destination.
  Do not push project files to GitHub, public hosting, personal storage, or
  other external services.
- Push only project-approved source, configuration, and flow-script files
  (such as `.tcl`) to LRZ GitLab. Do not push generated output files.
- GDS files are submitted locally. Never commit or push GDS.

## Files that must not be shared or committed

Do not commit, push, upload, or attach:

- GDS or extracted parasitics;
- binary files;
- logs, screenshots, or reports;
- any other generated files or outputs.

Keep outputs reproducible: document the commands, inputs, and steps needed to
regenerate them rather than sharing the generated files. Do not place restricted
outputs in the repository, even temporarily for staging or review.

## Agent procedure

Before running a flow that generates files, confirm the work is on an Eikon
machine and that its outputs will remain there. Before staging or pushing,
inspect the files being included and exclude all generated or disallowed files.
If the machine, file type, or destination is uncertain, do not generate or
transfer the files; ask the user for clarification.
