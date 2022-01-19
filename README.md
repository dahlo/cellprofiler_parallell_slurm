# cellprofiler_parallell_slurm

This is an example of how we use SLURM to parallellize CellProfiler pipelines. It started off as a small script that would only be used once, but ended up growing as we used it more and more.

## Background
The script is divided into 2 main stages, where it will first run the pipelines that require all imagesets in the same job (i.e. not parallellized) and then run pipelines that can run on only a subset of the imagesets (i.e. parallellized).

Our use-case was that we first have to do illumination correction, which requires all imagesets to be present when run. After that step is run, we can run the remaining part of our pipeline (feature extraction) on 1 imageset per job, and run them all in parallell.

# Basic usag

```bash
bash feature_extraxtion_parallelized_v3.sh \
    -i /path/to/image_files/U2OS-24hr-1/ \
    -o /path/to/output_folder/U2OS-24hr-1 \
    -w cp_pipelines/v3/combtoxU2OS_2_Calculate_IllumFunction_subset.cppipe
    -p cp_pipelines/v3/combtoxU2OS_3_Calculate_Features_withIllum_singularity.cppipe \
    -M snowy \
    -d \
    -s 2
```








