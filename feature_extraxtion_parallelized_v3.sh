#!/bin/bash

# a script to parallelize cellprofiler runs.
# input is the input dir where the images are, a output dir where to place the results, and optionally a barcode that will be used instead of picking it out from the images file names
# Ex.
# bash uppmax_cp_pipeline_test_v2.sh <input dir> <output dir> [<barcode override>]

#set -x
set -e


# save pwd and args
execute_pwd=$(realpath $(pwd))
args=$@
script_path=$(realpath $0)

#      _____ ______ _______ _______ _____ _   _  _____  _____ 
#     / ____|  ____|__   __|__   __|_   _| \ | |/ ____|/ ____|
#    | (___ | |__     | |     | |    | | |  \| | |  __| (___  
#     \___ \|  __|    | |     | |    | | | . ` | | |_ |\___ \ 
#     ____) | |____   | |     | |   _| |_| |\  | |__| |____) |
#    |_____/|______|  |_|     |_|  |_____|_| \_|\_____|_____/ 


# the number of image sets to have in each job (to make run time ~1h)
img_per_job_default=5

# project id that will run the jobs
slurm_account_default=snic2019-8-171
#projid=snic2019-8-198

slurm_cluster_default=rackham
#cluster=snowy


# define the root of the scripts
script_root=/proj/sllstore2017091/CellProfiler/uppmax_pipelines/

# subset image set to a fixed number (leave empty to not subset)
#subset=5

# the crex problem at uppmax requres jobs to be run on a specific reservation at the moment. Comment this line out after it is finished
#reservation="--reservation=job_might_be_killed"

# timelimits
slurm_timelimit_short="1:00:00"
slurm_timelimit_medium="3:00:00"
slurm_timelimit_long="6:00:00"

### END SETTINGS ###



#              _____   _____ _    _ __  __ ______ _   _ _______ _____ 
#        /\   |  __ \ / ____| |  | |  \/  |  ____| \ | |__   __/ ____|
#       /  \  | |__) | |  __| |  | | \  / | |__  |  \| |  | | | (___  
#      / /\ \ |  _  /| | |_ | |  | | |\/| |  __| | . ` |  | |  \___ \ 
#     / ____ \| | \ \| |__| | |__| | |  | | |____| |\  |  | |  ____) |
#    /_/    \_\_|  \_\\_____|\____/|_|  |_|______|_| \_|  |_| |_____/ 

# mount sshfs if needed
#[[ -d /proj/snic2019-8-149/private/mnt/$USER/mikro/IMX ]] || /proj/snic2019-8-149/private/mount_with_sshfs.sh

print_usage() {
  usage="""
  $(basename $0)
  -------------------------------------
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
  
"""
  printf "$usage"

}

# check arguments
while getopts 'i:o:b:c:hj:s:f:A:e:M:dn:p:P:w:' flag; do
  case "${flag}" in
    A) slurm_account="${OPTARG}" ;;
    b) barcode="${OPTARG}" ;;
    c) ch_names="-c ${OPTARG}" ;;
    d) devel='true' ;;
    e) email_options="${OPTARG}" ;;
    f) imageset="${OPTARG}" ;;
    h) only_help='true' ;;
    i) input_dir="${OPTARG}" ;;
    j) img_per_job="${OPTARG}" ;;
    M) slurm_cluster="${OPTARG}" ;;
    n) slurm_n="${OPTARG}" ;;
    o) output_dir="${OPTARG}" ;;
    P) slurm_partition="${OPTARG}" ;;
    p) partial_imgset_pipelines="${OPTARG}" ;;
    s) subset="${OPTARG}" ;;
    w) whole_imgset_pipelines="${OPTARG}" ;;
    *) print_usage
       exit 1 ;;
  esac
done

# check if only help
[[ ! -n "$only_help" ]] || { print_usage ; exit 0 ; }

# check mandatory options
[[ -n "$input_dir" ]] || { printf "ERROR: input directory (-i) missing.\n" ; print_usage ; exit 1 ; }
[[ -n "$output_dir" ]] || { printf "ERROR: output directory (-o) missing.\n" ; print_usage ; exit 1 ; }


