#!/bin/bash

# for each logged job
for job_line in $(cat log/cmds.log | cut -d '#' -f 2)
do
    # save the info
    job_cluster=$(echo $job_line | cut -d ':' -f 1)
    job_id=$(echo $job_line | cut -d ':' -f 2)
    job_fail_counter=$(echo $job_line | cut -d ':' -f 3)

    # skip if job id is empty
    if [[ -z $job_id ]]
    then
        continue
    fi

    # get the info from slurm
    slurm_info=$(sacct -j $job_id -M $job_cluster -nP | grep -v 'batch\|extern' )
    
    # print info
    printf "$slurm_info\t$job_line\n"

done
    




