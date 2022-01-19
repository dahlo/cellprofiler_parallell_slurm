#!/bin/bash

set -x
set -e

# get args dir
output_dir=$1
script_root=$2
projid=$3
barcode=$4
email_options=$5


email_user (){

    if [[ -z "$email_options" ]]
    then
        # no email available, print the message to terminal instead
        echo -e "$1"
        return 0
    fi
    
    # split out the email address if there is one
    user_email=$(echo $email_options | grep -E -o "\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,6}\b")
    message=$1
    cluster=$2

    if [[ -z "$user_email" ]]
    then
        # no email available, print the message to terminal instead
        echo -e "$1"
        return 0
    fi

    # there is an email, go for it
    echo -e "$1" | sendmail -r pipeline@$2.uppmax.uu.se $user_email

}


# go to the slurmfile dir
cd $output_dir/slurmfiles

# move to a work copy
mv ../log/jobs.pending ../log/jobs.workcopy

# indicator for resubmissions
resubmitted=false

# init
previous_job_stage=-1
job_list=''
previous_job_lists=''

# for each job
ORG_IFS=$IFS # save for later
IFS=$'\n'
for job in $(cat ../log/jobs.workcopy)
do
    IFS=$ORG_IFS
    # skip the job if it is the previous validate_pipeline_run
    # skip also the python script that runs locally
    if [[ "$job" =~ 'genereate_ImageSetList.py' ]]
    then
        continue
    elif [[ "$job" =~ '_validate:stage_' ]]
    then
        validation_job_cluster=$(echo $job_info | cut -d ":" -f 1 | tr -d '[:space:]')
        continue
    fi
    
    # get the job info
    job_info=$(echo $job | cut -d "#" -f 2)
    job_cmd=$(echo $job | cut -d "#" -f 1)
    job_cluster=$(echo $job_info | cut -d ":" -f 1 | tr -d '[:space:]')
    job_id=$(echo $job_info | cut -d ":" -f 2)
    job_fail_counter=$(echo $job_info | cut -d ":" -f 3)

    # get the job stage
    regex=':stage_([0-9]+)'
    [[ $job_cmd =~ $regex ]]
    job_stage=${BASH_REMATCH[1]}

    # if it is the first loop
    if [[ $previous_job_stage == -1 ]]
    then
        previous_job_stage=$job_stage
    fi

    # if we are at a new job stage
    if [[ $job_stage != $previous_job_stage ]]
    then
        # save submitted jobs as previous stage amd reset
        previous_job_stage=$job_stage
        previous_job_lists=$previous_job_lists$job_list
        job_list=''
    fi

    # remove the slurm dependency part of the command
    job_cmd=$(echo $job_cmd | sed 's>--dependency=[^[:space:]]*>>')


    # add dependency info if need be
    if [[ $previous_job_lists != '' ]]
    then
        job_cmd=$(echo $job_cmd | sed "s>$script_root>--dependency=afterok$previous_job_lists $script_root>")
    fi

    # get the jobstate for the job
    slurm_info=$(sacct -j $job_id -M $job_cluster -o JobID,JobName,Partition,Account,AllocCPUS,State,TimelimitRaw -nP | grep -v 'batch\|extern' )
    job_state=$(echo $slurm_info | cut -d "|" -f 6 | cut -d " " -f 1)
    job_cores=$(echo $slurm_info | cut -d "|" -f 5)
    job_timelimit=$(echo $slurm_info | cut -d "|" -f 7)

    # if job failed, resubmit and increase fail counter
    if [[ $job_state == 'FAILED' ]]
    then
        # fail counter less than 3
        if (( $job_fail_counter < 3 ))
        then

            # resubmit and save jobid
            job_resubmit_id=$($job_cmd | cut -f 4 -d " ")
            job_list="$job_list:$job_resubmit_id"

            # add job to jobs.pending and cmds.log
            echo "$(echo $job | cut -d '#' -f 1) # $job_cluster:$job_resubmit_id:$((job_fail_counter+1))" | tee -a ../log/cmds.log >> ../log/jobs.pending

            # flag resubmission
            resubmitted=true

        else
            # contact someone
            email_user "$barcode: $job_id failed too many times, giving up \n Command that fails:\n$job_cmd" $job_cluster
            touch ../looks_bad_failedTooManyTimes
            exit 1
        fi 

    # if job ran out of mem, resubmitt with 2x cores
    elif [[ $job_state == 'OUT_OF_MEMORY' ]]
    then
        # if cores less than 20
        if (( $job_cores < 20 ))
        then

            # resubmit with 2x cores, max 20 cores, and save jobid
            new_n_cores=$(( (job_cores*2)<20 ? job_cores*2 : 20 ))
            job_cmd=$(echo $job_cmd | sed "s>$script_root>-n  $new_n_cores $script_root>")
            job_resubmit_id=$($job_cmd | cut -f 4 -d " ")
            job_list=$job_list:$job_resubmit_id

            # add job to jobs.pending and cmds.log
            echo $job_cmd \# $job_cluster:$job_resubmit_id:$job_fail_counter | tee -a ../log/cmds.log >> ../log/jobs.pending
            
            # flag resubmission
            resubmitted=true

        else
            # contact someone
            email_user "$barcode: $job_id out of memory too many times, giving up \n Command that fails:\n$job_cmd" $job_cluster
            touch ../looks_bad_outOfMemoryTooMuch
            exit 1
        fi
    # if job ran out of time, resubmitt with 4x time
    elif [[ $job_state == 'TIMEOUT' ]]
    then
        # if timelimit is less than a week, in minutes
        if (( $job_timelimit < 10080 ))
        then

            # resubmit with 4x time, max 1 week, and save jobid
            new_timelimit=$(( (job_timelimit*4)<10080 ? job_timelimit*4 : 10080 ))
            job_cmd=$(echo $job_cmd | sed "s>$script_root>-t  00:$new_timelimit:00 $script_root>")
            job_resubmit_id=$($job_cmd | cut -f 4 -d " ")
            job_list=$job_list:$job_resubmit_id

            # add job to jobs.pending and cmds.log
            echo $job_cmd \# $job_cluster:$job_resubmit_id:$job_fail_counter | tee -a ../log/cmds.log >> ../log/jobs.pending
            
            # flag resubmission
            resubmitted=true

        else
            # contact someone
            email_user "$barcode: $job_id timed out too many times, giving up \n Command that fails:\n$job_cmd" $job_cluster
            touch ../looks_bad_timeoutTooMuch
            exit 1
        fi


    # if the job got cancelled because a job in the previous stage failed, or other reason not because of this job, resubmit
    elif [[ $job_state == 'CANCELLED' ]] || [[ $job_state == 'NODE_FAIL' ]] 
    then
        # resubmit and save jobid
        job_resubmit_id=$($job_cmd | cut -f 4 -d " ")
        job_list=$job_list:$job_resubmit_id

        # add job to jobs.pending and cmds.log
        echo $job_cmd \# $job_cluster:$job_resubmit_id:$job_fail_counter | tee -a ../log/cmds.log >> ../log/jobs.pending

        # flag resubmission
        resubmitted=true

    
    elif [[ $job_state == 'COMPLETED' ]]
    then

        echo "$job_id finished successfully, nothing more to do."


    else
        email_user "$barcode: $job_id ended with an unknown jobstate: $job_state, giving up \n Command that fails:\n$job_cmd" $job_cluster
        touch ../looks_bad_unknownExitCode
        exit 1
    fi


