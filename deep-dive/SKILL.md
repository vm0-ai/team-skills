---
name: deep-dive
description: Structured workflow for complex tasks with three phases - research (gather information), innovate (explore solutions), plan (create implementation steps). Use for any non-trivial development task.
---

# Deep Dive Workflow

A structured approach for tackling complex development tasks through three distinct phases.

## When to Use

Use this workflow when you need to:

- Understand a complex codebase before making changes
- Explore multiple solution approaches for a problem
- Create a detailed implementation plan before coding
- Work on non-trivial features or refactoring tasks

## Overview

The deep dive workflow consists of three phases:

1. **Research** (`/deep-research`) - Gather information, understand the codebase
2. **Innovate** (`/deep-innovate`) - Brainstorm solutions, evaluate trade-offs
3. **Plan** (`/deep-plan`) - Create concrete implementation steps

Each phase builds on the previous one. Artifacts are stored in `deep-dive/{task-name}/`.

---

# Phase 1: Deep Research

**Command:** `/deep-research [task description]`

## Purpose

Information gathering phase. Analyze the codebase without suggesting solutions.

## Restrictions

**PERMITTED:**
- Reading files and code
- Asking clarifying questions
- Understanding code structure and architecture
- Analyzing dependencies and constraints
- Recording findings

**FORBIDDEN:**
- Suggestions or recommendations
- Implementation ideas
- Planning or roadmaps
- Any hint of action

## Workflow

1. **Clarification** - Ask questions to understand the scope
2. **Research** - Systematically analyze relevant code
3. **Documentation** - Record findings to `deep-dive/{task-name}/research.md`
4. **Completion** - Summarize findings (facts only), ask what to do next

## Thinking Principles

- **Systems Thinking** - Analyze from architecture to implementation
- **Dialectical Thinking** - Understand multiple aspects and trade-offs
- **Critical Thinking** - Verify understanding from multiple angles
- **Mapping** - Separate known from unknown elements

---

# Phase 2: Deep Innovate

**Command:** `/deep-innovate [task description]`

## Prerequisites

Research document must exist at `deep-dive/{task-name}/research.md`

## Purpose

Creative brainstorming phase. Explore multiple approaches based on research findings.

## Restrictions

**PERMITTED:**
- Discussing multiple solution ideas
- Evaluating advantages and disadvantages
- Exploring architectural alternatives
- Comparing technical strategies
- Considering trade-offs

**FORBIDDEN:**
- Concrete planning with specific steps
- Implementation details or pseudo-code
- Committing to a single solution
- File-by-file change specifications

## Workflow

1. **Review** - Read research document, summarize key findings
2. **Exploration** - Generate 2-3 distinct solution approaches
3. **Analysis** - Document pros/cons, trade-offs for each
4. **Documentation** - Create `deep-dive/{task-name}/innovate.md`
5. **Discussion** - Present approaches, gather user feedback

## For Each Approach Document

- Core concept and philosophy
- Key advantages
- Potential challenges or risks
- Compatibility with existing architecture
- Scalability and maintainability

---

# Phase 3: Deep Plan

**Command:** `/deep-plan [task description]`

## Prerequisites

Both documents must exist:
- `deep-dive/{task-name}/research.md`
- `deep-dive/{task-name}/innovate.md`

## Purpose

Transform research and innovation into a concrete implementation plan.

## Restrictions

**PERMITTED:**
- Creating detailed implementation steps
- Specifying file changes
- Defining task dependencies
- Breaking down work into actionable items
- Identifying blockers or risks

**FORBIDDEN:**
- Actually writing or modifying code
- Making commits or file changes
- Running tests or build commands
- Any implementation execution

## Workflow

1. **Context Review** - Read research and innovate documents
2. **Task Breakdown** - Identify discrete work items, order by dependency
3. **Specification** - For each task: description, files affected, acceptance criteria
4. **Risk Assessment** - Identify challenges, external dependencies
5. **Documentation** - Create `deep-dive/{task-name}/plan.md`
6. **Approval** - Present plan, get explicit approval before implementation

## Plan Document Structure

- Chosen approach summary
- Task breakdown with details
- Test strategy
- Dependency graph (if complex)
- Risk assessment
- Definition of done

---

## Artifacts

All artifacts are stored in `deep-dive/{task-name}/`:

| File | Phase | Content |
|------|-------|---------|
| `research.md` | Research | Codebase analysis, technical constraints |
| `innovate.md` | Innovate | Solution approaches, trade-offs |
| `plan.md` | Plan | Implementation steps, task breakdown |

## Best Practices

1. **Complete phases in order** - Each phase builds on previous findings
2. **Don't skip phases** - Even simple tasks benefit from structured thinking
3. **Keep artifacts updated** - Reference and update docs as understanding evolves
4. **Get approval before implementing** - The plan is a contract with the user
