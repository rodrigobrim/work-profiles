# Expected environment variables:

# export _CODEFRESH_TOKEN=
# export _TF_TOKEN=
# export _TENV_AUTO_INSTALL=
# export _OPSLEVEL_API_TOKEN=
# export SLACK_TOKEN=
# export SLACK_SIGNING_SECRET=
# export _DD_CLIENT_API_KEY=
# export _DD_CLIENT_APP_KEY=
# export AZURE_SUBSCRIPTION_DEV_ID=
# export AZURE_SUBSCRIPTION_PRD_ID=
# export AZURE_SC_RG_PREFIX=
# export AZURE_SC_CLUSTER_PREFIX=
# export SCRIPTCYCLE_AD_USERNAME=
# export SCRIPTCYCLE_AD_PASSWORD=

# export Codefresh token env vars (CODEFRESH_TOKEN/CF_KEY/CF_API_KEY) from $_CODEFRESH_TOKEN
codefresh_auth () {
  export CODEFRESH_TOKEN=$_CODEFRESH_TOKEN
  export CF_KEY=$CODEFRESH_TOKEN
  export CF_API_KEY=$CODEFRESH_TOKEN
}

# clone a repo into ~/repos and cd into it
git-clone () {
  cd ~/repos
  git clone $1
  cd `echo $1 | cut -d'/' -f2 | cut -d'.' -f1`
}

# export TF_TOKEN (Terraform Cloud) from $_TF_TOKEN
tf-login () {
  export TF_TOKEN=$_TF_TOKEN
}

# export OPSLEVEL_API_TOKEN from $_OPSLEVEL_API_TOKEN
ops-auth () {
  export OPSLEVEL_API_TOKEN=$_OPSLEVEL_API_TOKEN
}

# list processes listening on TCP port $PORT (IPv4)
ss () {
  sudo lsof -i -P | grep LISTEN | grep :$PORT | grep IPv4 $@
}

# list processes listening on TCP port $PORT (IPv6)
ss-ipv6 () {
  sudo lsof -i -P | grep LISTEN | grep :$PORT | grep IPv6 $@
}

# export Datadog API/APP key env vars from $_DD_CLIENT_API_KEY / $_DD_CLIENT_APP_KEY
datadog-auth () {
  export DD_CLIENT_API_KEY=$_DD_CLIENT_API_KEY
  export DD_CLIENT_APP_KEY=$_DD_CLIENT_APP_KEY
}

# alias for kubectl command
k () {
  kubectl $@
}

# generate a random password (default 16 chars): generate_password [length]
generate_password() {
  local password_length=${1:-"16"}
  echo -e "Generating a random password with ${password_length} characters: Use \`generate_password [length]\` to specify length.\n"
  echo -n "password: "; LC_ALL=C tr -dc 'A-Za-z0-9!@#$%^&*_-' < /dev/urandom | head -c $password_length && echo
}

# (helper) az login and select subscription $1
_az_login () {
  trap "az config set core.login_experience_v2=on &>/dev/null" EXIT HUP INT QUIT PIPE TERM
  az account set --subscription $1 &>/dev/null
  if [ $? -ne 0 ]; then
    az config set core.login_experience_v2=off &>/dev/null
    az login &>/dev/null
    if [ $? -ne 0 ]; then
      echo "Azure login failed"
      return 1
    fi
  fi
  az account set --subscription $1 &>/dev/null
}

# (helper) az aks get-credentials for resource-group $1 / cluster $2 in subscription $3
_aks-login () {
  _az_login $3
  if [ $? -ne 0 ]; then
    echo "AKS login failed"
    return 1
  fi
  az aks get-credentials --resource-group $1 --name $2 --overwrite-existing
}

# get AKS credentials for a scriptcycle environment: aks-sc-login [dev|prd|prddr|test|uat]
aks-sc-login () {
  case "$1" in
    "dev")
      _aks-login ${AZURE_SC_RG_PREFIX}-dev-1 ${AZURE_SC_CLUSTER_PREFIX}-dev-1 $AZURE_SUBSCRIPTION_DEV_ID
      return
      ;;
    "prd"|"prod")
      _aks-login ${AZURE_SC_RG_PREFIX}-prod-1 ${AZURE_SC_CLUSTER_PREFIX}-prod-1 $AZURE_SUBSCRIPTION_PRD_ID
      return
      ;;
    "prddr"|"proddr")
      _aks-login ${AZURE_SC_RG_PREFIX}-prod-dr-1 ${AZURE_SC_CLUSTER_PREFIX}-prod-dr-1 $AZURE_SUBSCRIPTION_PRD_ID
      return
      ;;
    "test")
      _aks-login ${AZURE_SC_RG_PREFIX}-test-1 ${AZURE_SC_CLUSTER_PREFIX}-test-1 $AZURE_SUBSCRIPTION_DEV_ID
      return
      ;;
    "uat")
      _aks-login ${AZURE_SC_RG_PREFIX}-uat-1 ${AZURE_SC_CLUSTER_PREFIX}-uat-1 $AZURE_SUBSCRIPTION_DEV_ID
      return
      ;;
    *)
      echo "Usage: aks-sc-login [dev|prd|prddr|test|uat]"
      return 1
      ;;
  esac
}

