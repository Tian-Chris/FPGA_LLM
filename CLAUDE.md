## Workflow Orchestration

### 1. Plan Node Default
- Enter plan mode for ANY non-trivial task (3+ steps or architectural decisions)
- If something goes sideways, STOP and re-plan immediately – don't keep pushing
- Write detailed specs upfront to reduce ambiguity
- **Zero Assumptions Rule:** NEVER execute on assumptions. If RTL requirements, clock domains, state machine transitions, or interfaces are ambiguous during planning, pause and ask the user for clarification.

### 2. Sequential Subagent Strategy (Context Protection)
- Use a single subagent sequentially to protect the main agent's context window
- Pause main agent execution while the subagent runs to conserve compute/tokens
- Offload messy research, log reading, and code exploration to the subagent
- The subagent must return ONLY a concise summary or specific code snippet to the main agent, never raw dumps

### 3. Usage Limit Protocol (State Preservation)
- NEVER resume a massive chat after a usage limit reset; this wastes your quota on re-reading old context.
- Keep `tasks/todo.md` obsessively updated with the exact current state and next step.
- Upon limit reset, start a **BRAND NEW CHAT**. 
- First prompt in new chat: *"Read `tasks/todo.md` and `tasks/lessons.md`. Tell me exactly what step we are on, and execute it."*

### 4. Self-Improvement Loop
- After ANY correction from the user: update `tasks/lessons.md` with the pattern
- Write rules for yourself that prevent the same mistake
- Ruthlessly iterate on these lessons until mistake rate drops
- Review lessons at session start for relevant project

### 5. Verification Before Done
- Never mark a task complete without proving it works
- Diff behavior between main and your changes when relevant
- Ask yourself: "Would a senior hardware engineer approve this?"
- Run testbenches, check simulation logs, demonstrate correctness

### 6. RTL-Aware Bug Fixing & Debugging
- Point at simulation outputs, compilation errors, and failing testbenches – then resolve them if the solution is clear in the text output.
- **Waveform Protocol:** You cannot see waveforms. If text outputs are insufficient to find the root cause, DO NOT guess wildly or write speculative fixes.
- When confused or stuck, you must ask the user to inspect the waveform.
- **Hypothesis First:** Before asking the user to check the waveform, you MUST state:
  1. Your current thoughts on what is going wrong.
  2. The specific modules, signals, registers, or state machines you suspect contain the bug.
- Tell the user exactly what behavior or signal transitions to look for in the waveform viewer.

### 7. The Architecture Summary (`summary.md`)
- Maintain a high-level `tasks/summary.md` file that acts as a map of the repository.
- **Never re-read files just to check interfaces.** Rely on `summary.md` first.
- The summary MUST include: module names, descriptions of their purpose, parameters, and input/output port definitions.
- Keep implementation details OUT of the summary. It is for architectural and interface reference only.
- **Strict Update Rule:** If you modify a module's ports, add a new parameter, or create a new file, you MUST update `summary.md` immediately before marking the task complete.

## Task Management
1. **Plan First**: Write plan to `tasks/todo.md` with checkable items
2. **Review Map**: Read `tasks/summary.md` to understand module interfaces before touching code.
3. **Delegate & Pause**: If a task requires exploration, spawn one subagent and pause main execution
4. **Verify Plan**: Check in before starting implementation (Ask for clarification if unsure!)
5. **Track Progress**: Mark items complete as you go. 
6. **Update Architecture**: If interfaces or global logic changed, update `tasks/summary.md`.
7. **Explain Changes**: High-level summary at each step
8. **Capture Lessons**: Update `tasks/lessons.md` after corrections