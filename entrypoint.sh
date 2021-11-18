#!/bin/sh

# Error handling
set -eo pipefail
# set -e : Instructs bash to immediately exit if any command has a non-zero exit status.
# (not active) set -u : Reference to any variable not previously defined - with the exceptions of $* and $@ - is an error
# set -o pipefail : Prevents errors in a pipeline from being masked.

##################################################################
urlencode() (
    i=1
    max_i=${#1}
    while test $i -le $max_i; do
        c="$(expr substr $1 $i 1)"
        case $c in
            [a-zA-Z0-9.~_-])
		printf "$c" ;;
            *)
		printf '%%%02X' "'$c" ;;
        esac
        i=$(( i + 1 ))
    done
)
##################################################################

# Time interval with which gutlab asked if it has finished CI yet.
DEFAULT_POLL_TIMEOUT=20
POLL_TIMEOUT=${POLL_TIMEOUT:-$DEFAULT_POLL_TIMEOUT}

DEFAULT_GITHUB_REF=${GITHUB_REF:11}

mirror_repo="$MIRROR_REPO"

sh -c "git config --global user.name $GITLAB_USERNAME"
sh -c "git config --global user.email ${GITLAB_USERNAME}@${GITLAB_HOSTNAME}"
sh -c "git config --global credential.username $GITLAB_USERNAME"
sh -c "git config --global core.askPass /cred-helper.sh"
sh -c "git config --global credential.helper cache"

if [[ ${IS_CMSSW:-false} == "true" ]]; then
  # Checkout .gitlab-ci.yml
  sh -c "git clone -o mirror -b masterCI $mirror_repo ."
  branch="${CHECKOUT_BRANCH:-$DEFAULT_GITHUB_REF}"
else
  git checkout "${CHECKOUT_BRANCH:-$DEFAULT_GITHUB_REF}"
  sh -c "git remote add mirror $mirror_repo"
  branch="$(git symbolic-ref --short HEAD)"
fi

echo "mirror repo = $mirror_repo and branch = $branch"

branch_uri="$(urlencode ${branch})"

git branch -v
ls -la

if [[ ${REBASE_MASTER:-"false"} == "true" ]]; then
   if [[ ${IS_CMSSW:-false} == "false" ]]; then
      git rebase origin/master
   fi
fi

# Removing and readding branch on mirror triggers CI there.
if [[ ${REMOVE_BRANCH:-"false"} == "true" ]]; then
   # If branch exists
   branchExists=$(git ls-remote $(git remote get-url --push mirror) ${CHECKOUT_BRANCH:-$DEFAULT_GITHUB_REF} | wc -l)
   if [[ "${branchExists}" == "1" ]]; then
      echo "removing the ${branch} branch at $(git remote get-url --push mirror)"
      sh -c "git push mirror --delete ${branch}"
   fi
fi        

sh -c "echo pushing to $branch branch at $(git remote get-url --push mirror)"
if [[ ${IS_CMSSW:-false} == "true" ]]; then
  # Copy .gitlab-ci.yml from branch masterCI to new branch triggers gitlab CI in the latte branch.
  # The -o option here passes the owner-name of the repo where the new branch is located
  # and the L1 track algorithm to be run to gitlab CI.
  # https://docs.gitlab.com/ee/user/project/push_options.html#push-options-for-gitlab-cicd
  sh -c "git push -o ci.variable="GITHUB_USER_UNDER_TEST=$GITHUB_REPOSITORY_OWNER" mirror masterCI:$branch"
  # IDEA FOR FUTURE IMPROVEMENT
  # Instead of triggering gitlab CI by pushing to branch,
  # add a web hook https://gitlab.cern.ch/cms-l1tk/cmssw_CI/-/hooks
  # and trigger it with "curl" (which can also pass variables)
  # https://gitlab.cern.ch/cms-l1tk/cmssw_CI/-/settings/ci_cd#js-pipeline-triggers

else # not CMSSW
  sh -c "git push mirror $branch"
