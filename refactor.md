# Refactoring Rules

1. **Reduce complexity** — fewer branches, simpler control flow, smaller methods
2. **Stay DRY** — no repeated logic; extract shared patterns
3. **Reduce line count** — less code = less to maintain
4. **Avoid monolithic files** — split large files into focused modules/concerns
5. **AI-agent friendly** — clear naming, obvious structure, fast context comprehension
6. **Token efficient** — concise code that conveys intent in minimal tokens
7. **Consistent patterns** — every instance of a pattern should follow the exact same structure; "almost the same but slightly different" burns tokens and causes AI misunderstanding

## Process

1. **Discover** — send parallel agents to scan models, services, controllers, and views for violations of the rules above
2. **Rank** — sort findings by severity (worst offenders first)
3. **Execute** — refactor top-down, tackling the biggest wins first
4. **Verify** — run tests after each refactor to ensure nothing breaks
