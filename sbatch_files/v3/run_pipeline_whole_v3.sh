#!/bin/bash -l    

set -x

# get variables
datafile=$1
barcode=$2
output_path=$3
pipeline=$4
link_list=$5


# mount sshfs if needed
mkdir -p $TMPDIR/crex/proj
ln -s crex/proj $TMPDIR/proj
#[[ -d $TMPDIR/proj/snic2019-8-149/private/mnt/$USER/mikro/IMX ]] || { /proj/snic2019-8-149/private/mount_with_sshfs.sh $TMPDIR ,ro ; sshfs_keeper=1 ; }

# avoid any symlinks in the cwd
cd $(pwd -P)

# create the local output dir
mkdir -p $TMPDIR/output $TMPDIR/tmp

# link items into the link local dir if asked to
if [[ -n link_list ]]; then
    # split on commas
    for item in $(echo $link_list | tr "," "\n")
    do
        # link each item to the local output folder
        ln -s $output_path/$item $TMPDIR/output/
    done
fi

# make a copy of the imglist and adjust paths
cp $datafile ${datafile}.$SLURM_JOB_ID
sed -i -e "s#,/#,$TMPDIR/#g" ${datafile}.$SLURM_JOB_ID
sed -i -e "s#:/#:$TMPDIR/#g" ${datafile}.$SLURM_JOB_ID

# exit on errors
set -e

singularity exec /proj/sllstore2017091/CellProfiler/cellprofiler.sif cellprofiler \
-r \
-c \
-p $pipeline \
-o $TMPDIR/output/ \
--data-file="${datafile}.$SLURM_JOB_ID" \
-t $TMPDIR/tmp 

# move all non-linked files/dirs to the network storage
rsync -aP --safe-links $TMPDIR/output/* $output_path/

# clean up
rm ${datafile}.$SLURM_JOB_ID

# check if the container output had any error in it
if [[ $(grep "Traceback" $output_path/slurmfiles/slurm-$SLURM_JOB_ID.out | grep -v "grep") ]]
then
    # if there was an error, exit with an error
    echo "ERROR: The cellprofiler output contains error messages, probably failed."
    exit 1 
fi
