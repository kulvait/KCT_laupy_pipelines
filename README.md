# KCT [laupy](https://github.com/kulvait/KCT_laupy) Pipelines

Versioned processing recipes and scripts for [laupy](https://github.com/kulvait/KCT_laupy) tomography workflows.

This repository contains processing recipes used with [laupy](https://github.com/kulvait/KCT_laupy). A recipe is a collection of scripts, batch jobs, configuration files, and other tools used to process a particular dataset or type of experiment.

The recipes are intentionally kept as complete processing environments. Similar recipes may contain duplicated or slightly different scripts. This is deliberate: preserving the exact scripts used for a particular processing workflow makes it possible to reproduce previous results.

## Recipes

Each top-level directory is a separate recipe:

```text
KCT_laupy_pipelines/
├── synchro_root/
├── synchro_nanop5/
├── synchro_.../
└── ...
```

Structure of each recipe directory is as follows:

```text
synchro_mouse/
├── bin/
├── sbatch/
├── script/
└── INFO
```


