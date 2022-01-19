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

# Help message

```
  A script to parallelize cellprofiler runs. Will run the specified pipelines on 
  
  Usage:
  bash $(basename $0) -i <input dir> -o <output dir> [-h -w <path to whole imgset pipeline(s)> -p <path to partial imgset pipeline(s)> -b <barcode override> -c <channel names override> -j <imgs per job> -s <subset to this number of imgsets> -f <path to premade ImageSetList> -A <slurm projid> -n <slurm cores to use> -P <slurm partition> -M <slurm cluster> -e <slurm email options> -d]
  
  Mandatory options:
  -i    Input directory containing images (will get all images recursivly).
  -o    Output directory where all output from the analysis will go.
  (either -w or -p has to be specified as well, see below)
  Optional options:
  -b    Barcode override, will use what you give as barcode instead of extracting
        from input directory name.
  -c    Channel name override, will use a comma separated list of new channel names.
        assigned in order given w1,w2,w3...
        Ex: HOECHST,CONCANALIN,SYTO,MITO will create a imgset file expecting 4 channels.
  -f    Path to pre-made Imageset CSV file.
  -h    Print this help message.
  -p    A comma separated list of paths to CellProfiler pipelines, or path to text file 
        with a path to a CellProfiler pipeline per rows, that will be executed after 
        each other on a subset of the ImageSetList. The subsets will run in parallel.
  -w    A comma separated list of paths to CellProfiler pipelines, or path to text file 
        with a path to a CellProfiler pipeline per row, that will be executed after 
        each other on the whole ImageSetList.
  Slurm options:
  -A    Slurm account to run on (default: $slurm_account_default)
  -e    Slurm email options, ex \"--mail-type=FAIL --mail-user=user@domain.se\"
  -j    Number of images to analyse in each slurm job (default: $img_per_job_default).
  -M    Slurm cluster to run on
  -n    Number of cores to use (default: 1)
  -P    Slurm partition to use (default: core)
  Debug options:
  -d    Devel mode, set time limit under an hour and use the devcore partition
  -s    Subset the image set list to the first s  number of files. Uses all files in image set by default.
```






