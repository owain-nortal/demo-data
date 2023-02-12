#!/bin/bash
export HOST="mx01.neosdata.net"
export PASS=$(cat ~/.demo_password)
export PROFILE="neosadmin"
export USERNAME="neosadmin"
export NEOS_CTL_VERSION="0.4.3"

sink_output=$(pip install neosctl==$NEOS_CTL_VERSION)

echo "Setting up profile on $HOST"

neosctl -p $PROFILE profile init -h https://$HOST --non-interactive -u $USERNAME
neosctl -p $PROFILE auth login -p $PASS

echo "clean all json file"
rm *.json
rm tmp.csv
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
    
    
    res=$(neosctl -p $PROFILE product get $dp_name)
    ret=$?
    if [ $ret -eq 0 ]; then
        echo "$dp_name exists not creating"
    else
        echo "Create dp schema: $dp_json"
        neosctl -p $PROFILE product template -f $tmp_file $dp_name -o .
        echo "Create data product in neos core with name: $dp_name"
        neosctl -p $PROFILE product create -e postgres -f $dp_json $dp_name
    fi
    
    res=$(neosctl -p $PROFILE spark job-status $dp_name)
    ret=$?
    if [ $ret -ne 0 ]; then
        echo "Create spark job $dp_name"
        neosctl -p $PROFILE spark csv-job $dp_name -f $tmp_file
        echo "Wait for upload to complete"
        sleep 20
        while [ $(neosctl -p $PROFILE spark job-status $dp_name  | jq -r '.status' | grep COMPLETED | wc -l) -ne 0 ]
        do
            echo "$dp_name : $(neosctl -p $PROFILE spark job-status $dp_name | jq -r '.status')"
            sleep 5
        done
        echo "neosctl -p $PROFILE spark job-status $dp_name"
    else
        echo "spark job $dp_name exists not uploading data"
    fi
    
    echo "publish data product $dp_name"
    sink_errors=$(neosctl -p $PROFILE product publish $dp_name)
    
done