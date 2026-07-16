# Common Generated Source

`common/` is maintained source for duplicated mechanical files shipped inside
`ha`, `sa`, and `ca/claude`.

Generated files remain committed in each plugin because plugins are installed
individually and must stay self-contained. Do not make generated files refer back
to `common/`, and do not treat `common/` as a plugin.

## Workflow

Edit files under `common/src/`, `common/plugins/<plugin>/vars`, or
`common/plugins/<plugin>/fragments/`, then run:

```bash
bash common/sync.sh
bash common/sync.sh --check
bash common/tests/run.sh
```

`common/manifest.tsv` lists generated destinations. If a duplicated file is
intentionally not generated, list it in `common/exclusions.tsv` with a reason.

The generator supports:

- `@@VAR@@` values from `common/plugins/<plugin>/vars`
- `@@FRAGMENT:name@@` blocks from
  `common/plugins/<plugin>/fragments/<skill>/<name>.md`

Variable files are parsed as data and are never sourced.