fi

sleep $POLL_TIMEOUT

pipeline_id=$(curl --header "PRIVATE-TOKEN: $GITLAB_PASSWORD" --silent "https://${GITLAB_HOSTNAME}/api/v4/projects/${GITLAB_PROJECT_ID}/repository/commits/${branch_uri}" | jq '.last_pipeline.id')
pipeline_url="$mirror_repo/-/pipelines/${pipeline_id}"

echo "Poll timeout set to ${POLL_TIMEOUT}"
echo "Triggered CI for branch ${branch}"
echo "Working with pipeline id #${pipeline_id}"
echo ""
echo "--- GITLAB PIPELINE URL: $pipeline_url ---"
echo ""

# Is this the only way to return the pipeline URL to the calling .yml job?
echo "$pipeline_url" > $RETURN_FILE

ci_status="pending"

until [[ "$ci_status" != "pending" && "$ci_status" != "running" ]]
do
   sleep $POLL_TIMEOUT
   ci_output=$(curl --header "PRIVATE-TOKEN: $GITLAB_PASSWORD" --silent "https://${GITLAB_HOSTNAME}/api/v4/projects/${GITLAB_PROJECT_ID}/pipelines/${pipeline_id}")
   ci_status=$(jq -n "$ci_output" | jq -r .status)
   ci_web_url=$(jq -n "$ci_output" | jq -r .web_url)
   
   echo "Current pipeline status: ${ci_status}"
   if [ "$ci_status" = "running" ]
   then
     echo "Checking pipeline status..."
     curl -d '{"state":"pending", "target_url": "'${ci_web_url}'", "context": "gitlab-ci"}' -H "Authorization: token ${GITHUB_TOKEN}"  -H "Accept: application/vnd.github.antiope-preview+json" -X POST --silent "https://api.github.com/repos/${GITHUB_REPOSITORY}/statuses/${GITHUB_SHA}"  > /dev/null 
   fi
done

echo "Pipeline finished with status ${ci_status}"

echo "Fetching all GitLab pipeline jobs involved"
ci_jobs=$(curl --header "PRIVATE-TOKEN: $GITLAB_PASSWORD" --silent "https://${GITLAB_HOSTNAME}/api/v4/projects/${GITLAB_PROJECT_ID}/pipelines/${pipeline_id}/jobs" | jq -r '.[] | { id, name, stage }')
echo "Posting output from all GitLab pipeline jobs"
for JOB_ID in $(echo $ci_jobs | jq -r .id); do
  echo "##[group]Stage $( echo $ci_jobs | jq -r "select(.id=="$JOB_ID") | .stage" ) / Job $( echo $ci_jobs | jq -r "select(.id=="$JOB_ID") | .name" )"
  curl --header "PRIVATE-TOKEN: $GITLAB_PASSWORD" --silent "https://${GITLAB_HOSTNAME}/api/v4/projects/${GITLAB_PROJECT_ID}/jobs/${JOB_ID}/trace"
  echo "##[endgroup]"
done
echo "Debug problems by unfolding stages/jobs above"
  
if [ "$ci_status" = "success" ]
then 
  curl -d '{"state":"success", "target_url": "'${ci_web_url}'", "context": "gitlab-ci"}' -H "Authorization: token ${GITHUB_TOKEN}"  -H "Accept: application/vnd.github.antiope-preview+json" -X POST --silent "https://api.github.com/repos/${GITHUB_REPOSITORY}/statuses/${GITHUB_SHA}" 
  exit 0
elif [ "$ci_status" = "failed" ]
then 
  curl -d '{"state":"failure", "target_url": "'${ci_web_url}'", "context": "gitlab-ci"}' -H "Authorization: token ${GITHUB_TOKEN}"  -H "Accept: application/vnd.github.antiope-preview+json" -X POST --silent "https://api.github.com/repos/${GITHUB_REPOSITORY}/statuses/${GITHUB_SHA}" 
  exit 1
fi
