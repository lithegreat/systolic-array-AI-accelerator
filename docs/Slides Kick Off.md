MSMCD Research Lab – Part 1 – AI Accelerator

Dr.-Ing. Paul R. Genssler, Prof. Hussam Amrouch

Technical University of Munich

TUM School of Computation, Information and Technology

Chair of AI Processor Design

Project Content

MC

Status /
Control

Matrix A

Matrix B

Matrix C

B
U
S

Control logic

Systolic Array
Module

D
O
M
P

Triggers for
measurements

Systolic array

Tasks for Students:
▪ Functional Design:

MAC
Unit

MAC
Unit

MAC
Unit

MAC
Unit

1. Design of the accelerator structure.

• Size defined at design-time
• Data preprocessing
• Buffer management

2. Design of a flexible multiply
accumulate (MAC) unit.

3. Verification and testing based on

simulations and FPGA.

4. Embed into neural network C code.

▪ Physical Design: Layout
▪ Test & Evaluation: Performance and power

measurements

2

Timeline (Detailed Discussion on Friday)

17 April

24 April

Group forming and
introduction.

Block Diagram &
Tasks fixed

– Main Tool: Xilinx Vivado
– Main Tool: Synopsys Fusion Compiler

1 May

8 May

15 May

22 May

29 May

Interfaces between
blocks agreed and
implemented.

RTL for FPGA started,
modules have at least
dummy behavior.

Tests for RTL code
fully prepared.

RTL for FPGA code
90% ready, start of
ASIC specific parts.

RTL for FPGA and
integration for FPGA
completed.

5 June

12 June

19 June

26 June

Design runs on
FPGA, Tests on FPGA
started.

FPGA Tests
completed, ASIC-
specific blocks
prepared & integrated.

Synthesis for ASIC
prepared and running
without faults.

Functional tests on
gate level successful.

3 July

10 July

17 July

All specifications
fulfilled on gate level.

Final deliverable and
documentation
prepared.

Final deliverable.

We will offer replacement
dates for 1 and 8 May;
Regarding final deliverable:
see below.

3

Milestones (Detailed Discussion on Friday)

1 May: Documentation – Block diagram and interface description.

15 May: Code + Documentation – Tests defined (code for system level can come later).

12 June: Demonstration – Design running on FPGA.

3 July: Code + Documentation: Specification fulfilled for ASIC.

17 July: Code + Documentation: All source files + documentation + presentation.

All RTL code, documentation, etc. must be delivered via a group specific GitLab project (ideally in

incremental steps, latest to the dates of the milestones).

4

FAQs and Remarks

▪ Additional seminar and shift of dates:

− The dates on 1 May and 8 May will be shifted (details on Friday).
− There will be an additional seminar on entrepreneurship → date will be announced soon.

▪ Attendance for seminars:

− We expect every week for every group a status update (presentation of < 3 minutes per

person+discussion).

− The default should be: All group members join and present their own work.

▪ Usage of AI-Tools and sources from the web is allowed but:

− Has to be declared.
− You must be able to explain every line of code you have written.
Improvement of the design over the summer and before the backend part (first two October weeks!!!)
is possible but without any support from us.
▪ On Fridays we split the course in two groups:

▪

− 9:45 – 11:15: groups without export control restrictions.
− 11:30 – 13:00: groups with export control restriction.

5

Final Deliverable

▪ RTL Design

− Fulfilling the specifications.
− Passing all test.
− Clean synthesizable.
→ Delivered via GitLab

▪ Documentation of design → via GitLab (hint: start from beginning and reuse weekly reporting).
▪ Final Presentation (decision expected in May):

− Most likely (planned but not yet confirmed): “Exhibition”, i.e., flash talk + poster presentation +

demonstration with industry partners with DECS professors.

− Backup: Presentation + demonstration.

6

NDA, License, and Export Control

▪ Export Control:

➢ First check done by TUM based on the declared citizenship.
➢ Passport for persons not under export control will be checked when signing the NDA/License

Agreement form.

▪ You have received an email with

− Link to NDA/license agreements
− The text of the document to be signed.

▪ You need to sign the NDA/license agreement document in the technical introduction session.
▪ Access to tools/PDKs/standard cell libraries will be granted when and for the period needed for the lab.

7

Group Forming

Members of the same group
▪ Must:

➢ Have the same export control (and NDA) category.
➢ Be able to work together efficiently.

▪ Shall:

➢ Have interest in different building blocks.

▪ Form a group now!

➢ Work together today and meet the next few days.
➢ In urgent cases we try to exchange participants between groups.
➢ We fix the groups on Friday (ideally for 1.5 years).

8