# set defaults
[[ -n "$img_per_job" ]] || img_per_job=$img_per_job_default
[[ -n "$slurm_account" ]] || slurm_account=$slurm_account_default
[[ -n "$slurm_cluster" ]] || slurm_cluster=$slurm_cluster_default
[[ -n "$slurm_n" ]] || slurm_n=1
[[ -n "$slurm_partition" ]] || slurm_partition="core"


# check if devel mode
if [[ $devel == 'true' ]]
then
    slurm_partition="devcore"
    # set short time limits
    slurm_timelimit_short="0:09:00"
    slurm_timelimit_medium="0:30:00"
    slurm_timelimit_long="0:55:00"

fi


# make sure all specified pipelines exist
[[ -z $partial_imgset_pipelines ]] && [[ -z $whole_imgset_pipelines ]] && { printf "No pipelines were given (-p, -w), exiting.\n" ; exit 1 ; }

#set -x

get_pipline_paths () {
    
    # get the user supplied argument
    arg=$1

    # reconstruct the pipeline list
    pipeline_list=""

    # skip tests if arg is empty
    if [[ -z $arg ]] 
    then
        echo ""
        return 0
    fi

    # check it it ends with .cppipe, in which case it will be interpreted as a comma separated list
    if [[ $arg == *".cppipe" ]]
    then

        # loop over the list split by comma
        for pipeline_file in $(echo $arg | sed "s/,/ /g")
        do
            # check that the path is valid
            [[ -f "$pipeline_file" ]] || { printf "ERROR: specified pipeline file does not exist: $pipeline_file\n" ; exit 1 ; }
            pipeline_list+=$(realpath "$pipeline_file")","
        done

    else

        [[ -f "$arg" ]] || { printf "ERROR: specified pipeline file does not exist: $arg\n" ; exit 1 ; }

        # loop over the lines in the specified file
        while read pipeline_file; do
            # check that the path is valid
            [[ -f "$pipeline_file" ]] || { printf "ERROR: specified pipeline file does not exist: $pipeline_file\n" ; exit 1 ; }
            pipeline_list+=$(realpath "$pipeline_file")","
        done < $arg
    fi
    
    # return the pipeline list without the last comma sign
    echo "${pipeline_list::-1}"

}
# replace the given pipelines with absolute paths to the pipeline files
whole_imgset_pipelines=$(get_pipline_paths $whole_imgset_pipelines)
partial_imgset_pipelines=$(get_pipline_paths $partial_imgset_pipelines)

# make all paths realative
mkdir -p $output_dir
input_dir=$(realpath $input_dir)
output_dir=$(realpath $output_dir)

# create the folder structure if needed
cd $output_dir
mkdir -p slurmfiles log
cd slurmfiles # make sure the slurm-$jobid.out files ends up here


#     _____ __  __  _____  _____ ______ _______ 
#    |_   _|  \/  |/ ____|/ ____|  ____|__   __|
#      | | | \  / | |  __| (___ | |__     | |   
#      | | | |\/| | | |_ |\___ \|  __|    | |   
#     _| |_| |  | | |__| |____) | |____   | |   
#    |_____|_|  |_|\_____|_____/|______|  |_|   

### generate the image set file (source ~/.bashrc to make the module command work)
py_barcode=""
[[ -z "$barcode" ]] || py_barcode="-b $barcode" # add -b infront of the barcode if need to use it for the python script
cmd="""
source $HOME/.bashrc &> /dev/null ; 
            module load python/3.6.8 &> /dev/null ; 
            python3 $script_root/cp_pipelines/v3/1_genereate_ImageSetList.py 
               -i $input_dir 
               -o $output_dir 
               $py_barcode 
               $ch_names
"""
datafile=$(eval $cmd)
barcode=$(basename $datafile | cut -f 2 -d "_" | cut -f 1 -d ".") # get the barcode from the generated imageset file

# log commands
echo $cmd "# $slurm_cluster:$jobid:0" >> ../log/cmds.log