# generate N xkcd-style passphrases of 6 words: gen-xkcd-pass [count]
gen-xkcd-pass() {
  [ $(echo "$1"|grep -E "[0-9]+") ] && NUM="$1" || NUM=1
  DICT=$(LC_CTYPE=C grep -E "^[a-zA-Z]{3,6}$" /usr/share/dict/words)
  for I in $(seq 1 "$NUM"); do
      WORDS=$(echo "$DICT"|gshuf -n 6|paste -sd ' ' -)
      XKCD=$(echo "$WORDS"|sed 's/ //g')
      echo "$XKCD ($WORDS)"|awk '{x=$1;$1="";printf "%-36s %s\n", x, $0}'
  done | column
}

source "$(dirname -- "${BASH_SOURCE[0]}")/scripts/k8s/manage-secrets.sh"

# run tflint, terraform fmt, validate and plan recursively in the current dir
tfcheck() {
  tflint --recursive
  terraform fmt --recursive
  terraform validate && terraform plan
}

# run a PowerShell script on Windows host(s) over WinRM/NTLM: winrun '<ps>' '<hosts>' (hosts default $WINRUN_HOSTS)
winrun() {
  local script="$1" hosts="${2:-$WINRUN_HOSTS}"
  if [ -z "$script" ] || [ -z "$hosts" ]; then
    echo "Usage: winrun '<powershell>' '<comma-separated-hosts>'   (or set \$WINRUN_HOSTS)" >&2
    return 2
  fi
  local b64
  b64=$(printf '%s' "$script" | base64 | tr -d '\n')
  OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES no_proxy='*' ANSIBLE_STDOUT_CALLBACK=minimal \
  ansible all -i "${hosts%,}," -c winrm \
    -e 'ansible_user={{ lookup("env","SCRIPTCYCLE_AD_USERNAME") }}' \
    -e 'ansible_password={{ lookup("env","SCRIPTCYCLE_AD_PASSWORD") }}' \
    -e ansible_port=5985 -e ansible_winrm_scheme=http \
    -e ansible_winrm_transport=ntlm -e ansible_winrm_server_cert_validation=ignore \
    -m ansible.windows.win_shell \
    -a "\$s=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$b64')); Invoke-Expression \$s"
}

# show drive sizes (GB + used/free %) on Windows host(s): windisk '<hosts>' (or set $WINRUN_HOSTS)
windisk() {
  local ps='
Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | Sort-Object DeviceID |
  Format-Table DeviceID,
    @{N="Label";E={$_.VolumeName}},
    @{N="SizeGB";E={"{0:N1}" -f ($_.Size/1GB)}},
    @{N="FreeGB";E={"{0:N1}" -f ($_.FreeSpace/1GB)}},
    @{N="FreePercentage";E={if ($_.Size) {"{0:N1}" -f ($_.FreeSpace/$_.Size*100)}}},
    @{N="UsedGB";E={"{0:N1}" -f (($_.Size-$_.FreeSpace)/1GB)}},
    @{N="UsedPercentage";E={if ($_.Size) {"{0:N1}" -f (($_.Size-$_.FreeSpace)/$_.Size*100)}}} -AutoSize | Out-String'
  winrun "$ps" "$1"
}

# du-style sizes (GB) for one or more paths on Windows host(s): windu '<path>'... (hosts via $WINRUN_HOSTS)
windu() {
  if [ "$#" -eq 0 ]; then
    echo "Usage: windu '<path1>' ['<path2>' ...]   (hosts from \$WINRUN_HOSTS)" >&2
    return 2
  fi
  local roots="" p
  for p in "$@"; do roots+="'$p',"; done
  roots="${roots%,}"
  local ps="\$Roots = @($roots)
foreach (\$Root in \$Roots) {
  \"== \$Root ==\"
  Get-ChildItem -LiteralPath \$Root -Force -ErrorAction SilentlyContinue | ForEach-Object {
    if (\$_.PSIsContainer) {
      \$b = (Get-ChildItem -LiteralPath \$_.FullName -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
    } else {
      \$b = \$_.Length
    }
    [pscustomobject]@{ Bytes = [int64]\$b; Path = \$_.FullName }
  } | Sort-Object Bytes | Format-Table @{N='SizeGB';E={'{0:N2}' -f (\$_.Bytes/1GB)}}, Path -AutoSize | Out-String
}"
  winrun "$ps"
}

# list these functions with their one-line descriptions (hides _-prefixed helpers)
show-functions() {
  awk '
    /^[A-Za-z0-9_-]+ *\(\)/ {
      name = $0; sub(/ *\(\).*/, "", name)
      if (name !~ /^_/ && prev ~ /^#/) {
        desc = prev; sub(/^# */, "", desc)
        names[++n] = name; descs[n] = desc
        if (length(name) > w) w = length(name)
      }
    }
    { prev = $0 }
    END { for (i = 1; i <= n; i++) printf "%-*s  %s\n", w, names[i], descs[i] }
  ' "${BASH_SOURCE[0]}" | sort
}
