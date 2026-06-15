#!/usr/bin/env bash

file=$1
branch=$2

typeset -A expected_params

expected_params["bi-owner"]=1
expected_params["investment-level"]=1
expected_params["long-name"]=1
expected_params["product-owner"]=1
expected_params["rto"]=1
expected_params["runtime"]=1
expected_params["service-type"]=1
expected_params["short-name"]=1
expected_params["software-audience"]=1
expected_params["software-scope"]=1
expected_params["tech-owner"]=1
expected_params["runtime_2"]=1
expected_params["service_in_stage_prod_like"]=1
expected_params["release_process_pipeline_paths"]=1

path=`dirname $file`
filename=`basename $file`
pushd $path
main_branch=`git branch -a | grep HEAD | awk '{print $NF}' | cut -d'/' -f2`
current_branch=`git branch | grep '^\*' | awk '{print $NF}'`
echo $current_branch | grep -i $branch 2>&1 >/dev/null
if [ $? -ne 0 ]
then
    current_branch=$(basename `git branch -a | grep -i $branch`)
fi
git checkout $current_branch
if [ $? -ne 0 ]
then
    echo "Branch $current_branch not found"
    exit 1
fi
 echo $filename
actual_params=`yq -r '.service.properties | keys' $filename | cut -d" " -f2`

change_required=0
wrong_params=""

for p in $actual_params 
do
    if [[ ${expected_params[$p]} != "1" ]]
    then
        wrong_params+="$p\n"
        change_required=1
    fi
done

if [[ $change_required == 1 ]]
then
    git checkout $main_branch
    git pull
    git checkout $current_branch
    git merge $current_branch $main_branch
    echo Current branch: $current_branch
    echo
    echo Wrong parameters:
    printf $wrong_params
    read -p "Press ENTER to open $file"
    code $filename
    read -p "Commit/push $file to the branch $current_branch? [Y/N]" commit
    commit=${commit:-N}
    if [[ ${commit^^} == "Y" ]]
    then
        echo "Commit: $commit"
        git add $filename && git commit -m "$current_branch Remove default parameters from custom params key" && git push
        if [ $? -eq 0 ]
        then
            popd
        fi
    fi
fi