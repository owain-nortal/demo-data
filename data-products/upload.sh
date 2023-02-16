#!/bin/bash
#set -ex
# export CORE_HOST="alpha.neosdata.net"
# export NEOS_ADMIN_PASSWORD=$(cat ~/.demo_password)
# export NEOS_PROFILE_NAME="neosadmin"
# export NEOS_ADMIN_USER="neosadmin"
# export NEOS_CTL_VERSION="0.5.2"

# sink_output=$(pip install neosctl==$NEOS_CTL_VERSION)

echo "Setting up profile on $NEOS_PROFILE_NAME"

neosctl -p $NEOS_PROFILE_NAME profile init -h "https://$CORE_HOST" --non-interactive -u $NEOS_ADMIN_USER

echo "neosctl -p $NEOS_PROFILE_NAME profile init -h $CORE_HOST --non-interactive -u $NEOS_ADMIN_USER"

neosctl -p $NEOS_PROFILE_NAME auth login -p $NEOS_ADMIN_PASSWORD


echo "create data products"

FILES="*.csv"
for csv in $FILES
do
    dp_name="${csv%.*}"
    dp_json="$dp_name.json"
    tmp_file="tmp.csv"
    awk 'NR==1{$0=tolower($0)} 1'  $csv > tmp1
    sed '1s/ /_/g' tmp1 > $tmp_file
    #rm tmp1

    echo "Processing $f with data product name $dp_name"
    
    
    res=$(neosctl -p $NEOS_PROFILE_NAME product get $dp_name)
    ret=$?
    if [ $ret -eq 0 ]; then
        echo "$dp_name exists not creating"
    else
        echo "Create dp schema: $dp_json"
        echo "neosctl -p $NEOS_PROFILE_NAME product template -f $tmp_file $dp_name -o ."
        neosctl -p $NEOS_PROFILE_NAME product template -f $tmp_file $dp_name -o .
        echo "Create data product in neos core with name: $dp_name"
        neosctl -p $NEOS_PROFILE_NAME product create-stored -f $dp_json $dp_name
    fi
    
    res=$(neosctl -p $NEOS_PROFILE_NAME spark job-status $dp_name)
    ret=$?
    if [ $ret -ne 0 ]; then
        echo "Create spark job $dp_name"
        neosctl -p $NEOS_PROFILE_NAME spark csv-job $dp_name -f $tmp_file
        echo "Wait for upload to complete"
        sleep 20
        while [ $(neosctl -p $NEOS_PROFILE_NAME spark job-status $dp_name | jq -r '.status' |  grep COMPLETED | wc -l) -ne 1 ]
        do
            echo "$dp_name : $(neosctl -p $NEOS_PROFILE_NAME spark job-status $dp_name | jq -r '.status')"
            sleep 5
           
        done
        echo "neosctl -p $NEOS_PROFILE_NAME spark job-status $dp_name"
    else
        echo "spark job $dp_name exists not uploading data"
    fi
    
    echo "publish data product $dp_name"
    sink_errors=$(neosctl -p $NEOS_PROFILE_NAME product publish $dp_name)
    
done