# subset the image set if requested
[[ -z $subset ]] || $(head -n $((subset+1)) $datafile > $datafile.subset ; mv $datafile.subset $datafile)

# init the stage counter
stage=1
# __        ___   _  ___  _     _____   ___ __  __  ____ ____  _____ _____ 
# \ \      / / | | |/ _ \| |   | ____| |_ _|  \/  |/ ___/ ___|| ____|_   _|
#  \ \ /\ / /| |_| | | | | |   |  _|    | || |\/| | |  _\___ \|  _|   | |  
#   \ V  V / |  _  | |_| | |___| |___   | || |  | | |_| |___) | |___  | |  
#    \_/\_/  |_| |_|\___/|_____|_____| |___|_|  |_|\____|____/|_____| |_|  
#                                                                          
# pipelines to run using the whole imgset
slurm_dependency=""
for pipeline_file in $(echo $whole_imgset_pipelines | sed "s/,/ /g")
do
    cmd="""
        sbatch  -A $slurm_account 
                -M $slurm_cluster 
                -p $slurm_partition 
                -n $slurm_n 
                -t $slurm_timelimit_long 
                -J "cellprofiler_${barcode}_$(basename $pipeline_file):stage_$stage" 
                $slurm_dependency
                $reservation 
                $email_options 
                $script_root/sbatch_files/v3/run_pipeline_whole_v3.sh
                $datafile 
                $barcode 
                $output_dir 
                $pipeline_file

    """
    ### submit a pipeline to be run in one job using all imagesets at the same time (e.i. not parallellized)
    jobid_prev=$($cmd | cut -f 4 -d " ")
    printf "Submitted batch job $jobid_prev on cluster $slurm_cluster\n"

    # save jobid as dependency
    slurm_dependency="--dependency=afterok:$jobid_prev"

    # log the commands
    echo $cmd "# $slurm_cluster:$jobid_prev:0" >> ../log/cmds.log
    
    # increase stage counter
    let "stage++"
done

#  ____   _    ____ _____ ___    _    _       ___ __  __  ____ ____  _____ _____ 
# |  _ \ / \  |  _ \_   _|_ _|  / \  | |     |_ _|  \/  |/ ___/ ___|| ____|_   _|
# | |_) / _ \ | |_) || |  | |  / _ \ | |      | || |\/| | |  _\___ \|  _|   | |  
# |  __/ ___ \|  _ < | |  | | / ___ \| |___   | || |  | | |_| |___) | |___  | |  
# |_| /_/   \_\_| \_\|_| |___/_/   \_\_____| |___|_|  |_|\____|____/|_____| |_|  
#                                                                                
# pipelines to run on a subset of the imgset

# get number of image sets in the csv file (number of lines, minus 1 for the header row)
n_img=$(($(wc -l $datafile | cut -f 1 -d ' ')-1))

# if the user wants more files per job than there are files
if (( img_per_job > n_img )) 
then
    # adjust it so that all files go in one job
    img_per_job=$n_img 
fi


# adjust the numbers if the number of imgsets per job is larger than the # of imgsets
[[ $n_img < $img_per_job ]] || img_per_job=$((n_img))

# loop through the specified pipelines
for pipeline_file in $(echo $partial_imgset_pipelines | sed "s/,/ /g")
do
    ### submit the parallelized pipeline step
    for i in $(seq 1 $img_per_job $n_img)
    do
        first_img=$i
        last_img=$((i+img_per_job-1))

        # chech if we went too far
        if (( last_img > n_img ))
        then
            last_img=$n_img
        fi

        # submit the job

        cmd="""sbatch   -A $slurm_account 
                        -M $slurm_cluster 
                        -p $slurm_partition 
                        -n $slurm_n 
                        -t $slurm_timelimit_medium 
                        -J "cellprofiler_${barcode}_$(basename $pipeline_file)_$first_img-${last_img}:stage_$stage" 
                        $slurm_dependency
                        $reservation 
                        $email_options 
                        $script_root/sbatch_files/v3/run_pipeline_partial_v3.sh 
                        $datafile 
                        $barcode 
                        $output_dir 
                        $pipeline_file
                        $first_img 
                        $last_img 
                        illum 
        """


        # submit job and save jobid
        jobid=$($cmd | cut -f 4 -d " ")
        printf "Submitted batch job $jobid on cluster $slurm_cluster\n"

        # log command
        echo $cmd "# $slurm_cluster:$jobid:0" >> ../log/cmds.log

        # add jobid to list of jobids in this stage
        jobids+="afterok:$jobid,"

        sleep 0.5
    done

    

    # the pipeline is submitten, prepare for the next one

    # remove the last comma
    jobids=${jobids::-1}

    # update the slurm dependency with the jobids from this stage
    slurm_dependency="--dependency=$jobids"

    # increase the stage number
    let "stage++"