done

# cleanup
rm ../log/jobs.workcopy


# if anything was resubmitted this script will have to be rerun as well.
if [[ $resubmitted == "true" ]]
then
    # increase the stage counter
    let 'job_stage++'

    # construct the command
    cmd="""sbatch   -A $projid \
                    -M $validation_job_cluster \
                    -p core \
                    -n 1 \
                    -t 00:30:00 \
                    -J "cellprofiler_${barcode}_validate:stage_$(job_stage)" \
                    --dependency=afterany$previous_job_lists$job_list \
                    $email_options \
                    $script_root/sbatch_files/v3/validate_pipeline_run_v3.sh \
                    $output_dir \
                    $script_root \
                    $projid \
                    $barcode \
                    "$email_options"
"""

    # run and log the command
    job_resubmit_id=$($cmd | cut -f 4 -d " ")
    echo $cmd "# $validation_job_cluster:$job_resubmit_id:0" | tee -a ../log/cmds.log >> ../log/jobs.pending

    # exit
    exit 0

# if nothing was resubmitted, check if result looks good
else

    # go to the root dir
    cd ..

    # for each parts dir
    for parts_dir in $(ls -d *.parts/)
    do

        # check if parts is empty
        if [[ $(ls $parts_dir | wc -w) != 0 ]] 
        then
            # create an error file and email user
            touch looks_bad_nonEmptyPartsDir
            email_user "$barcode: run ended badly. $parts_dir is not empty." $validation_job_cluster

            # exit
            exit 1
        fi

        # remove the dir if it is empty
        rm -r $parts_dir
    done

    # if it made it this far it must have been a successful run, right?
    touch looks_good
    email_user "$barcode: run ended successfully." $validation_job_cluster

    # remove any remaining job specific csv files
    rm -f ./ImageSetList_*.csv.*
fi

exit 0


