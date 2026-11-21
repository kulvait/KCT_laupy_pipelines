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
synchro_sample/
├── bin/
├── sbatch/
├── script/
└── INFO
```



- `sbatch/`: the SLURM job scripts, submitted with `submitslurm`.
- `bin/`: programs the job scripts call, and `initPython`.
- `script/`: scripts of the recipe run in or on the working directory (e.g. `02destar`).
- `INFO`: the order of the steps and the `submitslurm` calls of the pipeline.

The job scripts set up Python with `source initPython` (GPU scripts with
`source initPython --module cuda/11.8`). `bin/initPython` is a copy of the `initPython` of the
laupy deployment (laupy-deploy), kept with the recipe: it loads the modules `maxwell` and
`mamba/3.13` plus the `--module` ones and activates `$LAUPY_PYTHON` (`submitslurm --python`) if
set, else the shared Lau environment, using `initEnv`. Adapt it if a recipe needs another setup.
