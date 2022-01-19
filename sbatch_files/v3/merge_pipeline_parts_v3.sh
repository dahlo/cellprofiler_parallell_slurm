#!/bin/bash -l    

set -x
    
# get variables
barcode=$1
output_path=$2

# mount sshfs if needed
#[[ -d /proj/snic2019-8-149/private/mnt/$USER/mikro/IMX ]] || /proj/snic2019-8-149/private/mount_with_sshfs.sh

# go to the output folder and create a results folder
cd $output_path

# exit on errors
set -e

# for all folders named *.parts
for parts_dir in $(ls -d *.parts/)
do

    # get the directory prefix, i.e. remove .parts from the name
    dir_prefix=${parts_dir::-7}

    # create the output directory
    mkdir -p $dir_prefix

    # go through the files and add their content to the final csv files
    file_mem=''
    header_mem=''
    final_file_mem=''
    for file in $(ls $parts_dir/*.csv)
    do

        # pick out the file prefix and file property (e.g. Image, primobj_nuclei, Experiment etc)
        file_prefix=$(basename $file | cut -d "." -f 1) # split on . and get first word
        file_property=$(basename $file | tr "." " " | awk '{print $(NF-1)}') # split on . and get 2nd last word

        # put the file content in the final csv file
        # first check if the final file already exists, in which case the header of this file should not be included
        if [[ -f "$TMPDIR/${file_prefix}.${barcode}.${file_property}.csv.tmp" ]]
        then
            # skip the first line of the content
            tail -n +2 $file >> $TMPDIR/${file_prefix}.${barcode}.${file_property}.csv.tmp
        else
            # take all of the content, including the header row
            cat $file >> $TMPDIR/${file_prefix}.${barcode}.${file_property}.csv.tmp
            final_file_mem+="${file_prefix}.${barcode}.${file_property}.csv "
        fi

        # save the file name
        file_mem+="$file "
    done

    # copy the final files to the final folders and delete the processed files
    for final_file in $final_file_mem
    do
        mv $TMPDIR/${final_file}.tmp $dir_prefix/$final_file
    done
    
    # remove processed files
    rm $file_mem

    # try removing the parts dir if it is empty, leave it otherwise
    rmdir --ignore-fail-on-non-empty $parts_dir

done

