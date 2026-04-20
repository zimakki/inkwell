---
name: ash-framework
description: "Use when working with Ash resources, actions, queries, migrations, code interfaces, or any ash_* extension (incl. spark, reactor, igniter generators)."
metadata:
  managed-by: usage-rules
---

<!-- usage-rules-skill-start -->
## Additional References

- [actions](references/actions.md)
- [aggregates](references/aggregates.md)
- [authorization](references/authorization.md)
- [calculations](references/calculations.md)
- [code_interfaces](references/code_interfaces.md)
- [code_structure](references/code_structure.md)
- [data_layers](references/data_layers.md)
- [exist_expressions](references/exist_expressions.md)
- [generating_code](references/generating_code.md)
- [migrations](references/migrations.md)
- [query_filter](references/query_filter.md)
- [querying_data](references/querying_data.md)
- [relationships](references/relationships.md)
- [testing](references/testing.md)
- [ash](references/ash.md)

## Searching Documentation

```sh
mix usage_rules.search_docs "search term" -p ash -p ash_sqlite
```

## Available Mix Tasks

- `mix ash` - Prints Ash help information
- `mix ash.codegen` - Runs all codegen tasks for any extension on any resource/domain in your application.
- `mix ash.extend` - Adds an extension or extensions to the given domain/resource
- `mix ash.gen.base_resource` - Generates a base resource. This is a module that you can use instead of `Ash.Resource`, for consistency.
- `mix ash.gen.change` - Generates a custom change module.
- `mix ash.gen.custom_expression` - Generates a custom expression module.
- `mix ash.gen.domain` - Generates an Ash.Domain
- `mix ash.gen.enum` - Generates an Ash.Type.Enum
- `mix ash.gen.gettext` - Copies Ash's .pot file for error message translation
- `mix ash.gen.preparation` - Generates a custom preparation module.
- `mix ash.gen.resource` - Generate and configure an Ash.Resource.
- `mix ash.gen.validation` - Generates a custom validation module.
- `mix ash.generate_livebook` - Generates a Livebook for each Ash domain
- `mix ash.generate_policy_charts` - Generates a Mermaid Flow Chart for a given resource's policies.
- `mix ash.generate_resource_diagrams` - Generates Mermaid Resource Diagrams for each Ash domain
- `mix ash.gettext.extract` - Extracts Ash error messages into a .pot file
- `mix ash.install` - Installs Ash into a project. Should be called with `mix igniter.install ash`
- `mix ash.migrate` - Runs all migration tasks for any extension on any resource/domain in your application.
- `mix ash.patch.extend` - Adds an extension or extensions to the given domain/resource
- `mix ash.reset` - Runs all tear down & setup tasks for any extension on any resource/domain in your application.
- `mix ash.rollback` - Runs all rollback tasks for any extension on any resource/domain in your application.
- `mix ash.setup` - Runs all setup tasks for any extension on any resource/domain in your application.
- `mix ash.tear_down` - Runs all tear_down tasks for any extension on any resource/domain in your application.
- `mix ash_sqlite.create` - Creates the repository storage
- `mix ash_sqlite.drop` - Drops the repository storage for the repos in the specified (or configured) domains
- `mix ash_sqlite.generate_migrations` - Generates migrations, and stores a snapshot of your resources
- `mix ash_sqlite.install` - Installs AshSqlite. Should be run with `mix igniter.install ash_sqlite`
- `mix ash_sqlite.migrate` - Runs the repository migrations for all repositories in the provided (or configured) domains
- `mix ash_sqlite.rollback` - Rolls back the repository migrations for all repositories in the provided (or configured) domains
<!-- usage-rules-skill-end -->
