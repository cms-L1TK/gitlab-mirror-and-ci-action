# Mirror to GitLab and trigger GitLab CI

## Use cased by CMS L1 track group

   * CMSSW L1 track development: when someone makes a PR to our CMSSW development L1 track github repo, github CI runs following the instructions in https://github.com/cms-L1TK/cmssw/blob/L1TK-dev-12_0_0_pre4/.github/workflows/github_CI.yml . This calls the script https://github.com/cms-L1TK/gitlab-mirror-and-ci-action , which triggers detailed code checks in https://gitlab.cern.ch/cms-l1tk/cmssw_CI/-/blob/masterCI/.gitlab-ci.yml .

## Generic Functionality

A GitHub Action that mirrors all commits to GitLab, triggers GitLab CI, and returns the results back to GitHub. 

This action uses active polling to determine whether the GitLab pipeline is finished. This means our GitHub Action will run for the same amount of time as it takes for GitLab CI to finish the pipeline. 

## Example workflow

This is an example of a pipeline that uses this action:

```workflow
name: Mirror and run GitLab CI

on: [push]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v1
    - name: Mirror + trigger CI
      uses: SvanBoxel/gitlab-mirror-and-ci-action@master
      with:
        args: "https://gitlab.com/<namespace>/<repository>"
      env:
        GITLAB_HOSTNAME: "gitlab.com"
        GITLAB_USERNAME: "svboxel"
        GITLAB_PASSWORD: ${{ secrets.GITLAB_PASSWORD }} // Generate here: https://gitlab.com/profile/personal_access_tokens
        GITLAB_PROJECT_ID: "<GitLab project ID>" // https://gitlab.com/<namespace>/<repository>/edit
        GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }} // https://docs.github.com/en/actions/reference/authentication-in-a-workflow#about-the-github_token-secret
```

Be sure to define the token `GITLAB_L1TK_CMSSW_CI_TOKEN_2FA` secret in `https://github.com/cms-L1TK/cmssw/settings/secrets/actions` . This token name matches the one that the code looks for at https://github.com/cms-L1TK/cmssw/blob/L1TK-dev-13_3_0_pre2/.github/workflows/github_CI.yml#L63 . 
Before setup a token to use as `GITLAB_L1TK_CMSSW_CI_TOKEN_2FA` here `https://gitlab.cern.ch/cms-l1tk/cmssw_CI/-/settings/access_tokens` . You must give this token must have `read_api`, `read_repository` & `write_repository` permissions in GitLab.  
For granular permissions create seperate users and tokens in GitLab with restricted access.  
