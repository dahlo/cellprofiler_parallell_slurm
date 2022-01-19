# to split the queue output line by line
#set -x

usage="Usage: bash $0 <pattern>"
if [[ -z "$1" ]]
then
    printf "ERROR: search pattern missing\n\n$usage\n"
    exit
elif [[ $1 == '-h' ]] || [[ $1 == '--help' ]]
then
    printf "$usage\n"
    exit
fi

job_list=''

# for each job
while IFS= read -r job
do
    # pick out the id and name
    job_id=$(echo $job | cut -d " " -f 1)
    job_name=$(echo $job | cut -d " " -f 2)

    # if the name matches the search pattern
    if [[ $job_name == *"$1"* ]]
    then
        # inform the user about jobid and jobname and add it to the list
        printf "Found jobid $job_id:\t$job_name\n"
        job_list="$job_list$job_id "
    fi

# the ugly bash way of reading a file line by line..
done < <(squeue -u $USER -h -o "%A %j")

if [[ -z "$job_list" ]]
then
    printf "No matches found for pattern $1\n"
else
    # print the cancel command and let the user do it after seeing which jobs will be cancelled
    printf "Run this command to cancel the jobs above:

scancel $job_list\n\n"
fi