done
    





#     __  __ ______ _____   _____ ______ 
#    |  \/  |  ____|  __ \ / ____|  ____|
#    | \  / | |__  | |__) | |  __| |__   
#    | |\/| |  __| |  _  /| | |_ |  __|  
#    | |  | | |____| | \ \| |__| | |____ 
#    |_|  |_|______|_|  \_\\_____|______|

### submit the merger job

cmd="""sbatch   -A $slurm_account 
                -M $slurm_cluster 
                -p $slurm_partition 
                -n 1 
                -t $slurm_timelimit_short 
                -J "cellprofiler_${barcode}_merge:stage_$stage" 
                $slurm_dependency 
                $reservation 
                $email_options 
                $script_root/sbatch_files/v3/merge_pipeline_parts_v3.sh 
                $barcode 
                $output_dir
"""

jobid=$($cmd | cut -f 4 -d " ")
printf "Submitted batch job $jobid on cluster $slurm_cluster\n"

# log commands
echo $cmd "# $slurm_cluster:$jobid:0" >> ../log/cmds.log

# increase the stage counter
let "stage++"



# __     ___    _     ___ ____    _  _____ _____ 
# \ \   / / \  | |   |_ _|  _ \  / \|_   _| ____|
#  \ \ / / _ \ | |    | || | | |/ _ \ | | |  _|  
#   \ V / ___ \| |___ | || |_| / ___ \| | | |___ 
#    \_/_/   \_\_____|___|____/_/   \_\_| |_____|
#                                                
# VALIDATE

# submit the job that will validate that all jobs have finished correctly

cmd="""sbatch   -A $slurm_account 
                -M $slurm_cluster 
                -p $slurm_partition
                -n 1 
                -t $slurm_timelimit_short 
                -J "cellprofiler_${barcode}_validate:stage_$stage" 
                --dependency=afterany:$jobid 
                $reservation 
                $email_options 
                $script_root/sbatch_files/v3/validate_pipeline_run_v3.sh 
                $output_dir 
                $script_root 
                $slurm_account 
                $barcode 
                "$email_options"
"""

jobid=$($cmd | cut -f 4 -d " ")
printf "Submitted batch job $jobid on cluster $slurm_cluster\n"

# log commands
echo $cmd "# $slurm_cluster:$jobid:0" >> ../log/cmds.log




#  ____   ___  ____ _____   ____  _   _ ____  __  __ ___ _____  
# |  _ \ / _ \/ ___|_   _| / ___|| | | | __ )|  \/  |_ _|_   _|
# | |_) | | | \___ \ | |   \___ \| | | |  _ \| |\/| || |  | |
# |  __/| |_| |___) || |    ___) | |_| | |_) | |  | || |  | |
# |_|    \___/|____/ |_|   |____/ \___/|____/|_|  |_|___| |_|
#
# POST SUBMIT

# save the command used to generate this run
printf "#!/bin/bash

# go to the folder the script was executed from
cd $execute_pwd

# run the command
bash $script_path $args
" > $output_dir/cmd_used.sh



# create a link to the utils folder
ln -s $script_root/utils/ $output_dir 


# copy all the commands submitted to the pending file
cp ../log/cmds.log ../log/jobs.pending
