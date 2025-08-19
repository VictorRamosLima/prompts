```yml
detekt:
  config:
    validation: true
  build:
    maxIssues: 0

style:
  MaxLineLength:
    active: true
    maxLineLength: 120
    excludePackageStatements: true
    excludeImportStatements: true
    excludeCommentStatements: false
    severity: error

formatting:
  active: true

  Indentation:
    active: true
    indentSize: 4
    continuationIndentSize: 4

  ChainWrapping:
    active: true
    # Garante quebra após o ponto em chamadas encadeadas quando multilinha.

  ArgumentListWrapping:
    active: true
    # Em chamadas multilinha, exige um argumento por linha, alinhados.

  TrailingCommaOnCallSite:
    active: true
    # Exige vírgula em chamadas multilinha; não exige em linha única.

  TrailingCommaOnDeclarationSite:
    active: true
    # Exige vírgula em listas de parâmetros/propriedades multilinha.

  NoWildcardImports:
    active: true

  MaximumLineLength:
    active: false
    # Desabilitado aqui para usar o Style/MaxLineLength acima com severidade "error".

```

```yml
root = true

[*]
charset = utf-8
end_of_line = lf
insert_final_newline = true
indent_style = space
indent_size = 4
ij_continuation_indent_size = 4
continuation_indent_size = 4
max_line_length = 120

# Trailing comma (Kotlin)
ij_kotlin_allow_trailing_comma = true
ij_kotlin_allow_trailing_comma_on_call_site = true

# Code style do ktlint
ktlint_code_style = ktlint_official

# Regras específicas
ktlint_standard_chain-wrapping = enabled
ktlint_standard_trailing-comma-on-call-site = enabled
ktlint_standard_trailing-comma-on-declaration-site = enabled
ktlint_standard_no-wildcard-imports = enabled
```
